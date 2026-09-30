#!/usr/bin/env python3
"""
BRICKSTORM - a Breakout game for the Commodore 64.

Generates all data tables into brickstorm_data.inc and assembles brickstorm.asm
with 64tass into brickstorm.prg (optionally a D64 disk image).

    brew install tass64
    python3 build.py               # -> brickstorm.prg
    python3 build.py --d64         # -> brickstorm.prg + brickstorm.d64
    python3 build.py --autoplay    # -> brickstorm_auto.prg (paddle plays itself, for testing)
    python3 build.py --autolose    # -> brickstorm_lose.prg (paddle stands still, for testing game over)
"""
import math
import os
import shutil
import subprocess
import sys

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


# name -> (col, row, colour, text)
STRINGS = {
    "score": (1, 0, 1, "SCORE"),
    "hi": (15, 0, 1, "HI"),
    "level": (26, 0, 1, "LEVEL"),
    "launch": centered("PRESS FIRE TO LAUNCH", 13, 7),
    "cleared": centered("LEVEL CLEARED!", 13, 13),
    "gameover": centered("GAME OVER", 12, 2),
    "again": centered("PRESS FIRE", 14, 1),
    "paused": centered("PAUSED", 13, 7),
    "t_sub": centered("A BREAKOUT GAME FOR THE C64", 10, 3),
    "t_by": centered("BY GUENTHER HASLBECK + CLAUDE CODE", 12, 7),
    "t_year": centered("2026", 13, 7),
    "t_ctl1": centered("JOYSTICK PORT 2  OR  KEYS A / D", 16, 15),
    "t_ctl2": centered("FIRE = SPACE OR RETURN", 17, 15),
    "t_ctl3": centered("P = PAUSE     M = MUSIC ON/OFF", 18, 15),
    "press": centered("PRESS FIRE TO START", 21, 1),
    "blank": centered(" " * 19, 21, 1),
    "t_hi": (13, 23, 12, "HIGH SCORE"),
}
HI_DIGITS_COL = 24        # where the 6 digits of the hi-score go on the title row 23


# ---------------------------------------------------------------- big title logo (3x5)
FONT = {
    'B': ["XX.", "X.X", "XX.", "X.X", "XX."],
    'R': ["XX.", "X.X", "XX.", "X.X", "X.X"],
    'I': ["X", "X", "X", "X", "X"],
    'C': ["XXX", "X..", "X..", "X..", "XXX"],
    'K': ["X.X", "X.X", "XX.", "X.X", "X.X"],
    'S': ["XXX", "X..", "XXX", "..X", "XXX"],
    'T': ["XXX", ".X.", ".X.", ".X.", ".X."],
    'O': ["XXX", "X.X", "X.X", "X.X", "XXX"],
    'M': ["X..X", "XXXX", "XXXX", "X..X", "X..X"],
}
LOGO = "BRICKSTORM"


def logo_rows():
    rows = [[0x20] * 40 for _ in range(5)]
    total = sum(len(FONT[ch][0]) + 1 for ch in LOGO) - 1
    assert total <= 40
    col = (40 - total) // 2
    for ch in LOGO:
        w = len(FONT[ch][0])
        for r in range(5):
            for c in range(w):
                if FONT[ch][r][c] == 'X':
                    rows[r][col + c] = 0x40
        col += w + 1
    return [v for row in rows for v in row]


# ---------------------------------------------------------------- levels (12 x 6 bricks)
# 0 = empty, 1 = normal brick, 2 = armored brick (two hits)
def level_full():
    return [[1] * 12 for _ in range(6)]


def level_checker():
    return [[1 if (r + k) % 2 == 0 else 0 for k in range(12)] for r in range(6)]


def level_pyramid():
    g = [[0] * 12 for _ in range(6)]
    for r in range(6):
        n = 2 * r + 2
        start = (12 - n) // 2
        for k in range(start, start + n):
            g[r][k] = 2 if k in (start, start + n - 1) and r > 1 else 1
    return g


def level_stripes():
    g = [[1] * 12 for _ in range(6)]
    for r in range(6):
        for k in range(12):
            if r % 2 == 1:
                g[r][k] = 2 if k % 3 == 0 else 1
            if r in (2, 3) and k in (5, 6):
                g[r][k] = 0
    return g


def level_diamond():
    g = [[0] * 12 for _ in range(6)]
    for r in range(6):
        for k in range(12):
            d = abs(k - 5.5) / 5.5 + abs(r - 2.5) / 2.5 * 0.8
            if d <= 1.0:
                g[r][k] = 2 if d < 0.45 else 1
    return g


