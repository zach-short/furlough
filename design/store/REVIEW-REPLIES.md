# Replies for App Review

Written 2026-09-14, while version 1.2.0 sat in `WAITING_FOR_REVIEW`. The point of writing them
before the letter arrives is that a rejection is answered the same day: Apple's clock runs on the
reply, and a reply drafted under time pressure is where a wrong claim gets made.

**How to use one.** Open App Store Connect > the version > **Resolution Center**, paste the reply,
attach nothing unless the reply says to, and send. Then, if a new build is needed, upload it and
run `scripts/store-resubmit.sh` (its header has the recipe); if the reply alone answers the letter,
Resolution Center's own reply moves the item back into review without a new build.

**Read the letter first and match it to a heading below.** Apple cites a guideline number; that is
the index. If nothing here matches, do not stretch one of these to fit — the replies work because
every sentence in them is true of this build, and a reply that overreaches earns a second letter.

**Every factual claim below was checked against the tree on 2026-09-14** and carries its citation
in the sub-bullets, which are notes to Zach and are **not** part of what gets pasted. The pasted
text is the indented block only.

---

## The one that already happened: Guideline 2.1, a demo video of the hardware

**Version 1.0 was rejected on this, 2026-09-10.** Apple asked for a video of the phone and the NFC
tag interacting, filmed together on real hardware. It is already answered: the notes now carry
`https://furloughapp.com/review/anchor` (`design/store/LISTING.md:451`), which serves a 20.4 MB
`video/mp4` and returned HTTP 200 on 2026-09-14. **If a second 2.1 letter arrives asking again**,
it means the reviewer did not find or could not play the video, and the reply is about access, not
about the feature.

> The demo video is linked in the App Review notes and is public, with no sign-in and no
> redirect: https://furloughapp.com/review/anchor
>
> It is a single take on a physical iPhone with the tag and the screen in the same frame. The tag
> is paired at 1:29, a blocked app shows the shield at 2:20, and the tag lifts it at 3:01. The
> file itself is at https://furloughapp.com/review/anchor.mp4 if the player does not load.
>
> On the hardware question: the tag is an ordinary NTAG sticker from a pack of fifty. No hardware
> ships with this app, none is sold, and the app is not paired to or dependent on any particular
> product. Furlough reads a tag's hardware identifier, in the foreground, only when the person
> taps to scan. It never writes to a tag and never reads one in the background. Any NFC tag works,
> including one the reviewer already owns.
>
> The Anchor is also optional. Every other feature — the schedules, the daily budgets, the
> shields, the delay on loosening a rule — works with no tag at all, and the app can be reviewed
> end to end without one.

- The 2026-09-13 rewrite that added the video is recorded at `design/store/LISTING.md:425-435`.
  The old section was headed "NFC IS OPTIONAL AND CANNOT BE TESTED WITHOUT HARDWARE", which reads
  as a reason not to test it; that heading is most likely what invited the letter, and it is gone.
- How the video was shot is archived at `~/Projects/archive/furlough/demo-video/DEMO-VIDEO.md`.

---

## Entitlement justification — why a Family Controls app is not a parental control

Usually arrives as **5.1.1**, **2.5.1**, or a plain request to justify
`com.apple.developer.family-controls`.

> Furlough is a self-restriction tool. One adult sets rules for the apps on their own iPhone, and
> the person choosing what to block and the person being blocked are the same person. It is not a
> parental control app, it has no parent or guardian role, and it never asks one account to
> restrict another.
>
> That is enforced by which authorization we request, not only by intent. Furlough calls
> AuthorizationCenter.shared.requestAuthorization(for: .individual). We never request
> .child. iOS refuses the individual grant to a child account or a Managed Apple ID, so the
> app cannot be pointed at someone else's device even by a user who wanted to.
>
> The entitlement is load-bearing rather than decorative: shielding an app is the entire product,
> and ManagedSettings is the only API that can do it. Without Family Controls the app has no
> feature left.
>
> The second entitlement, com.apple.developer.family-controls.app-and-website-usage, is used
> for one optional screen that reads the last 14 days of the person's own Screen Time history on
> the device and suggests a rule per app. Nothing read there leaves the phone. The app has no
> server, no accounts, no analytics, no third-party SDKs and no networking code of any kind.

- Individual authorization is real: `Furlough/Model/AppModel.swift:423`. A grep for
  `requestAuthorization` over `Furlough/` and `Shared/` on 2026-09-14 returns no `.child` call.
- Both entitlements verified present in the binary under review — build `202609140523`, read with
  `codesign -d --entitlements :-` on 2026-09-14.
- The 14 days is `UsageReader.days` (`Furlough/Model/UsageReader.swift:15`).

---

## "There is no way to unblock" read as a broken feature

Usually arrives as **2.1 Performance: App Completeness**, worded as though a button failed to
work, or as **4.2 Minimum Functionality**.

