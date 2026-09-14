#!/usr/bin/env python3
"""Removes the iOS status bar from the raw App Store captures, in place.

    ./scripts/strip-status-bar.py                 every design/store/raw/NN.png
    ./scripts/strip-status-bar.py raw/03.png …    just these

The clock, the silent-mode bell, the signal and Wi-Fi glyphs and a charging battery
at 72% are the phone's business, not the product's, and they differ in every capture
of a set that is meant to read as one phone. Apple asks for no status bar and the
device frame in `design/store/board.html` draws no notch, so the honest thing is to
take it off.

Rather than paint a flat band over it — which seams the moment a capture's top is not
flat, and only frames 3, 6 and 10 are — each row above the bar is replaced with a copy
of the first row of real background below it. Horizontal variation is kept, so a lit
wall still reads correctly; only vertical variation over those few hundred pixels is
lost, and there is none worth keeping in a status bar's worth of wall.

The copied row is then blurred sideways. Behind a sheet (frame 7 is the week grid over
a blurred YouTube) that row crosses real shapes, and stretching it unblurred smears the
app icon into a hard-edged red bar up the corner. A wide blur turns the same pixels
into the soft wash that region already looks like, and does nothing at all where the
row was flat to begin with.

Idempotent: a capture that has already been stripped has a flat band at the top, so
the source row is found in the same place and copied over identical pixels.

Needs Pillow, which is already on this machine (`python3 -c "import PIL"`).
"""

import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "design" / "store" / "raw"

# The status bar and the Dynamic Island both sit inside the top 8% of an iPhone 17 Pro
# capture (1206x2622): the island ends near y=140, the first app chrome — Home's gear
# pill — starts near y=198. Search between them for a row of pure background.
SEARCH_TOP = 0.055
SEARCH_BOTTOM = 0.072
# A glyph is much brighter than any wall Furlough draws; the lit end of the ember glow
# tops out around 40.
GLYPH = 70


def source_row(im: Image.Image) -> int:
    """The topmost row in the search band carrying no status-bar glyph."""
    w, h = im.size
    lo, hi = int(h * SEARCH_TOP), int(h * SEARCH_BOTTOM)
    px = im.load()
    for y in range(lo, hi):
        # The clock sits left, the battery right; the island spans the middle. Sample
        # the whole row rather than guessing where each lives.
        if max(max(px[x, y][:3]) for x in range(0, w, 4)) < GLYPH:
            return y
    # Nothing clean in the band: fall back to its bottom rather than guess wrong.
    return hi


def strip(path: Path) -> str:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    y = source_row(im)
    band = im.crop((0, y, w, y + 1)).resize((w, y), Image.NEAREST)
    band = band.filter(ImageFilter.GaussianBlur(w / 16))
    im.paste(band, (0, 0))
    im.save(path)
    return f"{path.name}  {w}x{h}  cleared the top {y}px from row {y}"


def main() -> int:
    args = sys.argv[1:]
    paths = [Path(a) for a in args] if args else sorted(RAW.glob("[0-9][0-9].png"))
    if not paths:
        print(f"No captures in {RAW}", file=sys.stderr)
        return 1
    for p in paths:
        if not p.exists():
            print(f"missing: {p}", file=sys.stderr)
            return 1
        print(" ", strip(p))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
