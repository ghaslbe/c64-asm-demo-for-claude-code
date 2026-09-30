#!/usr/bin/env python3
"""
IAC MASTERMIND CREW cracktro - build script.

Generates all data tables (sine, rainbow, music, stars, logo, scroll text, sprite)
into demo_data.inc and assembles demo.asm with 64tass into demo.prg.

    brew install tass64
    python3 build_demo.py
"""
import math
import os
import random
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PAL_CLOCK = 985248


# ---------------------------------------------------------------- text
def screen_codes(text):
    """ASCII -> C64 screen codes (uppercase/graphics set). '_' becomes code 63."""
    out = []
    for c in text.upper():
        if c == ' ': out.append(32)
        elif 'A' <= c <= 'Z': out.append(ord(c) - 64)
        elif '0' <= c <= '9': out.append(ord(c))
        elif c == '_': out.append(63)          # patched to an underscore glyph
        elif c in '!*-.,:\'': out.append(ord(c))
        else: out.append(32)
    return out


TITLE1 = "*** GUENTHER HASLBECK PRESENTS ***"
TITLE2 = "CODED WITH CLAUDE CODE * 2026"
SCROLL = ("    GUENTHER HASLBECK AND CLAUDE CODE PROUDLY PRESENT ... A BRAND NEW C64 DEMO FOR 2026 ..."
          "   HOW WAS IT MADE?   CREATED ON A MACBOOK IN 2026 - NO C64 NEEDED!"
          "   GUENTHER TALKED TO CLAUDE CODE IN THE TERMINAL AND CLAUDE WROTE THE 6502 ASSEMBLY CODE - "
          "A PYTHON SCRIPT GENERATES THE SINE TABLES - MUSIC - STARS AND LOGO - 64TASS ASSEMBLES IT INTO A PRG FILE - "
          "THE VICE EMULATOR RAN THE DEMO AND SCREENSHOTS SHOWED CLAUDE WHAT IT LOOKED LIKE - "
          "THEN IT WAS TUNED UNTIL EVERY RASTER LINE FIT INTO THE FRAME ..."
          "   EFFECTS: RAINBOW RASTER BARS - COPPER BARS - WOBBLING LOGO - 3 LAYER PARALLAX STARS - SPRITE SNAKE - 3 VOICE SID TUNE"
          "   GREETS TO ALL CLOUD ENGINEERS - PULUMI CREW - DEVOPS LEGENDS - AND EVERY C64 FAN OUT THERE ...        ")

# ---------------------------------------------------------------- big logo font (3x5)
FONT = {
    'M': ["X..X", "XXXX", "XXXX", "X..X", "X..X"],
    'A': [".X.", "X.X", "XXX", "X.X", "X.X"],
    'S': ["XXX", "X..", "XXX", "..X", "XXX"],
    'T': ["XXX", ".X.", ".X.", ".X.", ".X."],
    'E': ["XXX", "X..", "XXX", "X..", "XXX"],
    'R': ["XX.", "X.X", "XX.", "X.X", "X.X"],
    'I': ["X", "X", "X", "X", "X"],
    'N': ["X..X", "XX.X", "XXXX", "X.XX", "X..X"],
    'D': ["XX.", "X.X", "X.X", "X.X", "XX."],
    'C': ["XXX", "X..", "X..", "X..", "XXX"],
    'O': ["XXX", "X.X", "X.X", "X.X", "XXX"],
    '6': ["XXX", "X..", "XXX", "X.X", "XXX"],
    '4': ["X.X", "X.X", "XXX", "..X", "..X"],
    ' ': ["..", "..", "..", "..", ".."],
}
LOGO_TEXT = "C64 DEMO"


