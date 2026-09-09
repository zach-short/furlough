# Raw device captures

Drop phone screenshots here as `01.png` … `06.png`, matching the **six** frames in
`../board.html`. Each one appears inside its device frame automatically; until a
file exists, that frame falls back to a drawn placeholder mock. A placeholder must
never reach App Store Connect: guideline 2.3.3 requires screenshots to show the app
in actual use.

What each frame wants, in order:

| File | Frame | The screen to capture |
|---|---|---|
| `01.png` | No unblock button. | The home hero for an app that is currently shielded, with its hourglass and "opens at" line. |
| `02.png` | Thirty minutes. Then it's gone. | A daily budget: the editor's budget slider, or the home list showing what is left today. |
| `03.png` | Open only when you said so. | The rule editor's windows, with **Same every day** off so the per-day rows show. |
| `04.png` | Loosening waits a day. | The Pending screen with at least one queued loosening, showing the now/waiting comparison. |
| `05.png` | Locked till you tap the tag. | The Anchor screen while anchored, asking for the tag. |
| `06.png` | Nothing to tap but Close. | The shield itself. Captured from inside the blocked app, not from Furlough: open a shielded app and screenshot what iOS puts in front of it. |

The Screen Time API does not run in the Simulator, so these have to come off a real
phone: take them on the iPhone, AirDrop them over, and convert the HEIC:

```bash
sips -s format png shot.heic --out design/store/raw/01.png
```

Any resolution works. An iPhone 17 Pro captures 1206x2622, which is smaller than
the 1320x2868 upload canvas, but the device frame is scaled down inside it, so the
capture is never upscaled. Set the phone to 9:41 with a full battery first if you
want the status bar to match the mock.

Then render the frames and flatten them for upload:

```bash
./scripts/store-shots.sh
```

That writes `01.jpg` … `06.jpg` into `build/store-shots/`. Upload the JPEGs, not the
PNGs: App Store Connect rejects images carrying an alpha channel.
