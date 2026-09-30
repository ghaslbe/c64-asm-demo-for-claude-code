# C64 Demo Project - Günther Haslbeck & Claude Code (2026)

## Overview
Commodore 64 cracktro-style demo, written in 6502 assembly (64tass) on a MacBook:
- Wobbling 3x5 block logo ("C64 DEMO") with per-line `$D016` sine and rainbow colour cycling
- Rainbow raster bars in the top/bottom border
- Three sine-driven copper bars with a 3-layer pixel-smooth parallax starfield in front
- Double-height, pixel-smooth scroller on a shaded band
- 6-sprite Pulumi snake on a figure-eight path with colour cycling
- 3-voice SID tune (PWM arpeggios/lead, bass, kick/snare/hat, filter sweep)

## Files
- `demo.asm` - the demo source (64tass syntax)
- `build_demo.py` - generates `demo_data.inc` (sine/rainbow tables, music, stars, logo, scroll text, sprite) and assembles `demo.prg`
- `demo_data.inc` - generated, git-ignored
- `demo.prg` / `demo.d64` - build outputs
- `make_d64.py` - creates `demo.d64` from `demo.prg`
- `test_demo.sh` - builds, runs VICE headless in warp mode, saves `screenshot.png`

## Games
`games/brickstorm/` contains BRICKSTORM, a Breakout game (own `build.py`, `brickstorm.asm`,
README and `test.sh`). `make_d64.py` accepts optional arguments: `make_d64.py in.prg out.d64 NAME`.

## Build
```bash
brew install tass64      # assembler, once
python3 build_demo.py    # -> demo.prg
python3 make_d64.py      # -> demo.d64 (optional)
```

## Run / test
```bash
x64sc -autostart demo.prg                     # interactive
x64sc -8 demo.d64 -keybuf 'load"*",8,1\n'     # types load (lowercase!), does not RUN
./test_demo.sh                                # screenshot after 45M cycles
```
Loading from a PRG via the emulated drive takes ~20M cycles before the demo
appears; use at least that for `-limitcycles` when taking screenshots.
`x64sc -autostart-delay <sec> -autostart demo.prg` delays the autostart.

## Technical details

### Memory map
- `$0801` BASIC stub `SYS 2064`, code at `$0810`, tables follow (must stay below `$3000`)
- `$0400` screen, `$D800` colour RAM
- `$3000` charset (ROM font copied at start, plus generated glyphs), `$3800` sprite data (pointer `$E0`)
- `$C000` copper bar line buffer (80 bytes)
- KERNAL/BASIC ROM are switched off (`$01=$35`), own IRQ/NMI vectors at `$FFFA/$FFFE`

### Charset layout
- `$00-$3F` ROM glyphs, `$40` solid block (logo), `$60-$77` star glyphs (3 layers x 8 pixel offsets)
- `$80-$BF` top halves and `$C0-$FF` bottom halves of the double-height scroller font
  (generated at start from the ROM font; `_` is code 63 and patched to an underscore)

### Raster stages (PAL, 312 lines)
Table-driven IRQ chain, each stage busy-loops over its lines and writes colours/`$D016`:
1. line 19: top border rainbow (20..50)
2. line 74: logo wobble (75..114)
3. line 130: copper bars from `BUF` (131..210), scroller band + fine scroll (211..242)
4. line 250: bottom border rainbow (251..283), then sets `fflag`

The main loop runs `logic` once per frame (after `fflag`): logo colours, bar buffer,
stars, scroller, sprites, music. Stars/bars must finish before line 131 and the
scroller before line 219 - keep an eye on the CPU budget when adding work
(roughly 5800 free cycles per frame; measured: ~2 lines of headroom).

### Zero page
`$02` frame counter, `$03` frame flag, `$04` line counter, `$05` rainbow phase,
`$06` wobble phase, `$07/$08` scroller fine scroll / `$D016` value, `$09/$0A` scroll text pointer,
`$0B-$11` music state, `$12-$14` bar phases, `$15-$19` sprite path state,
`$1A-$1F` charset generator pointers, `$20/$21` screen pointer, `$24` temp,
`$26/$27` raster stage vector, `$28` logo row.

## Modifying
- **Texts:** `TITLE1`, `TITLE2`, `SCROLL` in `build_demo.py` (uppercase; no umlauts; `_` allowed)
- **Big logo:** `LOGO_TEXT` and the 3x5 `FONT` glyphs (max 40 columns wide)
- **Music:** `CHORDS`, `ROOTS`, `BASSPAT`, `DRUMS`, `MELODY` (128 steps, 5 frames each)
- **Colours:** `RAMPS`, `LOGO_COLORS`, `BAND`, `SPRITE_COLORS`
- **Sprite:** `SPRITE_DATA` (21 rows x 3 bytes, monochrome, X/Y expanded)
- **Effects/timing:** `demo.asm`

### C64 colour codes
```
0=black, 1=white, 2=red, 3=cyan, 4=purple, 5=green,
6=blue, 7=yellow, 8=orange, 9=brown, 10=light red,
11=dark gray, 12=gray, 13=light green, 14=light blue, 15=light gray
```
