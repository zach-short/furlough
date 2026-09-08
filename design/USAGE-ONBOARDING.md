# Hand-off: turn the usage page into an onboarding step

Written 2026-09-08 by the session that built the usage feature, for the session that will
redesign it. Zach (he runs Furlough, a personal iOS Screen Time blocker; see `HANDOFF.md`)
has used the page on his phone and wants it rebuilt as an onboarding step. Read this file,
then `HANDOFF.md` and `design/DESIGN.md`, before touching code. Ask Zach when a decision is his.

## The one-line goal

An app-by-app judgement. One card per app that answers three questions visually, in this
order, then offers **Apply** or **Skip**:

1. **What is it.** The real icon and name, and how much time it takes in a day.
2. **Where the time goes.** A picture, not a sentence: which hours, which days.
3. **What Furlough would do about it.** The rule as a picture with a one-line consequence,
   then the button.

Deterministic throughout. No model, no scoring that cannot be explained in a sentence.
`UsageAnalysis` already does the arithmetic and is tested; change its numbers if the advice
is wrong, not its nature.

## What exists

- `Shared/Core/UsageAnalysis.swift`: pure Foundation. Folds hourly usage onto a week
  (`UsageHistogram`), finds the shortest run of hours holding 60 % of an app's use
  (`peak`, wraps midnight), closes those hours per weekday, groups days with identical hours,
  keeps half the daily average as the budget. Emits a ready `Rule`. Every knob is a
  `static let` at the top. Tests in `Tests/Core/UsageAnalysisTests.swift`.
- `Shared/Usage/UsageCollector.swift`: walks Screen Time's data into histograms, keyed by
  bundle identifier or `web:` + domain, carrying tokens. Declares the report contexts
  `.rank(n)` and `.focus`. Compiled into the app and the extension.
