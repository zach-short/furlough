# Raw device captures

This folder holds the ten iPhone screenshots behind the App Store frames: `01.png` to `10.png`, matching the ten frames in `../board.html`. Each file is 1206x2622 (what an iPhone 17 Pro captures), was shot on a real phone on 2026-09-14, and had its status bar removed afterwards. `../board.html` draws each capture inside a device frame. If a file is missing, that frame falls back to a drawn placeholder mock. A placeholder must never reach App Store Connect, because guideline 2.3.3 requires screenshots to show the app in actual use. The mocks are stand-ins, not designs to copy, and some of them draw as a page what the app has as a card (the tier chooser lives inside the rule editor). Each frame's caption is a claim, so a capture has to show what its caption says and nothing more.

The ten shipped with version 1.2.0, which went live on the App Store on 2026-09-15 (`HANDOFF.md`, step 19). Two things have changed since then:

- On 2026-09-25 the anchored Anchor page was replaced by a minimal hero view (commit `6d2b4a3`). Frames 2 and 4 show the page as it was before that.
- The iPad set in `../raw-ipad/` was generated from these ten files, so a change to a file here leaves its iPad reflow out of date.

The quoted strings below were checked against the source on 2026-09-30 and against the ten files. Where a shipped file differs from the plan for its frame, the frame's section says so.

## Before you start

Shoot all ten in one sitting, with real time. **Do not change the phone's clock** to get 9:41 in the status bar. Furlough watches for clock changes and holds pending changes while the clock disagrees, so you would capture its clock banner instead of the screen. Real times are fine, and the status bar is removed afterwards anyway (see the last section).

### The trial, and what shipped anyway

**Settled 2026-09-14: the set was shot inside the trial and ships that way.** Frame 8's card reads "59 min, 51 sec from now" under a caption that says a day. That was Zach's call. The line is a few pixels tall inside a tilted phone on a product page, and a week's delay to reshoot one frame costs more than it buys. Do not "fix" it in a later pass: the mismatch is known. What follows is the cause, and what to do if the set is ever reshot from scratch.

`Forgiveness` stamps `trialStartedAt` the first time Screen Time access is granted and runs a `Furlough.trialDays` week (seven days). During that week `Config.delayHours` caps every delay at `Furlough.trialDelayHours`, which is one hour. On a phone inside the week:

- Frame 8's pending card lands about an hour out, not tomorrow, so the caption "Loosening waits a day" is contradicted by its own screenshot.
- The rule editor's consequence card reads "Your first week runs to <day>: until then <loosening it or removing it> takes 1 hour, and after it, <the full delay>". That is in shot for frame 6 and reads as a trial nobody asked about. Frame 9 shows the same clue as a banner, "Looser than now · takes effect <date> at <time>", with the time an hour out.

Frame 9's tier card is the exception and is safe either way. `UtilityPicker` builds a fresh `Config` from the base delay (24 hours by default) to price each chip, so it prints the full delay during the trial too.

A reshoot from scratch should use a phone whose access was granted more than seven days ago. A reshoot of frame 8 alone works any time after the trial ends.

### The cast

Use the same apps throughout, so the ten read as one phone:

| App | Tier | Carries |
|---|---|---|
| Instagram | Idle | frame 1's closed hero, frame 10's shield |
| TikTok | Hazard | frame 9 |
| YouTube | Useful | frames 6 and 7, the 60-minute budget and the week |
| reddit.com | none | frame 5, typed |
| Messages, Phone, Maps, Authenticator | Essential | frame 4's allowlist |
| X, Snapchat, Netflix, News | any | filler rows, so no list looks like a first run |

Eight to twelve targets in total. The shipped set follows this plan loosely. The apps that appear are Instagram, Snapchat, TikTok, Netflix and Bloons TD 6 (frames 1, 2, 5, 8 and 10), and frame 4's allowlist is WhatsApp, Chrome, Messages and an hourglass tile.

### State to arrange first