LEVELS = [level_full(), level_checker(), level_pyramid(), level_stripes(), level_diamond()]
PALETTES = [                       # colour per brick row (top .. bottom)
    [2, 8, 7, 5, 3, 14],           # rainbow
    [10, 4, 14, 3, 13, 7],
    [7, 8, 2, 4, 6, 14],
    [13, 5, 3, 14, 4, 10],
    [1, 7, 8, 10, 2, 9],
]
ROW_SCORE_BCD = [0x50, 0x40, 0x30, 0x20, 0x10, 0x10]

# ---------------------------------------------------------------- ball speed / launch angles
SPEEDS = [40, 46, 52, 58, 64, 70]                       # 1/16 pixel per frame
ANGLES = [-58, -40, -22, -7, 7, 22, 40, 58]             # degrees from vertical, one per paddle zone


def s16(v):
    v &= 0xFFFF
    return v & 255, v >> 8


# ---------------------------------------------------------------- SFX and music
# type: wave|gate, start freq hi, step per frame, duration (frames), AD, SR
SFX = [
    ("WALL",   0x41, 0x14, 0xFF, 5, 0x04, 0x00),
    ("PADDLE", 0x11, 0x18, 0x00, 6, 0x04, 0x00),
    ("BRICK",  0x41, 0x38, 0x00, 6, 0x04, 0x00),
    ("ARMOR",  0x81, 0x26, 0x00, 5, 0x03, 0x00),
    ("LOSE",   0x21, 0x30, 0xFF, 40, 0x08, 0xA8),
    ("LEVELUP", 0x41, 0x10, 0x02, 24, 0x08, 0x88),
    ("START",  0x11, 0x10, 0x01, 20, 0x08, 0x88),
]
NOTE_SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def note_freq(name, transpose=0):
    semi = NOTE_SEMI[name[0]]
    rest = name[1:]
    if rest[0] == 'b': semi -= 1; rest = rest[1:]
    elif rest[0] == '#': semi += 1; rest = rest[1:]
    midi = 12 * (int(rest) + 1) + semi + transpose
    hz = 440.0 * 2 ** ((midi - 69) / 12.0)
    return round(hz * 16777216 / PAL_CLOCK)


CHORDS = [['A4', 'C5', 'E5', 'A5'], ['F4', 'A4', 'C5', 'F5'],      # Am F C G
          ['C5', 'E5', 'G5', 'C6'], ['G4', 'B4', 'D5', 'G5']]
ROOTS = ['A1', 'F1', 'C2', 'G1']
BASS = ['R', '.', 'R', '.', 'O', '.', 'R', '.', 'R', '.', 'R', '.', 'O', '.', 'R', 'O']
LEAD = [0, 1, 2, 3, 2, 1, 2, 1, 0, 1, 2, 3, 2, 3, 2, 1]


def music():
    bl, bh, ll, lh = [], [], [], []
    for bar in range(4):
        for k in range(16):
            b = BASS[k]
            if b == '.':
                bl.append(0); bh.append(0)
            else:
                f = note_freq(ROOTS[bar], 12 if b == 'O' else 0)
                bl.append(f & 255); bh.append(f >> 8)
            f = note_freq(CHORDS[bar][LEAD[k]])
            ll.append(f & 255); lh.append(f >> 8)
    return bl, bh, ll, lh


# ---------------------------------------------------------------- graphics data
CTAB = [2, 2, 8, 8, 7, 7, 13, 13, 5, 5, 3, 3, 14, 14, 4, 4]
GLYPH_BLOCK = [0xFF] * 8
GLYPHS = (                                                   # codes $60..$64
    [0xFF] * 7 + [0x00] +                                    # $60 brick body
    [0xFE] * 7 + [0x00] +                                    # $61 brick right end
    [0xFF, 0xFF, 0xC3, 0xC3, 0xC3, 0xFF, 0xFF, 0x00] +       # $62 armored body
    [0xFE, 0xFE, 0xC2, 0xC2, 0xC2, 0xFE, 0xFE, 0x00] +       # $63 armored right end
    [0xFF] * 7 + [0x00]                                      # $64 wall
)


def sprite(rows):
    data = []
    for r in range(21):
        data += rows[r] if r < len(rows) else [0, 0, 0]
    return data + [0]