def logo_rows():
    rows = [[0x20] * 40 for _ in range(5)]
    total = sum(len(FONT[ch][0]) + 1 for ch in LOGO_TEXT) - 1
    col = (40 - total) // 2
    for ch in LOGO_TEXT:
        w = len(FONT[ch][0])
        for r in range(5):
            for c in range(w):
                if FONT[ch][r][c] == 'X':
                    rows[r][col + c] = 0x40      # solid block glyph
        col += w + 1
    assert total <= 40, "logo too wide"
    return [v for row in rows for v in row]


# ---------------------------------------------------------------- SID music
NOTE_SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def note_freq(name, transpose=0):
    letter, rest = name[0], name[1:]
    semi = NOTE_SEMI[letter]
    if rest[0] == 'b': semi -= 1; rest = rest[1:]
    elif rest[0] == '#': semi += 1; rest = rest[1:]
    midi = 12 * (int(rest) + 1) + semi + transpose
    hz = 440.0 * 2 ** ((midi - 69) / 12.0)
    return round(hz * 16777216 / PAL_CLOCK)


CHORDS = [['C5', 'Eb5', 'G5', 'C6'], ['Ab4', 'C5', 'Eb5', 'Ab5'],
          ['Bb4', 'D5', 'F5', 'Bb5'], ['G4', 'B4', 'D5', 'G5']]          # Cm Ab Bb G
ROOTS = ['C2', 'Ab1', 'Bb1', 'G1']
BASSPAT = [0, '-', 1, 0, 0, '-', 1, '-', 0, '-', 1, 0, 0, 1, '-', 1]
DRUMS = [1, 0, 3, 0, 2, 0, 3, 0, 1, 0, 3, 1, 2, 0, 3, 3]                 # 1 kick 2 snare 3 hat
DRUMS_FILL = [1, 0, 3, 0, 2, 0, 3, 0, 1, 3, 2, 3, 2, 2, 2, 2]
MELODY = [
    "G5 - . G5   Eb5 - D5 C5   D5 - Eb5 -   G5 - - .",
    "Ab5 - . Ab5  G5 - F5 Eb5   F5 - G5 -    Ab5 - - .",
    "Bb5 - . Bb5  Ab5 - G5 F5   G5 - Ab5 -   Bb5 - - .",
    "D5 - G5 -    B5 - - .      A5 - G5 -    F5 - D5 -",
]
TIE, ARP = 0xFF, 0xFE


def music_tables():
    v1, v2, dr = [], [], []
    for bar in range(8):
        chord = bar % 4
        melody = MELODY[chord].split()
        for k in range(16):
            if bar < 4:
                v1.append((chord * 4, ARP))
            else:
                t = melody[k]
                if t == '-': v1.append((0, TIE))
                elif t == '.': v1.append((0, 0))
                else:
                    f = note_freq(t)
                    v1.append((f & 255, f >> 8))
            b = BASSPAT[k]
            if b == '-':
                v2.append((0, TIE))
            else:
                f = note_freq(ROOTS[chord], 12 * b)
                v2.append((f & 255, f >> 8))
            dr.append((DRUMS_FILL if chord == 3 else DRUMS)[k])
    chlo, chhi = [], []
    for ch in CHORDS:
        for n in ch:
            f = note_freq(n)
            chlo.append(f & 255)
            chhi.append(f >> 8)
    return v1, v2, dr, chlo, chhi


# ---------------------------------------------------------------- colours
# C64 palette ramps sorted by luminance
RAMPS = {
    'blue':   [0, 6, 14, 3, 1],
    'red':    [0, 9, 2, 8, 10, 7, 1],
    'green':  [0, 11, 5, 13, 1],
    'purple': [0, 6, 4, 10, 15, 1],
}


def mirrored(ramp):
    return ramp + ramp[-2:0:-1] if len(ramp) > 2 else ramp


