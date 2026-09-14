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

### The trial, and what shipped anyway

**Settled 2026-09-14: the set was shot inside the trial and ships that way.** Frame
8's card reads "59 min, 51 sec from now" under a caption saying a day. Zach's call,
and the right one at this size — the line is a few pixels tall inside a tilted phone
on a product page, and a week's delay to reshoot one frame costs more than it buys.
Do not "fix" it in a later pass: the mismatch is known. What is below is why, and
what to do if the set is ever reshot from scratch.

`Forgiveness` stamps `trialStartedAt` the
moment Screen Time access is granted and runs a `Furlough.trialDays` week, during
which `Config.delayHours` caps every delay at `Furlough.trialDelayHours` — one
hour. On a phone inside that week:

- frame 8's pending card lands about an hour out, not tomorrow, and the caption
  "Loosening waits a day" is then a lie in its own screenshot;
- the rule editor's consequence card reads "Your first week runs to <day>: until
  then loosening it takes 1 hour, and after it, 4 days", which is in shot for
  frames 6 and 9 and reads as a trial nobody asked about.

Frame 9's tier card is the exception and is safe either way: `UtilityPicker` builds
a fresh `Config` to price each chip, so it always prints the full delay.

A reshoot from scratch should use a phone whose access was granted more than seven
days ago. A reshoot of frame 8 alone would do it too, any time after the trial ends.

### The cast

Use the same apps throughout, so the ten read as one phone:

| App | Tier | Carries |
|---|---|---|
| Instagram | Idle | frame 1's closed hero, frame 10's shield |
| TikTok | **Hazard** | frame 9 |
| YouTube | Useful | frames 6 and 7 — the 55-minute budget and the week |
| reddit.com | — | frame 5, typed |
| Messages, Phone, Maps, Authenticator | **Essential** | frame 4's allowlist |
| X, Snapchat, Netflix, News | any | filler rows, so no list looks like a first run |

Eight to twelve targets in total. Nicknames render in the display face, system
names in SF; either is fine, but use one or the other in all ten.

### State to arrange first

- **Instagram closed right now**, with a window opening later today (frame 1).
- **One queued loosening** — raise YouTube's budget and save — made before you
  start, so it is still pending when you reach frame 8.
- **Two tags paired**, named "Kitchen drawer" and "By the front door" (frame 3).
- **Four apps tiered Essential**, which is what the everything-except scope seeds
  its allowlist from (frame 4).

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

Every quoted string below is what the screen renders, taken from the source, not a
paraphrase. If the phone says something else, the state is wrong, not the note.

### 1 · `01.png` — No unblock button.

Home, **Rules** page, anchor up.

- The **Rules | Anchor** segment sits in the title's place. Leave it in shot; it is
  the only thing in the set that says there are two halves.
- Hero paged to Instagram: eyebrow **"Next window"** in amber, a live countdown,
  and under it **"opens 8:00 PM · 30 min a day"**.
- The **"1 pending"** pill in the toolbar, from the loosening you queued. It is
  real, and it sets up frame 8.
- Four or more rows below the hero, grouped under their section labels.
- No **"Anchored"** section — that is what shooting this in pass A buys.

### 2 · `02.png` — Locked till you tap the tag.

Home, **Anchor** page, scope Chosen apps, anchor down, six things held.

- State card: the anchor glyph in ember, eyebrow **"Anchored"** in ember, and the
  state line **"6 items since 3:12 PM"** — `heldDescription` counts items, so six
  in the list is literally what it prints.
- The button on the right reads **"Unanchor"** with the wave glyph.
- Section label **"Held"**, then the apps grid.
- Footnote: **"Unanchor with your tag to change the list."**
- Not in shot: the system NFC sheet. It covers this screen whenever the reader is
  armed, so let it time out before you shoot.

### 3 · `03.png` — Any sticker will do.

Anchor page → the Settings card → **Tags**. Anchor **up**, or the lead changes.

- The row you came through reads **"Tags · Kitchen drawer · 2 of 3"**.
- Title **"Tags"**; lead begins **"Anchoring works without a tag. Weighing anchor
  needs one, so keep every tag somewhere that makes you think."** and ends with the
  cap of three.
- Two rows: **"Kitchen drawer"**, **"By the front door"**.
- Below them the placement row, then the **"Scanner"** section.
- This is also the frame App Review asked to see, so let the two named tags be
  plainly legible — that is the whole argument that the tag is not hardware.

### 4 · `04.png` — Everything but four.

Anchor page again, scope **Everything except**, anchored, four apps allowed.

- State line: **"Everything except 4 since 9:58 PM"**.
- Section label reads **"Stays open"**, not "Held" — that flip is the frame.
- Exactly four tiles: Messages, Phone, Maps, Authenticator. Four reads as a
  deliberate allowlist; more and the point goes soft.
- Footnote: **"Everything not listed here is blocked while anchored. What is listed
  keeps its own windows and budget."**

### 5 · `05.png` — Websites, too.

Home → **+** → **Website**, which opens the typed-address sheet.

- Title **"Add a website"**, lead **"Type the address. Furlough blocks it and every
  subdomain outside its hours, in every browser on this phone."**
- Type `reddit.com` so the button reads **"Add reddit.com"** — it takes the host
  from what you typed, so an empty field just says "Add".
- The card underneath, **"Want a daily time limit on a site?"**, should be in shot:
  it is the honest half of the caption.
- The keyboard being up is fine and is what real use looks like.

### 6 · `06.png` — Sixty minutes. Then it's gone.

YouTube's rule editor, scrolled so **DAILY BUDGET** sits at the top.

- **"60"** with **MIN** beside it, and **"for the whole day"** on the right.
- The slider knob on the 60 tick; ticks read 5, 30, 60, 120, 240.
- **HOW MUCH IT IS WORTH** below it with **Useful** selected.
- The headline names the number on the slider. If you shoot a different budget,
  change the headline in `../board.html` to match.

### 7 · `07.png` — Draw the whole week.

**Visualize windows**, from that same editor.

- Seven columns, evening blocks down them: Sun–Thu 8:00–10:00 PM, and Fri–Sat
  running 8:00 PM to 2:00 AM so those two columns are visibly longer.
- **In words** underneath.
- Do not tap a column; that opens the day editor.

### 8 · `08.png` — Loosening waits a day.

The **"1 pending"** pill in Home's toolbar.

- The card shows **"Now"** over **"Becomes"**, then **"Takes effect <date> at
  <time> · in 1 day from now"**, then **"Cancel change"**.
- The relative half of that line is the trial tell. The shipped capture says
  "59 min, 51 sec from now" because the phone was in its first week; see the note
  at the top. Known, accepted, not a defect to re-raise.

### 9 · `09.png` — The worst apps wait longest.

TikTok's rule editor, scrolled so **HOW MUCH IT IS WORTH** is centred.

- **Hazard** selected of the four chips.
- Under them, **"The reason you installed Furlough."**
- Then **"Loosening this one waits 4 days."** — Hazard is four times the 24-hour
  base, and the picker prices it off a fresh config, so this reads 4 days whatever
  the phone's own delay is set to.
- Do it on TikTok rather than something harmless, so the choice looks true.

### 10 · `10.png` — Nothing to tap but Close.

From the home screen, open Instagram while the anchor is down.

- iOS shows **"Instagram is anchored"** over **"Unanchor with your tag in
  Furlough."**, and **Close**.
- Shoot the anchored wording, not the timed one. With frames 2 and 3 this closes
  the Anchor story: the key, the lock, the wall.

Frames 6, 7 and 9 are the same editor at three positions. That is fine; the frame
around each phone carries the difference.

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