- `FurloughReport/`: the ExtensionKit report extension (`DeviceActivityReportExtension`). Five
  `RankReport` scenes (one per position, so each row has a height the app knows) and one
  `FocusReport` (one app's 24-hour bars). Views in `ReportViews.swift`. Scenes are
  `nonisolated` on purpose; see the comment there.
- `Furlough/Model/UsageReader.swift`: the filters the app asks with, `hasDataAccess`, the
  in-app fetch (`summary()`), and a token lookup for entries that arrive without one.
- `Furlough/Views/UsageView.swift`: the page. Reached from Settings, "Where the time goes".
- `project.yml`: the `FurloughReport` target, and the data-access entitlement on `Furlough`.

Uncommitted as of this writing: `project.yml` and `Furlough/Furlough.entitlements` (the
entitlement, clean, safe to commit), and `UsageReader.swift` / `UsageView.swift`, which a
sibling session has also edited to add a `.host` case that depends on their uncommitted
model change. Check `git status` and `git log` before assuming anything about what is in HEAD.

## How the numbers reach the app, which decides everything

There are two paths, chosen at runtime by `UsageReader.hasDataAccess(model.authorization)`.

**Path A, data access.** iOS 26.4 added `DeviceActivityData.activityData(filteredBy:)` and
`FamilyActivityData.shared.installedApplications`, behind the entitlement
`com.apple.developer.family-controls.app-and-website-usage` and the status
`.approvedWithDataAccess`. The app gets minutes per app per hour, plus tokens. It does **not**
get names: `Application.localizedDisplayName` is nil on this path (Zach's screenshot shows
`com.zhiliaoapp.musically`). Names and icons come from SwiftUI's `Label(token)`, which is
exactly what `TokenLabel` in `Furlough/Views/Components.swift` already does for the home
list. You cannot read the name as a string; the shield extension learns it later into
`Target.systemName`. Apple's docs: development builds work in any region; App Store customers
get data access only in the EU; with the entitlement on, the Screen Time prompt is
all-or-nothing. Zach knows and chose it. Zach's phone is on this path today.

**Path B, no data access.** Only the report extension ever sees the numbers. It runs in a
sandbox with no network and App Group writes that never land; its output is pixels. Nothing in
it can tell the app which apps qualified, what rule was suggested, or that a button was
tapped. The extension does see `localizedDisplayName`. Every `DeviceActivityReport` the app
hosts is a remote view; the current page mounts five for the ranking plus one per managed
app, and that is why scrolling stutters. Any design for this path has to live with: few
remote views at a time, fixed heights the app chooses, and a hand-over to the picker and the
rule editor for anything that changes state.

## What Zach saw, and what is wrong with it

Screenshots from 2026-09-08 on an iPhone 17 Pro, iOS 26.6, with data access granted.

1. **Scrolling is not smooth.** Too many remote views (see Path B above). On Path A the page
   should contain none at all; the app has the numbers.
2. **Bundle identifiers instead of names**, and no icons, in the app-drawn "Suggested rules"
   card. Fix: `Label(token)` (or `TokenLabel(kind:)`). Never show a bundle identifier.
3. **Tapping Apply removed that row from view.** It should stay, turn into an "Applied" state,
   and offer undo. Reproduce first; I could not from the code. Hypotheses: the alert and the
   re-layout of remote views underneath it; or `load()` re-running through
   `.task(id: model.authorization)`. Check `SharedStore.log` output around a tap.
4. **The same app appears three times**: the app's "Suggested rules" row, the extension's
   rank card, and the extension's focus chart, the last titled "This app" because
   `systemName` is only learned once the shield has shown. One app, one card.
5. **The words are hard to interpret.** "Weekends 12:00 AM–1:00 PM, 8:00 PM–midnight ·
   Weekdays 12:00 AM–9:00 AM, 6:00 PM–midnight · 45 min/day" lists *allowed* windows as
   clock times. Nobody reads that as "closed during the school day". The rule needs to be
   drawn, and the sentence needs to say what it closes and why.
6. **Some advice looks odd.** TikTok's peak came out as 7 AM to 4 PM on weekdays, nine hours,
   because 60 % of his use is spread across the day. Closing a nine-hour block is not a
   suggestion anyone takes. See the knobs below.

## The page to build

### Card anatomy, one per app

- **Header**: `Label(token)` at a generous size, the daily figure in numerals
  ("1 h 17 min a day"), pickups if they add anything.
- **Where**: the 24-hour bars already in `HourBars`, kept, but with a drawn band over the
  hours the rule would close, and a weekday/weekend distinction when the two differ (two thin
  rows, or a segmented toggle). Under it one plain sentence: "Mostly evenings: 7 PM to 4 AM
  on weekends." Not a list of clock times.
- **What Furlough would do**: draw the rule. A 24-hour strip per day group, open in cream,
  closed in ember, the budget as a pill ("35 min a day"). Then one line of consequence:
  "Closed 7 PM to 4 AM on weekends, and 35 minutes a day the rest of the time."
- **Buttons**: Apply and Skip. Applied cards stay, marked, with Undo. Skipped cards collapse
  to a line.
- **No second listing anywhere on the page.** The "Where the time goes" ranking and the
  "What Furlough manages" charts go away; their content is these cards.

### Path A flow (native, no remote views)

Fetch once with `UsageReader.summary()`, rank with `UsageAnalysis.rank`, draw the cards
natively. Apply does what `UsageView.apply` does now (adds through the picker path with the
existing selection kept, then `model.apply(rule:)`), but the card updates in place. A summary
at the end: "3 apps managed, about 2 h 10 min a day taken back." Re-runnable from Settings.

### Path B flow (the extension draws, the person carries)

Say plainly, once, that Furlough cannot read the numbers here and why, and that the cards are
drawn by Screen Time. Show one app at a time: a single `DeviceActivityReport` in a fixed frame
whose context steps through `.rank(1)`, `.rank(2)`, … with app-side Previous/Next, so at most
one or two remote views exist. The extension's card should carry the same anatomy as Path A's
(it has names; try `Label(token)` for icons there too and verify it renders in the extension).
The action becomes "Manage this app": open `FamilyActivityPicker`, and when a pick comes back
open the rule editor right away so the person types what the card shows. Do not pretend the
app knows the suggestion. If you want a step further, the app can offer three or four named
candidate rules ("Evenings off", "Bedtime", "Budget only") and pass each as a separate report
context so the card can say which one fits; only do this if it stays simple.

### As an onboarding step

After Screen Time authorisation succeeds and before the first rule is written, offer "See
where the last two weeks went" as the next step in `OnboardingView`. Skippable. If data access
is possible but not granted (`isAuthorized` without `.approvedWithDataAccess` on iOS 26.4+),
the step opens with the ask that `UsageView.dataAccessCard` makes today. Decide with Zach
whether declining data access sends the person down Path B or straight to the picker.

### Voice

Furlough's copy is short, plain, and honest (see `design/DESIGN.md` and the existing
onboarding text). Prefer "Closed 7 PM to 4 AM" to any list of windows. Numbers in Geist Mono,
names in Bricolage, body in Onest; the palette is `Ember`. Dark ground, no white cards.