- Instagram closed right now, with a window opening later today (frame 1).
- One queued loosening (raise a budget and save), made before you start, so it is still pending when you reach frame 8.
- Two tags paired, named "Kitchen drawer" and "By the front door" (frame 3).
- Four apps tiered Essential, which is what the everything-except scope seeds its allowlist from (frame 4).

**Shoot in three passes, in this order.** The Anchor refuses changes to its scope and schedule while it is down (their screens say "Unanchor with your tag to change the scope." and "Unanchor with your tag to change the schedule."). So anything that needs an editable Anchor has to be shot before it drops.

| Pass | State | Frames |
|---|---|---|
| A | Anchor up, scope Chosen apps | 1, 3, 5, 6, 7, 8, 9 |
| B | Drop the anchor | 2, 10 |
| C | Lift with the tag, switch scope, rebuild a short list, drop again | 4 |

Frame 1 belongs in pass A rather than beside the other Home shot. With the anchor down, everything on its list reads as anchored, and the hero would show that instead of the timed state the caption is about.

Pass C costs a couple of minutes and there is no way around it. Switching scope starts the list again and does not carry the old one over (the confirmation says so), so the "Held" list in frame 2 and the "Stays open" list in frame 4 cannot both exist at once. Do frame 2 first, then switch and build four apps for frame 4.

## The set

**Rebalanced 2026-09-13.** The old set gave Rules six frames and the Anchor one, which is the app as it was before the two halves. The Anchor is half the product now, so it gets four frames where it had one: 2, 3 and 4, and the shield at 10. Frame 5 is a Rules screen, reached from Home. The first two images, which are all most people ever see, are now one of each half, with the Rules | Anchor bar visible in both.

Two frames were cut to pay for it: Allowed windows, because the week grid at 7 says the same thing in a better picture, and the widget, which is a surface every competitor also has. The widget stays in the description.

**Websites was kept, and the Anchor's schedule dropped instead** (Zach's call, 2026-09-13). Websites is a differentiator most blockers do not have, and the scheduled drop is the one Anchor frame whose work is invisible in a still. A screenshot of a time picker does not show a phone locking itself at ten.

`../LISTING.md` has a Screenshots section, but its caption table describes the set from before this rebalance. Read captions from `../board.html`.

## What each frame wants, in order

Every quoted string below is what the screen renders, taken from the source, not a paraphrase. Section labels such as "Held" are drawn in capitals on screen. If the phone says something else, the state is wrong, not the note.

### Frame 1, `01.png`: No unblock button.

Home, Rules page, anchor up.

- The Rules | Anchor bar floats at the bottom of the screen with Rules selected in amber. Leave it in shot. Frames 1 and 2 both carry it, which is how the first two images show two halves.
- Hero paged to Instagram: eyebrow "Next window" in amber, a live countdown, and under it "opens at 8:00 PM · 30 min a day".
- The "1 pending" pill in the toolbar, from the loosening you queued. It sets up frame 8.
- Four or more rows below the hero, grouped under their section labels.
- No "Anchored" section. That is what shooting this in pass A buys.

The shipped file has the hero, the "Open now" and "Later today" sections, and no "1 pending" pill. Frame 4 is the one with the pill.

### Frame 2, `02.png`: Locked till you tap the tag.

Home, Anchor page, scope Chosen apps, anchor down, a short list held.

- State card: the anchor glyph in ember, eyebrow "Anchored" in ember, and the state line "<n> items since <time>". `heldDescription` counts items, so the number is the length of the list.
- The button on the right reads "Unanchor" with the wave glyph.
- Section label "Held", then the apps grid.
- Footnote: "Unanchor with your tag to change the list."
- Not in shot: the system NFC sheet. It covers this screen whenever the reader is armed, so let it time out before you shoot.

The shipped file reads "5 items since 11:57 AM" over five tiles (Instagram, Snapchat, TikTok, Netflix, Bloons TD 6). Under the state card it also shows a "Hold your tag up to weigh anchor" card, and below the tiles a Settings card whose Tags row reads "Home · 1 of 3".

