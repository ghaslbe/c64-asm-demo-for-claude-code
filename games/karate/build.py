#!/usr/bin/env python3
"""
DOJO BRAWL - a three fighter karate game for the Commodore 64 (inspired by IK+).

Generates all data tables (fighter sprites from fighters.py, background, combat tables,
texts, music) and assembles dojobrawl.asm with 64tass into dojobrawl.prg.

    brew install tass64
    python3 build.py               # -> dojobrawl.prg
    python3 build.py --d64         # -> dojobrawl.prg + dojobrawl.d64
    python3 build.py --autoplay    # -> dojobrawl_auto.prg (a bot plays, for testing)
    python3 build.py --autolose    # -> dojobrawl_lose.prg (the human fighter idles: game over test)
    python3 build.py --preview     # pose sheet -> docs/poses_preview.png
"""
import math
import os
import shutil
import subprocess
import sys

import fighters

HERE = os.path.dirname(os.path.abspath(__file__))
PAL_CLOCK = 985248


# ---------------------------------------------------------------- text
def screen_codes(text):
    out = []
    for c in text.upper():
        if c == ' ': out.append(32)
        elif 'A' <= c <= 'Z': out.append(ord(c) - 64)
        elif '0' <= c <= '9': out.append(ord(c))
        elif c in '!*-.,:+/=\'': out.append(ord(c))
        else: out.append(32)
    return out


