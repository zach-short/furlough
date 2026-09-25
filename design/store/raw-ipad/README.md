# iPad reflows

`01.png` … `10.png` here are AI reflows of the matching `../raw/NN.png`, not real iPad
captures. Same reason `../raw/` had to come off a real iPhone — Screen Time does not run in the
Simulator — but no real iPad was on hand yet, and App Store Connect demands a 13-inch iPad
screenshot set for any app with `TARGETED_DEVICE_FAMILY: "1,2"` (`project.yml:24`). This is the
stopgap for that requirement. **Settled 2026-09-24: reshoot from a real iPad when one is
available**, the same way `../raw/README.md` describes for the phone set — do not treat these as
final.

## How they were made

Each was generated from its `raw/NN.png` reference via Higgsfield (`gpt_image_2_5`, `3:4`,
quality `high`, resolution `2k`), prompted to redraw the same screen — same text, numbers,
icons, colors, typography — reflowed to fill a wider iPad-shaped canvas: wider margins, larger
cards and rows, bigger buttons, not a phone screenshot padded into a bigger frame. Output lands
at 1744×2336. The model also invented an iOS status bar with a different, wrong date on every
frame, so the top 130px is cropped off each one before saving here (1744×2206) — `board.html`
draws no status bar of its own either way (see its `.statusbar { display: none }` rule).

Quality held up well across all ten on inspection: exact text, numbers, and third-party icons
(Instagram, Snapchat, TikTok, Netflix, Bloons TD 6) reproduced correctly, real widening rather
than padding. Not pixel-verified against the real app beyond that visual check.

`board.html` shows these via each frame's `data-ipad-src` attribute, swapped in for `?device=ipad`
by the script at the bottom of the file. If a file here is ever removed, that frame falls back to
the same `.mock` CSS placeholder the iPhone frames use when `raw/NN.png` is missing.