### Frame 3, `03.png`: Any sticker will do.

Anchor page, then the Settings card, then Tags. Anchor up: Rename, Forget and the pair row are hidden while it is down.

- The row you came through reads "Tags" with the detail "Kitchen drawer · 2 of 3" (the first tag's name and the count).
- Title "Tags". The lead begins "Anchoring works without a tag. Weighing anchor needs one, so keep every tag somewhere that makes you think." and ends with the cap: "Up to 3, so a key can live at each place you do."
- Two rows, "Kitchen drawer" and "By the front door", each with Rename and Forget, then the "Pair another tag" row.
- Below them the "Where to leave it" row (the placement help), then the "Scanner" section.
- This frame answers App Review's hardware question (see `../REVIEW-REPLIES.md`), so let the two named tags be plainly legible. That is the whole argument that the tag is not special hardware.

The shipped file has three tags ("Kitchen Drawer", "By the front door", "Nightstand"), so the card ends with "3 of 3 · forget one to pair another" in place of a pair row.

### Frame 4, `04.png`: Everything but four.

Anchor page again, scope Everything except, anchored, four apps allowed.

- State line: "Everything except 4 since <time>".
- Section label reads "Stays open", not "Held". That flip is the frame.
- Exactly four tiles. Four reads as a deliberate allowlist, and more makes the point go soft.
- Footnote: "Everything not listed here is blocked while anchored. What is listed keeps its own windows and budget."

The shipped file reads "Everything except 4 since 12:08 PM" with four tiles (an hourglass tile, WhatsApp, Chrome, Messages), not the four Essential apps in the cast table. It also shows the "1 pending" pill.

**Reshooting frames 2 and 4 on a current build.** The page described in frames 2 and 4 is gone from the source. `anchoredPane` in `Furlough/Views/AnchorView.swift` now draws a hero view: the anchor button in hero style, the eyebrow "Anchored", the state line ("<n> items since <time>", with " · lifts <time>" added when a lift time is set), and up to three pills. The pills are "View held apps" (or "View exceptions" under Everything except), "Devices" and "Lifts <time>". The list itself, titled "Held" or "Stays open", moved into a sheet behind the first pill. The settings card and the footnote are not drawn while anchored. This is read from the source and has not been seen running. Frame 4's caption depends on the four tiles, which are now only visible in that sheet, so both frames need a new plan before anyone reshoots them.

### Frame 5, `05.png`: Websites, too.

Home, then +, then Website, which opens the typed-address sheet.

- Title "Add a website", lead "Type the address. Furlough blocks it and every subdomain outside its hours, in every browser on this phone."
- Type `reddit.com` so the button reads "Add reddit.com". It takes the host from what you typed, so an empty field just says "Add".
- The card underneath, "Want a daily time limit on a site?", should be in shot. It is the honest half of the caption.
- The keyboard being up is fine and is what real use looks like. The shipped file has no keyboard.

### Frame 6, `06.png`: `Sixty minutes. Then it's gone.`

The rule editor of an app with no windows set, scrolled so DAILY BUDGET sits at the top.

- "60" with MIN beside it, and "for the whole day" on the right. With windows set, that line reads "across all windows" instead, which is why the editor has to be for an all-day rule.
- The slider knob on the 60 tick; ticks read 5, 30, 60, 120, 240.
- HOW MUCH IT IS WORTH below it, with the four tier chips.
- The headline names the number on the slider. If you shoot a different budget, change the headline in `../board.html` to match.

The plan was to have Useful selected. The shipped file has Idle selected, with "Passes the time." and "Loosening this one waits 2 days." under it. The caption names only the number, so it holds. The consequence card's trial line ("Your first week runs to Sep 21") is in this file.

### Frame 7, `07.png`: Draw the whole week.

Visualize windows, from the rule editor. The sheet is titled "Week".

- Seven columns, evening blocks down them: Sun to Thu 8:00 PM to 10:00 PM, and Fri and Sat 8:00 PM to 2:00 AM. The Fri and Sat blocks run to the bottom of their columns, and their 12 AM to 2 AM tails sit at the top of the Sat and Sun columns, so those two nights read as longer.
- In words underneath, with the same two lines.
- Do not tap a column. That opens the day editor.

The shipped file matches.

### Frame 8, `08.png`: Loosening waits a day.

The "1 pending" pill in Home's toolbar, which opens the Pending sheet.

- The card shows "Now" over "Becomes", then "Takes effect <date> at <time> · <relative time> from now", then "Cancel change".
- The relative half of that line is the trial tell. The shipped capture says "59 min, 51 sec from now" because the phone was in its first week; see the note at the top. Known, accepted, not a defect to re-raise.

The shipped card is Instagram going from 30 min/day to 1 hour/day, not YouTube as the cast table has it.

### Frame 9, `09.png`: The worst apps wait longest.

TikTok's rule editor, scrolled so HOW MUCH IT IS WORTH is centred.

- Hazard selected of the four chips.
- Under them, "The reason you installed Furlough."
- Then "Loosening this one waits 4 days." Hazard is four times the base delay, which is 24 hours by default. The picker prices it without the trial cap, so this reads 4 days during the trial and after it.
- Do it on TikTok rather than something harmless, so the choice looks true.

The shipped file matches, with a 30 min budget shown as "across all windows".

### Frame 10, `10.png`: Nothing to tap but Close.

From the home screen, open Instagram while the anchor is down.

- iOS shows "Instagram is anchored" over "Unanchor with your tag in Furlough.", and Close.
- Shoot the anchored wording, not the timed one. With frames 2 and 3 this closes the Anchor story: the key, the lock, the wall.

The shipped file matches.

Frames 6 and 9 are the same editor scrolled to two positions, and frame 7 opens from it. That is fine. The frame around each phone carries the difference.

## Getting them here

The Screen Time API does not run in the Simulator, so these have to come off a real phone. Take them on the iPhone, AirDrop them over, and convert the HEIC:

```bash
sips -s format png shot.heic --out design/store/raw/01.png
```

Any resolution works. An iPhone 17 Pro captures 1206x2622, which is smaller than the 1320x2868 upload canvas. The device frame is scaled down inside that canvas, so the capture is never upscaled.

Then remove the status bar. The script replaces the rows above the first clean row of background with a blurred copy of that row. It rewrites the files in place, it is safe to run twice, and it needs Pillow:

```bash
./scripts/strip-status-bar.py
```

Pass paths to strip only some files. Then render the frames and flatten them for upload. This needs Google Chrome at `/Applications/Google Chrome.app`:

```bash
./scripts/store-shots.sh
```

That writes `01.png` to `10.png` at 1320x2868, a `panorama.png` for review only, and `01.jpg` to `10.jpg`, all into `build/store-shots/`. Upload the JPEGs, not the PNGs: App Store Connect rejects images carrying an alpha channel. `./scripts/store-shots.sh 3` renders frame 3's PNG alone and skips the JPEG step.

To send the JPEGs to App Store Connect as the 6.9-inch iPhone set, run the upload script. It replaces whatever set the version already has, and it needs `ASC_KEY_ID` and `ASC_ISSUER_ID` exported, the `.p8` key in `~/.appstoreconnect/private_keys/`, and fastlane:

```bash
scripts/store-upload.sh
```

## Related files

- `../board.html` composes the frames. Opened in a browser it shows all ten side by side, and `?f=3` shows frame 3 alone.
- `../raw-ipad/README.md` explains the 13-inch iPad set and `scripts/store-shots-ipad.sh`, which renders it.
- `../LISTING.md` is the store listing text and the record of what was submitted.
- `../REVIEW-REPLIES.md` has the replies prepared for App Review.