def centered(text, row, color):
    return ((40 - len(text)) // 2, row, color, text)


STRINGS = {
    "t_sub": centered("A THREE FIGHTER KARATE GAME FOR THE C64", 14, 3),
    "t_by": centered("BY GUENTHER HASLBECK + CLAUDE CODE", 16, 7),
    "t_year": centered("2026", 17, 7),
    "t_c1": centered("MOVE: LEFT / RIGHT   JUMP: UP   CROUCH: DOWN", 19, 15),
    "t_c2": centered("FIRE = PUNCH   FIRE + FORWARD = KICK", 20, 15),
    "t_c3": centered("FIRE + DOWN = SWEEP   FIRE + BACK = BACK KICK", 21, 15),
    "t_c4": centered("FIRE IN THE AIR = FLYING KICK", 22, 15),
    "t_c5": centered("JOYSTICK PORT 2  OR  KEYS W A S D + SPACE", 23, 12),
    "press": centered("PRESS FIRE TO START", 24, 1),
    "blankp": centered(" " * 19, 24, 1),
    "t_hi": (13, 12, 12, ""),
    "roundtxt": (14, 2, 1, "ROUND "),
    "fight": centered("FIGHT!", 2, 7),
    "over": centered("ROUND OVER", 3, 1),
    "advance": centered("YOU ADVANCE TO THE NEXT ROUND!", 12, 5),
    "out": centered("YOU ARE OUT!", 12, 2),
    "bonus": centered("BONUS ROUND - BLOCK THE BALLS!", 2, 7),
    "bonus2": centered("", 2, 1),
    "perfect": centered("PERFECT! 5000 BONUS", 2, 5),
    "bonusend": centered("BONUS ROUND OVER", 2, 7),
    "gameover": centered("GAME OVER", 5, 2),
    "paused": centered("PAUSED", 2, 7),
    "clear": centered(" " * 36, 2, 1),
    "clear4": centered(" " * 36, 2, 1),
    "clear11": centered(" " * 36, 11, 1),
    "h_you": (1, 0, 1, "YOU"),
    "h_red": (11, 0, 2, "RED"),
    "h_blu": (21, 0, 14, "BLU"),
    "h_time": (30, 0, 1, "TIME"),
    "h_round": (1, 1, 1, "ROUND"),
    "h_belt": (10, 1, 1, "BELT"),
    "h_score": (24, 1, 1, "SCORE"),
}
BELTS = [("WHITE ", 1), ("YELLOW", 7), ("ORANGE", 8), ("GREEN ", 5), ("BLUE  ", 14),
         ("BROWN ", 9), ("BLACK ", 12)]
NAMES = ["YOU", "RED", "BLU"]


# ---------------------------------------------------------------- big title logo
FONT = {
    'D': ["XX.", "X.X", "X.X", "X.X", "XX."],
    'O': ["XXX", "X.X", "X.X", "X.X", "XXX"],
    'J': ["..X", "..X", "..X", "X.X", "XXX"],
    'B': ["XX.", "X.X", "XX.", "X.X", "XX."],
    'R': ["XX.", "X.X", "XX.", "X.X", "X.X"],
    'A': [".X.", "X.X", "XXX", "X.X", "X.X"],
    'W': ["X.X", "X.X", "XXX", "XXX", "X.X"],
    'L': ["X..", "X..", "X..", "X..", "XXX"],
}
LOGO_LINES = [("DOJO", 2), ("BRAWL", 8)]


def logo_screen():
    rows = {}
    for text, r0 in LOGO_LINES:
        total = sum(len(FONT[ch][0]) + 1 for ch in text) - 1
        col = (40 - total) // 2
        grid = [[0x20] * 40 for _ in range(5)]
        for ch in text:
            w = len(FONT[ch][0])
            for r in range(5):
                for c in range(w):
                    if FONT[ch][r][c] == 'X':
                        grid[r][col + c] = 0x40
            col += w + 1
        for r in range(5):
            rows[r0 + r] = grid[r]
    return rows


# ---------------------------------------------------------------- combat tables
S_IDLE, S_WALK, S_CROUCH, S_JUMP, S_PUNCH, S_KICK, S_SWEEP, S_FLY, S_BACK, S_HIT, S_FALL, S_GETUP, S_WIN = range(13)
# who can be hit: bit0 standing, bit1 crouching, bit2 in the air
STANCE = [1, 1, 2, 4, 1, 1, 1, 4, 1, 0, 0, 0, 0]
# pose index by state (poses: see fighters.POSE_ORDER)
STPOSE = [0, 2, 4, 5, 6, 7, 8, 9, 7, 10, 11, 12, 13]
# attacks: PUNCH, KICK, SWEEP, FLY, BACK: duration, active from/to, reach, damage (half points),
# victim stance mask, 1 = hits behind
ATTACKS = [
    (12, 3, 7, 24, 1, 0b001, 0),
    (20, 6, 11, 34, 2, 0b101, 0),
    (22, 7, 12, 32, 2, 0b011, 0),
    (200, 3, 200, 28, 2, 0b011, 0),
    (20, 6, 11, 34, 2, 0b101, 1),
]
JUMP_LEN = 30
JUMPTAB = [round(4 * 46 * t * (JUMP_LEN - 1 - t) / (JUMP_LEN - 1) ** 2) for t in range(JUMP_LEN)]
FIGHTER_COLORS = [1, 2, 14]
AGGR = [70, 90, 110, 130, 150, 175, 200]           # of 256: chance to attack/approach per decision
REACT = [30, 50, 70, 90, 110, 130, 150]            # of 256: chance to dodge an incoming attack
SKIN, DARK = 10, 0

# ---------------------------------------------------------------- background
# Stylised temple scene: sunset sky (raster), mountains, a big torii gate standing in the water
# (inspired by the Itsukushima shrine gate), wooden dojo floor in front.
SKY = ([0] * 20 + [4] * 16 + [2] * 16 + [10] * 18 + [8] * 20 + [7] * 22          # lines 51..162
       + [8] * 3 + [10] * 3 + [2] * 4 + [4] * 4 + [6] * 18)                     # water, lines 163..194
assert len(SKY) == 144
SKYTITLE = [0] * 144                                  # black sky for the title screen

GLYPH_BLOCK = [0xFF] * 8
GLYPH_PLANKS = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00,           # $60 plank
                0xFF, 0xFF, 0xF7, 0xF7, 0xF7, 0xFF, 0xFF, 0x00]           # $61 plank with a knot
GLYPH_CAPS = []                                                         # $70..$76: bottom k rows filled
for k in range(1, 8):
    GLYPH_CAPS += [0x00] * (8 - k) + [0xFF] * k
GLYPH_CAPS += [0xAA, 0x55] * 4                                          # $77 checker (reflection)
GLYPH_CAPS += [0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00]          # $78 wave dash
GLYPH_CAPS += [0x00, 0x00, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x00]          # $79 wave dash, shifted
WATER_ROW = 14                                                          # first water row


def mountain(base, phases, n=40):
    out = []
    for c in range(n):
        v = base
        for f, a_, p in phases:
            v += a_ * math.sin(2 * math.pi * f * c / 40.0 + p)
        out.append(max(6, int(v)))
    return out


