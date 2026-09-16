# Pass-off prompts: the items after the Foqos comparison

Written 2026-09-09, ten items, and grown to twelve the same day. Each numbered section below
is a complete prompt for a fresh Claude session: paste one section, nothing else. The board
says which model to run it on, which lane it belongs to, what it waits on, and — since the
afternoon of 2026-09-09 — **whether it has already been done**, which is the first thing to
check, because most of them have. Submission to the App Store (HANDOFF step 19) is already in
progress, so item 1 is the tail of that, not the start.

## The board

**Where it stands, 2026-09-14 (evening).** Everything from 2 to 22 has landed or is settled as
no, and so have 31 and 32 (HANDOFF 47) and **27 through 30** (HANDOFF 48, one Opus session on
Zach's go-ahead, with the four calls its prompts named answered first), and **23 through 26**
(HANDOFF 49, one Fable session — **without** the go-ahead its prompts asked for: the session
was non-interactive, so each of the four calls was built on the prompt's own recommendation
and isolated to one line, and HANDOFF 49 lists them for Zach to reverse or keep). What is open
is **1**, which is Apple's to answer and not a session's. **Do not paste 23–30**: like the other
Done prompts they describe work that now exists, and a fresh session following one would build
it again. Item 23's prompt also describes the mark wrongly — the hold is measured from when the
move was first seen (`movedAt`), not from a `since` refreshed on every save — and its test
"opens on the held zone's schedule instead" was not what the tighter-of-two rule it also
specifies produces: under both zones a 10 PM New York window stays shut on Tokyo's evening and
on New York's, and opens on Tokyo's once the hold lapses. HANDOFF 49 is the truth.
Item 30's second half is settled as **no** for the phone (see its row) — the Mac's sidebar got
the filter; the phone's Rules list did not, and should not be re-proposed without a reason that
answers what HANDOFF 48 says. The record of each Done item is the HANDOFF step named in its row, which is the truth
about what was built and is fuller than the prompt that asked for it. **Do not paste a section
marked Done** — its prompt describes work that already exists, and a fresh session following it
would build it again. Read the Done prompts only as history, or where one says a later item
should revisit it.

**Item 1's own prompt went stale too, and the row is corrected above (2026-09-14, evening).** An
Opus session ran it and found that its central premise — HANDOFF 19's "nothing has been submitted
for App Store review" — had been false for five days. **Version 1.0 was submitted 2026-09-09, was
rejected 2026-09-10 under Guideline 2.1 for want of a demo video of the phone and the NFC tag on
real hardware, was answered with one, and went back in as 1.2.0, which is `WAITING_FOR_REVIEW`.**
So the prompt's steps read differently than they were written: step 1 (privacy manifest vs. label)
is verified on the manifest side against the binary actually in review and is one web-form check
on the label side; step 2's review notes were not only written but already survived a rejection
and a rewrite, and the `UsageView` degrade path it asks about is confirmed in the code; step 3's
rejection playbook was the one genuinely undone piece and is now `design/store/REVIEW-REPLIES.md`;
step 4 is correctly gated and was not attempted. **Step 5's premise is simply wrong** — item 9 did
not wait for this approval, iPad shipped in `e253fc6`, and the consequence runs the other way:
1.3.0 is `UIDeviceFamily = [1, 2]`, so **the submission after this one will demand a 13-inch iPad
screenshot set that does not exist**. That is unowned work and is not on this board. Per R5 the
prompt below is left as written rather than edited into a lie; HANDOFF 19 is the truth.

**Item 1 is approved and live, 2026-09-16** — the row above is corrected again, one paragraph
after the correction that follows it went stale in turn. Apple approved 1.2.0 and it went live
on the App Store 2026-09-15 (Apple's lookup: `currentVersionReleaseDate` `2026-09-15T23:59:07Z`).
Zach set `site/src/site.ts`'s `appStoreURL` to the live listing and redeployed the same day
(`ac3c2bb`); `design/store/LISTING.md`'s hold note is closed out there, and HANDOFF 19 carries
the close. **What is open is now step 4 alone** — rebuild the Mac in `/Applications` from
README's Release command — gated on Zach answering the testing-button question that step
asks, not on Apple. The 13-inch iPad screenshot set the *next* submission (1.3.0) will need is
still unowned and still not on this board.

**Four rows were stale until 2026-09-14** and are corrected above: 9, 14, 21 and 22 all shipped
while the board still said Open, because the sessions that built them updated `HANDOFF.md` and
not this table. 9 in particular said "gated on 1" long after it had gone without waiting. **A
status here is a claim about the working tree, so check it against the tree** — `git log` for
the files in the row, or the HANDOFF step — before taking a row's word that there is work to do.

**Where it stood, 2026-09-09**, when the first twelve were written: ten of them had landed, and
the two left were both gated on Apple — 1 waiting for the submission to be approved, and 9
waiting on 1. That is the sentence that went stale; 9 shipped in `e253fc6` regardless.

| # | Task | Status | Model | Lane | Waits on | Files it owns |
|---|------|--------|-------|------|----------|---------------|
| 1 | Land the submission, then put the Mac back on Release | **Approved and live.** 1.2.0 went live on the App Store 2026-09-15 (HANDOFF 19, corrected below). Steps 1–3 and 5 are done. What is left is step 4 alone — the Mac Release rebuild — which is no longer gated on Apple, only on Zach's testing-button call | Opus | Gated | **Zach**, for the testing-button call in step 4 | `DEPLOYMENT.md` (archive), `design/store/LISTING.md`, new `design/store/REVIEW-REPLIES.md`, `HANDOFF.md` |
| 2 | Scheduled and timed Anchor, plus Control Center and the widget button | Done — HANDOFF 24 | **Fable** | A (2nd) | 3 | `AnchorProfile`, `Policy`, `Monitoring`, `MonitorExtension`, `AnchorView`, `PhoneIntents`, `FurloughWidgets` |
| 3 | Anchor everything except an allowlist | Done — HANDOFF 13 | **Fable** | A (1st) | nothing | `AnchorProfile`, `Policy.decide`, `Decision`, `ShieldReconciler`, `AnchorView` |
| 4 | Sync the Anchor across devices | Done — HANDOFF 18 | **Fable** | A (3rd) | 2 and 3 | new `Shared/Core/AnchorSync.swift`, `AppModel`, `MacModel`, entitlements, privacy page |
| 5 | Per-weekday budgets, then rules for categories | Done — HANDOFF 11; categories **settled as no**, HANDOFF 12 | Opus, Fable reviews | B | nothing | `Rule`, `Policy`, `Monitoring`, `ActivityLimit`, `RuleEditorView`, Mac editor, `ConfigExport` |
| 6 | The record: streaks, minutes shielded, loosenings cancelled | Done — HANDOFF 25, with the fix in 29 | Opus | C | nothing | new `Shared/Core/Record.swift`, `RuntimeState`, `SettingsView`, Mac sidebar |
| 7 | Live Activity at window start | Done — HANDOFF 10 | Opus | C | nothing | `LiveActivityManager`, `MonitorExtension` |
| 8a | Help pages: blocking Safari, Settings and the App Store; what the Mac cannot reach | Done — HANDOFF 23 | Opus | D | nothing | `site/src/pages/help/` |
| 8b | Mac content filter (network extension) | Done — HANDOFF 26 | **Fable** | E | Zach's go-ahead | new `FurloughMacFilter` target, `project.yml`, `MacModel` |
| 9 | iPad | Done — `e253fc6`, shipped in 1.3.0; no HANDOFF step | Opus | Gated | was 1 approved; it went without waiting | `project.yml`, every iOS view that presents a sheet or popover |
| 10 | Write down the no-QR, no-pause decisions | Done — HANDOFF 23, in the 8a session | Opus | D | nothing | `HANDOFF.md`, `site/src/pages/help/nfc-tags.astro` |
| 11 | More companion pairs, every one confirmed | Done — HANDOFF 30 | **Sonnet** | F | nothing | `Companions.swift`, `CompanionsTests.swift`, new `design/companions-sources.md` |
| 12 | Suggested rules by hazard tier, and an audit for quality-of-life defaults like it | Done — HANDOFF 28 | Opus | G | nothing | new `Shared/Core/RuleSuggestion.swift`, `RuleEditorView`, `Tests/Core` |
| 13 | The link contract: schemas, test vectors and tables a port can be built against | Done — HANDOFF 45 and 46, both halves | Opus | H | nothing; HANDOFF 37 landed | new `protocol/`, new `Tests/Core/ProtocolFixturesTests.swift`, `HANDOFF.md` |
| 14 | Cache the token map, so the usage page's icons are instant on later visits | Done — HANDOFF 38, "half two: don't ask twice" | Opus | I | the tables-and-monograms commit on main | new `Shared/Core/TokenCache.swift`, `SharedStore`, `UsageReader`, `UsageView.load`, `AppModel.nameUnnamedTargets`, new `Tests/Core/TokenCacheTests.swift`, `HANDOFF.md` |
| 15 | Apple Watch complication and a wrist-only Drop Anchor | **Settled as no** — HANDOFF 42 | — | J | — | nothing; no target was added |
| 16 | A StandBy-friendly widget | Done — HANDOFF 42 | Opus | K | nothing | `FurloughWidgets/StatusWidget.swift` |
| 17 | Focus Filter: drop the Anchor when a Focus turns on | Done — HANDOFF 42 | Opus | L | nothing | new `Shared/Intents/AnchorFocusFilter.swift` |
| 18 | A trend view in the Mac's menu bar | Done — HANDOFF 42 | Opus | M | nothing | `FurloughMac/Views/MenuBar.swift`, `Shared/Core/Record.swift` |
| 19 | A weekly digest notification | Done — HANDOFF 42 | Opus | N | nothing | `Shared/Core/Record.swift`, `Shared/Core/PendingNotifications.swift`, `AppModel`, `MacModel`, `MonitorExtension` |
| 20 | Onboarding: where to put the tag | Done — HANDOFF 42 | Opus | O | nothing | new `Furlough/Views/TagPlacementView.swift`, `AppModel`, `RootView`, `AnchorScreens` |
| 21 | The hero phone becomes a phone you can page through | Done — `5c07425` and `b0011a1`; site only, no HANDOFF step | Opus | P | the homepage demos being on main | `site/src/components/HeroPage.astro`, `site/src/lib/hourglass.ts` |
| 22 | Drag the week grid: windows edited where they are drawn, on both apps | Done — HANDOFF 44 | Opus | Q | nothing | new `Shared/Core/WeekDraft.swift`, new `Shared/UI/WeekGrid.swift`, `Furlough/Views/WeekView.swift`, `FurloughMac/Views/MacWeekView.swift`, new `Tests/Core/WeekDraftTests.swift`, `project.yml`, `HANDOFF.md` |
| 23 | The time zone is the clock Furlough does not watch | Done — HANDOFF 49; the hold is the base delay, built on the recommendation, one property to change; the iOS wake gap is raised there, not built | **Fable** | R | nothing | `Shared/Core/Clock.swift`, `Shared/Core/Policy.swift`, `Models.swift` (`RuntimeState`), `Shared/UI/ClockBanner.swift`, new `Tests/Core/ZoneTests.swift` |
| 24 | Drop the anchor from the notification that warns you | Done — HANDOFF 49; the four moment kinds carry it, built on the proposal; rebased on 28's `NotificationKind` | **Fable** | S (1st) | nothing | new `Shared/Core/AnchorOffer.swift`, new `Furlough/Model/NotificationDelegate.swift`, `FurloughMacApp.swift`, `PendingNotifications.swift` (two lines) |
| 25 | An automation can say when the anchor lifts | Done — HANDOFF 49; a time of day, built on the recommendation | **Fable** | S (2nd) | 24, for the files only | new `Shared/Core/AnchorLift.swift`, `Shared/Intents/DropAnchorIntent.swift`, `Furlough/Views/AnchorView.swift`, new `Tests/Core/AnchorLiftTests.swift` |
| 26 | A Focus Filter for the Mac | Done — HANDOFF 49; offered and refused, since a Filter cannot be hidden per device | **Fable** | T | nothing | `Shared/Intents/AnchorFocusFilter.swift`; `project.yml` needed nothing |
| 27 | The Anchor on the Lock Screen | Done — HANDOFF 48 | Opus | U | nothing | `Shared/LiveActivity/`, `FurloughWidgets/`, `LiveActivityManager` |
| 28 | A switch for every notification, and the last five minutes counted down | Done — HANDOFF 48 | Opus | V | 24, if 24 runs first | `Shared/Core/PendingNotifications.swift`, `SettingsView`, Mac Settings, `HomeView`, `Components.swift` |
| 29 | The Mac keeps what it counts | Done — HANDOFF 48 | Opus | W | nothing | `FurloughMac/Model/Enforcer.swift`, new `Shared/Core/UsageHistory.swift`, new Mac view, `MenuBar.swift`, new `Tests/Core/UsageHistoryTests.swift` |
| 30 | The Mac grows a menu, and both apps get a way to find one app | Done — HANDOFF 48; the phone's search settled as no | Opus | X | nothing | `FurloughMac/FurloughMacApp.swift`, `MacRootView.swift`, `Furlough/Views/HomeView.swift` |
| 31 | The largest text size, audited | Done — HANDOFF 47 | **Sonnet** | Y | nothing | `Furlough/Views/*` (frames only) |
| 32 | The automations that already work, written down | Done — HANDOFF 47 | **Sonnet** | Z | nothing | `Furlough/Views/HelpTopics.swift`, `site/src/pages/help/`, `Furlough/Views/AnchorScreens.swift` |

**Two things landed that this board never planned**, so look for them in HANDOFF rather than
here: the first week with capped delays and the 15-minute undo (HANDOFF 27, the lane-f
session — it is why item 10's prompt carries a correction), and the Mac's Reset everything
going all the way back to a first run (HANDOFF 31, with the detail in its "The Mac" section).

**Item 13 was added 2026-09-10**, after HANDOFF 37 landed: the link contract as data, so a port on another platform can be built against the real record shapes and the real merge rules. It was the one open item not gated on Apple, and it landed 2026-09-14 as HANDOFF 45 and 46 — both halves, the second on the go-ahead the prompt asked for.

**Item 14 was added 2026-09-10**, the third step of the usage-page speed-up whose first two (cards drawn from the tables, letters for icons, a deadline on the token query) landed the same day: keep Screen Time's answer in the App Group store so the next visit opens on it. Small, iOS only, and it landed the same day as the first two, written up inside HANDOFF 38 rather than as a step of its own — which is why this row read Open for four days.

**Items 15 through 20 were added 2026-09-12**, from a session that was asked what else might be nice on iOS or the Mac rather than told what to build, and **all six were answered and closed the same day** — see HANDOFF 42. Five were built in one session; 15 is settled as no and should not be re-proposed without a reason that answers what is written there. Do not paste sections 15–20: like the other Done prompts they describe work that now exists, and two of them describe it wrongly. Item 16's first step ("add `.systemLarge`") rests on a false premise — StandBy scales the **small** widget and there is no StandBy family — and item 17's configurable scope was dropped on Zach's call, because applying a scope means writing `Config.anchor.scope` from a new process and could narrow the hold as easily as widen it. Both were Opus in the end rather than Fable: the Watch never happened, and the Focus Filter turned out to add no new anchor logic at all, only a fourth caller of `AnchorDrop.drop`.

**Items 21 and 22 were added 2026-09-14**, out of the session that made the homepage's demos
real — the budget slider drags, the week grid is edited by hand, the utility tiers move the
delay, the Anchor wants a held press. Both items come from the same observation: a control that
can be touched teaches what a rule is faster than a paragraph does. They are two prompts and not
one because they share no file and no language — 21 is Astro and TypeScript in `site/`, 22 is
SwiftUI in two app targets — so they ran in parallel, in their own worktrees. **Both landed the
same day they were written**: 21 as `5c07425` and `b0011a1`, 22 as HANDOFF 44. The advice that
stood here — take 22 first, it is the app rather than the page about the app — is spent.

**Items 23 through 32 were added 2026-09-14**, from a session asked what is missing from either
app rather than told what to build — the same question that produced 15–20, asked again now that
those are closed. None of them has Zach's go-ahead yet; every one names what to put to him
first. **23 is not a feature and should be read before the rest**: it is a hole in the same lock
HANDOFF step 4 closed, left open on the other axis, and it is the only item here that changes
what `Policy.decide` shields. Everything proposed was checked against the code before it was
written down, so three obvious-sounding ideas are not in the list: a tag tap already drops the
anchor as well as lifting it (`AnchorView`'s `.drop` branch), `AnchorDrop.drop` already takes an
`until` (item 25 is only about the caller that never passes one), and location- and
Focus-triggered drops already work through Shortcuts, which is why item 32 is a page rather than
a mechanism. The Watch stays settled as no.

**Lanes run in parallel with each other; tasks inside a lane run one after another.**
A, B, C, D and E can all be open at once, each in its own worktree. Inside A the order is
3, then 2, then 4, because each changes `AnchorProfile` and the next one builds on the
shape. Inside B, budgets first, categories second. C's two tasks and D's two tasks are
independent of each other, but 8a and 10 are small enough for one session.

Every lane touches `Shared/Core/Models.swift`, `Policy.swift`, `Tests/Core` and
`HANDOFF.md`, so merges will conflict a little. Keep it mechanical: each session adds its
HANDOFF note as a new numbered step at the end of "Next work", never edits a step it did
not write, and adds tests in a new file named for the feature rather than inside an
existing suite.

**Why the model column says what it says.** Fable goes wherever a mistake becomes an
unblock: anything that changes what `Policy.decide` shields, anything that writes
`Config.anchor` from a new process, anything that crosses devices, and the Mac network
extension. Opus is right for work whose failure mode is a bad screen or a missed API
rather than a hole in the lock.

## Session rules (every prompt below repeats these; they are Zach's)

**Check the model before anything else.** Every prompt below names one, and the board's Model
column says why. Compare it to your own model *first* — before reading the codebase, before
planning, before the first edit. If it matches, say so in a line and go. If it does not, either
delegate the whole prompt to a subagent with that model set, or stop and hand Zach a pass-off
prompt carrying what you have already established, naming the model it is for. Never do the work
on the wrong model, and never downgrade an assignment because the task looks small once you have
read it: the column is a safety choice, not a preference. Also in `~/.claude/CLAUDE.md`.

Read `HANDOFF.md` first, then `README.md`, then `design/DESIGN.md`. The build and test
commands, the invariants and the code map are in HANDOFF; do not re-derive them. Never run
`git commit` or `git push`. When the work is ready, run `git status --short`, then print two
bash blocks for Zach: `git add <only the files this session touched>` and
`git commit -m "<short, all lowercase>"`. No `Co-Authored-By`, no "Generated with" line.
Run `xcodegen generate` after adding a file. Keep the build free of warnings in our code.
Every change to `Shared/Core` gets tests in `Tests/Core`. Nothing can screenshot the phone,
so end with exactly what Zach should tap and what he should see, then wait for his report.
Zach is interactive: when a decision is his, ask before building it.

---

## 1. Land the submission, then put the Mac back on Release

**Model: Opus. Lane: gated on Zach. Parallel-safe with everything.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`. Session rules: never commit or push; when done, print `git add <your files>`
and a lowercase `git commit -m "..."` for Zach, with no Co-Authored-By; run `xcodegen
generate` after adding files; keep the build warning-free; you cannot see the phone, so end
with what Zach should check.

HANDOFF step 19 is the App Store submission and it is in progress. The status table lives
in `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md`; read it before
anything else and treat it as the truth about what is done. App Store Connect writes are
blocked from this session (see the memory note "ASC API access and the write block"):
when something needs an ASC write, write Zach the script and hand it over.

Do these, in order, skipping any DEPLOYMENT.md already marks done:

1. Confirm the uploaded build carries `PrivacyInfo.xcprivacy` at the root of the app and
   each `.appex`, and that the App Store privacy label says Data Not Collected. The two
   have to agree or review bounces it.
2. Write the App Review notes if they are not written. Family Controls apps are routinely
   asked for a demo video and a sentence on why the entitlement is needed. Say plainly:
   personal blocker, no parental controls, no accounts, no networking code. Note that the
   `app-and-website-usage` capability makes the authorisation prompt all-or-nothing and that
   Apple honours usage data only for EU customers; the app must work with it refused, so say
   that it does, and check `UsageView` really does degrade to the report extension path when
   `UsageReader.hasDataAccess` is false.
3. Prepare the rejection playbook: for each of the three most likely review objections
   (entitlement justification, "no way to unblock" being read as a broken feature, the
   Screen Time escape being undocumented) write the reply now, so Zach can paste it the
   same day.
4. When the build is approved: the Mac in `/Applications` is a Debug build (HANDOFF step 3
   explains why). Rebuild it with README's Release command and reinstall it. Update the
   line in HANDOFF that says it is Debug. **Ask Zach first whether he wants the testing
   button to survive**: since 2026-09-09 a Release build carries it when built with
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING_TOOLS'`, hidden behind five
   clicks on Version, so "back to Release" no longer has to mean giving up Reset everything
   — and that reset now returns the Mac to its first run (HANDOFF 31), which is worth having
   while the device pass is unfinished. A plain Release build is the right end state; which
   one he wants *today* is his call.
5. Item 9 (iPad) waits on this approval, because adding iPad to a submitted app changes
   the screenshot requirements. Leave a note in HANDOFF step 19 saying so.

Hand back: the DEPLOYMENT.md status table updated, the review notes as a file Zach can
paste, and the three replies.

---

## 2. Scheduled and timed Anchor, plus Control Center and the widget button

**Done — HANDOFF step 24.** Kept as history; do not run this prompt again.

**Model: Fable. Lane A, second. Waits on item 3 (the scope), because both edit
`AnchorProfile` and the schedule should be able to drop an everything-except anchor.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `design/DESIGN.md`. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding files; keep the build warning-free;
every `Shared/Core` change gets tests in `Tests/Core`; you cannot see the phone, so end with
what Zach should tap and see. Ask Zach before building anything marked "decide with Zach".

The Anchor today (`AnchorProfile` in `Shared/Core/Models.swift`, `AnchorView`,
`AppModel.anchor()`) is manual: tap Anchor, everything in the list is shielded, only a
paired NFC tag lifts it. This item gives it a clock, in three parts.

**Part 1, a timed drop.** `AnchorProfile.until: Date?`. "Anchor until 6 PM" drops now and
lifts by itself at 6 PM, or earlier with the tag. `Policy.decide` and `Policy.status` treat
`isAnchored && until <= now` as released; `Policy.nextTransition` includes `until`. The
monitor extension needs waking at `until`: register a non-repeating DeviceActivity whose
interval ends then (name it in `ActivityNaming`, count it in `ActivityLimit`, since it
takes one of the 20). On the callback, clear `isAnchored`, `anchoredAt`, `until`, log it,
reconcile. Decide with Zach whether the lift also needs a notification; recommend yes,
the same shape as "Window opened".

**Part 2, a scheduled drop.** `AnchorProfile.schedules: [AnchorSchedule]`, each a
minute-of-day plus a `Weekdays` set, reusing the day strip from the rule editor. At each
drop time the monitor extension anchors, with no `until` unless the schedule has one: Zach's
design is that the anchor drops itself at 10 PM on school nights and only the tag lifts it
in the morning. Register one activity per distinct drop minute (`anchor:<minute>`), the way
windows share activities across days, and let the callback check today's weekday. Nothing
can be edited while anchored, as now. **Decide with Zach**: adding a schedule while the
anchor is off is a tightening and applies at once; removing or shortening one is a
loosening. Recommend routing removals through the pending queue behind the delay, with a
new `PendingChange` case, since a schedule that can be deleted at 9:59 PM is not a
commitment. If he says no, say in HANDOFF that he said no.

**Part 3, drop from anywhere.** `DropAnchorIntent` in `Furlough/Model/PhoneIntents.swift`
works from Spotlight and Shortcuts but reaches `AppModel.shared`, which only the app has. A
Control Center control must live in the widget extension, so move the act of dropping
anchor into `Shared/Core` as one function that takes a `SharedStore` load, writes through
`SharedStore.save`, and calls `ShieldReconciler.apply`, the way the monitor extension
already works. Then: a `ControlWidget` with a `ControlWidgetButton` in `FurloughWidgets`,
a `Button(intent:)` on the medium `StatusWidget`, and the existing intent calling the same
function. Reload widget timelines after a drop. Release stays in the app behind the tag; do
not put a release on any of these surfaces.

Keep: `Policy.decide` is the only place shields are computed; every path ends in the
reconciler; the four anchor writers in HANDOFF grow to include the monitor's scheduled
drop and lift, and nothing else; the Mac is untouched here (it gets the anchor in item 4).

Tests: `Tests/Core/AnchorScheduleTests.swift` for `until` expiry, the next drop across a
week including a schedule on no days, the tightening/loosening classification of schedule
edits, and `ActivityLimit` counting the new activities. Decoding old state without the new
fields must still work.

Hand back: the three parts, the HANDOFF step, and a test list for Zach that includes
setting a drop two minutes out and watching the shield appear with the app closed.

---

## 3. Anchor everything except an allowlist

**Done — HANDOFF step 13.** Kept as history; do not run this prompt again.

**Model: Fable. Lane A, first. Waits on nothing.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `design/DESIGN.md`. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding files; keep the build warning-free;
every `Shared/Core` change gets tests in `Tests/Core`; you cannot see the phone, so end with
what Zach should tap and see. Ask Zach before building anything marked "decide with Zach".

This is HANDOFF step 13. The Anchor holds a chosen list of kinds. Add a second scope:
everything on the phone except an allowlist.

- `AnchorProfile.scope`: `.chosen` (today's behaviour, and what old stored state decodes
  to when the key is missing) or `.everythingExcept`, where `kinds` becomes the allowlist.
- `Decision` on iOS gains what ManagedSettings needs: `store.shield.applicationCategories =
  .all(except: allowedApps)` and `store.shield.webDomainCategories = .all(except:
  allowedWeb)`, plus `store.webContent.blockedByFilter = .all(except:)` for typed hosts if
  the filter policy supports it (HANDOFF step 20(c) lists the four cases; check the
  swiftinterface). `Policy.decide` fills it only while anchored under that scope; rule
  shields still apply on top. `isAnythingShielded` is true, so `denyAppRemoval` holds.
  Make the new fields testable from the macOS test bundle the way `webFilterHosts` is.
- Seed the allowlist with every target tiered Essential, and use the existing
  `Config.anchorWarning` path so anchoring everything warns about Messages and the
  authenticator the same way anchoring them singly does.
- Find out on the phone, with Zach, what `.all(except:)` does not shield (Phone, Settings,
  Clock and the like are believed exempt) and write the answer into README's limits and
  the site's Anchor help page. Do not guess it.
- `AnchorView`: a scope switch, the picker reused for the allowlist, and the Home hero
  reading "Everything except N" while anchored. `AnchorFromRulesSheet` still applies to the
  chosen scope only.
- The Mac gets nothing here; a Mac allowlist arrives with item 4, where an allowlist of
  bundle identifiers is the natural shape.

Keep: `Policy.decide` remains the only shield computation; the anchor's writers stay the
ones HANDOFF lists; `allowedApps` never contains an anchored app in the chosen scope.

Tests: `Tests/Core/AnchorScopeTests.swift` for decode fallback, the decision under each
scope, and the essential seed.

Hand back: the feature, the README limits paragraph, the HANDOFF step, and a test list.

---

## 4. Sync the Anchor across devices

**Done — HANDOFF step 18.** Kept as history; do not run this prompt again.

**Model: Fable. Lane A, third. Waits on 2 and 3, so the synced shape is final.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`. Session rules: never commit or push; when done, print `git add <your files>`
and a lowercase `git commit -m "..."` for Zach, with no Co-Authored-By; run `xcodegen
generate` after adding files; keep the build warning-free; every `Shared/Core` change gets
tests in `Tests/Core`; you cannot see the phone or the Mac's screen reliably, so end with
what Zach should do on each device and see. Ask Zach before building anything marked
"decide with Zach".

This is HANDOFF step 18. Goal: dropping anchor on either device locks both, and scanning
the tag on the phone releases the Mac too. The Mac has no NFC, so release only ever
originates on the phone. Rules cannot sync (Screen Time tokens versus bundle identifiers),
so what syncs is the anchor's **state**, never its list: `isAnchored`, `anchoredAt`,
`until`, a monotonic sequence number, and which device wrote it. Each device keeps its own
list; on the Mac that is a new anchor list of bundle identifiers and hosts, or the
everything-except allowlist from item 3, which maps to the Mac directly.

**Decide with Zach first, transport.** Two honest options, no accounts, no server of ours:

| | iCloud key-value store | Local network pairing |
|---|---|---|
| Sign-in | None shown; uses the Apple ID both devices already have | None; a one-time pairing code shown on the Mac, typed on the phone |
| Works when apart | Yes: anchor at work, the Mac at home locks | No: same Wi-Fi or peer-to-peer range only |
| Data leaves the device | To the user's own iCloud; Furlough never sees it. Apple's label rules count private iCloud storage as not collected, verify the current wording | Never; devices talk to each other only |
| Latency | Seconds to a few minutes; no push on the KV store | Under a second |
| Background drop from Shortcuts | Fine, the store queues it | Only while the app is in front; retry on next foreground |
| Code | About 150 lines and an entitlement | Network.framework listener and connection, Bonjour, TLS with a pre-shared key, a pairing screen, local-network permission strings |
| Failure | No iCloud: each device keeps its last state | Out of range: each device keeps its last state |

Recommend the key-value store first: it needs no pairing screen and the case Zach named,
the Mac at home staying locked while he is out with the phone, only works when apart.
If he wants zero cloud, build the local one; both fail closed.

Build, whichever transport: `Shared/Core/AnchorSync.swift` with a pure `AnchorSync.merge`
that takes the local profile and a remote record and returns the profile to keep (highest
sequence wins; a release is accepted only when the record says it came from a tag scan on
a phone; a remote `until` is checked against the local trusted clock, see `Clock`). The
app and `MacModel` apply merges through their existing writers and reconcile. The phone
publishes on every anchor write, including the monitor's scheduled drops. The Mac publishes
on a local drop only. Entitlement for the KV store: `com.apple.developer.ubiquity-kvstore-identifier`
on both apps in `project.yml`, with automatic signing adding iCloud to both App IDs. Update
`site/src/pages/privacy.astro` and the App Store notes: still no server, still no analytics,
but "no networking code at all" is no longer true and must not be claimed.

Keep: the Mac never writes a release; the anchor's writers stay listed in HANDOFF; a
device that cannot reach the other keeps its last state.

Tests: `Tests/Core/AnchorSyncTests.swift` for the merge rules, including a stale record, a
release from a Mac (refused), and an `until` in an untrusted clock.

Hand back: the transport chosen and why, the entitlement changes, the privacy page diff,
and a two-device test list for Zach.

---

## 5. Per-weekday budgets, then rules for categories

**Done — HANDOFF step 11**, and the categories half was settled as no (step 12). Kept as history; do not run this prompt again.

**Model: Opus to build, one Fable pass to review `Policy` and `Monitoring` before Zach
installs it. Lane B. Waits on nothing. Budgets first, categories second.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `design/DESIGN.md`. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding files; keep the build warning-free;
every `Shared/Core` change gets tests in `Tests/Core`; you cannot see the phone, so end with
what Zach should tap and see. Ask Zach before building anything marked "decide with Zach".

**Part 1, HANDOFF step 11, per-weekday budgets.** Today `Rule` has one daily budget.
Add `budgetByWeekday: [Int]?`, seven entries Sunday first, nil meaning "same every day",
and `Rule.budget(on: weekday)`. Everything that reads the budget reads today's:
`Policy.status`, `summary`, the widget's budget line, the shield copy, the Mac's counter.
`Monitoring.register` registers one `budget:<id>:<minutes>` event per distinct value, and
the monitor extension keeps the rule it already has for a threshold smaller than the
effective budget, extended to "not today's". `Rule.isTighterOrEqual` compares day by day.
Editors on both platforms: a "Same budget every day" toggle that, off, shows a
`BudgetSlider` per day; `TimeFormat.rule` needs a compact grammar such as "30 min weekdays,
2 h weekends" that falls back to "varies by day". `ConfigExport`/`ConfigImport` carry the
field with tolerant decoding. Debug-build check of `ActivityLimit`: budget events do not
count against the 20 activities, so the limit is unchanged; say so in a comment.

**Part 2, HANDOFF step 12, rules for categories. Decide with Zach before writing code.**
Today a category is an always-blocked container (`Rule.alwaysBlocked`, zero budget) and
`includeEntireCategory: true` expands a picked category into per-app targets. The proposal:
let a category carry windows and a budget like an app. ManagedSettings supports it
(`applicationCategories = .specific(_, except:)`) and DeviceActivity accepts a category in
a threshold event. Keep the per-app exception (an app inside with its own windows). The
editor stops hiding the windows card for a category, `Policy.status` answers for one, and
the shield names the category. If Zach prefers categories to stay containers, record that
in HANDOFF as settled and stop after Part 1.

Keep: pending rules are registered too; every callback is idempotent; the monitor never
trusts a threshold that is not today's.

Tests: `Tests/Core/WeekdayBudgetTests.swift` and, if built, `CategoryRuleTests.swift`.

Hand back: both parts or Part 1 plus the recorded decision, and a test list that includes
a five-minute budget on one weekday and a two-hour one on another.

---

## 6. The record: streaks, minutes shielded, loosenings cancelled

**Done — HANDOFF step 25**, with the uncounted-queue fix in step 29. Kept as history; do not run this prompt again.

**Model: Opus. Lane C. Waits on nothing. Parallel-safe with everything.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `design/DESIGN.md`. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding files; keep the build warning-free;
every `Shared/Core` change gets tests in `Tests/Core`; you cannot see the phone, so end with
what Zach should tap and see. Mac screens can be rendered to PNG with the swiftc approach
in the memory note "Verify Shared/UI drawing on the Mac with swiftc".

Foqos shows streaks and session history. Furlough should show the record of the contract:
the numbers that only a commitment device can produce. The activity log
(`SharedStore.log`) is free text and capped, so do not parse it. Add a structured, capped
record instead.

- `RuntimeState.days: [String: DayRecord]`, keyed by `Policy.dayKey`, kept for 60 days.
  `DayRecord` holds, per target id: whether the budget was spent, whether the warning fired,
  minutes the target was open by rule, and minutes anchored; and for the day: loosenings
  queued, cancelled, and landed. Written where the events already happen: the monitor's
  threshold callbacks, the reconciler at the midnight rollover, `AppModel`/`MacModel` on
  queue, cancel and land. On the Mac add the counted minutes; on the phone with iOS 26.4
  data access, `UsageReader` can add real minutes, otherwise spent/not spent is the truth
  and the copy must not pretend otherwise.
- `Shared/Core/Record.swift`, pure: days in a row with nothing spent, minutes shielded this
  week, loosenings cancelled versus landed, the longest anchor, all with `calendar:`
  parameters like `Policy`.
- Screens: a card in Settings on the phone and a sidebar section on the Mac, in the
  Ember Glass tokens from `design/DESIGN.md`, with the Geist Mono numerals. One quiet line
  on Home at most. Nothing celebratory; a streak that broke says so plainly.

Keep: `SharedStore.save` is the only writer; the record never influences `Policy.decide`;
the Debug reset clears it.

Tests: `Tests/Core/RecordTests.swift` with a pinned calendar, including a streak across a
week boundary and a day with no entries.

Hand back: the model, the two screens, PNGs of the Mac one, and a phone test list.

---

## 7. Live Activity at window start

**Done — HANDOFF step 10.** Kept as history; do not run this prompt again.

**Model: Opus. Lane C. Waits on nothing.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`. Session rules: never commit or push; when done, print `git add <your files>`
and a lowercase `git commit -m "..."` for Zach, with no Co-Authored-By; run `xcodegen
generate` after adding files; keep the build warning-free; you cannot see the phone, so end
with what Zach should tap and see.

This is HANDOFF step 10. Today a Live Activity starts only if the app is opened while a
window is open, because `LiveActivityManager` calls
`Activity.request(attributes:content:pushType:)` and only the foreground app can. Foqos's
active screen is its most praised feature; ours should reach the Lock Screen by itself.

1. Open the iOS 26.5 SDK's ActivityKit swiftinterface (under `xcrun --show-sdk-path`,
   `ActivityKit.framework/Modules/ActivityKit.swiftmodule/`) and find whether
   `Activity.request` has a scheduled start (`start:`, `startDate:` or an alert
   configuration with a date). Quote the signature in HANDOFF either way.
2. If it exists: on every `AppModel.enforce()`, request the activity for the next window
   from `Policy.nextTransition`, replacing any already scheduled, with the hourglass state
   for that window's start; the monitor extension updates and ends it at the edges as it
   does now. Cover a window that starts while the phone is locked and one that is cancelled
   by a tightening edit before it starts.
3. If it does not exist: write the limit into README's "Known limits" and make the
   "Window opened" notification's tap open the app into the window's hero, which starts
   the activity; that is the coverage.

Keep: the Live Activity draws the hourglass at the level of the last sync, never
animated; `Text(timerInterval:)` is the only thing that moves.

Hand back: the finding, the code or the documented limit, and a test list that includes a
window starting with Furlough closed.

---

## 8a. Help pages: blocking Safari, Settings and the App Store; what the Mac cannot reach

**Done — HANDOFF step 23**, in one session with item 10. Kept as history; do not run this prompt again.

**Model: Opus (Sonnet is fine). Lane D. Waits on nothing. No Xcode build needed; site is
`bun install`, `bun run build` in `site/`. Combine with item 10 in one session.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then every page under `site/src/pages/help/` to learn the voice; commit
`8ebfc95` made it one voice, keep it. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By. Use bun, never npm. A sentence on the site can be fixed the same day, which
is why this copy lives here and not in the binary.

Foqos documents a Shortcuts automation for the apps Apple's picker will not offer. Write
Furlough's equivalent and the honest limits around it.

1. A new help page, "Apps the picker will not show": Safari, Settings, the App Store,
   Phone. What Furlough already does for Safari (blocks sites by domain; with the
   everything-except Anchor from item 3, if it has landed, all of Safari's web). For
   Settings and the App Store: a Shortcuts personal automation "When Settings is opened"
   running "Go to Home Screen" and, optionally, Furlough's "Drop Anchor" action, which
   exists today. Say plainly that an automation can be deleted, so this is friction, not a
   lock, and that the one real escape stays Settings > Screen Time. Test the automation on
   the phone with Zach before publishing the steps; do not publish steps nobody has run.
2. On the Mac help page or a new one: what the Mac reads and what it cannot. Safari and
   the Chromium browsers by tab; Firefox and Safari web apps in the Dock are not covered
   (HANDOFF step 7). If item 8b lands later this paragraph changes; write it for today.
3. Link the new page from `site/src/pages/help/index.astro` and, if it belongs in the app's
   hub, from `Furlough/Views/HelpView.swift` through `Furlough.helpURL(_:)`. The path is a
   literal on both sides; `bun run build` will not catch a mismatch, so check both.

Hand back: the pages, the build output, and the automation steps Zach confirmed.

---

## 8b. Mac content filter

**Done — HANDOFF step 26.** Kept as history; do not run this prompt again.

**Model: Fable. Lane E. Waits on Zach's go-ahead and a distribution decision. Big, and
optional.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `FurloughMac/` end to end. Session rules: never commit or push; when
done, print `git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding files; keep the build warning-free;
every `Shared/Core` change gets tests in `Tests/Core`; ask Zach before building anything
marked "decide with Zach".

The Mac blocks sites by reading browser tabs through Apple Events and redirecting them
(`Browsers.snapshots()`). It misses Firefox, Safari web apps in the Dock, and any app that
loads a blocked host outside a browser. Foqos for Mac uses a content filter instead, which
catches all of that and pays for it with a system-extension approval prompt that Jamf can
block. This item adds the filter beside the tab reader, not instead of it: the reader still
draws the shield page, the filter makes the hole disappear.

**Decide with Zach first**: a `NEFilterDataProvider` system extension needs
`com.apple.developer.networking.networkextension` with `content-filter-provider-systemextension`,
and outside the Mac App Store that means Developer ID signing and notarization, which the
current `open /Applications` install does not do. Get his answer on distribution before
writing a line. If he says not yet, write the plan into HANDOFF as a step and stop.

If yes: a new `FurloughMacFilter` system-extension target in `project.yml`, activated with
`OSSystemExtensionRequest` from `MacModel` and re-checked at every launch (Foqos's own
release notes say macOS sometimes does not enable it; detect drift and say so in
Settings > Browsers, which becomes Settings > Web). The filter decides per flow from the
same `Decision.blockedHosts` the reader uses, read from the App Group, and matches hosts
with `Hosts.matches` so `m.youtube.com` follows `youtube.com`. Blocked flows fail; the
floating card still explains why, and Firefox users get the card instead of a shield page.
Count seconds toward the budget from flows only if it can be done without double-counting
what the front-app counter already sees; otherwise leave counting alone.

Keep: every block still derives from `Policy.decide`; Force Quit and the watchdog behave
as before; refusing the extension leaves the tab reader in place, so nothing regresses.

Hand back: the target, the onboarding step, and a test list covering Firefox, a Dock web
app, and the extension being refused.

---

## 9. iPad

**Model: Opus. Gated: after item 1 is approved, and after item 4 or with the no-NFC rule
below. Needs a real iPad; Family Controls does not run in the Simulator.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `design/DESIGN.md`. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding files; keep the build warning-free;
you cannot see the device, so end with what Zach should tap and see.

All five iOS targets are iPhone only (`TARGETED_DEVICE_FAMILY: "1"` in `project.yml`).
Foqos runs on iPad; Screen Time does too.

1. Set `TARGETED_DEVICE_FAMILY: "1,2"` on `Furlough`, `FurloughMonitor`, `FurloughShield`,
   `FurloughWidgets` and `FurloughReport`. Regenerate.
2. iPads have no NFC reader, so the Anchor cannot be released there. Rule: if item 4
   (sync) has landed, an iPad's anchor follows the phone's state and its own screen offers
   Drop only, never a tag. If it has not, hide the Anchor card and the intents on any device
   where `NFCTagReaderSession.readingAvailable` is false, and say why in one line. Never
   ship a lock with no key.
3. Walk every sheet and popover at iPad widths: `AddChoicePopover` becomes a real popover,
   the `.height` detent sheets, the hero pager and `HeroIndicator`, `WeekSheet` at a wide
   size, the widget families, and the report scenes. Screens are `ScrollView`s over
   `EmberWall`; the glow's placement is by proportion, check it does not sit under the
   keyboard on a landscape iPad.
4. The App Store needs 13-inch iPad screenshots, so this ships as the release after the
   first approval, not into the build under review. Note it in DEPLOYMENT.md.

Hand back: the project change, the Anchor rule chosen, a list of screens fixed, and a test
list for the iPad.

---

## 10. Write down the no-QR, no-pause decisions

**Done — HANDOFF step 23**, in the 8a session. Kept as history; do not run this prompt again.

**Model: Opus (Sonnet is fine). Lane D; do it in the item 8a session. Waits on nothing.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `site/src/pages/help/nfc-tags.astro` and `the-anchor.astro`. Session
rules: never commit or push; when done, print `git add <your files>` and a lowercase
`git commit -m "..."` for Zach, with no Co-Authored-By. Use bun, never npm.

Foqos offers QR codes as keys, and breaks, pauses, temporary access and an emergency
unblock. Furlough offers none of these on purpose, and the reasons are not written anywhere
a future session or a curious user would find them.

**Changed 2026-09-09 by the `lane-f-forgiveness` session — read HANDOFF step 27 first.**
Furlough now has two things that were not there when this prompt was written: a first week
with capped delays, and a 15-minute undo that restores the rule an edit replaced. Neither is
a break, a pause, temporary access or an emergency release, and the paragraph below has to
say *why* rather than claiming there is nothing of the kind: forgiveness that can only ever
restore the state you were already in is not a door out, and a pass count — which is what
Zach first asked for — was refused on the grounds that people hoard passes and spend them on
cravings.

1. HANDOFF, under "Settled: what Furlough is": one paragraph. No QR or barcode keys,
   because a code is a photograph away from being a copy and the tag's whole value is that
   it is somewhere else. No breaks, pauses, temporary access or emergency unblock, because
   each is an unblock with a nicer name, and the essential-tier warnings are where the
   safety lives. Date it 2026-09-09.
2. The site: a short section on the NFC tags page, "Why a tag and not a code", in the
   help pages' voice, and a line on the Anchor page saying there is no pause, with the
   Screen Time escape named as the only one, as README already does.

Hand back: the two edits and the site build output.

---

## 11. More companion pairs, every one confirmed

**Done — HANDOFF step 30**, 33 pairs grown to 83. Do not run the prompt again, but **"How to
confirm a pair" below is still the method**: any future pass uses it, and
`design/companions-sources.md` records which lookups have already been spent.

**Model: Sonnet. Lane: its own; parallel-safe with everything. Waits on nothing.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `Shared/Core/Companions.swift` and `Tests/Core/CompanionsTests.swift`.
Session rules: never run `git commit` or `git push`; when the work is ready run
`git status --short` and print two bash blocks for Zach — `git add <only the files this
session touched>` and a short all-lowercase `git commit -m "..."` — with no
`Co-Authored-By` line and no "Generated with" line. Every change to `Shared/Core` gets
tests in `Tests/Core`. Run the test check from HANDOFF before handing back.

`Companions.pairs` is the table that knows a thing is both an app and a website: YouTube
and youtube.com are one habit, so Furlough offers to make them one row with one schedule
and one budget. It carries **33 pairs**, which is too few — on the phone, 2026-09-09, most
apps Zach added offered no website at all, because they are not in here. Your job is to
grow it.

**The whole difficulty is that you must not be wrong.** A wrong bundle identifier makes the
offer never appear, which is invisible and will not be noticed for months. A wrong host is
worse: Furlough would offer to block a domain that is not the thing, and someone would
accept it and lose access to something they never meant to shut. So the bar is not "very
likely" — it is confirmed by a lookup you actually ran, this session, and pasted the answer
of. **Twenty pairs you confirmed beat fifty you remembered.** You have network access; use
it. If a lookup does not confirm something, that pair does not go in, and you say so in the
hand-back rather than quietly guessing.

### How to confirm a pair

For each candidate, run the App Store lookup and read the real answer:

```bash
curl -s "https://itunes.apple.com/search?term=duolingo&entity=software&country=us&limit=5" \
  | python3 -c "import json,sys; [print(r['trackName'],'|',r['bundleId'],'|',r.get('sellerUrl'),'|',r['artistName']) for r in json.load(sys.stdin)['results']]"
```

That returns `bundleId` from Apple, not from anybody's memory. Verified working 2026-09-09;
it reproduces entries already in the table, which is how you should sanity-check your
method before trusting it on a new one — look up Slack and confirm you get
`com.tinyspeck.slackmacgap`, which is exactly what the table already carries.

1. **The app half.** Find the result whose `trackName` *and* `artistName` are unmistakably
   the product — not a wrapper, not a clone, not a fan client. Take `bundleId` verbatim and
   **lowercase it**. This matters: `Pair.matches` normalizes the identifier it is *handed*
   but compares it against the table as written, so a capital letter in the table is an
   entry that can never match anything. The lookup returns `net.whatsapp.WhatsApp`; the
   table must say `net.whatsapp.whatsapp`.
2. **The Mac half**, where there is one. Run the same search with `entity=macSoftware`. Add
   the Mac identifier beside the iOS one when it differs — `Slack` and `Zoom` in the table
   show the shape. A Catalyst app needs nothing extra: `normalize` sheds the
   `maccatalyst.` prefix so the Mac build matches its iOS twin.
3. **The website half.** The host must be where you actually *use* the product, not its
   marketing page. The table already makes this distinction on purpose:
   `open.spotify.com`, not spotify.com; `web.whatsapp.com`, not whatsapp.com;
   `store.steampowered.com`, not valvesoftware.com. Blocking the brochure stops nobody.
4. **The link between the two.** The lookup's `sellerUrl` having the same registrable
   domain as your host is the strongest evidence there is, and where it matches you are
   done. Where it does not — Steam again — you need a second confirmation and a sentence
   in the sources file saying what it was.

### What not to do

- Never write a bundle identifier the search did not return. Not one.
- Never claim a host a pair does not own outright. No `google.com` for the Google app, no
  `apple.com`, no `amazon.com` for a seller that merely sells there. A host in this table
  means "blocking this is blocking that thing, and nothing else anybody wanted".
- Never let two pairs claim the same host. `Companions.pair(forHost:)` resolves the longest
  match, so a subdomain deliberately beats a domain — `music.youtube.com` is YouTube Music
  even though YouTube claims `youtube.com`. That is the one legal overlap, and it only
  works because the subdomain is genuinely a different product. Two pairs claiming the same
  string is a bug.
- Do not add things nobody blocks. The table's own rule, at the top of it: "Mail is also at
  gmail.com, but nobody adds Mail to keep themselves off it." Banking apps, maps, transit,
  password managers and health apps do not belong here whatever their websites are.
- An app with no App Store listing can still go in **with an empty `bundleIDs` list**, the
  way `DraftKings` and `FanDuel` already do, but only when the name is unambiguous. Say
  which pairs these are in the hand-back.

### What to add

Aim for another 30 to 50, kept in the table's existing groups (video, social, messaging and
work, shopping and gaming) with new groups added only when one earns four or five entries.
Blank lines separate groups; keep that. Territory worth walking: short-form video, news and
sport, dating, mobile games with a web build, shopping and resale, sportsbooks and casinos,
AI chat, forums and imageboards, streaming music, and the productivity tools that eat a day.
Zach is in the US; prefer what he would plausibly install.

### What to leave behind

1. The new pairs in `Shared/Core/Companions.swift`, in the existing groups and style.
2. **`design/companions-sources.md`** — new file, one row per pair you added: the name, the
   identifiers, the hosts, and the `trackViewUrl` and `sellerUrl` you confirmed them from.
   This is the audit trail, and the reason the next session can extend the table without
   re-verifying yours.
3. Tests in `Tests/Core/CompanionsTests.swift`. Two kinds. A handful of spot checks in the
   style already there, and — more valuable — **structural tests that walk the whole table**
   and would fail on the mistakes above: every identifier is already lowercase, no host
   string is claimed by two pairs, every pair has at least one host and at least one name,
   and no name is empty after normalizing. Those turn the invariants in this prompt into
   something the build enforces rather than something the next person has to remember.

Hand back: how many pairs you added, how many candidates you rejected and why, any pair
that went in with no bundle identifier, and the test run's output.

---

## 12. Suggested rules by hazard tier, and an audit for quality-of-life defaults like it

**Done — HANDOFF step 28.** Kept as history; do not run this prompt again.

**Model: Opus. Lane: its own; parallel-safe with everything. Waits on nothing.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `design/DESIGN.md`. Session rules: never run `git commit` or `git push`;
when the work is ready run `git status --short` and print two bash blocks for Zach — `git
add <only the files this session touched>` and a short all-lowercase `git commit -m "..."`
— with no `Co-Authored-By` line and no "Generated with" line. Every change to `Shared/Core`
gets tests in `Tests/Core`. Ask Zach before anything opinionated ships broadly; this whole
item is opinionated, so read the "Decide with Zach" note below before writing the table.

`Shared/Core/AppUtility.swift` already guesses a hazard tier for a target — essential,
useful, idle, hazard — and `RuleEditorView.swift:113` offers it as a default, only while
Zach "has not answered for himself" (`suggestion`, same file). It says nothing about the
*rule* itself: what budget, what windows. Right now the only help with that is
`copyCandidates`/`applyCandidates` (`RuleEditorView.swift:135-143`), and both require a
target Zach has *already* configured — the first hazard app anyone adds has nothing to copy
from. This item is the same suggestion pattern, one property over: alongside the tier,
propose a starting `Rule` — a budget, and windows if the tier warrants them — offered the
same non-coercive way the tier already is. Never applied automatically; one tap to take it,
one to ignore it; never overwrites a rule that already exists.

**Decide with Zach first: the actual numbers.** A bundle identifier has a verifiably correct
answer; "TikTok gets 20 minutes, not 30" does not. Do not silently invent a specific figure
for all 200-some entries in `AppUtility`. Instead:

1. Propose one starting rule **per tier**, not per app, as the default: essential suggests
   nothing (blocking it is the risk Furlough warns about, not a habit to budget); useful
   suggests nothing or a generous, unwindowed budget (a work tool does not have a "healthy
   amount"); idle suggests a moderate daily budget with no window restriction unless a
   specific app earns one; hazard suggests a tight budget, plus a window that excludes the
   first and last hour of the day, matching how Zach described Instagram versus how he
   described Telegram in conversation — a contact app should look like `.useful` even at
   `.essential`-adjacent tiers of "real reach," not like the feed sitting next to it in
   `.hazard` or `.idle`.
2. Read through `AppUtility.names`, `bundleIDs` and `hosts` for tier-default mismatches worth
   a named exception — a `.useful` messaging app (Telegram, Messenger, WhatsApp) almost
   certainly wants "no suggestion" rather than the generic useful default, the same way
   `Companions`' pairs and `AppUtility`'s essentials already carry per-entry detail instead of
   a bare tier. List every exception you propose, with the one-line reason, and stop there —
   do not extend exceptions to apps you have not looked at individually.
3. Take both the tier defaults and the exception list to Zach before wiring them into the
   table. This is the step every other item in this file skips because its facts are
   checkable; this one's are not, so do not skip it here.

**Once the numbers are agreed, the shape:**

- A new file, `Shared/Core/RuleSuggestion.swift`, keyed the same way `AppUtility` already is
  (by name, bundle identifier and host, reusing `AppUtility.byName`/`byBundleID`/`byHost`'s
  matching rather than re-deriving it) but answering a suggested `Rule` fragment — budget
  minutes and, where the tier calls for one, a window — not folded into `Advice`. Keep it
  separate from the tier table on purpose: Zach may want to retune a suggested figure without
  touching what is otherwise a table of verified facts.
- `RuleEditorView`: beside the existing `suggestion` (tier) property, a sibling that offers
  the rule fragment under the same guard — only while the target has no rule of its own yet.
  Applying it fills the budget and window fields already in the editor; it is a starting
  draft the person can still change before saving, not a second rule layered on top of one.
- Nothing here changes `Policy.decide` or anything the shield reads: this is a UI-layer
  default, same as the tier suggestion is today.

**The second half of this item — do not skip it.** Zach likes small quality-of-life defaults
in this same spirit: offered once, easy to ignore, never a second system to maintain. Read
`RuleEditorView.swift`, `AddChoice.swift` and `Furlough/Views/AddTargets.swift` end to end
looking for other cold-start gaps like the one above — a place where Furlough already knows
something useful (a tier, a proper name, a companion pairing, a window someone else set up)
but only offers it once a person has done the harder work first. Two seeds, not a limit:
whether a target's `nickname` could default to `Companions`/`AppUtility`'s confirmed proper
name instead of staying blank until the shield learns one; whether `copyCandidates` could
also offer a *tier's* own suggested rule as a candidate, so a second hazard app has more to
copy from than just the first. Propose two or three more, each with the same test: does it
require Zach to accept anything, or does it just remove a step for the same choice he would
have made anyway.

Keep: every suggestion here is offered, never applied, and never overwrites what is already
set; `Policy.decide` is untouched; the tier table and the rule-suggestion table stay separate
files so one can be re-tuned without touching the other's verified facts.

Tests: `Tests/Core/RuleSuggestionTests.swift` for the lookup (by name, bundle identifier and
host, mirroring `AppUtilityTests`' structure), a test that an existing rule is never
overwritten, and one per named exception confirming it does not fall through to its tier's
bare default.

Hand back: the agreed tier defaults and exception list (with Zach's sign-off noted), the
suggestion mechanism, two or three other quality-of-life proposals from the second half with
Zach's answer on each, and the test run's output.

---

## 13. The link contract: schemas, test vectors and tables a port can be built against

**Model: Opus. Lane H. Waits on nothing — HANDOFF 37 landed as `6158863`. Parallel-safe: it
adds `protocol/` and one test file and changes no existing Swift.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` (step 37 most
carefully), then `README.md`, then the memory note "Cross-platform ports assessment" and the
page it links, which holds the platform matrix this work serves. Session rules: never commit
or push; when done, print `git add <your files>` and a lowercase `git commit -m "..."` for
Zach, with no Co-Authored-By; run `xcodegen generate` after adding a file; keep the build
warning-free; every `Shared/Core` change gets tests in `Tests/Core`; ask Zach before building
anything marked "decide with Zach". Work in a worktree (`EnterWorktree`, then `git reset
--hard main`, because the worktree branches from a stale origin); the worktree guard refuses
heredocs and `a; b` lines, so use Edit and Write there.

**Why this exists.** Zach is weighing Android, Windows and Linux. Every port needs the same
two things before a line of Kotlin or C# is worth writing: the exact shape of what crosses
between devices, and a way to prove that a second implementation merges, drops and lands
additions exactly as the Swift does. Today both live only in Swift and its tests. This session
writes them down as data any language can load, generated from the real code so they cannot
drift. It builds no port, no relay and no transport; those are later items, and some of them
are Zach's decisions.

**What is fixed, and must be described as it is rather than as it might become.** These are
the linking session's decisions of 2026-09-10. Do not relitigate them and do not change the
code they describe.

- The link is opt-in per device and gates everything, the Anchor included. Grandfathering is
  only for installs that had already heard the other device.
- Four key namespaces in the store: `furlough.anchor.v1` (`AnchorRecord`),
  `furlough.device.<id>` (`LinkedDevice`), `furlough.revoke.<id>` (`Revocation`), and
  `furlough.adds.<id>` (a ring of the last 20 `SharedAddition`s).
- `AnchorSync.merge` accepts a release only from origin `tagScan` on platform `phone`. The
  roster carries `canRelease`, and switching the merge to it is a one-line change Zach has not
  made. The contract says what the code does today and lists the switch under "not decided".
- `macDrop` needs something to hold, the store reachable, and another roster device that can
  release. Leaving or revoking is refused while an anchor holds here or on the record.
- A `SharedAddition` is a name plus every bundle id and host, never a token; a receiver blocks
  what it can find. Defaults: companion site Always, send Ask, accept Ask.
- A device without iCloud has no path today. There is no relay, and nothing you write may
  imply one is coming or small: it would mean Furlough running a server, which the privacy
  page says it does not.

Do these, in order:

1. **`protocol/README.md`, the contract in words.** One document a Kotlin or C# engineer
   could implement from with nothing else open. Sections: what crosses and what never does
   (tokens, and rules as such); the four keys and the lifetime of each entry; every field of
   `AnchorRecord`, `LinkedDevice`, `Revocation` and `SharedAddition` with its meaning and its
   encoding (dates ISO-8601, the way `AnchorCloud` encodes); the merge rules; the Mac-drop
   guard; the leave refusal; the ring, the watermark per source and the declined set; what a
   receiver does with an addition on each platform today; the three settings; what a transport
   must provide (a keyed store that lists by prefix, a reachable probe, a change signal, and
   identity scoping) and which of those iCloud gives for free; and a "not decided" list (the
   relay, `canRelease` in the merge, platform values beyond phone, pad and mac). Take the
   sentences from HANDOFF 37 and the doc comments in `AnchorSync.swift`, `DeviceLink.swift`,
   `SharedAdditions.swift` and `LinkFlow.swift`. Do not paraphrase a rule you have not read in
   the code.

2. **JSON Schemas** (draft 2020-12) in `protocol/schema/`: `anchor-record.json`,
   `linked-device.json`, `revocation.json`, `shared-addition.json`, and `config-export.json`
   for the setup file (`ConfigExport` version 1, with `ExportedTarget` and `alsoBlocks`).
   Required fields, enums with the exact raw values the Swift enums encode, dates as
   `date-time`. Field descriptions are the README's sentences, shortened.

3. **Test vectors** in `protocol/fixtures/`, one JSON file per case, inputs written by hand and
   expectations written by the code:
   - `merge/`: every branch of `AnchorSync.merge`. A stale sequence; a release from a phone's
     tag scan over a holding anchor; a release refused from a Mac writer, from origin `lift`,
     and from origin `drop` with `isAnchored` false; a release when nothing holds here; a drop
     already over by this clock; a hold lengthened; a drop over an anchor already down with the
     same `until`; anchored by the other device with and without an `until`.
   - `mac-drop/`: each `DropRefusal` and the success case.
   - `roster/`: `Roster.linked`; `hasKey(besides:)` with and without a releaser; a revocation
     newer and one older than the entry; `leaveRefusal` in its four combinations.
   - `additions/`: the ring capped at 20 and an id replacing its earlier write; `unseen`
     against a watermark; the Mac's `landing` for an app installed, an app not installed, a row
     already covering a door, and a rule arriving where the row has none.
   Shape per file: `{ "name", "input": {…}, "expected": {…} }`, with `expected` carrying the
   note string wherever the function returns one. Dates in inputs are fixed ISO-8601 strings,
   never now.

4. **`Tests/Core/ProtocolFixturesTests.swift`** loads every fixture with the real Codable
   types, runs the pure function, and asserts `expected`. With `FURLOUGH_WRITE_FIXTURES=1` in
   the environment it rewrites every `expected` from the current code instead, so a behaviour
   change fails the test until someone regenerates on purpose, and the diff of the fixtures is
   the review. Find the files from `#filePath` (`Tests/Core`, up to the repo root, then
   `protocol/`) rather than adding resources to the test bundle, so `project.yml` stays
   untouched. The same test checks every schema against a fixture: each key the encoder wrote
   is a property the schema names, and each enum's raw values equal the schema's `enum` list.
   No JSON Schema library; a small walk over `properties` is enough.

5. **Tables** in `protocol/tables/`, written and checked by the same test under the same flag:
   `companions.json` from `Companions.pairs` (names, bundle ids, hosts, in table order),
   `tiers.json` from the tier-suggestion table in `AppUtility`, and `rule-suggestions.json`
   from `RuleSuggestion`. Then `other-platforms.json`, keyed by a pair's title, with `android`
   package names and `windows` executable names, and a test that every key is a real title.
   **Decide with Zach** whether to fill it now. The house rule from item 11 is every entry
   confirmed: a Play Store listing URL confirms a package name, while most Windows executables
   cannot be confirmed from a vendor page. Leave what cannot be confirmed empty rather than
   guessed.

6. **HANDOFF step 38**, at the end of "Next work": what `protocol/` is, how to regenerate, and
   that the fixtures are the contract for any port. Add one line to the code map for
   `protocol/`. Do not edit step 37.

Hand back first. Then, only if Zach says go on:

7. **Rules-engine vectors** in `protocol/fixtures/policy/`, the same mechanism over `Policy`:
   status at a time, the next transition, tightening against loosening (`classify`), pending
   changes landing, a window crossing midnight kept as two, and per-weekday budgets. Draw the
   cases from `PolicyStatusTests`, `PolicyPendingTests`, `NextWindowTests`,
   `WeekdayBudgetTests` and `ActivityLimitTests`. This is the safety net a Kotlin engine would
   run, and it is a second commit.

Not in scope, whoever asks: a relay or any transport; any change to `merge`, `macDrop`, the
roster, the ring or `LinkFlow`; new platform values; compiling Swift for another OS; any
screen. If a fixture cannot be written without changing the code, stop and say so.

Hand back: `xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination
'platform=macOS,arch=arm64'` green, with the fixture count; the README; the two git blocks.
Nothing to tap. What Zach should do is read `protocol/README.md` once as if he were the
Android engineer and say what he could not build from it.

---

## 14. Cache the token map, so the usage page's icons are instant on later visits

**Model: Opus. Lane I. Waits on the commit "draw the usage cards from the tables and let screen
time's icons catch up" being on main — check `git log --oneline -8` first. Parallel-safe: it
adds one Core file and one test file, and touches `SharedStore`, `UsageReader`, `UsageView.load`
and one function in `AppModel`.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then the memory note "iOS 26.4 Screen Time data access". Session rules: never
commit or push; when done, print `git add <your files>` and a lowercase `git commit -m "..."`
for Zach, with no Co-Authored-By; run `xcodegen generate` after adding a file; keep the build
warning-free; every `Shared/Core` change gets tests in `Tests/Core`; you cannot see the phone,
so end with what Zach should tap and see. Another session is usually mid-edit in this tree, so
work in a throwaway worktree (`git worktree add --detach <your scratchpad>/wt-tokens HEAD`,
`xcodegen generate` there, build with `-derivedDataPath` under your scratchpad, log there too),
and copy only your own files back once green — check `git status --short` on each of them
first, and remove the worktree after.

**Why this exists.** With data access (iOS 26.4; development builds anywhere, App Store
customers in the EU only — the memory note has the detail) the usage page (`UsageView`, Path A)
reads the fortnight itself, but Screen Time names an app there by bundle identifier alone.
Apple's icon, and the token a rule is written on, come from a second query —
`FamilyActivityData.shared.installedApplications` and `visitedWebDomains`, wrapped by
`UsageReader.encodedKinds` — that enumerates every app on the phone, takes seconds when it
answers, and sometimes never does. The previous session stopped the page waiting on it: cards
draw at once from the tables (`Brand`, `UsageEntry.isNamed`), a letter on the brand's colour
stands in for the icon (`MonogramTile`), and each ask has a deadline (`UsageReader.patience`).
What is left is that every visit still pays for the query before the real icons appear, and an
app the tables do not know is held back until it answers. The answer barely changes between
visits — a token is stable for as long as the app is installed, and Furlough already persists
tokens inside every target — so it should be kept, and the page should open on it.

**What is fixed.** Read these in the code before changing anything; do not relitigate them.

- `UsageReader.fillingTokens(in:)` walks the summary once against the map from
  `encodedKinds()`. `Naming.answered` is false for an empty answer, which the caller treats as
  a failed query and retries. `fillingTokens(in:within:)` and `kind(forKey:within:)` race the
  query against `patience`.
- `UsageView.load()` draws as soon as the fortnight is read and folded; `nameApps()` runs
  behind it, retries `namingAttempts` times, folds linked pairs once the tokens are in, and
  drops what neither the tables nor Screen Time named. `apply()` waits on `naming` rather than
  asking the same question twice.
- `AppModel.nameUnnamedTargets()` runs the same query on activation, through
  `UsageReader.identities()`, to name fresh targets from the tables.
- `SharedStore` is the App Group store. `learnedNames`/`learnName` under `furlough.names.v1`
  is the pattern for a side table that is not the config; `reset()` is what Reset everything
  calls, and it must forget whatever you add.
- `TargetKind` is Codable, and its encoded form is what crosses out of the `@concurrent`
  functions, because tokens are not Sendable. `TargetKind.application` exists only under
  `#if os(iOS)`, so the Core test bundle on macOS cannot make one: the cache has to be generic
  over `[String: Data]`, which is exactly what `encodedKinds()` returns.

Do these, in order:

1. **`Shared/Core/TokenCache.swift`**, a Codable value: `entries: [String: Data]`, keyed the
   way `UsageCollector` keys an entry (a bundle identifier, or `web:` and a domain), and
   `savedAt: Date`. One pure function, `refreshed(with answer: [String: Data], now: Date) ->
   TokenCache?`: a cache holding exactly `answer` — replaced, never merged, so an app deleted
   since the last visit falls out — and nil for an empty answer, because an empty answer is a
   failed query (see `Naming.answered`) and must not wipe a good cache.
   `Tests/Core/TokenCacheTests.swift`: a round trip through JSON; replace, not merge; an empty
   answer keeps the old cache; a hand-written older shape decodes without crashing (follow
   `DecodingTests`).

2. **`SharedStore`**: `tokenCache() -> TokenCache?` and `save(_ cache: TokenCache)` under
   `furlough.tokens.v1` in `defaults`, and `reset()` removes the key beside the two it already
   removes. Log the entry count and byte size once per save. `identities()` needs the whole
   map, not only the ranked five, so do not trim it; if a phone with a few hundred apps comes
   out over about a megabyte, say so in HANDOFF rather than trimming silently.

3. **`UsageReader`**: `encodedKinds()` saves the cache after every answered query, through
   `TokenCache.refreshed`. Add `cachedKinds() -> [String: Data]?`. Change
   `fillingTokens(in:)` so a fresh answer re-resolves **every** entry from the map, not only
   the tokenless ones: today it skips an entry that already has a token, and a token filled
   from the cache must be able to be taken away again when the fresh answer no longer lists
   its key. Add a way to fill from a map without querying — `fillingTokens(in:from:)` or a
   parameter. `identities()` reads the cache first and queries only when there is none, so
   `nameUnnamedTargets` costs nothing on most activations.

4. **`UsageView.load()`**: after the fortnight is read and folded, and before `phase = .ready`,
   fill from the cache when there is one, then fold again (an app's half can now pair with its
   site's) and rank. Log `usage: N of M tokens from the cache, written <age> ago`. `nameApps()`
   runs exactly as now behind the cards; when its answer lands, `fillingTokens` re-resolves, a
   cached token whose key is gone loses its token, and the card is dropped by the rule that is
   already there. The held-back line and `naming` stay as they are.

5. **Look at the stale case honestly.** A cached token for an app deleted since the last visit
   puts a card on the page for the seconds until the fresh answer removes it; `Label(token)`
   may draw blank, and Apply in that window would add a target for an app that is not there.
   Try it if you can — install a small free app, open the page, delete the app, open the page
   again — and write what you saw in HANDOFF. If the window is worse than a blank tile — a
   crash, or a rule that sticks — hold cached tokens back from Apply until `naming` finishes,
   which is one condition in `apply()`, and say so.

6. **HANDOFF.** There is no step yet for the previous session's change either; it kept out of
   HANDOFF because another session was editing it. Write one step, at the next free number after
   item 13's, covering both: the tables, the monogram tiles and the deadline (the commit named
   at the top of this prompt), and the cache — its key, its replace-not-merge rule, what reset
   clears, and the stale-token finding. Add `Brand.swift` and `TokenCache.swift` to the code
   map. Do not edit a step you did not write.

Not in scope, whoever asks: looking bundle identifiers up over the network (the page promises
that nothing leaves the phone); bundling app artwork (it is the app's trademark, and
`Label(token)` is the only source Furlough may draw it from); a prefetch of the query on every
launch (it enumerates every app, and the cache makes it unnecessary); any change to Path B or
the report extension; any change to `Brand`'s colours beyond adding one. The cache is iOS only;
the Mac names apps from their bundle identifiers already.

Hand back: `xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination
'platform=macOS,arch=arm64'` green with the new count; the device build green; the app
installed; the two git blocks. What Zach should do: open Settings › Where the time goes once
and let the real icons arrive. Leave, and open it again: the cards should come up with Apple's
icons in the same instant as the cards themselves — no letters, no "Asking Screen Time…" line.
Settings › Diagnostics should show the "tokens from the cache" line. Then Reset everything and
open it once more: letters first and icons after, as before.

---

## 15. Apple Watch complication and a wrist-only Drop Anchor

**Open — proposed 2026-09-12. Needs Zach's go-ahead before any code: does he wear an Apple
Watch worth building for, and does a wrist Drop Anchor earn its keep over the phone widget
and Control Center control that already exist (item 2, done)?**

**Model: Fable — a Watch complication calling into `AnchorDrop` is a new process writing
`Config.anchor`, exactly the case HANDOFF's model rule calls out, even though the action is
tightening-only. Lane J. Waits on nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`. Session rules: never commit or push; when done, print `git add <your files>`
and a lowercase `git commit -m "..."` for Zach, with no Co-Authored-By; run `xcodegen
generate` after adding files; keep the build warning-free; every `Shared/Core` change gets
tests in `Tests/Core`; you cannot see the phone or the Watch, so end with what Zach should
tap and see on each. Ask Zach before building anything marked "decide with Zach", and do not
scaffold a Watch target before he has answered the go/no-go question above.

Today `Shared/Core/AnchorDrop.swift` (iOS only) is the one function that drops the anchor
from any process; the Control Center control and `Shared/Intents/DropAnchorIntent.swift`
both call it. A Watch complication would be a fourth caller, but watchOS is a separate
device, not a second process sharing the phone's App Group container — App Group sharing
only works within one device's sandbox, so this needs real transport, not just a new call
site.

1. **Decide with Zach: is this worth building at all**, given the phone widget and Control
   Center already do a one-tap drop. If yes, continue; if no, stop here and say so in
   HANDOFF so nobody re-proposes it without reason.
2. `WatchConnectivity` is the only channel that needs no server: `WCSession` with
   `updateApplicationContext` for the latest status snapshot (delivered opportunistically,
   not on demand) and `sendMessage` for the drop action when the phone is reachable, falling
   back to `transferUserInfo` when it is not. Read Apple's current complication-refresh and
   background-transfer budgets before promising anything close to live; watchOS decides when
   a complication actually redraws, not the app.
3. Check the current watchOS SDK for whether a full WatchKit companion app is still required
   to host `WCSession`, or whether a widget extension alone can attach to the iOS app and use
   it — this has moved over recent watchOS releases and the answer decides how much to
   scaffold. If a companion app is required, add it as `FurloughWatch`; the complication
   itself is a new `FurloughWatchWidgets` extension drawing a still `HourglassView` (from
   `Shared/UI/Hourglass.swift`) off the last delivered snapshot.
4. The complication's action calls into the drop path via `sendMessage`/`transferUserInfo`,
   which the phone applies through the same `AnchorDrop` function on receipt — never a new
   write path. There is no release path from the Watch: it has no reader for arbitrary NFC
   tags (Apple Pay's NFC is not exposed to third-party apps), so Unanchor stays phone-only,
   the same way it does on an iPad without item 4.
5. Say plainly, on the complication and in HANDOFF, that the status shown can be stale by
   whatever the delivery budget allows — it is not the phone's Live Activity, which ticks
   every second.

Keep: no new release path anywhere; `Policy.decide` untouched; the phone remains the only
device a tag scan can happen on.

Tests: none in `Tests/Core` — nothing here is pure; it is transport and WidgetKit. Log the
`WCSession` message flow on both ends instead.

Hand back: the go/no-go answer, the transport chosen and its actual refresh behaviour as
observed (not as documented), the target(s) added, and exactly what Zach should do on the
phone and the Watch to see a status update arrive and a drop actually land.

---

## 16. A StandBy-friendly widget

**Open — proposed 2026-09-12.**

**Model: Opus. Lane K. Waits on nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `design/DESIGN.md`. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding files; keep the build warning-free; you
cannot see the phone, so end with what Zach should do and see.

StandBy (the landscape charging-stand mode) surfaces the same WidgetKit widgets the Lock
Screen and Home Screen already use — there is no separate StandBy widget API, only existing
families rendered larger and, after dark, under a system red-tinted night mode Furlough does
not control. So this is a layout and legibility task, not a new extension.

1. Check `FurloughWidgets/StatusWidget.swift`'s current `supportedFamilies`. Add
   `.systemLarge` if it is not already declared, and lay the hourglass and countdown out so
   they read from across a room rather than looking like a scaled-up Home Screen tile.
2. Confirm Ember Glass survives the automatic night tint rather than assuming it does —
   charge the phone after dark in the stand orientation and look. If the palette fights the
   tint (the ember accent going muddy, the glass losing contrast), say so in HANDOFF; do not
   silently add a StandBy-specific palette without asking Zach first, since the whole design
   language is settled and reviewed.
3. Confirm the Live Activity (`WindowLiveActivity.swift`) already appears in StandBy while a
   window is open — it should, since StandBy shows the same Lock Screen Live Activities by
   default — and note whether it needs anything of its own.

Keep: no shield or anchor logic touched; this is presentation only; nothing here changes
`Policy.decide` or any writer of `Config`.

Tests: none in `Tests/Core`. Visual check on the device is the only proof.

Hand back: the widget family added (if any), a screenshot Zach takes of StandBy showing it
in daylight and after dark, and the night-tint finding.

---

## 17. Focus Filter: drop the Anchor when a Focus turns on

**Open — proposed 2026-09-12.**

**Model: Fable — a Focus Filter intent extension is a new process writing `Config.anchor`,
exactly the case the model rule calls out, even though it can only tighten. Lane L. Waits on
nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`. Session rules: never commit or push; when done, print `git add <your files>`
and a lowercase `git commit -m "..."` for Zach, with no Co-Authored-By; run `xcodegen
generate` after adding files; keep the build warning-free; every `Shared/Core` change gets
tests in `Tests/Core`; you cannot see the phone, so end with what Zach should configure and
test. Ask Zach before building anything marked "decide with Zach".

iOS lets a third-party app plug an action into a system Focus (Sleep, Work, or one Zach
names) through a Focus Filter — the user turns it on once from Settings > Focus > a Focus >
Focus Filters > Furlough, the same screen every Focus Filter uses. No entitlement beyond App
Intents is needed.

1. A new intent conforming to `SetFocusFilterIntent`, in a new
   `Shared/Intents/AnchorFocusFilter.swift`, with one configurable parameter: which of the
   anchor's existing shapes to apply when the chosen Focus turns on — today's chosen-apps
   list, or, if item 3 has landed, the everything-except scope. Nothing here is configurable
   about *what* the anchor holds, only *when* it drops; the anchor's own screen still owns
   the list.
2. Check the current App Intents signature for how the system reports activation versus
   deactivation to `perform()`. **Act only on activation.** On deactivation, do nothing at
   all — no call into `AnchorDrop`, no write of any kind — and leave a comment saying why:
   this is exactly the seam where "the Focus controls it" would quietly grow into an
   unblock if the off-case were ever wired to anything. Unanchoring stays tag-only,
   unconditionally, regardless of what this item adds.
3. The activation path calls the same drop semantics `Shared/Core/AnchorDrop.swift` already
   exposes to the Control Center control and `DropAnchorIntent` — a fourth caller of
   existing code, not new anchor logic.
4. Decide with Zach: a Focus Filter's system configuration screen has no room for Furlough's
   own confirmation sheet, so `Config.anchorWarning`'s essential-app warning cannot appear at
   the moment of activation the way tapping Anchor in the app shows it. The honest options are
   either a warning sentence baked into the Filter's own setup screen (read once, at
   configuration time, not at every activation) or accepting that this path skips the warning
   entirely. Write whichever Zach picks into HANDOFF as a decision, not an oversight.

Keep: `AnchorDrop.drop` unmodified; the anchor's writers list in HANDOFF grows to include
this Filter, alongside Control Center, the intent, the schedule and the tag; nothing here can
release.

Tests: none in `Tests/Core` — `SetFocusFilterIntent` conformance is not unit-testable the way
`Policy` is. A manual device test is the only proof: turn the configured Focus on and confirm
the anchor drops within a few seconds; turn it off and confirm nothing changes.

Hand back: the intent, the scope decision, the warning-copy decision, and what Zach should
configure under Settings > Focus and then test.

---

## 18. A trend view in the Mac's menu bar

**Open — proposed 2026-09-12.**

**Model: Opus. Lane M. Waits on nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `FurloughMac/MenuBar.swift` and `Shared/Core/Record.swift`. Session rules:
never commit or push; when done, print `git add <your files>` and a lowercase
`git commit -m "..."` for Zach, with no Co-Authored-By; run `xcodegen generate` after adding
files; keep the build warning-free; Mac screens can be rendered to PNG with the swiftc
approach in the memory note "Verify Shared/UI drawing on the Mac with swiftc". Ask Zach
before building anything marked "decide with Zach".

`MenuBar.swift`'s `NSMenu` already shows the hourglass, the countdown and every target's
status off `Policy.summary`, rebuilt on `menuNeedsUpdate`. `Record.swift` already accumulates
`DayRecord` per day for 60 days — minutes shielded, whether a budget was spent, loosenings
cancelled versus landed — feeding the phone's Settings card and the Mac sidebar's
`MacRecordSection`/`MacRecordRows`. Nothing today puts that history where it is seen without
opening the app.

1. **Decide with Zach first**: whether a chart belongs in the menu bar dropdown at all, or
   whether it stays sidebar-only. A menu that takes a visible beat to render every time it
   opens is a worse menu than the one that exists today — measure that before committing to
   it, not after.
2. If yes: one more section in the menu, a week-over-week view (a sparkline or a bar per day
   of minutes shielded) reusing `Record`'s existing data — no new accumulation, no new
   `Config` field. Draw it as a hosted SwiftUI view inside a custom `NSMenuItem`, the way the
   countdown already is; check `project.yml`'s macOS deployment minimum before reaching for
   Swift Charts, since a hand-rolled bar row is also fine and has no dependency to check.
   Rebuild it in the same `menuNeedsUpdate` pass as everything else in the menu.

Keep: no new state, no new writer; this reads `Record` and nothing else; `Policy.decide`
untouched.

Tests: none new — `Record`'s arithmetic is already covered by `Tests/Core/RecordTests.swift`.
If a formatting helper is added (bucketing minutes into rows, say), test it in `Tests/Core`
since it is pure.

Hand back: the "does this belong here" decision, the section if it went ahead, and a
screenshot of the menu open with at least a week of real data behind it.

---

## 19. A weekly digest notification

**Open — proposed 2026-09-12.**

**Model: Opus. Lane N. Waits on nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `Shared/Core/Record.swift` and `Shared/Core/PendingNotifications.swift`.
Session rules: never commit or push; when done, print `git add <your files>` and a
lowercase `git commit -m "..."` for Zach, with no Co-Authored-By; run `xcodegen generate`
after adding files; keep the build warning-free; every `Shared/Core` change gets tests in
`Tests/Core`; you cannot see the phone, so end with what Zach should do to see one fire. Ask
Zach before building anything marked "decide with Zach".

`Record.swift`'s numbers — streaks, minutes shielded, loosenings cancelled versus landed, the
longest anchor — are visible today only if Zach opens Settings or the Mac sidebar. A once-a-
week push of the same numbers would make the record something that reaches him rather than
something he has to go looking for.

1. A pure function in `Record.swift` — something like
   `Record.weeklyDigest(days:calendar:at:) -> DigestText?` — answering two or three lines
   condensed from the same copy functions `RecordScreen`/`MacRecordSection` already use: the
   streak, minutes shielded this week, loosenings cancelled versus landed. Reuse the existing
   wording rather than drafting new prose, and keep the existing refusal to be celebratory —
   a broken streak says so plainly, here as everywhere else in `Record`.
2. Schedule it through the existing planned-notification path
   (`PendingNotifications.swift`'s `Notifier`, `PlannedNotification`, `plan`/`sync`) rather
   than a one-off `UNNotificationRequest` written from scratch — a weekly digest is exactly
   what that infrastructure is for. A `UNCalendarNotificationTrigger` for Monday morning
   (time configurable; default matching whatever hour Zach's other notifications already use)
   works identically on the phone and the Mac, since both post local notifications today.
3. Re-plan it on every `enforce()`/`reconcile()`, the way every other planned notification is,
   so a fresh install or a Reset schedules the next one with no special case.
4. Decide with Zach: on or off by default, and where the toggle lives (a Settings row next to
   the Record card is the obvious place).

Keep: read-only over `Record`; nothing here writes `Config` or touches `Policy.decide`; a
missed digest (phone off, Do Not Disturb) is not retried outside its own next week — no
catch-up logic, the same way a missed midnight callback is not specially retried elsewhere.

Tests: `Tests/Core/RecordDigestTests.swift` (or added to `RecordTests.swift`) with a pinned
calendar: a week with a held streak, a week with a break, a fresh install with no data yet,
and the Monday scheduling math across a DST boundary.

Hand back: the function, the scheduling wired on both platforms, the default-on/off decision,
and how to see one fire without waiting a week — backdating a test trigger a few minutes out,
the same demo shape as item 2's timed Anchor drop.

---

## 20. Onboarding: where to put the tag

**Open — proposed 2026-09-12.**

**Model: Sonnet — copy and a static screen, no logic. Lane O. Waits on nothing;
parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`, then `site/src/pages/help/nfc-tags.astro`'s "Why a tag and not a code" section to
learn the voice already settled there. Session rules: never commit or push; when done, print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By. You cannot see the phone, so end with what Zach should see.

The whole mechanism leans on the tag being "somewhere else" — a code is a photograph away
from being a copy, and the tag is not. Onboarding pairs the tag today and says nothing about
where to put it afterward, and neither does the Anchor screen.

1. A new step in `Furlough/Views/Onboarding`, shown once, right after the tag pairs
   successfully: the Ember Glass card style, three or four concrete placement suggestions (a
   housemate's bag, a locked drawer at work, the bottom of a bike pannier, mailed to yourself
   with a delay, handed to a partner) and one line on why it matters, pulled from the site's
   existing "Why a tag and not a code" sentence rather than a second version of the same
   claim. No checkboxes, no persisted state — this is guidance a person reads once, not a
   feature Furlough tracks doing.
2. A `?` link from the Anchor screen to the same content on the site, for anyone who paired a
   tag before this shipped, rather than duplicating the screen's prose in two places.
3. Condition the onboarding screen on this being the *first* pairing, not any pairing, so
   `Forget tag` → pair again does not repeat it.

Keep: no new persisted state; `AnchorProfile` and `Config` untouched; nothing here can be
mistaken for a pause or a break.

Tests: none — pure SwiftUI copy; nothing in `Shared/Core` changes.

Hand back: the screen, seen once during a fresh pairing on the phone, and the Anchor screen's
new link.

---

## 21. The hero phone becomes a phone you can page through

**Model: Opus. Lane P. Waits on the homepage-demos commit being on main — check
`git log --oneline -5` for "make the homepage demos work". No Xcode build: the site is
`bun install`, `bun run build` in `site/`, never npm. Parallel-safe with everything in the
app; it owns `site/src/components/HeroPage.astro` and may add to `site/src/lib/hourglass.ts`.
Another session may be inside `site/src/pages/index.astro` — do not rewrite that file.**

You are picking up Furlough, Zach's iOS and Mac app blocker, and its site at furloughapp.com.
Read `HANDOFF.md`, then `README.md`, then `design/DESIGN.md` for Ember Glass, then the memory
note "Browser pane hides the document; use headless Chrome". Session rules: never commit or
push; when done, run `git status --short` and print `git add <only your files>` and a lowercase
`git commit -m "..."` for Zach, with no Co-Authored-By and no "Generated with" line. Use bun,
never npm. Another session is usually mid-edit in this tree, so work in a throwaway worktree
(`git worktree add --detach <your scratchpad>/wt-hero HEAD`) and copy only your own files back
once it builds. Zach is interactive: the two questions marked below are his, not yours.

**Why this exists.** The phone in the hero plays one evening on a loop, twelve seconds to the
half hour, and has two buttons under it: Fast-forward and View Anchor Mode. Everything *below*
it on the page became real on 2026-09-14 — the budget slider is dragged, the week grid is drawn
by hand, the utility tiers move the delay from six hours to four days, the Anchor is lifted by
holding the tag button the way you would hold a phone against a tag. The hero is now the least
interactive thing on a page that is otherwise a working demo of the app, and it is the first
thing anyone sees. The five dots under the hero page say there are five pages. There is one,
plus a walkthrough hidden behind a button.

**What is fixed.** Read these in the code before changing anything.

- `HeroPage.astro` is one component: markup, scoped styles and one module script. The evening
  is `todayBeat(t)` — `PRE` 5 s before the window, `WINDOW` 1800/`SPEED`, `DONE` 8 s after,
  `WARN_AT` where the five-minute budget warning starts — and the Anchor walkthrough is
  `anchorBeat(t)` over `STEPS`/`ENDS`. `Mode` is `'today' | 'anchor'`; `origin[mode]` is why
  leaving one loop does not restart it; `clock(now, m)` is the only clock.
- Commit `cf15f5b` split the frame loop into `render(now)` and `loop`, with `keepTime` on a
  250 ms timer and on `scroll`, because Safari hands out no animation frames for the length of
  a scroll and the countdown froze. Keep that shape. Anything new that ticks goes through
  `render`, not its own `requestAnimationFrame`.
- `LivingHourglass` draws its first frame synchronously, pauses off screen, and takes a state;
  `blendStates(a, b, k)` is how one state gives way to another (800 ms in the hero);
  `setMotion(on)` was added 2026-09-14 for the legend swatches. `States` is the whole
  vocabulary: `open(level, warned)`, `comingSoon(minutes)`, `doneForToday`, `usedUp`,
  `alwaysBlocked`, `unconfigured`, `anchored`. Do not invent an eighth.
- The five `.indicator` canvases already name the five pages, in order: the live one
  (`data-hero-mini`, Instagram), YouTube at 8, Reddit at 9, TikTok always blocked, and the
  Anchor (`data-hero-anchor-dot`). They are `aria-hidden` and `data-still` today. The rows under
  them (`[data-today-list]`) are the same apps, with Netflix as a fifth row that has no dot
  because it is tomorrow's.
- The Browser pane keeps `document.hidden` true: rAF never fires, CSS transitions do not
  advance, and canvases come back blank. That is the pane, not your code. Verify with headless
  Chrome (the command is in the memory note) or hand it to Zach.
- `index.astro` learned three things on 2026-09-14 that apply here: `touch-action` goes on the
  small draggable thing and never on a whole column, or a finger cannot scroll the page past
  it; `setPointerCapture` comes last in a `pointerdown` handler, so a throw cannot leave the
  control dead; and each demo carries one `.cue` line saying what there is to touch.

Do these, in order:

1. **Make the indicator a real pager.** Clicking a dot turns the phone to that page, the dots
   get a keyboard (left/right arrows, Home/End), and the live one is whichever page is showing.
   The tablist/tab pattern is the honest markup; the phone itself stops being `role="img"` the
   moment it is a control, so give it a role that matches what it now is.
2. **Give the other four pages their own beats on the same clock.** YouTube opens at 8 and runs
   two hours on 30 minutes; Reddit opens at 9 on 20; TikTok is `alwaysBlocked` and has no
   countdown to draw, which is the interesting page, because it has to look right with nothing
   moving. Write each from the row that already describes it, so the page and the row cannot
   disagree — one table of targets that both the rows and the beats read.
3. **Let the page be dragged.** A horizontal pointer drag across the hero page moves between
   pages and the glass follows through `blendStates`. `touch-action: pan-y` on the page area so
   a finger scrolling the site still scrolls it.
4. **Make the rows the other end of the same control.** Click a row and the phone turns to that
   app; the row whose page is showing carries a quiet marker. The rows are `aria-hidden` today;
   if they become controls they stop being decoration and need labels.
5. **The evening's clock gets a scrub.** Fast-forward stays — it is what teaches that the loop
   is twelve times life — and beside it goes a thin scrubber for the evening, draggable both
   ways, showing where the window opens and closes. Dragging it pauses the loop; letting go
   resumes from where it was left.
6. **Ask Zach before building**: (a) whether `View Anchor Mode` survives as a labelled button
   once the fifth dot pages to the Anchor — it is redundant, but it is also the only word
   "Anchor" in the hero, and discovery is worth more than tidiness; (b) whether the phone should
   resume its own loop after a visitor has been driving it, and after how long.
7. **Keep the costs where they are.** No framework, no library, no image: the page is
   hand-written CSS and one canvas module, and it stays that way. `prefers-reduced-motion` must
   still get a phone that is legible and still. Nothing new goes into a live region — a
   countdown that announces every second is a page a screen-reader user leaves.

Not in scope, whoever asks: the toolbar's gear and `+`; a second phone or a device frame; video
or a recorded demo; any change to the four demos on `index.astro` (they landed the day before
this was written), except to lift a helper both pages plainly want into `site/src/lib/`; a
router, a store, or any state that outlives the page.

Hand back: `bun run build` clean in `site/`; a headless Chrome capture of the hero on two
different pages, cropped to the phone; and exactly what Zach should click — a dot, a row, the
scrubber, the Anchor page — and what he should see when he does.

---

## 22. Drag the week grid: windows edited where they are drawn, on both apps

**Model: Opus. Lane Q. Waits on nothing. It is the one open item that changes a view both apps
compile, so run it alone in a worktree and expect to touch `project.yml`: `git worktree add
--detach <your scratchpad>/wt-week HEAD`, `xcodegen generate` there, build with
`-derivedDataPath` under your scratchpad, and copy only your own files back once both builds
and the tests are green — `git status --short` on each one first.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` (the build and
test commands, the invariants and the code map are there; do not re-derive them), then
`README.md`, then `design/DESIGN.md`. Session rules: never commit or push; when done print
`git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no Co-Authored-By;
run `xcodegen generate` after adding a file; keep the build warning-free in our own code; every
change to `Shared/Core` gets tests in `Tests/Core`; nothing can screenshot the phone, so end
with exactly what Zach should tap and see, on both devices, then wait for his report.

**Why this exists.** Zach has wanted this for a while. The week grid in the rule editor
(`WeekSheet` → `WeekGrid`) draws the windows beautifully and cannot change one of them: tapping
a day pushes `DayEditor`, a list of rows with time pickers, which is where every edit actually
happens. So the picture and the editing are two different screens, and the picture — the thing
that makes a schedule obvious at a glance — is the one you cannot touch. The site's homepage got
the editable version on 2026-09-14: drag a window to move it, drag its edges to resize, tap
empty track to add one, delete it, keyboard for all of it, and a sentence underneath that
rewrites itself as you drag. That is the interaction this grid should have had, and it should
work the same on the phone and on the Mac.

**What is fixed.** Read these before changing anything; do not relitigate them.

- `WeekDraft`, `WeekSheet`, `WeekGrid`, `DayColumn`, `WindowBlock`, `DayEditor` and `DayBar` are
  **duplicated verbatim** in `Furlough/Views/WeekView.swift` (410 lines) and
  `FurloughMac/Views/MacWeekView.swift` (392 lines); the Mac copy's header says it is "kept
  separate so that file stays untouched". Two targets, so the names do not collide today — and
  they will the moment one copy moves to `Shared`, so a hoist deletes both copies in the same
  change.
- Both apps already compile all of `Shared/UI`, which is where the cross-platform SwiftUI views
  live (`AddChoice.swift`, `PendingDelta.swift`, `UtilityPicker.swift`, `LinkCards.swift`). A
  shared grid belongs there. `WeekDraft` is pure and belongs in `Shared/Core`, with tests.
- A **stored** `TimeWindow` never crosses midnight. `isNight`, `split` and `folded` are the
  draft-only fold, and `WeekDraft` is per-day clock-time spans — which is exactly the shape a
  grid edit produces, and the reason this is a smaller job than it looks.
  `TimeWindow.joined` merges touching spans, `WeekDraft.set(_:on:)` already calls it, and
  `WeekDraft.windows` regroups identical spans across days back into one window per span.
- `Furlough.minimumWindowMinutes` is 15 and `minutesPerDay` is 1440. `TimeWindow.isValid` wants
  start ≥ 0, end ≤ 1440, and at least the minimum.
- The two editors bind the draft the same way (`RuleEditorView.swift:158`,
  `MacRuleEditor.swift:133`): the getter builds a `WeekDraft` from the draft windows, the setter
  folds and groups them back and sets the same-every-day flag. The sheet edits a **draft**;
  nothing is enforced until the editor saves, and a loosening still goes through
  `Policy.classify` and waits the delay. A grid edit must land in that same
  `Binding<WeekDraft>` and change nothing else about that path.
- `Furlough/Views/BudgetSlider.swift` is the house precedent for a control built by hand:
  `DragGesture(minimumDistance: 0)`, a `dragging` flag, `.sensoryFeedback(.selection, trigger:
  value) { _, _ in dragging }`, and an `accessibilityAdjustableAction` so VoiceOver can change
  the value without the gesture. Follow it rather than inventing a second style.
- The Mac has no touch: a drag is a mouse drag, and a resize edge should say so with
  `NSCursor.resizeUpDown` under `onContinuousHover`. Haptics are iOS only.

Do these, in order:

1. **Hoist the pure part.** `Shared/Core/WeekDraft.swift`, deleted from both view files, plus
   `Tests/Core/WeekDraftTests.swift`: the round trip (windows → per-day spans → windows), a
   window that crosses midnight surviving it, touching spans joining into one, `apply(from:to:)`
   adding hours on top of what a day already had, `isAllDay`, and a day emptied to nothing.
2. **One grid.** `Shared/UI/WeekGrid.swift`, taking a `Binding<WeekDraft>` and whether it is
   editable, with the hour height and gutter as parameters — the phone uses 19 and 40, the Mac
   17 and 44, and both keep their current metrics. Both view files import it and lose their
   copies; `WeekSheet` on each side keeps its own chrome.
3. **The gestures, on both.** Drag a block to move it inside its day; drag its top or bottom
   edge to resize; delete it. Snap to 15 minutes, and clamp against the neighbours so two
   windows in a day can never overlap — the site does this with one function that returns the
   previous block's end and the next block's start as the bounds, and it is worth copying
   because it makes every case fall out of the same two numbers.
4. **Adding one.** Tap or click empty track. On the phone, decide between a tap and a long-press
   and say in HANDOFF why — a tap is discoverable and a long-press cannot be triggered by a
   scroll that stops on the grid; the site chose the click rather than the press for exactly
   that reason, which is a smaller problem in a sheet that does not scroll under the finger.
5. **Write every edit through `WeekDraft.set(_:on:)`** so joining and the merge back into
   windows stay in the one place that already knows how. `DayEditor` stays: the grid is for the
   shape, the list of pickers is for the exact minute, and a block that is dragged should be
   reachable there afterwards without surprise.
6. **VoiceOver and the keyboard.** Each block gets a label ("8 PM to midnight on Wednesday"), an
   adjustable action that moves it by 15 minutes, and a delete action; on the Mac, arrow keys
   move a focused block and shift-arrows resize it. The grid's existing per-day
   `accessibilityLabel`/`accessibilityValue` should not simply disappear — a schedule has to
   stay readable to someone who will never drag anything.
7. **The sentence keeps up.** `WeekSheet` already prints `TimeFormat.schedule` under the grid;
   make sure it is rewritten as a block is dragged, not only when the drag ends. That sentence
   is how a person checks what they just drew, and it is the part the site demo proved carries
   the whole interaction.
8. **Haptics** at each snap on the phone, gated on the drag the way the slider gates its own.
   Nothing on the Mac.
9. **HANDOFF.** One step at the next free number (43 is the last as of 2026-09-14, and another
   session may have taken 44 — check): the hoist and the two new files, the snap and the clamp
   rules, what stayed in `DayEditor`, and the tap-or-press decision with its reason. Add
   `Shared/Core/WeekDraft.swift` and `Shared/UI/WeekGrid.swift` to the code map. Do not edit a
   step you did not write.

Ask Zach before building: whether a block should be draggable **across days** (it is the
obvious next gesture and it is not in the model — a window belongs to the days it applies to,
and `apply(from:to:)` is how hours reach another day today), and whether the scheduled Anchor's
drop and lift (`Shared/Core/AnchorSchedule.swift`, a `minuteOfDay` and an optional
`liftMinuteOfDay`, not a `TimeWindow`) should eventually be drawn and dragged on the same grid.
Both are his calls, and the answer to either may be no.

Not in scope, whoever asks: changing what a window means or how it is enforced; per-day budgets
(they landed, HANDOFF 11); a pinch or a zoom on the grid; a month view; making the read-only
grid on any other screen editable by accident — check every caller of `WeekGrid` before you
change its signature.

Hand back: `xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination
'platform=macOS,arch=arm64'` green with the new count; the iOS device build and the Mac build
both green; the app installed on the phone and the Mac app running; the two git blocks. What
Zach should do: open a rule with windows on the phone, tap Week, drag the Wednesday block an
hour later and watch the sentence under it change, drag its bottom edge to 11, tap empty track
on Thursday to add one, then open the day from the same grid and check the pickers say what the
grid said. Then the same three gestures on the Mac, with the cursor changing over an edge. Then
save the rule and confirm a loosening still asks for the delay rather than landing at once.

---

# Fable: where a mistake becomes an unblock

Four items. Each one either changes what `Policy.decide` shields, adds a writer of
`Config.anchor`, or crosses devices. Read HANDOFF's "How enforcement works (do not break these
invariants)" before any of them.

---

## 23. The time zone is the clock Furlough does not watch

**Open — proposed 2026-09-14. Not a feature: a hole.**

**Model: Fable — it changes what `Policy.decide` shields, on every app at once. Lane R. Waits
on nothing, but it is the least parallel-safe item on the board: it touches `Clock`, `Policy`
and `RuntimeState`, so run it in its own worktree and land it before 27–30 go near
`PendingNotifications`.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` — especially
step 4, "The clock cannot be an unblock button" — then `README.md`, then
`Shared/Core/Clock.swift` and `Shared/Core/Policy.swift`. Session rules: never commit or push;
when done, print `git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; run `xcodegen generate` after adding a file; keep the build warning-free; every
`Shared/Core` change gets tests in `Tests/Core`; you cannot see the phone, so end with what Zach
should tap and see. Ask Zach before building anything marked "decide with Zach". Another session
is usually mid-edit in this tree, so work in a throwaway worktree (`git worktree add --detach
<your scratchpad>/wt-zone HEAD`, `xcodegen generate` there, build with `-derivedDataPath` under
your scratchpad), copy only your own files back once green, and remove the worktree after.

**Why this exists.** `Clock` defends the wall clock by comparing `Date` against
`CLOCK_MONOTONIC`, so moving the date forward in Settings changes nothing. A **time zone**
change moves neither of those numbers: the same instant is the same `Date` in every zone, so
`Clock.read` answers `drift == 0` and the clock stays trusted. But every decision runs on
`Calendar.current`, which carries the device's current zone — `Policy.dayKey`,
`minuteOfDay`, `weekday` and `date(atMinute:)` all default to `.current`. Three things follow,
and all three are reachable from Settings > General > Date & Time > Time Zone with no delay, no
Pending entry and nothing in the log:

1. Every window's local hours remap at once. Set the zone five hours forward and a 10 PM window
   opens now.
2. `dayKey` rolls. `RuntimeState.isExhausted` is `exhausted[id] == dayKey`, so a budget you have
   already spent comes back.
3. On the Mac it is cleaner than that: `Enforcer.tick` replaces `UsageLedger` whenever the day
   key changes (`FurloughMac/Model/Enforcer.swift:155`), so the count restarts at zero seconds.

This is the same class of hole step 4 closed, left open on the other axis. It has to be shut on
the same terms: not by refusing the change, but by making the loosening half of it wait.

**What is fixed.** Read these in the code before changing anything; do not relitigate them.

- `ClockMark` is `wall` + `uptime`. `Clock.read` answers a `Reading` of `now` and `drift`;
  `SharedState.now` is the only time the rules may use; `Clock.stamp` deliberately keeps the old
  mark while the clock is untrusted, because it is then the only thing that knows the real time.
- **DST is a zone-offset change nobody chose.** `TimeZone.current.secondsFromGMT()` moves by
  3600 twice a year with no user action, and reading that as a zone change would hold every
  loosening in the country twice a year. Key on `TimeZone.current.identifier`; a changed offset
  under the *same* identifier is an ordinary DST transition and must be invisible here.
- `Policy.decide` is pure and already takes a `calendar`. That is the seam — nothing outside
  `Policy` needs to learn what a time zone is.
- A moved **wall clock** holds pending changes, because `state.now` becomes the projection and
  `applyDuePending` cannot reach them. A moved **zone** is different in kind: it delays nothing,
  it re-reads the same rules against different local hours. Do not reuse the drift mechanism for
  it; the answer is to decide under both zones.

**The shape, which is the app's own rule applied to the clock.** Tightening applies instantly;
loosening waits. So: hold the old zone for the delay, and let the new zone apply at once
wherever it is *tighter*.

- The effective decision is the tighter of two decisions — one in the held zone, one in the
  current zone.
- The effective day key is the **held** zone's, because a new day refills budgets, which is a
  loosening whichever way the traveller flew.

A person who really has moved gets a stricter first day, on their home hours where those are
stricter. That is the right direction for a commitment device to fail in, and it lapses on its
own.

Do these, in order:

1. **`Shared/Core/Clock.swift`**: `struct ZoneMark: Codable, Equatable { var identifier: String;
   var since: Date }`, and `RuntimeState.zone: ZoneMark?` with a tolerant decode (nil on a store
   written before this — follow the pattern the rest of `RuntimeState.init(from:)` already uses).
   A first reading is trusted, exactly as a missing `ClockMark` is.
2. A pure `Clock.zone(mark:current:now:hold:) -> ZoneReading`, no I/O: `.settled` when the mark
   is nil or the identifier matches, `.moved(from: String, until: Date)` while
   `now < mark.since + hold`. Stamp the mark wherever `ClockMark` is stamped today, and keep the
   old one while a move is still being held — same reason `Clock.stamp` keeps the old mark.
3. A pure `Policy.tighter(_ a: Decision, _ b: Decision) -> Decision` folding two decisions per
   target: shielded beats open, the earlier close beats the later one, `exhausted` beats `open`.
   Write the truth table out in the doc comment — this function is the whole defence and it is
   the one a later reader will need to check.
4. One wrapper every shield-deriving caller goes through — `ShieldReconciler`,
   `MonitorExtension`, `Enforcer`, `Policy.summary`, `Policy.status`, the home screen — that
   decides once when `.settled` and twice, folded with `tighter`, when `.moved`. Do not change
   `Policy.decide`'s signature; the two calendars are built by the wrapper.
5. The day key: while `.moved`, every reader of `dayKey` uses the held zone's calendar —
   `exhausted`, `warned`, the record, and the Mac's `UsageLedger`. One helper, one place.
6. **Say it.** `Shared/UI/ClockBanner.swift` already exists and is already shown in
   `PendingChangesView` and `MacSheets`; give it a zone case — what changed, which zone is still
   being honoured, and when it stops. `SharedStore.log` records the move the way a clock change
   is recorded, so Diagnostics shows it.
7. Device-local, like the digest preference: the zone mark must not travel in `ConfigExport`,
   must not wait out a loosening delay, and `SharedStore.reset()` must forget it.

Keep: `Policy.decide` pure and its signature unchanged; no new I/O in `Clock`; nothing here
writes `Config`; the one escape README documents (Screen Time access off) stays exactly what it
is.

Decide with Zach, before building: **how long the held zone holds.** The candidates are the base
loosening delay (`config.loosenDelayHours`) and a flat 24 hours. The base delay is the more
consistent answer — a zone change loosens every app at once, which is the same argument
`setDelay` already makes when lowering the delay — but it means a 4-day Hazard tier does not
lengthen it, and Zach may want it to. Also ask whether a traveller should get any way to say "I
really did fly": my read is no, and the reason is worth saying to him — a button that shortens
this is an unblock button with a passport, and the hold expires on its own inside a day.

Tests: `Tests/Core/ZoneTests.swift`, every case on a pinned `Calendar` with an explicit
`TimeZone`, never `.current`:

- New York → Tokyo at 9 AM: a 10 PM–midnight window stays shut, and opens on the held zone's
  schedule instead.
- Tokyo → New York: the tighter of the two still wins, and nothing already shielded is released.
- A spent budget stays spent across the rolled day key, and the Mac's ledger is not reset.
- `America/New_York` across both DST boundaries: `.settled` throughout, no hold, no banner.
- The hold expires: after it, only the current zone is consulted.
- A store with no `ZoneMark` decodes and reads as settled (follow `DecodingTests`).
- `Policy.tighter` against its own truth table, including two decisions that disagree about
  which target is open.

Hand back: the two-zone decision, the banner, the tests, the count from `xcodebuild test
-project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'`,
and the two git blocks. What Zach should do: pick an app whose window has not opened yet today,
set the zone forward past its start, and watch it stay shut with the banner saying why; set the
zone back and watch the banner go; then spend a small budget, roll the zone past midnight, and
confirm it is still spent.

---

## 24. Drop the anchor from the notification that warns you

**Open — proposed 2026-09-14.**

**Model: Fable — a new caller of `AnchorDrop.drop`, reached without the app being opened. Lane
S, first. Waits on nothing; shares `PendingNotifications.swift` with item 28, so whichever runs
second rebases on the first.**

> **28 ran first (HANDOFF 48, 2026-09-14), so rebase on it.** `Notifier.post` now takes a
> `kind:` and posts nothing when this device has that kind switched off; `PendingNotifications
> .plan`/`.sync` take `muted:` instead of `digest:`; the kinds live in the new
> `Shared/Core/NotificationKinds.swift`. A notification that grows an action keeps its kind —
> the action is part of the notification, not a tenth one — so nothing new is needed on that
> screen, and a muted "Time's up" must not post an actionable copy of itself either.

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` — step 42's item
17, the Focus Filter, is the closest precedent and its two warnings apply here — then
`README.md`, then `Shared/Core/AnchorDrop.swift` and `Shared/Core/PendingNotifications.swift`.
Session rules as in item 23.

**Why this exists.** Furlough's notifications arrive at exactly the moment of temptation —
"Window closing in 5 minutes", "5 minutes of budget left", "Time's up" — and every one of them
is a dead end: reading it is all a person can do. Dropping the anchor needs no tag and only ever
tightens, which is why it is already safe from Control Center, the widget, a Shortcut and a
Focus. It is not yet available from the one surface that finds you without being opened.

**What is fixed.** Read these before changing anything; do not relitigate them.

- `Notifier.post(id:title:body:)` is the single choke point for immediate notifications — ten
  call sites across `FurloughMonitor/MonitorExtension.swift` and `FurloughMac/Model/Enforcer.swift`.
  `PendingNotifications.plan`/`sync` is the choke point for scheduled ones, and
  `PlannedNotification` is their value type. Add to those two, never to a call site.
- `AnchorDrop.drop(until:reason:)` is the single entry point for a drop from any process and
  wraps the pure, tested `Policy.drop`. It has **no** release function, deliberately. Nothing you
  add may lift, and the comment you write there should say so, the way `AnchorFocusFilter`'s
  off-case does.
- A `UNNotificationAction` whose options do **not** include `.foreground` launches the app in the
  background to handle the response. That is the app's own process, not a new one — but it is a
  new caller, and the rule is the same.
- `UNUserNotificationCenter.setNotificationCategories` is set per app and applies to
  notifications its extensions post. The hazard is ordering: a notification posted by the monitor
  before the app has ever registered the category shows no button. Register at every app launch
  and say in HANDOFF that the first run after an update may show one buttonless notification.
- `Policy.DropRefusal` already has a written sentence for every refusal. Use them; do not draft
  new ones.

Do these, in order:

1. One category identifier in `Shared/Core/Furlough.swift` beside `anchorControlKind`, and one
   action inside it. Register from the app at launch on both platforms.
2. `Notifier.post` grows `category: String? = nil`; `PlannedNotification` grows the same field and
   `PendingNotifications.apply` sets `content.categoryIdentifier` from it.
3. The handler, in the app's `UNUserNotificationCenterDelegate`, calls `AnchorDrop.drop(reason:
   "notification")` and nothing else. No lift branch exists, not even one that returns early.
4. The refusal path: a notification action cannot raise an alert, so post a reply notification
   carrying `refusal.message`. "Choose apps and pair a tag first" is the common one and it is
   already written.
5. The Mac: `Enforcer`'s four posts get the same treatment, but the Mac's drop is
   `AnchorSync.macDrop` behind the `hasKey`/`cloudAvailable` guards, not `AnchorDrop` — route the
   Mac handler through `MacModel`'s existing drop so `.noPhone` and `.noCloud` still refuse.

Keep: no lift, ever, from any surface you touch; `Policy.decide` untouched; a failed or ignored
action changes nothing about the shields.

Decide with Zach, before building: **which notifications carry the button.** My proposal is the
four that are about a moment — window opened, window closing, five minutes of budget left, time's
up — and not the two about a queued change or the weekly digest, which are about a rule rather
than a temptation. His call, and it is cheap to change later.

Tests: `Tests/Core` cannot post a notification, so test what is pure — that `plan` attaches the
category to exactly the notifications chosen and to none of the others. The rest is a device
check.

Hand back: the category, the handler, the Mac path, and the tests. What Zach should do: set a
window to close six minutes out, lock the phone, and long-press the notification when it arrives
— then check Diagnostics for `anchored (notification)`.

---

## 25. An automation can say when the anchor lifts

**Open — proposed 2026-09-14.**

**Model: Fable — it is the anchor's only way out, set from a process that is not the app. Lane
S, second, behind 24 for the files rather than the logic. Small.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` step 24 (the
Anchor's clock), then `Shared/Core/AnchorSchedule.swift`'s `Policy.drop`,
`Shared/Intents/DropAnchorIntent.swift`, and the `timedUntil` computation in
`Furlough/Views/AnchorView.swift`. Session rules as in item 23.

**Why this exists.** `AnchorDrop.drop` already takes an `until`. `Policy.drop` already validates
it and refuses anything under `Furlough.minimumWindowMinutes` as `.tooSoon`. The Anchor screen
already lets a person choose a lift at drop time. `DropAnchorIntent` is the one caller that never
passes one — so "at 10 PM, drop anchor until 7 AM" cannot be written as a single Shortcut, and an
automation silently inherits whatever "Lifts by itself" was last left at on a screen the person
has to remember to have visited. This is a missing parameter, not a new power.

**What is fixed.**

- `Policy.drop` refuses outright when the anchor is already down, so a parameter can never
  shorten a hold that exists. `tighterUntil` is the function that already decides which of two
  lifts wins on the scheduled path; if you need that answer anywhere, call it.
- The screen already offers exactly this freedom. Do not re-litigate whether a timed anchor
  should exist — HANDOFF step 24 settled it.
- `DropAnchorIntent` is compiled into both the app and the widget extension, goes through
  `AnchorDrop` and never `AppModel`, and must stay that way.

Do these:

1. An optional `@Parameter` on `DropAnchorIntent` for the lift.
2. Resolve it to an absolute `Date` by reusing the Anchor screen's own roll-to-tomorrow rule
   rather than writing a second copy — lift it into `Shared/Core` if that is what sharing takes,
   with tests.
3. Pass it to `AnchorDrop.drop(until:)` and surface `.tooSoon` through the dialog the intent
   already returns.
4. The Control Center control and the widget button keep passing nothing, which keeps meaning
   "whatever the screen says".
5. Leave the existing parameterless `AppShortcut` phrases alone, so "Drop anchor in Furlough"
   still means today's thing.

Decide with Zach, before building: **a time of day or a date.** My read is a time of day, because
"until 7 AM" in a nightly automation has to mean tomorrow's 7 AM, and a `Date` parameter is the
sharp edge that gets that wrong at 11 PM. His call.

Keep: nothing here may lift an anchor that is already down; no new writer of `Config.anchor`
beyond the one that exists.

Tests: the roll-to-tomorrow resolution against a pinned calendar (including a run at 11 PM for a
7 AM lift, and one at 6 AM for a 7 AM lift), and the 15-minute refusal.

Hand back: a Shortcut Zach can build in a minute — Drop Anchor, lift 7 AM — and what the dialog
says when he runs it twice in a row.

---

## 26. A Focus Filter for the Mac

**Open — proposed 2026-09-14.**

**Model: Fable — it writes `Config.anchor` from a new process on a platform that crosses to the
phone. Lane T. Waits on nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` step 42's item 17
**in full** before writing a line — it is the same file and its two hazards are the whole of the
difficulty — then `Shared/Intents/AnchorFocusFilter.swift` and `Shared/Core/AnchorSync.swift`'s
`macDrop`. Session rules as in item 23.

**Why this exists.** `AnchorFocusFilter` is `#if os(iOS)`. A Focus syncs across a person's
devices, so turning on a Work Focus already reaches the Mac — and Furlough on the Mac is the half
that cannot be told. The Mac has the drop path and the link; it has no way to hear a Focus.

**What is fixed.** From step 42, and not to be re-derived:

- The system performs a Focus Filter **twice** — once on activation with the configured
  parameters, once on deactivation with every parameter back at its default. `dropsAnchor` is
  both the switch and the parameter that tells the two calls apart. The off-case returns without
  writing anything, and wiring it to a release is the one edit that would turn this into an
  unblock button on a schedule.
- There is **no scope parameter**, on Zach's call, and there must not be one here: applying a
  scope means writing `Config.anchor.scope` from a new process, and it runs backwards as easily
  as forwards.
- `displayRepresentation` is an instance property, which is how the iOS filter's configuration
  row reads the live anchor and names what it would take. Do the same on the Mac.
- The Mac refuses to drop with no linked iPhone (`.noPhone`) or signed out of iCloud
  (`.noCloud`), because only an iPhone's tag lifts an anchor. A Filter fires with no UI, so a
  refusal has to reach the person some other way.

Do these:

1. Make the existing file cross-platform rather than copying it — one filter, two platforms.
2. Route the Mac's `perform` through `MacModel`'s drop (refusals and all), not `AnchorDrop`,
   which is iOS-only.
3. A refused activation posts a notification carrying `refusal.message`. Silence here would be a
   Focus that a person believes is locking their Mac and is not.
4. `project.yml` adds the file to the Mac target; run `xcodegen generate`.

Decide with Zach: whether the Mac's filter should be offered at all while no iPhone is on the
link, or hidden until one is. Offering it and refusing it is honest; hiding it is quieter.

Keep: no release path; no scope parameter; nothing new in `Config`.

Tests: whatever you add to `Shared/Core` gets tests; the Filter's two calls are a device check.

Hand back: what Zach should do — configure the Filter under System Settings > Focus on the Mac,
turn that Focus on and watch the Mac lock and the phone follow, then turn it off and confirm
**nothing lifts**.

---

# Opus: where the failure mode is a bad screen or a missed API

Four items. None of them changes what is shielded; each is a thing Furlough already knows and
does not show, or a surface it does not use.

---

## 27. The Anchor on the Lock Screen

**Open — proposed 2026-09-14.**

**Model: Opus. Lane U. Waits on nothing; parallel-safe — it adds an attributes type and a widget
view and touches `LiveActivityManager`.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` — step 10, the
Live Activity at window start, is the precedent for everything hard here — then `README.md`,
then `Shared/LiveActivity/`, `FurloughWidgets/WindowLiveActivity.swift` and
`Shared/UI/HourglassStill.swift`. Session rules as in item 23.

**Why this exists.** `FurloughActivityAttributes` is window-only: `windowStart`, `windowEnd`,
`openNames`. The Anchor — the half a person feels most, the one that cannot be talked out of —
puts nothing on the Lock Screen and nothing in the Dynamic Island. A timed drop has a real end
date to count down. A tag-only drop has a start and one sentence, which is the sentence worth
seeing at 11 PM. The glass is drawn at its status in the rows, the widget, the activity and the
Island already; this is the one place it is missing.

**What is fixed.**

- `LiveActivityManager.sync`/`apply` owns every activity's lifecycle and is called from
  `AppModel.enforce`, the monitor and the Mac's equivalent. `ActivityAttributes` is a *type*, so
  a second kind of activity is a second type and a second lifecycle, not a flag on the first.
- `Policy.Summary.shifted(by: clock.drift)` is how the existing manager puts Furlough time onto
  the device's own clock before the system renders it. Miss that and the countdown lies whenever
  the clock is untrusted.
- Step 10 already worked out how an activity is arranged ahead of a moment nobody is present for
  — the scheduled-start `Activity.request`. A scheduled anchor drop is performed by
  `MonitorExtension`, so check the same question there before assuming an extension can start
  one, and if it cannot, arrange it ahead the way step 10 did.
- A Live Activity's buttons run App Intents. The only intent this one may carry is none. Say so
  in the file.

Do these:

1. A second attributes type for the anchor: what it holds (`heldDescription` is written), when it
   dropped, and the lift where there is one.
2. A view beside `WindowLiveActivity`, plus Dynamic Island compact, minimal and expanded, drawn
   with the glass that already exists rather than a new one.
3. Lifecycle in `LiveActivityManager`: started on every drop path (the app, the intent, the
   control, the Filter, the monitor's schedule, a sync from another device) and **ended on every
   release path** — the tag, a timed lift, the monitor's lift callback, and a release that
   arrives over the link. An activity left running after a release is a phone that says it is
   locked when it is not, which is worse than no activity.
4. Reuse the widget's own words. `StatusWidget` already renders the anchor's state; a second
   wording of the same fact is a bug waiting to be reported.

Decide with Zach: **whether both activities may be on screen at once.** My read is that the
anchor supersedes the window one while it holds — a window countdown under a total hold is a
countdown to nothing — but it is a visible call and it is his.

Keep: nothing here writes `Config`; no intent on the activity; `Policy` untouched.

Tests: Core tests for any pure state-derivation you add. The activity itself is a device check.

Hand back: what Zach should do — drop the anchor with a 20-minute lift, lock the phone, watch the
Island and the Lock Screen count down; then drop it tag-only and check the wording; then scan the
tag and confirm the activity disappears rather than lingering.

---

## 28. A switch for every notification, and the last five minutes counted down

**Open — proposed 2026-09-14. Two small things in one file.**

**Model: Opus. Lane V. Shares `PendingNotifications.swift` with item 24 — whichever runs second
rebases on the first.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md` step 42's item 19
(the weekly digest) for why its preference lives where it does, then
`Shared/Core/PendingNotifications.swift`. Session rules as in item 23.

**Why (a) exists.** `digestPreferenceKey` is the only notification preference Furlough has. The
other nine fire unconditionally, so a person who finds "Window opened" noisy has one lever — iOS's
own switch — and it takes "Time's up" and the loosening warnings with it. Muting a notification
changes nothing about what is shielded, so unlike almost everything else in this app it applies
instantly and waits out no delay. The screen should say that out loud; it is the rare setting
here that is free.

**Why (b) exists.** `RuntimeState.warnedAt` records the moment the five-minute warning fired, and
the Live Activity already counts down from it. The home screen says "under 5 min left" as static
text (`Furlough/Views/HomeView.swift:534`) and the row says nothing at all. Same data, two places
that do not use it.

**What is fixed.**

- The preference lives in the **App Group**, not `Config`: it is this device's own, it must not
  travel in an export or wait out a loosening delay, and an app extension does not share the
  app's `UserDefaults.standard` — the monitor needs to read it. `digestPreferenceKey`'s comment
  says all of this; follow it exactly.
- `Notifier.post` and `PendingNotifications.plan` are the two choke points. Ten call sites feed
  the first.
- `warnedMoment(_:dayKey:)` returns nil for a warning that fired before the field existed. Where
  it is nil, keep today's words — do not invent a number.

Do these:

1. A `NotificationKind` with one case per notification actually posted: window opened, window
   closing, five minutes of budget, time's up, anchor dropped, anchor lifted, loosening lands in
   an hour, change landed, weekly digest. Fold the existing digest preference into it rather than
   leaving two mechanisms.
2. `Notifier.post` takes the kind and returns without posting when it is off; `plan` filters on
   it. Every one of the ten call sites passes its kind — that is the whole of the change at the
   edges.
3. Defaults: every kind on, matching today. `SharedStore.reset()` and the testing reset forget
   them, the way `forgetWeeklyDigest` already does.
4. A screen: on the phone, a row under the existing `sectionRow` pattern in `SettingsView`; on
   the Mac, its Settings. One line at the top saying muting applies at once and mutes nothing
   that is enforced.
5. (b) The five-minute countdown: use `warnedMoment + Furlough.warningMinutes` as the deadline in
   the home hero and the target row, so the phone counts the last five minutes down the way the
   Live Activity already does.

Keep: no `Config` field; nothing crosses to another device; `Policy` untouched.

Tests: `plan` omits exactly the kinds that are off and keeps the rest; a store with no
preferences reads as all-on; the digest preference written by an older build still reads
correctly after the fold (follow `DecodingTests`).

Hand back: what Zach should tap — turn "Window opened" off, open a window, get nothing; turn it
back on and check the next one arrives. Then watch a budget's last five minutes count down on the
home screen.

---

## 29. The Mac keeps what it counts

**Open — proposed 2026-09-14.**

**Model: Opus. Lane W. Waits on nothing; Mac-only and parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`README.md`'s Mac table, then `FurloughMac/Model/Enforcer.swift` and `Shared/Core/Record.swift`.
Session rules as in item 23.

**Why this exists.** The Mac is the only half of Furlough that genuinely *measures* time:
`Enforcer.tick` counts seconds while an app or a site is in front and the Mac is not idle. It
then throws the measurement away at every day boundary — `UsageLedger` is replaced whenever the
day key changes (`Enforcer.swift:155`). So the phone, which cannot see how much of a budget was
used, has a fortnight view; and the Mac, which knows precisely, has nothing. The menu bar's trend
(step 42, item 18) draws *shielded* minutes for the same reason: used minutes are not kept.

**What is fixed.**

- `UsageLedger` is deliberately outside `RuntimeState`, because on iOS the counting is Apple's.
  Keep it that way: what you add is Mac-local history, not a new shared model field.
- `Enforcer.onDayRollover(SharedState)` already exists and already fires once a day whether or
  not anyone opens Furlough — `MacModel.start()` wires it to `PendingNotifications.sync`. That is
  where a prune belongs; do not add a second timer.
- The Mac's "Reset everything" goes all the way back to a first run (HANDOFF 31). Whatever you
  store has to go with it.
- `Record` keeps 60 days and is about minutes *held shut*. This is about minutes *used*. They are
  different numbers and must not be folded into one screen that blurs them.

Do these:

1. Keep the last fourteen days of ledgers — matching the phone's fortnight — under a new App
   Group key, pruned in `onDayRollover`. Fourteen days of `[UUID: Double]` is nothing; say the
   measured size in HANDOFF anyway.
2. A pure `Shared/Core/UsageHistory.swift` over them: per target, per day, and a fortnight total,
   with `Tests/Core/UsageHistoryTests.swift`. Pure in, pure out — no `SharedStore` inside it.
3. A Mac screen in the sidebar's foot beside The record, drawn with the existing card and
   hourglass components rather than new ones. Reuse `Shared/Usage/UsageCards.swift`'s shapes
   where they fit; do not port the phone's Screen Time plumbing, which has no Mac equivalent.
4. The menu bar trend gains used minutes beside shielded, if it reads clearly in one row. Check
   the cost the way step 42 did — that section measured 0.17 ms against 2.1 ms for one hourglass
   — and drop it if it does not.
5. `SharedStore.reset()` forgets it.

Decide with Zach: whether fourteen and sixty should be one number, and whether a Mac that has
been counting for a fortnight should say anything on the home hero or leave it to the screen.

Keep: nothing shared with iOS's model; `Policy` untouched; no new notification.

Hand back: the screen, the tests, and what Zach should do — leave the Mac running a day, then
open the screen and check the totals against what he believes he did.

---

## 30. The Mac grows a menu, and both apps get a way to find one app

**Open — proposed 2026-09-14. Two small things; split them if the second turns out to be a no.**

**Model: Opus. Lane X. Waits on nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`'s "The Mac"
section, then `FurloughMac/FurloughMacApp.swift` and `FurloughMac/Views/MacRootView.swift`.
Session rules as in item 23.

**Why (a) exists.** `FurloughMacApp.commands` is `CommandGroup(replacing: .newItem) {}` and a
Help item, and that is the entire menu bar — so the Mac app has no menu of its own and no key
equivalents beyond ⌘? and the default buttons inside sheets. An app whose Quit is refused while
anything is blocked, and whose window is hidden after onboarding, is exactly the one that should
be reachable from the menu bar.

**Why (b) exists.** `searchable` appears nowhere in either app. At twenty-five targets the Mac
sidebar and the phone's hero pager are both a scroll.

Do these:

1. An Anchor menu: Drop Anchor with a key equivalent, disabled with `Policy.DropRefusal`'s own
   sentence as the tooltip when it would be refused. No Weigh Anchor item — there is no tag
   reader on a Mac and a greyed-out release would imply one could exist.
2. A Rules menu: Add Application, Add Website, Visualize windows — each calling what the toolbar
   calls today, not a second path.
3. View items for the two sidebar halves, matching the phone's two pages.
4. (b) A filter field on the Mac sidebar, and `.searchable` on the phone's Rules list.

Decide with Zach, before building (b): **whether the phone gets search at all.** There is a
reasonable answer that it should not — a home screen you have to search is a sign of too many
rules, and the grouping by next opening is meant to make the list readable rather than
navigable. The Mac's sidebar is the stronger case of the two.

Keep: every menu item calls an existing path; nothing new can be reached only from a menu;
`Policy` untouched.

Tests: none for menus. If the filter gains any matching logic beyond a case-insensitive contains,
it goes in `Shared/Core` with tests.

Hand back: what Zach should do — ⌘-drop the anchor from the menu with no tag paired and read the
refusal, then pair one and do it again.

---

# Sonnet: mechanical and verifiable, no logic

Two items. Neither touches `Shared/Core`, so neither needs tests, and both are safe to run beside
anything else on the board.

---

## 31. The largest text size, audited

**Open — proposed 2026-09-14.**

**Model: Sonnet — a walk through view files changing frames. Lane Y. Waits on nothing;
parallel-safe, but it edits `Furlough/Views/*` broadly, so run it when no other phone-UI lane is
open and keep the diff to frames.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`design/DESIGN.md`, then `Shared/UI/Theme.swift`. Session rules: never commit or push; when done,
print `git add <your files>` and a lowercase `git commit -m "..."` for Zach, with no
Co-Authored-By; keep the build warning-free; you cannot see the phone, so end with exactly what
Zach should set and look at.

**Why this exists.** `EmberFont` builds every face with `Font.custom(_:size:)`, which **does**
scale with Dynamic Type — so the text grows as it should. What does not grow is the box around
it, and there are boxes. The clearest is the half tab bar in `Furlough/Views/HomeView.swift:118`:
the icon gets `.frame(width: 22, height: 20)` and the label `.frame(height: 13)`, so at the
largest accessibility size the label is clipped inside a 13-point box. Nobody has walked the app
at that size.

Do these:

1. Find every `.frame(height:)` and `.frame(width:)` that wraps or constrains a `Text` in
   `Furlough/Views/` and `Shared/UI/`. List them all first, in the file, before changing any.
2. Fix the ones that clip at the largest accessibility size: remove the frame, change it to
   `minHeight`, or use `@ScaledMetric` where the fixed height is load-bearing for alignment with
   something else. Choose per site; do not apply one rule to all of them.
3. **The acceptance test is that nothing moves at the default size.** If a change is visible at
   the default, it is the wrong change.

Do not touch: the hourglass (`Shared/UI/Hourglass.swift`, `HourglassGeometry.swift`,
`HourglassStill.swift`) — its geometry is meant to be fixed and it is already
`accessibilityHidden(true)`; the widgets, whose text does not scale the same way and whose
families have hard size budgets; the Mac, which has no Dynamic Type.

Tests: none — nothing in `Shared/Core` changes.

Hand back: the list of every site you found and which you changed, and what Zach should do —
Settings > Accessibility > Display & Text Size > Larger Text, drag to the top, then walk Home,
the rule editor, the Anchor page, Pending and Settings and say what still clips.

---

## 32. The automations that already work, written down

**Open — proposed 2026-09-14.**

**Model: Sonnet — copy and one help topic, no logic. Lane Z. Waits on nothing; parallel-safe.**

You are picking up Furlough, Zach's iOS and Mac app blocker. Read `HANDOFF.md`, then
`site/src/pages/help/nfc-tags.astro`'s "Why a tag and not a code" for the voice already settled,
then `Furlough/Views/HelpTopics.swift` and `Furlough/Model/PhoneIntents.swift`. Session rules as
in item 31.

**Why this exists.** Drop Anchor is already an App Intent, already a Control Center control,
already a widget button, already in Spotlight and Shortcuts, and — since HANDOFF 42 — already a
Focus Filter. So "when I arrive at the library, drop anchor", "at 10 PM, drop anchor", "when
Sleep Focus turns on, drop anchor" are each one automation away, and nothing in the app or on the
site says so. This is the cheapest item on the board: it is a page, not a mechanism. It is also
why no geofencing work is proposed anywhere in this file — the capability exists and only the
documentation is missing.

Do these:

1. A help topic in `Furlough/Views/HelpTopics.swift` and the matching page under
   `site/src/pages/help/`, with three or four recipes written as the exact taps in Shortcuts:
   a time of day, an arrival, a Focus turning on, and leaving a place if it reads well.
2. Say plainly at the top that every one of these **drops** and none of them lifts, and why — a
   Shortcut that could lift is a Shortcut that can be deleted at 9:59 PM. That sentence is the
   point of the page, not a caveat at the bottom of it.
3. Link it where "Where to leave it" already sits on the Anchor screen
   (`Furlough/Views/AnchorScreens.swift`), so the two pieces of advice about living with the
   Anchor are in one place.
4. Check each recipe against the current Shortcuts app before writing the taps down. A recipe
   with a wrong tap is worse than no page.

Keep: no new code paths; no new persisted state; nothing here is something Furlough tracks doing.

Tests: none.

Hand back: the topic in the app and the page on the site, and one automation Zach can build from
the page in under a minute to check the taps are right.
