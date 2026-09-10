# Raw device captures

Drop phone screenshots here as `01.png` … `10.png`, matching the **ten** frames in
`../board.html`. Each one appears inside its device frame automatically; until a
file exists, that frame falls back to a drawn placeholder mock. A placeholder must
never reach App Store Connect: guideline 2.3.3 requires screenshots to show the app
in actual use. The mocks are stand-ins, not designs to copy; some of them draw as a
page what the app has as a card (the tier chooser lives inside the rule editor).
Only the caption around the phone ships, so each capture has to show what its
caption claims, and nothing more.

## Before you start

Shoot all ten in one sitting, with real time. **Do not change the phone's clock**
to get 9:41 in the status bar: Furlough watches for clock changes and holds pending
changes while the clock disagrees, so you would capture its clock banner instead of
the screen. Real times are fine; Apple does not care.

At the moment you shoot you need two things at once:

- an app that is **closed right now**, with a window later today (frame 1);
- a **queued loosening** (frame 6).

So give one app a window that has not started yet today, and make one loosening
edit before you begin; frames 2, 9 and 10 were shot with the anchor on. Nicknames render in the
display face, system names in SF; either is fine, but use the same choice in all ten.

## What each frame wants, in order

**Reordered 2026-09-09:** the Anchor moved from ninth to second, so the two or three images most
people ever see carry both halves of the app rather than only the timed one. Everything between
shifted down by one, and the files here were renumbered to match.

1. **`01.png` · No unblock button.** Home, hero paged to the closed app. It reads
   "Next window", a countdown, and "opens at 8:00 PM · 30 min a day". "Used up
   today" in ember works too. The list sits below.
2. **`02.png` · Locked till you tap the tag.** Open the Anchor screen from its card
   on Home, with a tag paired and apps chosen, and tap Anchor. The state card reads
   "Anchored" and "6 apps since 3:12 PM" with the Unanchor button, apps grid below.
   Skip the NFC scan sheet; that is a system overlay.
3. **`03.png` · Fifty-five minutes. Then it's gone.** The rule editor, scrolled so the
   **Daily budget** card sits at the top: "55 MIN for the whole day" over the slider,
   the tier card under it. The headline names the number on the slider, so if the
   budget changes, change the headline in `../board.html` with it.
4. **`04.png` · Open only when you said so.** The top of the same editor, **Allowed
   windows**, with **Same every day** off so the day strips show. Two rows: Sun to
   Thu 8:00 to 10:00 PM, and Fri to Sat 8:00 PM to 2:00 AM as one night row. That
   is what the caption says.
5. **`05.png` · Draw the whole week.** Tap **Visualize windows** in that editor. The
   grid shows the evening blocks with the later nights on Fri and Sat, and **In
   words** underneath. Do not tap a column; that opens the day editor.
6. **`06.png` · Loosening waits a day.** Raise a budget from 30 to 45 and save, then
   tap **1 pending** in the home toolbar. The card shows Now over Becomes, "Takes
   effect …", and Cancel change.
7. **`07.png` · The worst apps wait longest.** The same editor, scrolled so **How
   much it is worth** is centred, with Hazard selected. The card reads "The reason
   you installed Furlough." and "Loosening this one waits 4 days." at the default
   delay. Do it on TikTok or similar so the choice looks true.
8. **`08.png` · Websites, too.** Home, +, Website. Type an address so the button
   reads "Add reddit.com". The keyboard being up is fine and is what real use looks
   like. If you would rather not show it, the home list with a website row in it
   also fits the caption.
9. **`09.png` · One glass, every status.** The **home screen** with the small Furlough
   widget placed, everything anchored, so it reads "Blocked · All blocked · 20 blocked
   all day · 20 anchored" with the hourglass stopped. Captured from the home screen,
   not from Furlough. Any state fits the caption; an open window would show "Open now"
   and a countdown instead.
10. **`10.png` · Nothing to tap but Close.** From the home screen, open an anchored app.
    iOS shows "Instagram is anchored", "Unanchor with your tag in Furlough." and Close.
    The timed shield fits the caption too: "Instagram opens at 8:00 PM" over "You get
    30 min per day." Together with frame 2 this is the Anchor story, the lock and then
    the wall.

Frames 3, 4 and 7 are the same editor at three scroll positions. That is fine; the
frame around each phone carries the difference.

## Getting them here

The Screen Time API does not run in the Simulator, so these have to come off a real
phone: take them on the iPhone, AirDrop them over, and convert the HEIC:

```bash
sips -s format png shot.heic --out design/store/raw/01.png
```

Any resolution works. An iPhone 17 Pro captures 1206x2622, which is smaller than
the 1320x2868 upload canvas, but the device frame is scaled down inside it, so the
capture is never upscaled.

Then render the frames and flatten them for upload:

```bash
./scripts/store-shots.sh
```

That writes `01.jpg` … `10.jpg` into `build/store-shots/`. Upload the JPEGs, not the
PNGs: App Store Connect rejects images carrying an alpha channel.