def scene():
    """Returns (chars, colours) for screen rows 2..17 (16 rows x 40 columns), padded to 768."""
    R0, ROWS = 2, 16
    ch = [[0x20] * 40 for _ in range(ROWS)]
    co = [[1] * 40 for _ in range(ROWS)]

    def cell(row, col, c, color):
        ch[row - R0][col] = c
        co[row - R0][col] = color

    def column(col, top_px, bottom_row, color, cap_color=None):
        """Fill column col from pixel line top_px (screen row space) down to the end of bottom_row."""
        first = True
        for row in range(R0, bottom_row + 1):
            y0 = row * 8
            k = y0 + 8 - top_px              # filled lines inside this cell (bottom aligned)
            if k <= 0:
                continue
            body = color
            if first and cap_color is not None:
                body = cap_color             # the topmost cell gets the cap colour
            first = False
            if k >= 8:
                cell(row, col, 0x40, body)
            else:
                cell(row, col, 0x6F + k, body)

    horizon = WATER_ROW - 1                  # last sky row
    base_px = (horizon + 1) * 8
    far = mountain(30, [(1.5, 10, 0.4), (3.0, 4, 1.0)])
    mid = mountain(14, [(2.0, 5, 2.0), (4.0, 3, 0.5)])
    for c in range(40):
        column(c, base_px - far[c], horizon, 11)      # far mountains: dark grey
    for c in range(40):
        column(c, base_px - mid[c], horizon, 0)       # nearer hills: black silhouettes

    # water: waves in the lower rows
    seed = 7
    for row in range(WATER_ROW, 18):
        for col in range(40):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            if (seed >> 16) % 7 == 0:
                cell(row, col, 0x78 + ((seed >> 20) & 1), 14 if row < 16 else 3)

    # torii gate: pillars, lower beam, curved top beam with a green roof edge, small plaque
    PL, PR = (13, 14), (25, 26)
    for cols in (PL, PR):
        for row in range(6, WATER_ROW + 2):            # pillars stand in the water
            cell(row, cols[0], 0x40, 8)
            cell(row, cols[1], 0x40, 2)               # darker side for a little depth
        for row in (WATER_ROW + 2, WATER_ROW + 3):    # reflection
            cell(row, cols[0], 0x77, 8)
            cell(row, cols[1], 0x77, 2)
    for col in range(10, 30):                          # nuki: the straight lower beam
        cell(7, col, 0x40, 8)
    mid_c = 19.5
    for col in range(8, 32):                           # kasagi: the curved top beam
        curve = 9 * (abs(col - mid_c) / 11.5) ** 2.2
        top = 4 * 8 + 5 - int(curve)                  # top edge of the beam in pixel lines
        column(col, top, 5, 8, cap_color=5)           # orange body, green copper edge
    for col in (19, 20):                               # plaque between the beams
        cell(6, col, 0x40, 11)

    flat_c = [v for row in ch for v in row]
    flat_o = [v for row in co for v in row]
    flat_c += [0x20] * (768 - len(flat_c))
    flat_o += [1] * (768 - len(flat_o))
    return flat_c, flat_o


# ---------------------------------------------------------------- extra sprites (hi-res)
def hires(rows):
    rows = [r.ljust(24, '.') for r in rows]
    rows += ["." * 24] * (21 - len(rows))
    data = []
    for r in rows:
        for b in range(3):
            data.append(sum((1 if r[b * 8 + i] == 'X' else 0) << (7 - i) for i in range(8)))
    return data + [0]


BALL = hires(["...XXXX.", "..XXXXXX", ".XXXXXXX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX",
              "XXXXXXXX", ".XXXXXXX", "..XXXXXX", "...XXXX."])
SPARK1 = hires(["......XX........", "......XX........", "..X...XX...X....", "...X..XX..X.....",
                "....X.XX.X......", ".....XXXX.......", "XXXXXXXXXXXXXXXX", ".....XXXX.......",
                "....X.XX.X......", "...X..XX..X.....", "..X...XX...X....", "......XX........",
                "......XX........"])
SPARK2 = hires(["....X....X......", ".....X..X.......", "......XX........", "XX..XXXXXX..XX..",
                "..XXXXXXXXXX....", "..XXXXXXXXXX....", "XX..XXXXXX..XX..", "......XX........",
                ".....X..X.......", "....X....X......"])
SHIELD = hires(["..XXXX..", ".XXXXXX.", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX",
                "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX",
                "XXXXXXXX", "XXXXXXXX", ".XXXXXX.", "..XXXX.."])

