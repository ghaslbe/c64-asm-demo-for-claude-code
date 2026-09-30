#!/bin/bash
# Build the self-playing test version and take screenshots in the VICE emulator.
# Usage: ./test.sh [cycles ...]     (default: 8M 20M 60M cycles = start, playing, later)
set -e
cd "$(dirname "$0")"
python3 build.py --autoplay
command -v x64sc >/dev/null || { echo "x64sc (VICE) not found: brew install vice"; exit 1; }
CYCLES=("$@")
[ ${#CYCLES[@]} -eq 0 ] && CYCLES=(8000000 20000000 60000000)
for c in "${CYCLES[@]}"; do
    out="test_${c}.png"
    x64sc -console -warp -autostartprgmode 1 -limitcycles "$c" \
        -exitscreenshot "$out" -autostart brickstorm_auto.prg >/dev/null 2>&1 || true
    [ -f "$out" ] && echo "screenshot: $out" || echo "WARNING: $out not created"
done
