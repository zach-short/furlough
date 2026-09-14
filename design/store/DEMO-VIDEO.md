# The App Review demo video

Version 1.0 came back on 2026-09-10 under **Guideline 2.1 — Information Needed**, asking for a
video of the NFC tag and the phone working together. This is how to shoot it. The link goes in
the `## App Review notes` block in `LISTING.md`, replacing
`[PASTE THE VIDEO URL HERE BEFORE SUBMITTING]`.

## What Apple actually asked for

Four things, in their words. Every one of them has to be visibly satisfied or the next rejection
says the same thing:

1. **The current version of the app in use on a physical Apple device, not on a simulator.**
2. **The initial pairing process** between the app and the designated hardware.
3. **The entire app workflow** with the designated hardware.
4. Filmed to show **both the designated hardware and the app running on a physical device** —
   in the same frame.

Point 4 is the one that decides the rig, and it is why a screen recording cannot pass. They have
already read the notes saying the tag is optional; they want to watch it happen.

## The framing problem, and the rig that solves it

The iPhone's NFC reader sits at the **top edge of the back**. To scan, the top of the phone has
to come down onto the tag — which naturally tips the screen away from anyone standing in front
of it. Shoot it flat-on and the screen goes dark exactly when the tag is read.

So put the camera **above and in front**:

| | |
|---|---|
| Camera | A second phone or a DSLR on a tripod. Landscape. 1080p30 is plenty; 4K if it costs nothing. |
| Height | About 40–50 cm above the table top. |
| Angle | Tilted down roughly 45°, framing a square of table about 40 cm across. |
| The tag | Flat on the table, a little below centre of frame, plain face up. **It never leaves frame and never moves.** |
| The phone | Held in your hand, screen toward the camera, tilted maybe 30–40° off the table. Bring the phone's top edge down to the tag; because the lens is above and in front, the screen stays readable right through the tap. |
| Light | One soft source from above and off to one side. Not directly behind the camera — that puts a reflection of it in the middle of the screen. |
| Screen | Brightness to maximum, **auto-brightness off** (Settings > Accessibility > Display & Text Size), Night Shift off. |
| Interruptions | Do Not Disturb on, so no banner lands on the screen mid-take. |

Rehearse the tap two or three times before you roll. The gesture you want is a slow deliberate
lower-and-hold, not a flick — a reviewer has to see the tag and the phone meet.

## Before you roll

- **Build 1.2.0 (202609140523) or newer on the device.** Apple asked for the current version, and
  that is the build now attached to the submission.
- Screen Time access granted, and a few apps already in Furlough so the app doesn't look empty.
- **Forget every paired tag** — Anchor > Settings > Tags > Forget on each. Apple asked for the
  *initial* pairing, so the app has to be in the state where it has no key. The last one warns
  "This is the last key. Anchoring is refused until you pair another"; that is expected.
- Make sure the anchor is **up** (not down) before you start.

Forgetting the tags is what makes the Anchor page show its three-step guide again, and that guide
is the single most useful thing you can put on camera. Step one reads:

> **Pair a tag** — Any NTAG sticker, or the tag that came with another blocking product. Hold it
> to the top of your phone.

That is the app itself, on screen, telling the reviewer the hardware is generic. Let it be legible
for a beat.

## The shot list

One continuous take, about two and a half minutes. If you must cut, never cut during the pairing
or during the release.

| Time | What is on camera | What must be legible or said |
|---|---|---|
| 0:00–0:12 | The bare tag, held up to the lens, turned over, set on the table. | *"This is an NTAG sticker out of a pack of ten. Nothing ships with the app — any NFC tag works."* |
| 0:12–0:25 | The phone enters frame, unlocked, Furlough opened **from the home screen**. | That this is a real device running the real app. Land on Home, then swipe to the **Anchor** half. |
| 0:25–1:00 | **The initial pairing.** The three-step guide, with "Pair a tag" live. Tap **Hold a tag up**; the button turns to **Listening…** and iOS's own scan sheet appears. Lower the phone onto the tag — **both in frame**. | The read succeeds, the alert **"Pair this tag?"** appears — *"Furlough does not know this tag. Pair it and it becomes the key…"* — type **Kitchen drawer**, tap **Pair it**. This is Apple's bullet 2; do not rush it. |
| 1:00–1:15 | Step two: choose what it holds. The + / picker, three or four apps. | The list filling in. |
| 1:15–1:25 | Step three: tap **Anchor**. | The state card flips to **Anchored** in ember, *"4 items since …"*, and the button becomes **Unanchor**. |
| 1:25–1:45 | **Prove the block.** Swipe home — keep the phone in frame — and tap Instagram. | iOS shows **"Instagram is anchored"** over **"Unanchor with your tag in Furlough."** and a lone **Close**. Tap Close. |
| 1:45–2:15 | **The release — the whole workflow closing.** Back into Furlough, Anchor page, and hold the phone to the tag again, both in frame. | The scan reads, the anchor lifts, the card reads **Free**. Then swipe home and open Instagram again: it opens normally. |
| 2:15–2:30 | The tag back in shot, alone. | *"The tag is a commodity NFC sticker. No hardware is sold with this app, and the app is not paired to any product. The Anchor is optional — everything else in Furlough works without it."* |

Narration or burnt-in captions both work. A quiet voiceover is faster to make and easier to skim,
which is what a reviewer will do.

## What not to do

- **No screen recording.** It cannot show the hardware, which is the whole request.
- **No simulator.** Family Controls does not run there anyway, so nothing would shield.
- **Do not let the phone or the tag leave frame**, even between beats.
- **Do not cut during the pairing or the release.** Those are the two moments being verified.
- No music, no titles, no transitions. This is evidence, not marketing.
- Do not show a tag that looks like a product. If you film the printed puck from
  `design/anchor-puck/`, say on camera that it is a 3D-printed case around the same sticker —
  otherwise it reads as the "designated hardware" the rejection was about.

## After

Host it where a reviewer can open it with no account: `furloughapp.com/review/anchor` on the
existing Cloudflare Pages deploy, or an unlisted YouTube link. Not Drive, not iCloud, nothing
behind a sign-in.

Then put the URL in `design/store/LISTING.md` over the placeholder and check it took:

```bash
grep -n "PASTE THE VIDEO URL" design/store/LISTING.md
```

One hit is the warning paragraph and means you are clear; two means the block still holds the
placeholder. `scripts/store-submit.sh` refuses to run either way until it is gone.
