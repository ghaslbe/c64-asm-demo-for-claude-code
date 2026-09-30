#!/usr/bin/env python3
"""
DUNGEON BLAST - a maze shooter for the Commodore 64 (in the spirit of Wizard of Wor).

Generates all data tables into dungeonblast_data.inc and assembles dungeonblast.asm
with 64tass into dungeonblast.prg (optionally a D64 disk image).

    brew install tass64
    python3 build.py               # -> dungeonblast.prg
    python3 build.py --d64         # -> dungeonblast.prg + dungeonblast.d64
    python3 build.py --autoplay    # -> dungeonblast_auto.prg (a bot plays, for testing)
    python3 build.py --autogod     # -> dungeonblast_god.prg (unkillable bot, for testing later levels)
"""
import math
import os
import shutil
import subprocess
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
PAL_CLOCK = 985248
W, H = 20, 11                    # maze size in 16x16 pixel tiles


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
    "score": (1, 0, 1, "SCORE"),
    "hi": (15, 0, 1, "HI"),
    "level": (26, 0, 1, "LEVEL"),
    "ready": centered("GET READY!", 24, 7),
    "wizard": centered("THE WIZARD APPEARS!", 24, 4),
    "cleared": centered("LEVEL CLEARED!", 24, 13),
    "gameover": centered("GAME OVER", 24, 2),
    "paused": centered("PAUSED", 24, 7),
    "blank": (0, 24, 1, " " * 40),
    "t_sub": centered("A MAZE SHOOTER FOR THE C64", 14, 3),
    "t_by": centered("BY GUENTHER HASLBECK + CLAUDE CODE", 16, 7),
    "t_year": centered("2026", 17, 7),
    "t_ctl1": centered("JOYSTICK PORT 2  OR  KEYS W A S D", 19, 15),
    "t_ctl2": centered("FIRE = SPACE OR RETURN", 20, 15),
    "t_ctl3": centered("P = PAUSE     M = MUSIC ON/OFF", 21, 15),
    "press": centered("PRESS FIRE TO START", 23, 1),
    "blankp": centered(" " * 19, 23, 1),
    "t_hi": (13, 24, 12, "HIGH SCORE"),
}
HI_DIGITS_COL = 24


# ---------------------------------------------------------------- title logo (3x5, two lines)
FONT = {
    'D': ["XX.", "X.X", "X.X", "X.X", "XX."],
    'U': ["X.X", "X.X", "X.X", "X.X", "XXX"],
    'N': ["X..X", "XX.X", "XXXX", "X.XX", "X..X"],
    'G': ["XXX", "X..", "X.X", "X.X", "XXX"],
    'E': ["XXX", "X..", "XXX", "X..", "XXX"],
    'O': ["XXX", "X.X", "X.X", "X.X", "XXX"],
    'B': ["XX.", "X.X", "XX.", "X.X", "XX."],
    'L': ["X..", "X..", "X..", "X..", "XXX"],
    'A': [".X.", "X.X", "XXX", "X.X", "X.X"],
    'S': ["XXX", "X..", "XXX", "..X", "XXX"],
    'T': ["XXX", ".X.", ".X.", ".X.", ".X."],
}
LOGO_LINES = [("DUNGEON", 2), ("BLAST", 8)]      # text, first screen row


def logo_screen():
    """Returns a list of (row, [40 codes]) - 5 rows per logo line."""
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


# ---------------------------------------------------------------- mazes (left half, mirrored)
HALVES = [
    ["##########",
     "#.....#...",
     "#.###.#.#.",
     "#.#.....#.",
     "#.#.###.#.",
     "..........",
     "#.#.###.#.",
     "#.#.....#.",
     "#.###.#.#.",
     "#.....#...",
     "##########"],
    ["##########",
     "#........#",
     "#.##.###.#",
     "#.#......#",
     "#.#.####..",
     "..........",
     "#.#.####..",
     "#.#......#",
     "#.##.###.#",
     "#........#",
     "##########"],
    ["##########",
     "#...#.....",
     "#.#.#.###.",
     "#.#...#...",
     "#.####.#.#",
     ".......#..",
     "#.####.#.#",
     "#.#...#...",
     "#.#.#.###.",
     "#...#.....",
     "##########"],
    ["##########",
     "#.........",
     "#.#####.#.",
     "#.#.....#.",
     "#.#.###.#.",
     "....#.....",
     "#.#.###.#.",
     "#.#.....#.",
     "#.#####.#.",
     "#.........",
     "##########"],
]
WALL_COLORS = [6, 9, 11, 2]          # per maze
START = (1, 9)


def full_maze(half):
    return [[(1 if c == '#' else 0) for c in (row + row[::-1])] for row in half]


