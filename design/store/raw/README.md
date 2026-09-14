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

Set the phone up once, before the first shot:

- **Eight to twelve targets** with rules, so no list looks like a first run.
- **One app closed right now** with a window later today (frame 1).
- **One queued loosening** (frame 8) — raise a budget and save, before you begin.
- **Two or three tags paired**, named for the place each one lives (frame 3).
- **One app tiered Hazard** (frame 9), a couple tiered Essential (they seed frame 4).
- Nicknames render in the display face, system names in SF. Either is fine; use
  the same choice in all ten.

**Shoot in three passes, in this order.** The Anchor locks its own settings while
it is down — the scope chips are disabled and both leads change to "Unanchor with
your tag to change …" — so anything that needs an editable Anchor has to be shot
before it drops:

| Pass | State | Frames |
|---|---|---|
| A | Anchor up, scope **Chosen apps** | 1, 3, 5, 6, 7, 8, 9 |
| B | Drop the anchor | 2, 10 |
| C | Lift with the tag, switch scope, rebuild a short list, drop again | 4 |

Frame 1 belongs in pass A rather than beside the other Home shot: with the anchor
down, everything on its list reads as anchored, and the hero would show that
instead of the timed state the caption is about.

Pass C costs a couple of minutes and there is no way around it: switching scope
**starts the list again** and does not carry the old one over, so the "Held" list
in frame 2 and the "Stays open" list in frame 4 cannot both exist at once. Do
frame 2 first, then switch and build four apps for frame 4.

## The set

**Rebalanced 2026-09-13.** The old set gave Rules six frames and the Anchor one,
which is the app as it was before the two halves — the Anchor as a feature. It is
half the product now, so it carries half the set: frames 2, 3, 4, 5 and the shield
at 10 against 1, 6, 7, 8, 9. The first two images, which are all most people ever
see, are now one of each half with the segment visible in both.

Two frames were cut to pay for it: **Allowed windows**, because the week grid at 7
says the same thing in a better picture, and **the widget**, which is a surface
every competitor also has. It stays in the description.

**Websites was kept, and the Anchor's schedule dropped instead** (Zach's call,
2026-09-13). Websites is a differentiator most blockers do not have, and the
scheduled drop is the one Anchor frame whose work is invisible in a still — a
screenshot of a time picker does not show a phone locking itself at ten.

## What each frame wants, in order

1. **`01.png` · No unblock button.** Home on the **Rules** page, hero paged to the
   closed app. It reads "Next window", a countdown, and "opens at 8:00 PM · 30 min
   a day". "Used up today" in ember works too. The list sits below, and the
   **Rules | Anchor** segment sits in the toolbar — leave it in shot, it is doing
   the work of teaching that there are two halves.
2. **`02.png` · Locked till you tap the tag.** Swipe to the **Anchor** page with a
   tag paired, apps chosen and the anchor down. The state card reads "Anchored" in
   ember over "6 apps since 3:12 PM" with the Unanchor button; "Held" labels the
   grid below. Skip the NFC sheet; that is a system overlay.
3. **`03.png` · Any sticker will do.** Anchor page → Settings → **Tags**, with two
   or three paired and named for where they live ("Kitchen drawer", "By the door").
   The lead reads "Anchoring works without a tag. Weighing anchor needs one …" and
   names the cap of three. This frame is also what App Review asked to see, so it
   earns its slot twice.
4. **`04.png` · Everything but four.** The Anchor page again, in
   **Everything except** scope, anchored, so the label over the grid reads **Stays
   open** and the footnote reads "Everything not listed here is blocked while
   anchored." Four apps in the list is the right number: enough to read as a
   deliberate allowlist, few enough that the point lands.
5. **`05.png` · Websites, too.** Home, **+**, Website. Type an address so the button
   reads "Add reddit.com". The keyboard being up is fine and is what real use looks
   like. If you would rather not show it, the home list with a website row in it
   also fits the caption.
6. **`06.png` · Fifty-five minutes. Then it's gone.** The rule editor, scrolled so
   the **Daily budget** card sits at the top: "55 MIN for the whole day" over the
   slider, the tier card under it. The headline names the number on the slider, so
   if the budget changes, change the headline in `../board.html` with it.
7. **`07.png` · Draw the whole week.** Tap **Visualize windows** in that editor.
   The grid shows evening blocks with the later nights on Fri and Sat, and **In
   words** underneath. Do not tap a column; that opens the day editor.
8. **`08.png` · Loosening waits a day.** With the loosening you queued before you
   started, tap **1 pending** in the home toolbar. The card shows Now over Becomes,
   "Takes effect …", and Cancel change.
9. **`09.png` · The worst apps wait longest.** The same editor, scrolled so **How
   much it is worth** is centred, with Hazard selected. The card reads "The reason
   you installed Furlough." and "Loosening this one waits 4 days." at the default
   delay. Do it on TikTok or similar so the choice looks true.
10. **`10.png` · Nothing to tap but Close.** From the home screen, open an anchored
    app. iOS shows "Instagram is anchored", "Unanchor with your tag in Furlough."
    and Close. Shoot the **anchored** wording rather than the timed one: with
    frames 2 and 3 it closes the Anchor story, the key and the lock and the wall.

Frames 6, 7 and 9 are the same editor at three scroll positions. That is fine; the
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
