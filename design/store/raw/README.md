# Raw device captures

Drop phone screenshots here as `01.png` … `05.png`, matching the five frames in
`../board.html`. Each one appears inside its device frame automatically; until a
file exists, the frame falls back to a placeholder mock.

The Screen Time API does not run in the Simulator, so these have to come off a
real phone: take them on the iPhone, AirDrop them over, and convert the HEIC:

```bash
sips -s format png shot.heic --out design/store/raw/01.png
```

Any resolution works. An iPhone 17 Pro captures 1206x2622, which is smaller than
the 1320x2868 upload canvas, but the device frame is scaled down inside it, so
the capture is never upscaled. Set the phone to 9:41 with a full battery first if
you want the status bar to match the mock.
