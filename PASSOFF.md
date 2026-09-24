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
**Closed 2026-09-23, HANDOFF 53.** Zach answered plain Release, and the Mac was rebuilt and
reinstalled that way. The step's "it is a Debug build" had been false since 2026-09-10, and on
the day nothing was installed at all: a session Zach ran had uninstalled Furlough on
2026-09-22. The reinstall starts from onboarding, and it has no Reset everything.

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
| 1 | Land the submission, then put the Mac back on Release | Done — HANDOFF 53. 1.2.0 went live 2026-09-15 (HANDOFF 19); step 4 ran 2026-09-23 as plain Release, no testing button, on Zach's answer. The uninstall residue he asked cleared was refused by auto mode and is his (HANDOFF 53) | Opus | Gated | nothing | `DEPLOYMENT.md` (archive), `design/store/LISTING.md`, new `design/store/REVIEW-REPLIES.md`, `HANDOFF.md` |
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
| 33 | The site sends a Mac visitor to the Mac build | Done — HANDOFF 50; site only, not deployed | Opus | AA | nothing | new `site/src/pages/mac.astro`, `site/src/components/StoreButton.astro`, `Nav.astro`, `Footer.astro`, `site/src/pages/index.astro`, `support.astro`, `site/src/styles/global.css`, `site/src/site.ts` |
| 34 | Furlough for Mac, from download to first block, watched on a clean Mac | Open — the walk is scripted in `design/MAC-FIRST-RUN.md`; the copy waits on Zach walking it | Opus | AA (2nd) | 33, Zach deploying it, and the walk | `design/MAC-FIRST-RUN.md`, `site/src/pages/mac.astro` |
| 35 | The filter offer is spent by a copy that could never take it | Done — HANDOFF 51; not seen on a Mac, and "Move to Applications" is still Zach's call | Opus | AB | nothing | `FurloughMac/Views/MacFilterOffer.swift`, `FurloughMac/Model/MacModel.swift` |

**Two things landed that this board never planned**, so look for them in HANDOFF rather than
here: the first week with capped delays and the 15-minute undo (HANDOFF 27, the lane-f
session — it is why item 10's prompt carries a correction), and the Mac's Reset everything
going all the way back to a first run (HANDOFF 31, with the detail in its "The Mac" section).

**Items 33 and 34 were added 2026-09-16**, out of Zach downloading 1.2.0 from the App Store onto
his Mac and finding it was not the Mac app. It is not, and the store is the reason: the listing
carries a **Mac** compatibility heading ("Requires macOS 15.0 or later and a Mac with Apple M1
chip or later", read off the page 2026-09-16), so Apple silicon Macs are offered the iPhone
build — which HANDOFF 43's "The Mac" section predicted on 2026-09-07 would "launch but could not
enforce". 33 is the site half and is done: a `/mac` page, and every Mac call to action pointing
at it rather than at the App Store. **33 does not fix the cause.** That is one checkbox in App
Store Connect — "available on Mac with Apple silicon", which wants turning off — and it is
Zach's, because an ASC write is not a thing an agent session does here. 34 is what 33 could not
verify and deliberately did not write: the install watched end to end on a clean Mac, so the
first-run permissions can be documented in the order they actually appear rather than merely
named. HANDOFF 43 has listed that walkthrough as owed since 2026-09-14.

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

## Completed prompts have moved

**Consolidated 2026-09-24.** Every full prompt this file used to carry for items 1–33 and 35 is
now in `~/Projects/archive/furlough/passoff-completed/PROMPTS.md`, verbatim and unedited, kept
for R5's sake (a wrong or superseded claim stays findable, not deleted). All of it was Done or
**settled as no** by this date, per the board table above — which stays here, in full, as the
authoritative status, alongside every correction and disproof this board has recorded. The
HANDOFF step a row names is still the fuller truth about what was built.

**Do not paste anything from the archive.** Same reason the board has repeated all along: those
prompts describe work that already exists, or a no that was already answered.

**What is still open:** item 34 alone. It never had a numbered prompt here — its walk is scripted
in `design/MAC-FIRST-RUN.md`, gated on item 33's deploy and Zach walking a clean Mac, exactly as
the board row above says. When it lands, or when anything else is added to this board, it gets a
prompt written here in full — this file is the board's working half; the archive only holds what
has already left it.