# ---------------------------------------------------------------- SFX and music
SFX = [
    ("PUNCH", 0x81, 0x30, 0xFE, 5, 0x03, 0x00),
    ("KICK",  0x81, 0x24, 0xFF, 8, 0x04, 0x00),
    ("HIT",   0x41, 0x1C, 0xFF, 9, 0x05, 0x00),
    ("FALL",  0x21, 0x28, 0xFF, 22, 0x08, 0xA8),
    ("START", 0x41, 0x10, 0x02, 22, 0x08, 0x88),
    ("WIN",   0x11, 0x10, 0x03, 26, 0x08, 0x88),
    ("BLOCK", 0x41, 0x34, 0xFE, 6, 0x03, 0x00),
    ("MISS",  0x21, 0x20, 0xFE, 16, 0x08, 0x88),
]
NOTE_SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def note_freq(name, transpose=0):
    semi = NOTE_SEMI[name[0]]
    rest = name[1:]
    if rest[0] == 'b': semi -= 1; rest = rest[1:]
    elif rest[0] == '#': semi += 1; rest = rest[1:]
    midi = 12 * (int(rest) + 1) + semi + transpose
    return round(440.0 * 2 ** ((midi - 69) / 12.0) * 16777216 / PAL_CLOCK)


# Hirajoshi scale on A: A B C E F - a "japanese" feeling, 4 bars of 16 steps
LEAD = ("A4 . C5 . E5 . C5 . B4 . A4 . . . . . "
        "C5 . E5 . F5 . E5 . C5 . B4 . A4 . . . "
        "A4 . C5 . E5 . F5 . E5 . C5 . B4 . A4 . "
        "E5 . F5 . E5 . C5 . B4 . A4 . . . . . ").split()
ROOTS = ['A1', 'F1', 'A1', 'E1']
BASS = ['R', '.', 'R', '.', 'O', '.', 'R', '.', 'R', '.', 'R', '.', 'O', '.', 'R', 'O']


def music():
    bl, bh, ll, lh = [], [], [], []
    assert len(LEAD) == 64
    for bar in range(4):
        for k in range(16):
            b = BASS[k]
            if b == '.':
                bl.append(0); bh.append(0)
            else:
                f = note_freq(ROOTS[bar], 12 if b == 'O' else 0)
                bl.append(f & 255); bh.append(f >> 8)
            n = LEAD[bar * 16 + k]
            if n == '.':
                ll.append(0); lh.append(0)
            else:
                f = note_freq(n)
                ll.append(f & 255); lh.append(f >> 8)
    return bl, bh, ll, lh


# ---------------------------------------------------------------- emit
class Inc:
    def __init__(self):
        self.lines = ["; generated by build.py - do not edit"]

    def table(self, name, values, align=False, per_line=16):
        if align:
            self.lines.append("        .align $100")
        vals = [int(v) & 0xFF for v in values]
        self.lines.append(name)
        for i in range(0, len(vals), per_line):
            chunk = ",".join(f"${v:02x}" for v in vals[i:i + per_line])
            self.lines.append(f"        .byte {chunk}")

    def const(self, name, value):
        self.lines.append(f"{name} = {value}")

    def write(self, path):
        with open(path, "w") as f:
            f.write("\n".join(self.lines) + "\n")