def bfs(maze, start):
    dist = {start: 0}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = (x + dx) % W, y + dy
            if 0 <= ny < H and maze[ny][nx] == 0 and (nx, ny) not in dist:
                dist[(nx, ny)] = dist[(x, y)] + 1
                q.append((nx, ny))
    return dist


def build_mazes():
    mazes, spawns = [], []
    for i, half in enumerate(HALVES):
        m = full_maze(half)
        assert m[START[1]][START[0]] == 0, f"maze {i}: start is a wall"
        assert m[5][0] == 0 and m[5][W - 1] == 0, f"maze {i}: no tunnel"
        d = bfs(m, START)
        floors = sum(1 for y in range(H) for x in range(W) if m[y][x] == 0)
        assert len(d) == floors, f"maze {i}: {floors - len(d)} unreachable floor tiles"
        cand = sorted((t for t in d if t[1] <= 6 and d[t] >= 10), key=lambda t: -d[t])
        chosen = []
        for t in cand:
            if all(abs(t[0] - c[0]) + abs(t[1] - c[1]) >= 5 for c in chosen):
                chosen.append(t)
            if len(chosen) == 5:
                break
        assert len(chosen) == 5, f"maze {i}: not enough spawn tiles"
        mazes.append(m)
        spawns.append(chosen)
    return mazes, spawns


# ---------------------------------------------------------------- levels
# monster types: 1 = slow, 2 = medium + invisible, 3 = fast; 0 = no enemy
ENEMIES = [[1, 1, 1, 0, 0], [1, 1, 2, 0, 0], [1, 2, 2, 1, 0], [2, 2, 3, 1, 0],
           [3, 2, 2, 1, 1], [3, 3, 2, 2, 1], [3, 3, 3, 2, 2]]
CHASE = [40, 60, 80, 100, 120, 140, 170]         # of 256, chance to chase the player
SHOOT = [6, 10, 14, 18, 24, 30, 40]              # of 256, chance to shoot when lined up
GATE = [0, 0, 0, 0,   1, 0, 1, 0,   1, 1, 1, 0,   1, 1, 1, 1,   1, 1, 1, 1]   # move gating per type/frame
SCORE_HUNDREDS_BCD = [0x00, 0x01, 0x02, 0x04, 0x10]                       # type 1..3, wizard


# ---------------------------------------------------------------- sprites (16x16 in a 24x21 sprite)
def art(lines):
    assert len(lines) == 16 and all(len(l) == 16 for l in lines), lines
    return [[1 if c == 'X' else 0 for c in l] for l in lines]


def pad(rows):
    rows = rows + ["." * 16] * (16 - len(rows))
    return [r.ljust(16, '.') for r in rows]


def shift_rows(bits, first, dx):
    out = [r[:] for r in bits]
    for y in range(first, 16):
        row = bits[y]
        out[y] = ([0] * dx + row[:16 - dx]) if dx > 0 else (row[-dx:] + [0] * (-dx))
    return out


def to_sprite(bits):
    data = []
    for y in range(21):
        row = bits[y] if y < 16 else [0] * 16
        b0 = sum(v << (7 - i) for i, v in enumerate(row[:8]))
        b1 = sum(v << (7 - i) for i, v in enumerate(row[8:16]))
        data += [b0, b1, 0]
    return data + [0]


PLAYER_BODY = pad([
    "................",
    "....XXXXXX......",
    "...XXXXXXXX.....",
    "...XXX..XXX.....",
    "...XXXXXXXX.....",
    "....XXXXXX......",
    "..XXXXXXXXXX....",
    "..XXXXXXXXXX....",
    "..XXXXXXXXXX....",
    "..XX.XXXX.XX....",
    "...X.XXXX.X.....",
    "....XXXXXX......",
    "....XX..XX......",
    "....XX..XX......",
    "...XXX..XXX.....",
])


