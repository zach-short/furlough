# Pass-off prompts: the items after the Foqos comparison

Written 2026-09-09, ten items, and grown to twelve the same day. Each numbered section below
is a complete prompt for a fresh Claude session: paste one section, nothing else. The board
says which model to run it on, which lane it belongs to, what it waits on, and — since the
afternoon of 2026-09-09 — **whether it has already been done**, which is the first thing to
check, because most of them have. Submission to the App Store (HANDOFF step 19) is already in
progress, so item 1 is the tail of that, not the start.

## The board

**Where it stands, 2026-09-09.** Ten of the twelve have landed; the record of each is the
HANDOFF step named below, which is the truth about what was built and is fuller than the
prompt that asked for it. **Do not paste a section marked Done** — its prompt describes work
that already exists, and a fresh session following it would build it again. The two left are
both gated on Apple, not on a session: 1 waits for the submission to be approved, and 9 waits
on 1. Read the Done prompts only as history, or where one says a later item should revisit it.

| # | Task | Status | Model | Lane | Waits on | Files it owns |
|---|------|--------|-------|------|----------|---------------|
| 1 | Land the submission, then put the Mac back on Release | **Open** — in progress, see HANDOFF 19 | Opus | Gated | Zach's ASC access | `DEPLOYMENT.md` (archive), `README.md`, `HANDOFF.md` |
| 2 | Scheduled and timed Anchor, plus Control Center and the widget button | Done — HANDOFF 24 | **Fable** | A (2nd) | 3 | `AnchorProfile`, `Policy`, `Monitoring`, `MonitorExtension`, `AnchorView`, `PhoneIntents`, `FurloughWidgets` |
| 3 | Anchor everything except an allowlist | Done — HANDOFF 13 | **Fable** | A (1st) | nothing | `AnchorProfile`, `Policy.decide`, `Decision`, `ShieldReconciler`, `AnchorView` |
| 4 | Sync the Anchor across devices | Done — HANDOFF 18 | **Fable** | A (3rd) | 2 and 3 | new `Shared/Core/AnchorSync.swift`, `AppModel`, `MacModel`, entitlements, privacy page |
| 5 | Per-weekday budgets, then rules for categories | Done — HANDOFF 11; categories **settled as no**, HANDOFF 12 | Opus, Fable reviews | B | nothing | `Rule`, `Policy`, `Monitoring`, `ActivityLimit`, `RuleEditorView`, Mac editor, `ConfigExport` |
| 6 | The record: streaks, minutes shielded, loosenings cancelled | Done — HANDOFF 25, with the fix in 29 | Opus | C | nothing | new `Shared/Core/Record.swift`, `RuntimeState`, `SettingsView`, Mac sidebar |
| 7 | Live Activity at window start | Done — HANDOFF 10 | Opus | C | nothing | `LiveActivityManager`, `MonitorExtension` |
| 8a | Help pages: blocking Safari, Settings and the App Store; what the Mac cannot reach | Done — HANDOFF 23 | Opus | D | nothing | `site/src/pages/help/` |
| 8b | Mac content filter (network extension) | Done — HANDOFF 26 | **Fable** | E | Zach's go-ahead | new `FurloughMacFilter` target, `project.yml`, `MacModel` |
| 9 | iPad | **Open** — gated on 1 | Opus | Gated | 1 approved; 4 or the no-NFC rule | `project.yml`, every iOS view that presents a sheet or popover |
| 10 | Write down the no-QR, no-pause decisions | Done — HANDOFF 23, in the 8a session | Opus | D | nothing | `HANDOFF.md`, `site/src/pages/help/nfc-tags.astro` |
| 11 | More companion pairs, every one confirmed | Done — HANDOFF 30 | **Sonnet** | F | nothing | `Companions.swift`, `CompanionsTests.swift`, new `design/companions-sources.md` |
| 12 | Suggested rules by hazard tier, and an audit for quality-of-life defaults like it | Done — HANDOFF 28 | Opus | G | nothing | new `Shared/Core/RuleSuggestion.swift`, `RuleEditorView`, `Tests/Core` |
| 13 | The link contract: schemas, test vectors and tables a port can be built against | **Open** — added 2026-09-10 | Opus | H | nothing; HANDOFF 37 landed | new `protocol/`, new `Tests/Core/ProtocolFixturesTests.swift`, `HANDOFF.md` |
| 14 | Cache the token map, so the usage page's icons are instant on later visits | **Open** — added 2026-09-10 | Opus | I | the tables-and-monograms commit on main | new `Shared/Core/TokenCache.swift`, `SharedStore`, `UsageReader`, `UsageView.load`, `AppModel.nameUnnamedTargets`, new `Tests/Core/TokenCacheTests.swift`, `HANDOFF.md` |

**Two things landed that this board never planned**, so look for them in HANDOFF rather than
here: the first week with capped delays and the 15-minute undo (HANDOFF 27, the lane-f
session — it is why item 10's prompt carries a correction), and the Mac's Reset everything
going all the way back to a first run (HANDOFF 31, with the detail in its "The Mac" section).

**Item 13 was added 2026-09-10**, after HANDOFF 37 landed: the link contract as data, so a port on another platform can be built against the real record shapes and the real merge rules. It is the one open item not gated on Apple, and it is parallel-safe with everything.

**Item 14 was added 2026-09-10**, the third step of the usage-page speed-up whose first two (cards drawn from the tables, letters for icons, a deadline on the token query) landed the same day: keep Screen Time's answer in the App Group store so the next visit opens on it. Small, iOS only, and it waits only on that commit being on main.

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