def resample(seq, n):
    return [seq[k * len(seq) // n] for k in range(n)]


def rainbow_pattern():
    out = []
    for name in ['blue', 'red', 'green', 'purple', 'blue', 'red', 'green', 'purple']:
        out += resample(mirrored(RAMPS[name]), 32)
    return out


def bar_profile(name):
    ramp = RAMPS[name][1:]                    # no black -> every line of the bar is coloured
    return resample(ramp + ramp[-2::-1], 14)


BAND = ([0, 6, 6, 14, 14, 3, 3, 1] + [6] * 16 + [1, 3, 3, 14, 14, 6, 6, 0])
LOGO_COLORS = [2, 2, 8, 8, 7, 7, 13, 13, 5, 5, 3, 3, 14, 14, 4, 4]
SPRITE_COLORS = [1, 7, 13, 3, 14, 4, 10, 2, 8, 7, 5, 13, 3, 6, 14, 1]

# ---------------------------------------------------------------- sprite (Pulumi logo)
SPRITE_DATA = [
    0b00000000, 0b01111110, 0b00000000,
    0b00000000, 0b11111111, 0b00000000,
    0b00000000, 0b01111110, 0b00000000,
    0b00001111, 0b00000000, 0b11110000,
    0b00011111, 0b10000001, 0b11111000,
    0b00011111, 0b00000000, 0b11111000,
    0b11000000, 0b01111110, 0b00000011,
    0b11110000, 0b11111111, 0b00001111,
    0b11111000, 0b01111110, 0b00011111,
    0b01111011, 0b10111101, 0b10011110,
    0b00111011, 0b11000011, 0b11011100,
    0b00011011, 0b11100111, 0b11011000,
    0b01100011, 0b11100111, 0b11000110,
    0b11110001, 0b11100111, 0b00001111,
    0b11111000, 0b01100110, 0b00011111,
    0b01111011, 0b10000001, 0b11011110,
    0b00111011, 0b11100111, 0b11011100,
    0b00000011, 0b11100111, 0b11000000,
    0b00000011, 0b11100111, 0b11000000,
    0b00000001, 0b11100111, 0b00000000,
    0b00000000, 0b00000000, 0b00000000,
    0,  # pad to 64
]


# ---------------------------------------------------------------- emit
class Inc:
    def __init__(self):
        self.lines = ["; generated by build_demo.py - do not edit"]

    def table(self, name, values, align=False, per_line=16):
        if align:
            self.lines.append("        .align $100")
        vals = [int(v) & 0xFF for v in values]
        self.lines.append(f"{name}")
        for i in range(0, len(vals), per_line):
            chunk = ",".join(f"${v:02x}" for v in vals[i:i + per_line])
            self.lines.append(f"        .byte {chunk}")

    def const(self, name, value):
        self.lines.append(f"{name} = {value}")

    def write(self, path):
        with open(path, "w") as f:
            f.write("\n".join(self.lines) + "\n")


def sine256(amp=127.5, mid=127.5, phase=0.0, periods=1):
    return [int(round(mid + amp * math.sin(2 * math.pi * periods * i / 256 + phase))) for i in range(256)]


def generate():
    inc = Inc()

    # sine / rainbow / wobble tables
    inc.table("sintab", sine256(), align=True)
    inc.table("pat", rainbow_pattern(), align=True)
    inc.table("bpos", sine256(amp=33, mid=33), align=True)
    inc.table("wob", [0xC8 + int(round(2.5 + 2.5 * math.sin(2 * math.pi * i / 64))) for i in range(128)])
    inc.table("prof", bar_profile('blue') + bar_profile('red') + bar_profile('green'))
    inc.table("band", BAND)
    inc.table("ctab", LOGO_COLORS)
    inc.table("sprcol", SPRITE_COLORS)
    inc.table("sprbit", [1, 2, 4, 8, 16, 32])

    # sprite path (figure eight), reg X 24..296, top Y inside the bar zone
    xs = [int(round(160 + 136 * math.sin(2 * math.pi * t / 256))) for t in range(256)]
    ys = [int(round(151 + 18 * math.sin(2 * math.pi * 2 * t / 256 + math.pi / 2))) for t in range(256)]
    inc.table("pxlo", [x & 255 for x in xs], align=True)
    inc.table("pxhi", [x >> 8 for x in xs], align=True)
    inc.table("pyy", ys, align=True)

    # screen row tables
    inc.table("crlo", [(0xD800 + (3 + r) * 40) & 255 for r in range(5)])
    inc.table("crhi", [(0xD800 + (3 + r) * 40) >> 8 for r in range(5)])

    # starfield: 3 parallax layers, each layer owns a band of screen rows (static colour ram)
    rnd = random.Random(64)
    bands = {1: (10, 12), 2: (13, 16), 3: (17, 19)}
    per_layer = 8
    sadlo, sadhi, scol, ssub, sspd, sgb = [], [], [], [], [], []
    for spd in (1, 2, 3):
        for _ in range(per_layer):
            row = rnd.randint(*bands[spd])
            col = rnd.randint(0, 39)
            addr = 0x0400 + row * 40 + col
            sadlo.append(addr & 255)
            sadhi.append(addr >> 8)
            scol.append(col)
            ssub.append(rnd.randint(0, 7))
            sspd.append(spd)
            sgb.append(0x60 + (spd - 1) * 8)
    inc.const("NSTARS", 3 * per_layer)
    inc.table("sadlo", sadlo)
    inc.table("sadhi", sadhi)
    inc.table("scol", scol)
    inc.table("ssub", ssub)
    inc.table("sspd", sspd)
    inc.table("sgb", sgb)
    glyphs = []
    for spd in (1, 2, 3):
        prow = {1: 1, 2: 4, 3: 6}[spd]
        for s in range(8):
            g = [0] * 8
            width = {1: 1, 2: 2, 3: 3}[spd]                # far = dot, middle = 2px, near = 3px streak
            b = 0
            for k in range(width):
                if s + k < 8:
                    b |= 0x80 >> (s + k)
            g[prow] = b
            glyphs += g
    inc.table("stars", glyphs)
    inc.table("uscore", [0, 0, 0, 0, 0, 0, 0xFF, 0xFF])

    # text / logo / sprite
    inc.table("logo", logo_rows())
    t1 = screen_codes(TITLE1)
    t2 = screen_codes(TITLE2)
    inc.const("T1LEN", len(t1))
    inc.const("T1POS", (40 - len(t1)) // 2)
    inc.const("T2LEN", len(t2))
    inc.const("T2POS", (40 - len(t2)) // 2)
    inc.table("title1", t1)
    inc.table("title2", t2)
    inc.table("scrtext", screen_codes(SCROLL) + [0xFF])
    inc.table("sprite", SPRITE_DATA[:63] + [0])

    # music
    v1, v2, dr, chlo, chhi = music_tables()
    inc.table("v1lo", [a for a, _ in v1])
    inc.table("v1hi", [b for _, b in v1])
    inc.table("v2lo", [a for a, _ in v2])
    inc.table("v2hi", [b for _, b in v2])
    inc.table("drm", dr)
    inc.table("chlo", chlo)
    inc.table("chhi", chhi)
    inc.table("dwave", [0x00, 0x10, 0x80, 0x80])
    inc.table("dfhi", [0x00, 0x0E, 0x28, 0xB0])
    inc.table("dad", [0x00, 0x05, 0x04, 0x01])
    inc.table("kickhi", [0x00, 0x0E, 0x0A, 0x06, 0x04])

    inc.write(os.path.join(HERE, "demo_data.inc"))


def main():
    generate()
    tass = shutil.which("64tass")
    if not tass:
        sys.exit("64tass not found - install with: brew install tass64")
    out = os.path.join(HERE, "demo.prg")
    cmd = [tass, "--cbm-prg", "-a", "-C", "-Wall", "-o", out, os.path.join(HERE, "demo.asm")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        sys.exit(r.returncode)
    print(f"Created demo.prg ({os.path.getsize(out)} bytes)")
    print("Run: x64sc -autostart demo.prg")


if __name__ == "__main__":
    main()
