#!/usr/bin/env bash
# Renders design/store/board.html into the 13-inch iPad App Store screenshots (2064x2752).
# Same board as scripts/store-shots.sh, in the ?device=ipad slot added for the squarer canvas —
# see board.html's body.ipad rules for why the phone mockup itself is untouched.
#
#   ./scripts/store-shots-ipad.sh            # ten 2064x2752 frames
#   ./scripts/store-shots-ipad.sh 3          # just frame 3, while iterating
#
# Output lands in build/store-shots-ipad/ (gitignored). Upload the .jpg files: App Store Connect
# rejects images with an alpha channel, which Chrome's PNGs carry.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BOARD="file://$ROOT/design/store/board.html"
OUT="$ROOT/build/store-shots-ipad"
W=2064; H=2752

[ -x "$CHROME" ] || { echo "Google Chrome not found at $CHROME" >&2; exit 1; }
mkdir -p "$OUT"

shoot() { # <name> <query>
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --allow-file-access-from-files --force-device-scale-factor=1 \
    --virtual-time-budget=4000 --window-size="$W,$H" \
    --screenshot="$OUT/$1.png" "$BOARD?f=$2&device=ipad" >/dev/null 2>&1
  echo "  $1.png  $(sips -g pixelWidth -g pixelHeight "$OUT/$1.png" | awk '/pixel/{printf "%s ", $2}')"
}

if [ $# -gt 0 ]; then
  echo "Rendering frame $1"
  shoot "$(printf '%02d' "$1")" "$1"
else
  echo "Rendering ten frames"
  for f in $(seq 1 10); do shoot "$(printf '%02d' $f)" "$f"; done
  echo "Flattening to JPEG for upload"
  for f in $(seq -w 1 10); do
    sips -s format jpeg -s formatOptions 100 "$OUT/$f.png" --out "$OUT/$f.jpg" >/dev/null
  done
fi
echo "Done: $OUT"
