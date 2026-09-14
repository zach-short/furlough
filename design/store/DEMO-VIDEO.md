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

### Shoot it vertically

**Portrait, settled 2026-09-14.** Nothing in Apple's request specifies an orientation, and this is
not an App Preview — that is the clip on the product page, which has its own resolution and length
rules. This is a link a reviewer opens as evidence, so the format is ours to choose, and portrait
is the better one:

- **The subject is a portrait phone.** In take 1's 16:9 frame the phone filled about a quarter of
  the width, which is why the screen is marginal to read. Vertical, it fills the frame, and the
  "Pair this tag?" alert and the shield text go from squinting to obvious.
- **The tag gets a natural place to live**: top of frame, phone below it, hands entering from the
  bottom. It stays in shot throughout without competing for width.
- The phone's long axis and the frame's long axis finally agree, so the app is upright rather than
  lying on its side.

So put the camera **above and in front**:

| | |
|---|---|
| Camera | A second phone or a DSLR on a tripod. **Portrait** — see below. 1080p30 is plenty; 4K if it costs nothing. |
| Height | About 40–50 cm above the table top. |
| Angle | Tilted down roughly 45°, framing a square of table about 40 cm across. |
| The tag | Flat on the table, a little below centre of frame, plain face up. **It never leaves frame and never moves.** |
| The phone | Held or propped, screen toward the camera, tilted maybe 30–40° off the table — **never flat on its back**, see below. Lay it so its long axis runs *away* from the camera, not across the frame, or the app's portrait UI reads sideways for the whole video. |
| Light | One soft source from above and off to one side. Not directly behind the camera — that puts a reflection of it in the middle of the screen. |
| Screen | Brightness to maximum, **auto-brightness off** (Settings > Accessibility > Display & Text Size), Night Shift off. |
| Interruptions | Do Not Disturb on, so no banner lands on the screen mid-take. |

Rehearse the tap two or three times before you roll. The gesture you want is a slow deliberate
lower-and-hold, not a flick — a reviewer has to see the tag and the phone meet.

### The mistake to avoid, learned the hard way

**Take 1 (IMG_3924.MOV, 2026-09-14) failed on exactly one thing: the tag is never visible
touching the phone.** Everything else in it was right — the pairing, the naming, the shield, the
release, Instagram reopening — but the phone lay flat on the table, screen up, which puts its NFC
antenna face-down against the table. The only way to reach it is from behind or underneath, so in
both scans a hand comes over the phone, the tag is hidden behind it, and the next frame is a
successful read. A reviewer sees a hand and a result, never the hardware. That is precisely what
Apple's fourth bullet asks to see, so the take cannot pass however good the rest of it is.

**The phone must never lie flat screen-up.** Pick one of these instead, in order of preference:

1. **Test a front tap first.** Touch the tag to the *front* of the phone, over the Dynamic
   Island, while the scan sheet is up. The antenna sits at the top and often reads through the
   front. If it does, the shot becomes trivial and is the one to shoot: camera directly overhead
   in portrait, phone flat and filling the frame, tag lowered onto the top of the screen.
   Everything visible, everything upright, one take.
2. **Prop the phone** at about 60° on a small stand, screen to camera, and bring the tag to its
   top edge from the front, so the tag is in shot the whole way in.
3. **Lower the phone onto the tag top-edge-first**, screen toward a camera placed low and in
   front rather than overhead, so you see the screen and the tag meet.

Whichever you use, the tag has to be **in frame and unobscured at the moment of contact**, not
merely somewhere on the table.

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

## Take 2 is the one, and it needs captions burned in

**IMG_3925.MOV, 2026-09-14, 3:15, portrait — accepted.** Checked frame by frame against all four
bullets: physical device, the initial pairing with the tag visibly in contact, the whole workflow
through to Instagram reopening, and hardware and screen in the same frame at both scans. The marks
that matter, and the ones named in the review notes:

| 1:29 | The tag between your fingers on the top of the phone, **"Pair this tag?"** on screen. |
|---|---|
| 2:20 | **"Instagram is anchored / Unanchor with your tag in Furlough."** |
| 3:01 | Instagram reopening after the tag lifted the anchor. |

