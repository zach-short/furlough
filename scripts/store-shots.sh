#!/usr/bin/env bash
# Renders design/store/board.html into App Store screenshots.
#
#   ./scripts/store-shots.sh            # six 1320x2868 frames + the panorama
#   ./scripts/store-shots.sh 3          # just frame 3, while iterating
#
# Output lands in build/store-shots/ (gitignored). Upload the .jpg files:
# App Store Connect rejects images with an alpha channel, and Chrome's PNGs
# carry one, so each frame is flattened to JPEG at quality 100.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BOARD="file://$ROOT/design/store/board.html"
OUT="$ROOT/build/store-shots"
W=1320; H=2868

[ -x "$CHROME" ] || { echo "Google Chrome not found at $CHROME" >&2; exit 1; }
mkdir -p "$OUT"

shoot() { # shoot <name> <width> <height> <query>
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --allow-file-access-from-files --force-device-scale-factor=1 \
    --virtual-time-budget=4000 --window-size="$2,$3" \
    --screenshot="$OUT/$1.png" "$BOARD?f=$4" >/dev/null 2>&1
  echo "  $1.png  $(sips -g pixelWidth -g pixelHeight "$OUT/$1.png" | awk '/pixel/{printf "%s ", $2}')"
}

if [ $# -gt 0 ]; then
  echo "Rendering frame $1"
  shoot "$(printf '%02d' "$1")" $W $H "$1"
else
  echo "Rendering six frames"
  for f in 1 2 3 4 5 6; do shoot "$(printf '%02d' $f)" $W $H "$f"; done
  echo "Rendering the panorama (review only, not for upload)"
  shoot panorama $((W * 6)) $H all
  echo "Flattening to JPEG for upload"
  for f in 01 02 03 04 05 06; do
    sips -s format jpeg -s formatOptions 100 "$OUT/$f.png" --out "$OUT/$f.jpg" >/dev/null
  done
fi
echo "Done: $OUT"
