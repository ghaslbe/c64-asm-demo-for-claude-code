#!/bin/bash
# Test C64 demo in VICE emulator (headless-ish mode)
# Runs in warp mode and captures a screenshot

set -e

DEMO="${1:-demo.prg}"
SCREENSHOT="${2:-screenshot.png}"
CYCLES="${3:-45000000}"  # loading via the emulated drive takes ~20M cycles

echo "=== C64 Demo Tester ==="
echo "Demo: $DEMO"
echo "Screenshot: $SCREENSHOT"
echo "Cycles: $CYCLES"
echo ""

# Check if demo exists
if [ ! -f "$DEMO" ]; then
    echo "ERROR: Demo file not found: $DEMO"
    exit 1
fi

# Build if needed
if [ "$DEMO" = "demo.prg" ]; then
    echo "Building demo..."
    python3 build_demo.py
    echo ""
fi

# Check for VICE
if ! command -v x64sc &> /dev/null; then
    echo "ERROR: VICE emulator (x64sc) not found"
    echo "Install with: brew install vice"
    exit 1
fi

echo "Running VICE emulator..."
echo "(Will run for $CYCLES cycles in warp mode, then exit)"
echo ""

# Run VICE with:
# -warp: Fast mode
# -silent: Reduce log spam
# -limitcycles: Exit after N cycles
# -exitscreenshot: Save screenshot on exit
# -autostart: Load and run the PRG
# -default: Use default settings (clean state)

# Note: This will open a window briefly, then exit
x64sc \
    -default \
    -warp \
    -silent \
    -limitcycles "$CYCLES" \
    -exitscreenshot "$SCREENSHOT" \
    -autostart "$DEMO" \
    2>&1 | grep -v "^Error" | head -20 || true

# Check if screenshot was created
if [ -f "$SCREENSHOT" ]; then
    echo ""
    echo "SUCCESS: Screenshot saved to $SCREENSHOT"
    echo "File size: $(ls -lh "$SCREENSHOT" | awk '{print $5}')"

    # On macOS, we can open the screenshot
    if command -v open &> /dev/null; then
        echo "Opening screenshot..."
        open "$SCREENSHOT"
    fi
else
    echo ""
    echo "WARNING: Screenshot not created (emulator may have exited early)"
fi

echo ""
echo "Test complete!"