PADDLE = sprite([[0x7F, 0xFF, 0xFE]] + [[0xFF, 0xFF, 0xFF]] * 4 + [[0x7F, 0xFF, 0xFE]])
BALL = sprite([[0x78, 0, 0]] + [[0xFC, 0, 0]] * 4 + [[0x78, 0, 0]])


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
    inc.table("tcolo", [(0xD800 + (3 + r) * 40) & 255 for r in range(5)])
    inc.table("tcohi", [(0xD800 + (3 + r) * 40) >> 8 for r in range(5)])
    inc.table("bcolk", [2 + 3 * k for k in range(12)])
    inc.table("bstart", [(2 + 3 * ((c - 2) // 3)) if 2 <= c <= 37 else 0 for c in range(40)])
    inc.table("zone_of", [max(0, min(7, (d - 2) // 6)) for d in range(53)])
    inc.table("rowscore", ROW_SCORE_BCD)
    inc.table("ctab", CTAB)

    # velocity table: index = speed * 8 + zone
    vxl, vxh, vyl, vyh = [], [], [], []
    for s in SPEEDS:
        for a in ANGLES:
            rad = math.radians(a)
            vx = round(s * math.sin(rad))
            vy = -round(s * math.cos(rad))
            lo, hi = s16(vx); vxl.append(lo); vxh.append(hi)
            lo, hi = s16(vy); vyl.append(lo); vyh.append(hi)
    inc.table("tvxl", vxl)
    inc.table("tvxh", vxh)
    inc.table("tvyl", vyl)
    inc.table("tvyh", vyh)

    # levels
    flat = []
    lvl_lo, lvl_hi = [], []
    for i, lvl in enumerate(LEVELS):
        lvl_lo.append(f"<(levels+{i * 72})")
        lvl_hi.append(f">(levels+{i * 72})")
        for row in lvl:
            flat += row
    inc.table("levels", flat)
    inc.lines.append("lvlplo")
    inc.lines.append("        .byte " + ",".join(lvl_lo))
    inc.lines.append("lvlphi")
    inc.lines.append("        .byte " + ",".join(lvl_hi))
    pal = []
    for p in PALETTES:
        pal += p + [0, 0]
    inc.table("lvlpal", pal)

    # strings
    for name, (col, row, color, text) in STRINGS.items():
        inc.table(f"str_{name}", [col, row, color] + screen_codes(text) + [0xFF])
    inc.const("HI_DIGITS_COL", HI_DIGITS_COL)
    inc.table("tlogo", logo_rows())

    # graphics
    inc.table("glyph_block", GLYPH_BLOCK)
    inc.table("glyph_set", GLYPHS)
    inc.table("sprites", PADDLE + BALL)

    # sfx
    for i, (name, *_rest) in enumerate(SFX):
        inc.const(f"SFX_{name}", i)
    inc.table("swave", [s[1] for s in SFX])
    inc.table("shi", [s[2] for s in SFX])
    inc.table("sstep", [s[3] for s in SFX])
    inc.table("sdur", [s[4] for s in SFX])
    inc.table("sad", [s[5] for s in SFX])
    inc.table("ssr", [s[6] for s in SFX])

    # music
    bl, bh, ll, lh = music()
    inc.table("bassl", bl)
    inc.table("bassh", bh)
    inc.table("leadl", ll)
    inc.table("leadh", lh)

    inc.write(os.path.join(HERE, "brickstorm_data.inc"))


def main():
    autolose = "--autolose" in sys.argv          # test mode: paddle never moves, ball falls through
    autoplay = "--autoplay" in sys.argv or autolose
    generate()
    tass = shutil.which("64tass")
    if not tass:
        sys.exit("64tass not found - install with: brew install tass64")
    name = "brickstorm_lose.prg" if autolose else "brickstorm_auto.prg" if autoplay else "brickstorm.prg"
    out = os.path.join(HERE, name)
    cmd = [tass, "--cbm-prg", "-a", "-C", "-Wall", f"-DAUTOPLAY={2 if autolose else 1 if autoplay else 0}",
           "-o", out, os.path.join(HERE, "brickstorm.asm")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        sys.exit(r.returncode)
    print(f"Created {name} ({os.path.getsize(out)} bytes)")
    if "--d64" in sys.argv and not autoplay:
        root = os.path.abspath(os.path.join(HERE, "..", ".."))
        d64 = os.path.join(HERE, "brickstorm.d64")
        subprocess.run([sys.executable, os.path.join(root, "make_d64.py"), out, d64, "BRICKSTORM"], check=True)
    print("Run: x64sc -autostart " + name)


if __name__ == "__main__":
    main()
