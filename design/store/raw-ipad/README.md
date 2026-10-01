# iPad reflows

`01.png` through `10.png` here are AI reflows of the matching `../raw/NN.png` phone captures, not
real iPad captures. They are the source images for the 13-inch iPad half of the App Store
screenshot set, and they are a stopgap.

The phone set had to come off a real iPhone because Screen Time does not run in the Simulator
(see `../raw/README.md`). No real iPad was on hand for the same job. App Store Connect still
demands a 13-inch iPad screenshot set for any app that targets iPad, and all five iOS targets in
`project.yml` do: each sets `TARGETED_DEVICE_FAMILY: "1,2"` (first at `project.yml:106`). The
project-level value on line 25 is `"1"`, but the target-level values win, so edit those.

**Settled 2026-09-24: reshoot from a real iPad when one is available**, the same way
`../raw/README.md` describes for the phone set. Do not treat these ten files as final.

## How they were made

Each file was generated from its `raw/NN.png` reference with Higgsfield (`gpt_image_2_5`, `3:4`,
quality `high`, resolution `2k`). The prompt asked for the same screen redrawn with the same text,
numbers, icons, colors and typography, reflowed to fill a wider iPad-shaped canvas: wider margins,
larger cards and rows, bigger buttons, not a phone screenshot padded into a bigger frame. The
output was 1744x2336.

The model also drew an iOS status bar with a different, wrong date on every frame, so the top
130px was cropped off each one. The first render then showed header buttons touching the top edge
of the device, so 70px of matched-color padding was added back on top. The files here are
therefore 1744x2276, and their first 70 rows are flat color. `board.html` draws no status bar of
its own either way (its `.statusbar` rule is `display: none`).

On visual inspection the quality held across all ten: the text, the numbers and the third-party
icons (Instagram, Snapchat, TikTok, Netflix, Bloons TD 6) came out correct, and the layout is
widened, not padded. Nothing was checked pixel by pixel against the real app.

## How they are used

`board.html` shows these files when it is opened with `?device=ipad`. Each frame's `<img>` has a
`data-ipad-src="raw-ipad/NN.png"` attribute, and the script at the bottom of the file swaps it in
for the `src` of the phone capture. The image fills the redrawn iPad screen with
`object-fit: cover`. If a file here is removed, the frame falls back to the same `.mock` CSS
placeholder the iPhone frames use when `raw/NN.png` is missing.

These files are inputs, not the upload. They are 1744x2276, and App Store Connect wants 2064x2752
for the 13-inch slot. Render the board to get the upload set:

```bash
./scripts/store-shots-ipad.sh
```

That writes ten `.png` and ten `.jpg` frames into `build/store-shots-ipad/` (gitignored). Upload
the `.jpg` files, because App Store Connect rejects images with an alpha channel. A first upload
from this folder instead of from `build/store-shots-ipad/` failed with a dimension mismatch.

## Replacing them with real captures

When a real iPad is available, take the ten screenshots the way `../raw/README.md` lays out for
the phone, save them here as `01.png` through `10.png` over the reflows, and run
`./scripts/store-shots-ipad.sh` again. Rewrite this README at that point, because the sections
above describe the reflows.