## Knobs to reconsider with Zach

All in `UsageAnalysis`:

- `peakShare = 0.6` and `longestPeakMinutes = 10 * 60`: a diffuse daytime habit yields a long
  daytime closure. Consider a lower cap (six hours?) with budget-only advice beyond it, or a
  bedtime heuristic: when `lateNightShare` is above a half, close the late hours and nothing
  else.
- `budgetKeep = 0.5`: half of today's average, rounded down to five minutes.
- `minimumDailyMinutes = 10`, `rankLimit = 5`, `dayGroups = [.weekdays, .weekend]`.

Whatever changes, keep it explainable in one sentence on the card, and add a test.

## Acceptance

- Names and icons everywhere; no bundle identifier and no "This app" on this page.
- Path A mounts zero `DeviceActivityReport`s; Path B mounts at most two at a time. Scrolling
  is smooth on the phone.
- Each app appears once, as one card.
- Apply keeps the card, marks it, and can be undone. A summary closes the flow.
- A stranger can look at a card and say what the rule closes and how much time it leaves.
- Both paths work; the Path B copy is honest about what it cannot do.
- `FurloughCoreTests` pass; new pure logic has tests.

## How to build, test, and put it on the phone

The project is XcodeGen output: after adding a file, `xcodegen generate`. Grep build logs for
`BUILD FAILED` rather than trusting a wrapper's exit code. Signing needs an Apple ID in Xcode;
Zach signed in on 2026-09-08 and the `com.zachshort.furlough.report` profile exists. Sibling
Claude sessions edit this repo at the same time; if their uncommitted work breaks the tree,
build from a detached `git worktree` of HEAD with your files copied in, as this session did.

```bash
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedDataTests > build/test.log 2>&1; grep -E "error:|✘|Test run" build/test.log | sort -u
```

```bash
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug -destination 'platform=iOS,id=00008150-0010050A0247801C' -allowProvisioningUpdates -derivedDataPath build/DerivedData build > build/build.log 2>&1; grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED" build/build.log | grep -v appintentsmetadata | sort -u
```

```bash
xcrun devicectl device install app --device 00008150-0010050A0247801C build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app && xcrun devicectl device process launch --terminate-existing --device 00008150-0010050A0247801C com.zachshort.furlough
```

Nothing on the Mac can see the phone's screen. Tell Zach exactly what to open and what he
should see, and wait for his screenshots (HEIC; convert with `sips -s format png`).

## Traps this session hit

- Report scenes must be `nonisolated`: `AppExtensionScene` is a main-actor protocol and the
  extension's `body` is not.
- `FamilyActivityData` and the arrays it returns are not Sendable. Read them in an
  `@concurrent` function and pass the result back encoded; `TargetKind` is Codable.
- A report cannot report its height. Fixed frames only, content top-aligned, texts given
  their lines with `fixedSize(horizontal: false, vertical: true)` and a `lineLimit`.
- The extension bundles its own fonts under `Fonts/`; `UIAppFonts` paths carry that prefix.
- Never run `git commit`; print the `git add` and `git commit -m` lines (lowercase message)
  for Zach, and stage only your own files.

## Questions for Zach before designing

1. Does the onboarding step replace the Settings entry or sit beside it?
2. On Path B, should the step exist at all, or should those users go straight to the picker
   with a one-line explanation?
3. Skip semantics: does skipping an app hide it next time, or just this run?
4. Is a six-hour cap on closures right, or should long daytime peaks become budget-only?