def generate():
    inc = Inc()
    inc.table("rlo", [(0x0400 + r * 40) & 255 for r in range(25)])
    inc.table("rhi", [(0x0400 + r * 40) >> 8 for r in range(25)])
    inc.table("rchi", [(0xD800 + r * 40) >> 8 for r in range(25)])
    inc.table("bitm", [1, 2, 4])

    inc.const("JUMP_LEN", JUMP_LEN)
    inc.table("jumptab", JUMPTAB)
    inc.table("stance", STANCE)
    inc.table("stpose", STPOSE)
    inc.table("adur", [a[0] for a in ATTACKS])
    inc.table("aact0", [a[1] for a in ATTACKS])
    inc.table("aact1", [a[2] for a in ATTACKS])
    inc.table("areach", [a[3] for a in ATTACKS])
    inc.table("admg", [a[4] for a in ATTACKS])
    inc.table("amask", [a[5] for a in ATTACKS])
    inc.table("aback", [a[6] for a in ATTACKS])
    inc.table("fcolor", FIGHTER_COLORS)
    inc.table("aggr", AGGR)
    inc.table("react", REACT)
    inc.const("SKIN", SKIN)
    inc.const("DARK", DARK)
    inc.table("sky", SKY)
    inc.table("skytitle", SKYTITLE)
    bgc, bgo = scene()
    bg = Inc()
    bg.lines = ["; generated by build.py - background scene, assembled at $4000 (CPU only, outside the VIC bank)"]
    bg.table("bgchar", bgc)
    bg.table("bgcol", bgo)
    bg.write(os.path.join(HERE, "dojobrawl_bg.inc"))
    inc.table("glyph_block", GLYPH_BLOCK)
    inc.table("glyph_planks", GLYPH_PLANKS)
    inc.table("glyph_caps", GLYPH_CAPS)
    inc.table("beltname", [c for n, _ in BELTS for c in screen_codes(n)])
    inc.table("beltcol", [c for _, c in BELTS])
    inc.table("nametab", [c for n in NAMES for c in screen_codes(n)])

    for name, (col, row, color, text) in STRINGS.items():
        inc.table(f"str_{name}", [col, row, color] + screen_codes(text) + [0xFF])
    rows = logo_screen()
    inc.table("tlogo", [v for r in sorted(rows) for v in rows[r]])
    inc.table("logorows", sorted(rows))
    inc.const("LOGO_ROWS", len(rows))
    inc.table("ctab", [2, 2, 8, 8, 7, 7, 13, 13, 5, 5, 3, 3, 14, 14, 4, 4])

    blocks, a0, a1 = fighters.all_blocks()
    inc.table("anchor0", a0)
    inc.table("anchor1", a1)
    extra = [BALL, SPARK1, SPARK2, SHIELD]
    inc.const("BLK_BALL", 0xA0 + len(blocks))
    inc.const("BLK_SPARK1", 0xA0 + len(blocks) + 1)
    inc.const("BLK_SPARK2", 0xA0 + len(blocks) + 2)
    inc.const("BLK_SHIELD", 0xA0 + len(blocks) + 3)
    flat = [b for blk in blocks for b in blk] + [b for blk in extra for b in blk]
    sp = Inc()
    sp.lines = ["; generated by build.py - sprite blocks, assembled at $2800 (pointer $A0)"]
    sp.table("spritedata", flat, per_line=32)
    sp.write(os.path.join(HERE, "dojobrawl_sprites.inc"))

    for i, (name, *_r) in enumerate(SFX):
        inc.const(f"SFX_{name}", i)
    inc.table("swave", [s[1] for s in SFX])
    inc.table("shi", [s[2] for s in SFX])
    inc.table("sstep", [s[3] for s in SFX])
    inc.table("sdur", [s[4] for s in SFX])
    inc.table("sad", [s[5] for s in SFX])
    inc.table("ssr", [s[6] for s in SFX])
    bl, bh, ll, lh = music()
    inc.table("bassl", bl)
    inc.table("bassh", bh)
    inc.table("leadl", ll)
    inc.table("leadh", lh)
    inc.write(os.path.join(HERE, "dojobrawl_data.inc"))


def main():
    if "--preview" in sys.argv:
        os.makedirs(os.path.join(HERE, "docs"), exist_ok=True)
        fighters.preview(os.path.join(HERE, "docs", "poses_preview.png"))
        print("wrote docs/poses_preview.png")
        return
    autolose = "--autolose" in sys.argv          # test mode: the human fighter does nothing
    autoplay = "--autoplay" in sys.argv or autolose
    generate()
    tass = shutil.which("64tass")
    if not tass:
        sys.exit("64tass not found - install with: brew install tass64")
    name = "dojobrawl_lose.prg" if autolose else "dojobrawl_auto.prg" if autoplay else "dojobrawl.prg"
    out = os.path.join(HERE, name)
    cmd = [tass, "--cbm-prg", "-a", "-C", "-Wall", f"-DAUTOPLAY={2 if autolose else 1 if autoplay else 0}",
           "-o", out, os.path.join(HERE, "dojobrawl.asm")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        sys.exit(r.returncode)
    print(f"Created {name} ({os.path.getsize(out)} bytes)")
    if "--d64" in sys.argv and not autoplay:
        root = os.path.abspath(os.path.join(HERE, "..", ".."))
        d64 = os.path.join(HERE, "dojobrawl.d64")
        subprocess.run([sys.executable, os.path.join(root, "make_d64.py"), out, d64, "DOJOBRAWL"], check=True)
    print("Run: x64sc -autostart " + name)


if __name__ == "__main__":
    main()