**Burn the captions into the picture — do not rely on the audio.** The take is narrated
throughout, which is right, but a reviewer may never hear a word of it:

- Browsers and embedded players start muted by default. A reviewer opening a link on a page can
  easily watch the whole thing in silence and conclude nothing was explained.
- App Review is staffed worldwide; the reviewer may not be a native English speaker and reads far
  more reliably than they listen.
- A sidecar `.srt` is at the mercy of the host and the player. Pixels are not.

If you auto-generate the transcript, **fix the nouns before burning it in**. Speech recognition
reliably mangles exactly the words this video exists to establish — *Furlough*, *NTAG*, *Anchor*,
*anchored* — and a reviewer reading "furlow" and "N tag" over a demo about NFC tags is worse off
than one reading nothing. Check those four by hand.

**Homebrew's ffmpeg here is built without libass**, so `-vf subtitles=…` and `-vf ass=…` both
fail with a filter-parse error — the filters simply are not in the build. Rather than rebuild
ffmpeg from source, `scripts/burn-captions.py` draws each cue to a transparent PNG with Pillow and
composites it with the core `overlay` filter, gated per cue on `between(t,start,end)`.

The transcript came from `whisper-cli` with the `large-v3-turbo` model already on this machine,
then had its product nouns corrected by hand; it is kept as `demo-captions.srt` beside this file,
because that correction is work worth not doing twice. To rebuild the burnt-in video:

```bash
whisper-cli -m ~/.local/share/whisper-models/ggml-large-v3-turbo.bin -l en -osrt -of build/demo audio.wav
./scripts/burn-captions.py IMG_3925.MOV design/store/demo-captions.srt build/demo-video.mp4
```

The output lands in `build/`, which is gitignored — 86 MB of video does not belong in the repo.

A quiet voiceover plus burnt-in captions is the belt-and-braces version, and it is what ships.

## What not to do

- **No screen recording.** It cannot show the hardware, which is the whole request.
- **No simulator.** Family Controls does not run there anyway, so nothing would shield.
- **Do not let the phone or the tag leave frame**, even between beats.
- **Do not cut during the pairing or the release.** Those are the two moments being verified.
- No music, no titles, no transitions. This is evidence, not marketing.
- Do not show a tag that looks like a product. If you film the printed puck from
  `design/anchor-puck/`, say on camera that it is a 3D-printed case around the same sticker —
  otherwise it reads as the "designated hardware" the rejection was about.

## Where it is hosted

**Live at <https://furloughapp.com/review/anchor> since 2026-09-14.** The page is
`site/src/pages/review/anchor.astro`: the video, the three timestamps above, and the paragraph
saying the tag is a commodity sticker. It carries `noindex, nofollow`, sits in no nav and no
sitemap, and needs no sign-in — which is the one thing Apple's request actually demands of a host.

**Cloudflare Pages refuses any single file over 25 MiB**, and the captioned master is 86 MiB. It
ships re-encoded at `-crf 31 -preset slow`, audio down to 64 kbps mono, which lands at **19.4 MiB**
with the phone's screen still legible — the "Pair this tag?" alert, "Kitchen drawer" and both
buttons were compared against the master frame by frame before choosing that number. Do not push
the quality lower without checking those again; the screen being readable is the point of the
video. If it ever will not fit, put the file in R2 and leave the page on Pages rather than
degrade it further.

The master stays in `build/` (gitignored). The deployed 19.4 MiB copy is committed under
`site/public/review/`, because wrangler deploys what is built from `public/` and the source
`.MOV` is not in the repo — without it a fresh clone could not rebuild the site as served.

## After

Put the URL in `design/store/LISTING.md` over the placeholder and check it took:

```bash
grep -n "PASTE THE VIDEO URL" design/store/LISTING.md
```

One hit is the warning paragraph and means you are clear; two means the block still holds the
placeholder. `scripts/store-submit.sh` refuses to run either way until it is gone.