def player_sprite(direction):                # 0 right, 1 left, 2 down, 3 up
    rows = [list(r) for r in PLAYER_BODY]
    # body is centred at columns 2..11 -> move it to columns 3..12 first
    rows = [['.'] + r[:15] for r in rows]
    def put(x0, x1, y0, y1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                rows[y][x] = 'X'
    if direction == 0: put(12, 15, 7, 8)
    elif direction == 1: put(0, 3, 7, 8)
    elif direction == 2: put(7, 8, 12, 15)
    else: put(7, 8, 0, 3)
    return [''.join(r) for r in rows]


MONSTERS = {
    1: pad([
        "................",
        "....X......X....",
        "....XX....XX....",
        "...XXXXXXXXXX...",
        "..XXXXXXXXXXXX..",
        "..XXX..XX..XXX..",
        "..XXX..XX..XXX..",
        "..XXXXXXXXXXXX..",
        "..XXXXXXXXXXXX..",
        "...XXX.XX.XXX...",
        "...XXXXXXXXXX...",
        "....XXXXXXXX....",
        "....XX....XX....",
        "...XX......XX...",
    ]),
    2: pad([
        "................",
        "..X..X....X..X..",
        "..XX.XX..XX.XX..",
        "...XXXXXXXXXX...",
        "..XXXXXXXXXXXX..",
        ".XXX.XX..XX.XXX.",
        ".XXX.XX..XX.XXX.",
        ".XXXXXXXXXXXXXX.",
        ".XXXXXXXXXXXXXX.",
        "..XX.XXXXXX.XX..",
        "..X..X.XX.X..X..",
        "..X..X....X..X..",
        "...XX......XX...",
    ]),
    3: pad([
        "................",
        "....XXXXXXXX....",
        "...XXXXXXXXXX...",
        "..XXXXXXXXXXXX..",
        "..XX..XXXX..XX..",
        "..XX..XXXX..XX..",
        "..XXXXXXXXXXXX..",
        "...XXXX..XXXX...",
        "...X.X.XX.X.X...",
        "...XXXXXXXXXX...",
        "....XXXXXXXX....",
        "....X.X..X.X....",
        "...XX.X..X.XX...",
    ]),
    4: pad([
        ".......XX.......",
        "......XXXX......",
        ".....XXXXXX.....",
        "....XXXXXXXX....",
        "..XXXXXXXXXXXX..",
        "....XXXXXXXX....",
        "....XX.XX.XX....",
        "....XXXXXXXX....",
        "...XXXXXXXXXX...",
        "..XXXXXXXXXXXX..",
        "..XXXXXXXXXXXX..",
        ".XXXXXXXXXXXXXX.",
        ".XXXXXXXXXXXXXX.",
        ".XXXXXXXXXXXXXX.",
    ]),
}
BULLET = pad(["XXXX............"] * 4)
TEXT_TILE = None


def sprite_blocks():
    """13 sprite blocks: 4 player, 4 monsters x2 frames, bullet."""
    blocks = []
    for d in range(4):
        blocks.append(to_sprite(art(player_sprite(d))))
    for t in (1, 2, 3, 4):
        a = art(MONSTERS[t])
        blocks.append(to_sprite(a))
        blocks.append(to_sprite(shift_rows(a, 11, 1)))
    blocks.append(to_sprite(art(BULLET)))
    data = []
    for b in blocks:
        data += b
    return data


# ---------------------------------------------------------------- wall glyphs
TILE = [[1 if (x < 15 and y < 15) else 0 for x in range(16)] for y in range(16)]
for _y in range(3, 12):                  # a small bevel highlight so walls look like stone blocks
    pass


def glyph_bytes(x0, y0):
    out = []
    for y in range(8):
        v = 0
        for x in range(8):
            v |= TILE[y0 + y][x0 + x] << (7 - x)
        out.append(v)
    return out


GLYPHS = glyph_bytes(0, 0) + glyph_bytes(8, 0) + glyph_bytes(0, 8) + glyph_bytes(8, 8)   # $60..$63
GLYPH_BLOCK = [0xFF] * 8

# ---------------------------------------------------------------- SFX and music
SFX = [
    ("SHOT",  0x41, 0x30, 0xFE, 7, 0x04, 0x00),
    ("KILL",  0x81, 0x30, 0xFF, 12, 0x08, 0x00),
    ("DIE",   0x21, 0x30, 0xFF, 44, 0x08, 0xA8),
    ("TELE",  0x11, 0x10, 0x03, 12, 0x04, 0x00),
    ("LEVEL", 0x41, 0x10, 0x02, 24, 0x08, 0x88),
    ("START", 0x11, 0x10, 0x01, 20, 0x08, 0x88),
    ("ESHOT", 0x41, 0x1A, 0xFF, 6, 0x04, 0x00),
    ("WIZ",   0x21, 0x20, 0xFD, 24, 0x08, 0x88),
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


CHORDS = [['D4', 'F4', 'A4', 'D5'], ['Bb3', 'D4', 'F4', 'Bb4'],          # Dm Bb C A
          ['C4', 'E4', 'G4', 'C5'], ['A3', 'C#4', 'E4', 'A4']]
ROOTS = ['D2', 'Bb1', 'C2', 'A1']
BASS = ['R', '.', '.', 'R', '.', '.', 'R', '.', 'O', '.', '.', 'R', '.', 'R', '.', 'O']
LEAD = [0, 2, 1, 3, 0, 2, 1, 3, 2, 1, 3, 1, 2, 3, 2, 1]


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
    mazes, spawns = build_mazes()

    inc.table("rlo", [(0x0400 + r * 40) & 255 for r in range(25)])
    inc.table("rhi", [(0x0400 + r * 40) >> 8 for r in range(25)])
    inc.table("rchi", [(0xD800 + r * 40) >> 8 for r in range(25)])
    inc.table("t16lo", [(x * 16) & 255 for x in range(W)])
    inc.table("t16hi", [(x * 16) >> 8 for x in range(W)])
    inc.table("y16", [y * 16 for y in range(H)])
    inc.table("row20", [y * W for y in range(H)])
    inc.table("dxt", [1, 0xFF, 0, 0])
    inc.table("dyt", [0, 0, 1, 0xFF])
    inc.table("sprbit", [1, 2, 4, 8, 16, 32, 64, 128])

    # mazes: 4 x 220 bytes, wall colours, spawn tiles
    flat = []
    for m in mazes:
        for row in m:
            flat += row
    inc.table("mazes", flat)
    inc.table("mazecol", WALL_COLORS)
    inc.lines.append("mazelo")
    inc.lines.append("        .byte " + ",".join(f"<(mazes+{i * W * H})" for i in range(len(mazes))))
    inc.lines.append("mazehi")
    inc.lines.append("        .byte " + ",".join(f">(mazes+{i * W * H})" for i in range(len(mazes))))
    for i, sp in enumerate(spawns):
        inc.table(f"spawn{i}", [v for t in sp for v in t])
    inc.lines.append("spawnlo")
    inc.lines.append("        .byte " + ",".join(f"<spawn{i}" for i in range(4)))
    inc.lines.append("spawnhi")
    inc.lines.append("        .byte " + ",".join(f">spawn{i}" for i in range(4)))
    inc.const("STARTX", START[0])
    inc.const("STARTY", START[1])

    flat = []
    for row in ENEMIES:
        flat += row
    inc.table("lvlenemy", flat)
    inc.const("NLEVELS", len(ENEMIES))
    inc.table("chase", CHASE)
    inc.table("shootp", SHOOT)
    inc.table("gate", GATE)
    inc.table("scorehund", SCORE_HUNDREDS_BCD)
    inc.table("tcolor", [0, 14, 5, 2, 4])

    for name, (col, row, color, text) in STRINGS.items():
        inc.table(f"str_{name}", [col, row, color] + screen_codes(text) + [0xFF])
    inc.const("HI_DIGITS_COL", HI_DIGITS_COL)
    rows = logo_screen()
    inc.table("tlogo", [v for r in sorted(rows) for v in rows[r]])
    inc.const("LOGO_FIRST_ROW", min(rows))
    inc.const("LOGO_ROWS", len(rows))
    inc.table("logorows", sorted(rows))

    inc.table("ctab", [2, 2, 8, 8, 7, 7, 13, 13, 5, 5, 3, 3, 14, 14, 4, 4])
    inc.table("glyph_block", GLYPH_BLOCK)
    inc.table("glyph_walls", GLYPHS)
    inc.table("sprites", sprite_blocks())

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

    inc.write(os.path.join(HERE, "dungeonblast_data.inc"))
    return mazes, spawns


def main():
    autogod = "--autogod" in sys.argv            # test mode: bot that cannot be killed
    autoplay = "--autoplay" in sys.argv or autogod
    mazes, spawns = generate()
    if "--show" in sys.argv:
        for i, m in enumerate(mazes):
            print(f"maze {i}  spawns {spawns[i]}")
            for row in m:
                print("".join("#" if v else "." for v in row))
    tass = shutil.which("64tass")
    if not tass:
        sys.exit("64tass not found - install with: brew install tass64")
    name = "dungeonblast_god.prg" if autogod else "dungeonblast_auto.prg" if autoplay else "dungeonblast.prg"
    out = os.path.join(HERE, name)
    cmd = [tass, "--cbm-prg", "-a", "-C", "-Wall", f"-DAUTOPLAY={2 if autogod else 1 if autoplay else 0}",
           "-o", out, os.path.join(HERE, "dungeonblast.asm")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        sys.exit(r.returncode)
    print(f"Created {name} ({os.path.getsize(out)} bytes)")
    if "--d64" in sys.argv and not autoplay:
        root = os.path.abspath(os.path.join(HERE, "..", ".."))
        d64 = os.path.join(HERE, "dungeonblast.d64")
        subprocess.run([sys.executable, os.path.join(root, "make_d64.py"), out, d64, "DUNGEONBLAST"], check=True)
    print("Run: x64sc -autostart " + name)


if __name__ == "__main__":
    main()