> This is intended behaviour and it is the product, not a defect.
>
> Furlough exists for people who have found that a blocker they can switch off in the moment does
> not work for them. So there is deliberately no unblock button, no pause, no break, and no
> emergency access. Anything that would grant more time waits out a delay the person chose for
> themselves in advance — the wait is visible on screen, counts down, and can be cancelled while it
> runs. Tightening a rule, by contrast, applies immediately. That asymmetry is the whole design:
> the app is slow to give and instant to take.
>
> The user is never trapped. The way out is Apple's own, always works, and takes about four taps:
>
> Settings > Screen Time > Apps with Screen Time Access > Furlough > off.
>
> That lifts every shield immediately and re-enables deleting the app. Their rules are kept, so
> turning access back on resumes where they left off. We do not hide this — it is written in the
> app's own Help, shown on the screen the user sees if they decline Screen Time access, and
> documented on our support page at https://furloughapp.com/support
>
> If the reviewer was looking at Furlough's block screen and looking for a way past it, that
> screen behaving exactly that way is the feature working correctly.

- The delay-on-loosening, apply-tightening-now rule is the engine's, in `Shared/Core/Policy.swift`.
- In-app documentation of the escape: `Furlough/Views/HelpTopics.swift:431` (the step) and `:435`
  (the "The way out" prose, which says in the app's own voice that Furlough cannot prevent it),
  plus `Furlough/Views/OnboardingView.swift:228`. On the site: `site/src/pages/support.astro:23`,
  `index.astro:318`, and three help pages.

---

## The Screen Time escape being undocumented

Usually arrives as **2.3.1** (accurate metadata) or as a safety question: can the user get out.

> The escape is documented in three places, all of them reachable without our help.
>
> In the app: Help > "If something gets stuck" names it as a step and then again under a heading
> called "The way out", and the onboarding screen shown when Screen Time access is declined tells
> the user where the switch is.
>
> On the web: https://furloughapp.com/support states it in the first section, and three of our
> help pages repeat it, including the one about the NFC tag, which says plainly that if the tag is
> lost this is how the Anchor is released.
>
> In the App Review notes for this version, under the heading "THERE IS INTENTIONALLY NO UNBLOCK
> BUTTON".
>
> We document it on purpose rather than reluctantly. An app that restricts someone at their own
> request has to be honest about its own limits: Furlough cannot prevent this and does not try to,
> and a user who believes they are locked in when they are not is worse off than one who knows
> exactly what the app can and cannot do.
>
> If the letter is about the App Store description rather than the app, we are happy to add the
> sentence to the description text — tell us the wording you would accept and we will make the
> change in this submission.

- The NFC page's version of it: `site/src/pages/help/nfc-tags.astro:96`.
- The last paragraph is deliberate: offering the metadata edit converts a 2.3.1 into a one-round
  fix instead of an argument.

---

## The usage screen showing nothing, or the all-or-nothing prompt

Not asked for in the pass-off, but the likeliest 2.3.1 after the three above, because the reviewer
is outside the EU and will therefore see the degraded path. Worth having ready.

> Both behaviours are expected, and the App Review notes describe them.
>
> The "Where your time went" step has two paths, chosen at runtime. Where iOS grants the app App &
> Website Usage data access — which Apple currently grants to App Store customers in the EU only —
> the app reads the fortnight itself and draws the cards natively. Everywhere else, only the
> sandboxed DeviceActivityReport extension ever sees a number, so the cards are remote views shown
> one at a time and "Apply" hands off to Apple's own picker. Outside the EU the second path is the
> expected one, and on a device with little Screen Time history the step may legitimately show
> nothing at all.
>
> The step is skippable — "Skip for now" — and nothing else in the app depends on it.
>
> The authorization prompt being all-or-nothing is iOS's own wording and behaviour for that
> capability, not a choice of ours and not something the app can soften. The app is built to work
> with the capability refused, and that is the ordinary case for almost every user.

- The two paths are `Furlough/Views/UsageView.swift:113-118`: `hasDataAccess` true draws
  `suggestions`; false falls to `dataAccessCard` + `tour`, and `tour` (line 343-345) hosts
  `DeviceActivityReport(.rank(position), filter: UsageReader.filter())`.
- `UsageReader.hasDataAccess(_:)` (`Furlough/Model/UsageReader.swift:47-50`) returns false below
  iOS 26.4 and for every status except `.approvedWithDataAccess`, so the degrade is the default.
- Verified by reading on 2026-09-14, not by running: this path has not been walked on a device
  with the capability refused.

---

## Before sending any of them

1. **Check the reply against the build actually in review**, not against `main`. On 2026-09-14
   those differ: the version in review is 1.2.0 on build `202609140523`, while `main` is at 1.3.0.
   A reply describing a screen that only exists in 1.3.0 is a wrong claim.
2. **Do not promise a behaviour change in Resolution Center** unless you are willing to ship it in
   this submission. A promise recorded there and not kept is the fastest way to a harder second
   review.
3. **If a new build is required**, upload it first and confirm it reaches `VALID`
   (`scripts/status.sh`), then run `BUILD=<number> scripts/store-resubmit.sh`. Attaching a build
   that is still processing fails, and re-attaching the same build restarts Apple's checks and
   makes the resubmit hang on "not ready yet" — the script's header records both.
