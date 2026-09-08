# Handoff: Furlough

You are picking up Furlough, a personal iOS Screen Time blocker for Zach. Read this file,
then `README.md` and `design/DESIGN.md`, before touching code (and `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md` if the
work is about shipping). Do not re-ask anything under
"Settled". Zach is a web developer (Next.js, Vercel), comfortable with Xcode, and prefers a
small codebase he fully understands over a fork. He is interactive: ask when a decision is his.

## Environment

- Repo: `~/Projects/furlough` (git, main). XcodeGen project: edit `project.yml`, then
  `xcodegen generate`. Never hand-edit the `.xcodeproj` (it is gitignored).
- Mac: Xcode 26.6 (build 17F113, iOS 26.5 SDK), Swift 6.3, Homebrew, XcodeGen 2.46.
- Phone: iPhone 17 Pro, iOS 26.6, UDID `00008150-0010050A0247801C`, paired to this Mac.
  When it is plugged in and unlocked, `xcrun devicectl list devices` says "available" and
  `xcodebuild -showdestinations` lists it; when it says "unavailable", ask Zach to plug it in.
  The build, install and launch commands below are verified. Nothing can screenshot the phone
  from the Mac; Zach sends screenshots (HEIC: convert with `sips -s format png`).
- Apple team `X9V4L6HR2R` (paid). Automatic signing works from the command line; all four
  bundle IDs are provisioned with Family Controls (development) and App Groups.
- Build check (use this after every change; the log goes to `build/build.log`):
  ```bash
  xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug \
    -destination 'generic/platform=iOS' -allowProvisioningUpdates \
    -derivedDataPath build/DerivedData build > build/build.log 2>&1; \
    grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED" build/build.log | grep -v appintentsmetadata | sort -u
  ```
  Keep the project free of warnings in our own code.
- Test check (the rules engine has a macOS test bundle: `Tests/Core`, Swift Testing, no host
  app; `Shared/Core` is compiled into it with `ShieldReconciler.swift` excluded because it
  imports ManagedSettings, plus `FurloughMac/Model/QuitGrace.swift`, which is pure and decides
  whether a Mac app is killed under a save dialog). Run it after every change to `Shared/Core`:
  ```bash
  xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedDataTests \
    > build/test.log 2>&1; grep -E "error:|✘|Test run" build/test.log | sort -u
  ```
  Tests pin a calendar (`fixedCalendar()` in `Tests/Core/Support.swift`: GMT, en_US_POSIX,
  a chosen first weekday), so nothing depends on this Mac's clock, time zone or locale.
  `Policy.status`, `Policy.decide`, `Policy.summary` and every `TimeFormat` function that
  renders a date take a `calendar:` parameter defaulting to `.current` for that reason.
- Install on the phone once connected: build with `-destination 'platform=iOS,id=<UDID>'`,
  then `xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app`
  and `xcrun devicectl device process launch --device <UDID> com.zachshort.furlough`. You cannot
  see the phone. After each phase, tell Zach exactly what to test and what he should see, then
  wait for his report.
- Commit at the end of each phase, with the `Co-Authored-By` line your harness gives you.

## Settled: what Furlough is

- Apps and websites chosen with `FamilyActivityPicker` are shielded by default. Each target
  has allowed windows, each on a set of weekdays (`TimeWindow.days`, every day by default;
  added 2026-09-07 so YouTube can end at midnight on school nights and later on weekends),
  and one daily minute budget. Windows never cross midnight: a late weekend night is an
  evening window plus an early-morning window on the next day. No windows means open all
  day, every day, up to the budget (decided 2026-09-07: a budget alone is the default rule,
  so the editor no longer pre-fills an 8–10 PM window and says "No windows. Open all day, up
  to the budget."); once a target has windows, a day none of them covers is blocked.
  Categories are blocked by their zero budget (`Rule.alwaysBlocked`). The rule editor has a
  "Same every day" toggle that hides or shows a day strip on
  each window, a "Use windows from another app" sheet that copies another target's
  windows, days and budget into the draft, an "Apply these windows to other apps" sheet
  (added 2026-09-07) that saves the draft here and gives it to any number of chosen
  targets in one save (`AppModel.apply`; each classified on its own, so tightenings land
  now and loosenings queue), and a "Visualize windows" sheet
  (`Views/WeekView.swift`): a seven-column 24-hour grid, a per-day editor reached by
  tapping a column, and "Apply to other days" which adds that day's hours to the chosen
  days on top of what they have, joining spans that overlap or touch (Zach's call,
  2026-09-07: merge, not replace). Connected hours are always one window: rows on the
  same days that overlap or touch join when a time picker closes (`DraftWindow.joined`,
  `TimeWindow.joined`), and the week and day pictures draw joined spans. A freshly added
  row is left alone until its times are set, since it starts where the last one ends. `WeekDraft` is the bridge: per-day span lists both ways, merging identical spans
  across days back into one window, so edits in the sheet land in the editor's draft
  through one binding and the Same every day toggle follows. Categories are always-blocked containers; apps inside them that have their own
  windows are excepted.
- Rule-based targets have no unblock action in a Release build, and must never get one.
  Debug builds carry **Settings > Testing > Reset everything** (`AppModel.resetEverything`,
  behind `#if DEBUG`; Zach asked for it on 2026-09-07 after a week-long delay and a
  five-minute FaceTime budget locked him out mid-test): after a confirmation it removes the
  stored state, clears the managed settings, and enforces the empty state, so the app matches
  a fresh install with Screen Time access still granted. Keep it behind `#if DEBUG`; the
  commands in this file build Debug, so it is present on the phone until Zach switches to
  `-configuration Release`. The one exception in every build is the Anchor profile (`Config.anchor`, decided 2026-09-07): a separate
  set of kinds that "Anchor" shields instantly without a tag, and that only scanning the paired
  NFC tag in the app can weigh anchor. While anchored, the list and the tag are locked. Anchoring is
  refused until a tag is paired. When the anchor is off, apps fall back to their rules.
  It was called the Brick until 2026-09-08 and was renamed because that is another product's
  name. Stored state keeps working: `Config.init(from:)` reads `anchor` and falls back to the
  old `brick` key, and `AnchorProfile.init(from:)` reads `isAnchored`/`anchoredAt` and falls
  back to `isBricked`/`brickedAt`. Encoding always writes the new names, so the fallback is
  read-once in practice. Do not drop it: it is the only thing standing between a reinstall and
  a lost pairing. The glyph is still `cube.fill`; SF Symbols has no anchor.
- Tightening edits apply instantly. Loosening edits (longer or more windows, bigger budget,
  removing a target, lowering the delay) queue for the loosening delay (24 h default) and can
  be cancelled from the pending list. A target's first rule is always instant because the
  baseline for a new target is "unrestricted".
- `denyAppRemoval` is on whenever anything is shielded and cleared otherwise.
- The only escape is Settings > Screen Time > Apps with Screen Time Access > Furlough off.
  It is documented on purpose in the app and README.
- No emergency unblocks, no schedules beyond the windows. NFC exists only for the Anchor tag
  (in-app scan of the tag's hardware identifier; no background tag reading, no writes).
  Personal use, Xcode installs.
- Extras that are in scope: "5 minutes left" notification, Live Activity during a window,
  home-screen widget. Websites are supported.

## Settled: the look ("Ember Glass")

`design/DESIGN.md` has the tokens and per-screen specs. Summary: clear iOS 26 Liquid Glass
over a dark warm room with one ember glow low on the screen; Bricolage Grotesque for names,
Onest for body, Geist Mono for every countdown; cream text, ember accent, moss for "open",
amber for pending. The mockups Zach approved are at
https://claude.ai/code/artifact/15056f39-c30e-4295-addf-4dc8d79108ed (section "Glass").

Zach rejected the first mockups as looking AI-generated. He wants glass buttons, better fonts,
and a premium feel. Spend the boldness on the hero countdown and the glowing hourglass; keep
everything else quiet.

Already in place: fonts in `Furlough/Fonts` (static TTFs, OFL licences alongside),
registered via `UIAppFonts` in the app and widget targets; `Shared/UI/Theme.swift` with the
palette (`Ember`), font helpers (`EmberFont`, PostScript names such as
`BricolageGrotesque72pt-Bold`, `Onest-SemiBold`, `GeistMono-Medium`), view helpers
(`emberDisplay`, `emberNumerals`, `emberBody`, `emberCard`), `Eyebrow`, and `EmberWall`
(elliptical glows plus a 7 % grain tile, `Noise` in `Shared/UI/Ember.xcassets`, generated by
`scripts/make-noise.swift`). `Shared/UI/Hourglass.swift` is the living hourglass (see below);
it is vectors, not the generated image, and may stay that way. The shared
catalog also holds `AccentColor`, because the widget target compiles it too and warns if the
accent colour is missing. The app icon is done
(`Furlough/Assets.xcassets/AppIcon.appiconset/icon-1024.png`).

The restyle has been seen on the phone (2026-09-07) and matches the mockups: wall, glass
toolbar circles, hero, countdown, cards, chips, section labels all as intended. Findings from
a sizing lab run on the device, now applied:
- `Label(token)`'s title view ignores `.font`, `.fontWeight`, `.foregroundStyle` and
  `.textScale`, but follows `.dynamicTypeSize` (`.xSmall` ≈ 14 pt, `.xxxLarge` ≈ 23 pt). It
  renders in SF, white. `TokenName(kind:size:)` wraps that; the hero shows the nickname in
  Bricolage when one is set, else the system name at `.xxxLarge`. `legibilityWeight: .bold`
  is applied speculatively; nobody has confirmed it bolds.
- The icon view is always 32 pt whatever is proposed, with the artwork in about 65 % of it.
  `TokenTile` measures it and scales by `size / (32 × 0.655)`, no frame of its own.

## Settled: the living hourglass (Direction C, header H1, chosen 2026-09-07)

The brief with all the directions is `design/HOURGLASS.md`; its "Chosen" section records what
was built and where. The short version: the top bulb is the window and drains with the
countdown, exact; the mound's colour is the budget (sand, Amber after the 5-minute warning,
Ember when spent), because the Screen Time API reports budget only at those two callbacks.
No quarter thresholds were added. The home header pages through every target in the list's
order with a strip of 11 pt status hourglasses as the indicator; rows, the widget and the
Live Activity show the same glass in the status colour. `design/DESIGN.md` has the status
table. Not yet seen on the phone: install, then check the test steps in the last message.

## Code map

- `Shared/Core` (compiled into all four targets, no SwiftUI):
  `Models.swift` (Weekdays bit set stored as a bare integer, TimeWindow with `days` and a
  tolerant `init(from:)` that reads old rules as every day, Rule with `isAllDay` and
  per-weekday `windows(on:)`/`allowedMask(on:)` that answer `Rule.allDay` when there are no
  windows, and a 7-day `isTighterOrEqual`, Target, AnchorProfile,
  Config with a tolerant `init(from:)`, PendingChange, RuntimeState, SharedState),
  `Policy.swift` (pure engine: `status(of:config:)` returns `.anchored` first and looks at
  today's weekday, `nextOpen(in:afterWeekday:)` searches up to a week ahead, `NextOpen` carries
  `daysAhead`, `decide` adds anchor-only kinds to the shields, `applyDuePending`, `classify`
  tightening/loosening, `windowFraction`, `summary` with `isAnchored`/`anchoredCount` and
  `openStart`/`openWarned`/`nextOpenIsExhausted` for the widget's glass, `nextTransition`),
  `SharedStore.swift` (App Group UserDefaults JSON plus a capped activity log; `reset()`
  drops the state and keeps the log),
  `ShieldReconciler.swift` (idempotent shield apply and `denyAppRemoval`),
  `ActivityNaming.swift`, `TimeFormat.swift` (`days`, `schedule`, `chip`, `nextOpen` with
  weekday names, + `ShieldText`; every function that renders a date takes a `calendar:`),
  `Hosts.swift` (`normalize`, `matches`; it lived in `MacModel.swift` until the tests wanted
  it, and is harmlessly unused on iOS),
  `PendingNotifications.swift` (`PlannedNotification`, the pure `plan`, `sync`, and the one
  `Notifier` both platforms post through),
  `ActivityLimit.swift` (how many DeviceActivity activities a save would need; iOS-only, and
  harmlessly unused on the Mac).
- `Tests/Core` (target `FurloughCoreTests`, macOS, Swift Testing, no host app): `Support.swift`
  (the pinned calendar and the fixtures), `ModelsTests`, `PolicyStatusTests`,
  `PolicyPendingTests`, `PolicySummaryTests`, `NamingTests`, `DecodingTests`, `ClockTests`,
  `QuitGraceTests`, `PendingNotificationTests`. 110 tests in 17 suites.
- `Shared/LiveActivity/FurloughActivityAttributes.swift` (app + widgets).
- `Shared/UI/Theme.swift` (app + widgets), `Shared/UI/Hourglass.swift` (`HourglassState`
  with its presets and `of(target:status:runtime:now:)`, `HourglassView(state:phase:)` pure,
  `LivingHourglass` animated, `TopSandShape`/`MoundShape` animatable).
- `Furlough/` app: `Model/AppModel.swift` (`@MainActor @Observable`; `enforce()` folds in due
  pending changes, calls `Monitoring.register`, `ShieldReconciler.reconcile`, reloads widgets,
  syncs the Live Activity), `Model/Monitoring.swift` (DeviceActivity registration),
  `Model/LiveActivityManager.swift`, `Model/TagScanner.swift` (Core NFC tag session as one
  async call; the identifier is read at detection, no connect), `Views/`: `Root` (dark scheme,
  ember tint, holds the launch screen for a returning user and dissolves between launch,
  onboarding and home), `Launch` (`LaunchView`, the `Launch` timings,
  `HourglassState.launching`), `Onboarding`, `Anchor` (`AnchorView`, `AnchorCard` on Home, `AnchorToggleButton`,
  `AnchorGlyph`),
  `Home` (`HomeContent` holds the featured page id, `HomeGroups` for the sections including
  "Later this week" and `ordered` for the page order, `HeroPager`, `HeroPage` ticking once a
  second, `HeroIndicator`, `EmptyHero`, `TargetRow`; the + button shows `AddChoicePopover`
  from `Shared/UI/AddChoice.swift`, Application or Website, added 2026-09-07; both end at the
  one `FamilyActivityPicker`, which holds websites under each category as "Add Website", so
  the choice sets the picker's header and footer, and Website first opens
  `AddWebsiteGuideView` (added 2026-09-08) with the three steps to a site, because the footer
  alone read as a broken button; everything is presented through `openAfterDismissal`, a short
  wait, because a sheet presented while the popover or the previous sheet is still dismissing
  is dropped), `AddWebsiteGuide` (a self-sizing sheet: measured `contentHeight` into a
  `.height` detent, `StepRow`; the only way iOS mints a `WebDomainToken` is inside Apple's
  picker, so there is no typed-host path on the phone the way there is on the Mac),
  `Components` (`TokenLabel`, `TokenName`, `TokenTile`,
  `StatusChip`, `RowCopy`, `ProminentButton`, `GhostButton`, `SectionLabel`, `Footnote`,
  `CardDivider`), `RuleEditor` (`WindowRow` with `DayStrip`, `CopyRuleSheet`, `TimeChip`,
  `TimePickerSheet`, `EffectBanner`), `WeekView` (`WeekDraft`, `WeekSheet`, `WeekGrid`,
  `DayColumn`, `WindowBlock`, `DayEditor`, `DayBar`), `BudgetSlider` (piecewise
  linear over the 5/30/60/120/240 ticks), `PendingChanges`, `Settings` + `LogView`. Screens are
  `ScrollView`s over `EmberWall`, not `List`/`Form`; the iOS 26 toolbar supplies the glass.
- `FurloughMonitor/MonitorExtension.swift`: every callback reconciles from shared state.
- `FurloughShield/ShieldExtension.swift`: reads shared state, writes the copy via `ShieldText`,
  and records the name iOS gives the app it is covering (see the naming note below).
- `FurloughWidgets/`: `StatusWidget.swift`, `WindowLiveActivity.swift`, bundle.
- `design/`: `DESIGN.md`, `HOURGLASS.md` (the next brief), `icons/` (candidates);
  `scripts/make-icon.swift` (old placeholder), `scripts/make-noise.swift` (the wall grain).

## How enforcement works (do not break these invariants)

- One repeating DeviceActivity "day" (00:00 to 23:59:59, warningTime 5 min) carries one
  threshold event per target with a rule, named `budget:<uuid>:<minutes>`, with
  `includesPastActivity: true` so re-registering mid-day does not reset the day's usage.
  Pending (not yet effective) rules are registered too, so a loosening that lands while the
  app is closed is still enforced. The monitor ignores a threshold smaller than the currently
  effective budget.
- One repeating activity per distinct span, named `window:<start>-<end>` in minutes of day,
  whatever days the span applies on (`TimeWindow.span` drops the days before deduping). A
  callback on a day the window is off just reconciles to the same shields. iOS allows 20
  activities total, so at most 19 distinct spans across all targets and days; windows must
  be at least 15 minutes and cannot cross midnight (end is exclusive, 1440 means midnight).
  Do not register one activity per span per weekday: it would blow the limit fast.
- A rule without windows registers no window activity: the day activity's midnight callback
  resets it and its budget event limits it. `Policy.summary` lists such targets in
  `allDayNames`, not `openNames`, so they get no closing countdown and no Live Activity; the
  widget shows them as "Open all day" when nothing else is open or coming, else as a line
  under the card, and drains their glass over the day.
- Every monitor callback, every app activation, and every edit ends in
  `ShieldReconciler.reconcile`, which recomputes shields from persisted state. Nothing toggles
  state incrementally.
- Exhaustion is keyed by target id and day (`yyyy-MM-dd`), so a missed midnight callback
  still resets.
- `SharedStore.save` stamps `runtime.clock` on every save and returns the stamped state. Do not
  bypass it by writing the defaults key directly, and do not advance the mark while the clock
  is untrusted: that is what makes a forward jump stick until it is undone.
- The shield extension does not write the state. It folds due pending changes in memory for
  display, and the only thing it writes is under a key of its own: the name Screen Time
  gives the app it is covering (`SharedStore.learnName`, key `furlough.names.v1`, by target
  id). A token is opaque everywhere else — only `Label(token)` draws a name, and only
  inside the app, never in a widget — so the shield is the one place a name can be read as
  text. `SharedStore.load` folds those names into `Target.systemName`, which `displayName`
  prefers over "This app" and a nickname still beats, so the widget, the notifications and
  the Live Activity say the app's name from the first time Furlough blocks it. Added
  2026-09-08 because the widget only ever said "This app". A target added but never yet
  blocked still has no name; set a nickname to name it sooner.
- `Policy.decide` is the union of rule shields and, while anchored, every kind in the anchor.
  `allowedApps` never contains an anchored app, so category exceptions cannot leak one through.
  `AppModel.anchor()`, `unanchorWithTag()`, `pairTag()`, `setAnchorSelection()`, `unpairTag()`
  are the only writers of `Config.anchor`; the last three refuse while anchored.

## Known API facts and quirks

- Family Controls authorization and NFC do not work in the Simulator; build for the device.
- NFC: the app entitlement `com.apple.developer.nfc.readersession.formats` = `TAG` and
  `NFCReaderUsageDescription` are in `project.yml`; automatic signing adds NFC Tag Reading to
  the App ID. `NFCTagReaderSession` polls ISO 14443 and ISO 15693; `identifier` is read
  without connecting (unverified on device, see step 2).
  `AuthorizationStatus.approvedWithDataAccess` exists from iOS 26.4; `AppModel.isAuthorized`
  handles it with a default case.
- After a cold start `AuthorizationCenter.shared.authorizationStatus` reads `.notDetermined`
  for a moment before the real answer, which flashed onboarding before Home (Zach reported it
  2026-09-07). `AppModel.observeAuthorization()` follows the `$authorizationStatus` publisher
  and enforces when access arrives after activation; `AppModel.wasAuthorized` (the app's own
  defaults, key `furlough.wasAuthorized`, set on a definite answer) lets `RootView` hold
  `LaunchView` for `Launch.hold`, plus up to `Launch.patience` while the answer is still
  pending, then dissolve. The system launch screen is the `LaunchBackground` colour (Ground)
  from `project.yml`, so the flat frame before ours matches.
- Live Activities cannot animate custom views, so the hourglass in the activity and the
  island is drawn at the level of the last sync; only `Text(timerInterval:)` moves by itself.
- ActivityKit's `Activity` is not Sendable; `LiveActivityManager` marks it
  `@retroactive @unchecked Sendable` and does its work in a detached task. Live Activities can
  only be started by the foreground app, so today one starts only if Zach opens Furlough while a
  window is open. The iOS 26 `Activity.request(..., start:)` / `startDate:` overloads (see the
  ActivityKit swiftinterface in the SDK) may allow scheduling the next window's activity ahead
  of time; untested.
- Forum reports: threshold callbacks can fire a few minutes late, occasionally twice, and on
  iOS 26.2 sometimes with zero usage. The idempotent design absorbs the first two; if Zach
  reports budgets exhausting early, the activity log (Settings > Activity log) shows the raw
  callbacks.
- `FamilyActivitySelection(includeEntireCategory: true)` expands a picked category into
  individual app tokens so each app gets its own rule.
- The shield is laid out by iOS; we only control the icon image, background blur and color,
  title, subtitle, and button labels and colors.
- XcodeGen: the app target picks up `Furlough/Fonts` automatically as resources; the widget
  target lists the folder explicitly with `buildPhase: resources`. `.xcassets` under a
  `sources:` path are compiled for every target that lists the path.
- iOS 26 deprecates `Text + Text`; interpolate instead (`Text("… \(date, style: .relative)")`).
- `Label(token)` from FamilyControls is `Label<FamilyActivityTitleView, FamilyActivityIconView>`,
  a regular in-process SwiftUI view, so `.labelStyle`, `.font` and `.foregroundStyle` should
  apply; unverified until step 2.

## Where the 2026-09-08 review landed

Zach reviewed the whole repo on 2026-09-08 and listed what was unfinished, what could be
improved and what he would add. Each item is below with where it went, so nobody re-derives
the list. The numbers point at "Next work, in order".

Done:

- **A test target for the rules engine** — step 1. `Tests/Core`, 100 tests in 16 suites,
  `xcodebuild test -scheme FurloughCoreTests` on the Mac with no phone. Covers
  `isTighterOrEqual`, `TimeWindow.joined`, `nextFree`, `nextOpen`, `applyDuePending`,
  `Policy.status`/`decide`/`summary`/`classify`/`nextTransition`, `Hosts`, `Clock`, older
  stored JSON, and `QuitGrace`. **Not** covered: `WeekDraft`, which lives in
  `Furlough/Views/WeekView.swift` and so is outside the Core-only bundle; moving it into
  `Shared/Core` would make it testable and is worth doing when step 16 unifies the views.
- **The rename** — step 2. Brick became Anchor. Zach confirmed the name in the same review and
  wrote it as "Anchor/Unanchor". Confirmed the same day and done: the verb is **Unanchor**
  everywhere the user sees it, and prose says the tag *releases* the anchor. `weighAnchorWithTag()`
  became `unanchorWithTag()`; `AnchorOutcome.released` already read correctly.
- **The clock cannot be an unblock button** — step 4. `ClockMark`, `Clock.read`, and pending
  changes held while the device's clock disagrees.
- **The Mac force-quitting two seconds after asking** — step 7, and the reason `QuitGrace`
  exists. A blocked editor with unsaved work no longer loses it.
- **The Mac reading only the front tab of the front window** — step 7. Every window of every
  running browser is read and redirected now.
- **The Mac having no watchdog** — step 7. Zach said yes on 2026-09-08: `SMAppService.agent`,
  `open -g -b` once a minute. Force Quit still lifts every block; it just stops buying the
  rest of the day.

Open, and where each one lives:

- Nothing tested on the device beyond the basics → step 3, the two checklists. Zach's report
  is still outstanding, and it is the gate on a lot of this file.
- Third-party iOS browsers (does a web-domain shield reach Chrome on the phone?) → step 3; the
  answer goes in README's limits either way.
- The Live Activity only starting if the app is opened during a window → step 10.
- The shield icon still being the SF hourglass → step 17.
- The duplicated Mac UI (`MacComponents.swift`, `MacWeekView.swift`, two `Notifier`s) → step 16.
- Safari web apps in the Dock bypassing host rules → step 7. No web app on this Mac to test.
- **The 19-window limit only being checked after Save** — **done**, step 6, as `ActivityLimit`.
- Window start lagging by minutes with no way to hurry it → step 6/step 3; the shield extension
  has the App Group and the entitlement, so it may be able to reconcile itself on `.open`.
- Categories only being blockable all day → step 12. Ask Zach first.
- Pending cards showing the new rule rather than old → new → step 6.
- `widgetURL` and the `furlough://target/<id>` scheme, and iPad → step 6.
- Anchor from anywhere (App Intents, Siri, Control Center, the Action button) → step 8.
- Real usage on the phone (`DeviceActivityReport`) → step 9.
- Pending-change notifications → **done**, step 5.
- Per-weekday budgets → step 11.
- Anchor everything except an allowlist → step 13.
- A second tag → step 14.
- A longer delay for the worst apps → **done**, step 15, as four utility tiers rather than a
  raw hours field, because one tier drives both the delay and the warnings.
- iCloud sync of the Anchor → step 18. Rules cannot sync: tokens versus bundle ids.

## The utility tiers, reviewed 2026-09-08

The tier feature (`Utility`, `AppUtility`, `UtilityPicker`, `Target.utilityLevel`) was written in
a parallel session and reviewed after it landed. The delay arithmetic holds up: `delayHours`
floors at `Furlough.minimumLoosenDelayHours` so a small base times `essential` cannot round to
nothing, `setDelay` waits `Config.longestDelay` rather than the base because cutting the base
loosens every target at once, and a tier moving toward essential queues behind the delay the
target has *today*. The obvious escapes were traced and none of them shorten a wait:
"call it essential then loosen it", remove-and-re-add, and cutting the base while a target is
essential all cost the old delay first.

Three defects were found and fixed:

- `hasChanges` in both rule editors compared `target.utilityLevel` (a `Utility?`, nil until
  someone picks a tier) against `tier` (never nil). `nil != .useful` is true, so Save was live on
  an untouched editor for every target nobody had tiered, the banner said "Only the name changes"
  instead of "No changes", and saving recorded a tier the user never chose — which turns off the
  suggestion for good. Now compares `target.utility`.
- A queued tier change could not be cancelled from the editor. The picker is seeded from the
  *queued* tier (`pendingTier ?? target.utility`), but `setUtility` guarded on the *saved* tier, so
  choosing the saved one back compared equal, returned `.unchanged`, and left the loosening
  queued — the wrong way round for a commitment device. The decision now lives in
  `Policy.plan(utility:for:queued:)`, which is pure and tested: it drops a queued change whatever
  else it decides, and treats "the tier it already has" as an instant change when one was queued.
  Both `AppModel.setUtility` and `MacModel.setUtility` go through it.
- `warnsBeforeAnchoring` promised in its comment to warn "one tier wider" than blocking and was
  in fact identical to it. Zach chose the comment's version on 2026-09-08: idle now warns before
  an anchor and still says nothing before an ordinary rule, since anchoring is instant and only
  the tag lifts it. `UtilityText.fallback` gained an idle line, because the useful tier's "worth
  having around" would have been flattery. One test in `UtilityTests` asserted the old silence
  and was updated.

Also: the doc comment for `setUtility` had come to rest above `anchorCaution`, so the wrong
function was documented on both platforms.

Not changed, and worth a second opinion: `Config.anchorWarning` calls its result `worst` when it
means the *highest*-utility tier held (the lowest `rawValue`), which reads backwards.

## Next work, in order

The plan for this stretch. Tick each phase off here as it lands.

1. **A test target for the rules engine.** Done 2026-09-08: `FurloughCoreTests`, 71 tests over
   `Weekdays`, `TimeWindow`, `Rule`, `Policy` (status, decide, nextTransition, pending,
   classify, summary), `ActivityNaming`, `Hosts` and decoding older stored JSON. Every later
   phase that touches `Shared/Core` adds tests for what it changes.
2. **The rename: Brick became Anchor.** Done 2026-09-08, because "Brick" is another product's
   name. Lock is Anchor, the state is Anchored, release with the tag is Unanchor (the verb was
   Weigh anchor until 2026-09-08, when Zach chose Unanchor).
   Identifiers follow the UI: `AnchorProfile`, `Config.anchor`, `isAnchored`, `anchoredAt`,
   `canAnchor`, `AppModel.anchor()`, `unanchorWithTag()`, `anchorSelection`/
   `setAnchorSelection`, `AnchorOutcome` (`.anchored`, `.released`, `.paired`, `.wrongTag`,
   `.cancelled`, `.failed`), `TargetStatus.anchored`, `HourglassState.anchored`,
   `Policy.Summary.isAnchored`/`anchoredCount`, `HomeGroups.anchored`, and
   `AnchorView`/`AnchorCard`/`AnchorToggleButton`/`AnchorGlyph` in
   `Furlough/Views/AnchorView.swift`. The only place "Brick" survives is `TagScanner`'s comment
   and README, where it names the physical product whose tag also works.
3. **The device test pass.** One checklist for the phone and one for the Mac. Nobody has yet
   seen, on the phone: the shield copy and colours, a shield lifting by itself at a window's
   start, app deletion denied while blocked, the widget, the Live Activity, the living
   hourglass hero (built 2026-09-07, the widget timeline's three-minute entries included), and
   the whole Anchor flow (pair a tag, anchor, a wrong tag refused, weigh anchor, and whether
   the tag identifier is stable across two scans). On the Mac: the shield panel, the browser
   redirect and its one-time Automation prompt, budget counting, the login item, and the
   desktop widget placed on the desktop.
   Sent to Zach on 2026-09-08 as two checklists; his report is outstanding. The Debug build
   installed on the phone that day carries the rename and the clock guard. The Mac in
   `/Applications` is still the 2026-09-07 build: it has to be replaced with README's
   `xcodebuild … -scheme FurloughMac` + `ditto` lines, and Quit is refused while anything is
   blocked, so it may need Force Quit first. Record the answers here.
   The phone checklist: the Anchor card and the paired tag survived the rename; the shield's
   copy and colours; a shield lifting by itself at a window's start; Delete App refused while
   blocked; the widget; the Live Activity; pair a tag, anchor, a wrong tag refused, weigh
   anchor, and whether the tag's identifier is the same across two scans; the clock held and
   released with a pending change; and a blocked site opened in Chrome, for README's limits.
   The Mac checklist: the shield panel, the browser redirect in Safari and Chrome with the
   Automation prompt, a two-minute budget counting down to "Time's up", Open at login across a
   restart, the desktop widget, and the clock banner in the Pending sheet. Record the results here. Also: does a web-domain shield reach Chrome on the
   phone? Put the answer in README's limits.
4. **The clock cannot be an unblock button.** Done 2026-09-08. `ClockMark` (wall time plus the
   machine's count) lives in `RuntimeState`; `SharedStore.save` stamps it on every save, from
   every process, and the mark only advances while the clock is trusted, so a jump cannot be
   laundered by saving again. `Clock.isTrusted(now:uptime:mark:tolerance:)` in `Shared/Core` is
   pure, with a ten-minute tolerance. `Policy.applyDuePending(_:now:trust:)` holds changes that
   `Policy.loosens(_:in:)` says would loosen and applies the rest; `trust` defaults to reading
   this machine's clock rather than to `.trusted`, so no call site can forget and let a shield
   lift. Both Pending screens show `ClockBanner`; the app, the reconciler and the Mac enforcer
   log it, the enforcer once per crossing. The Mac also ticks on `NSSystemClockDidChange`.
   **Not the machine's `systemUptime`**: that stops while a Mac sleeps, so a night with the lid
   shut would read as an eight-hour jump. `Clock.uptime` is Darwin's `CLOCK_MONOTONIC`, which
   counts through sleep and still restarts at boot.
   **Still open, ask Zach**: windows themselves are still read off the wall clock, so setting
   the clock to 9 PM opens an 8–10 PM window. Making an untrusted clock close every window
   would fix it and is a tightening, but it blocks everything until the clock is right.
5. **Notifications.** Done 2026-09-08. `Shared/Core/PendingNotifications.swift` holds the lot.
   `plan(state:now:drift:calendar:)` is pure and tested (`Tests/Core/PendingNotificationTests`):
   for every change still queued it returns a warning an hour before (`lead`) and one when it
   lands, skipping the warning for a change queued with less than an hour to run, since it would
   fire at the same moment as the landing and say the opposite thing. `sync` makes the system
   agree with the plan — stale identifiers withdrawn so a cancelled change stops announcing
   itself, already-correct ones left alone — and is called from `AppModel.enforce` and
   `MacModel.enforce`, so the warning is rescheduled from saved state rather than only when the
   change is queued. Identifiers are `furlough.pending.<change id>.warning|landed`.
   Fire dates are moved onto the device's clock with `Clock.Reading.drift`, because the system
   fires them against its own clock while Furlough runs on its own; which changes are *due* is
   still judged on Furlough's time. Triggers are `UNCalendarNotificationTrigger` including
   seconds, so "landed" does not arrive at the top of the minute before it lands.
   "Window opened" is `MonitorExtension.announceOpening` at `intervalDidStart`, matching targets
   by the span's end minute the way `intervalWillEndWarning` already did, so a window activity
   firing on a day none of its targets use posts nothing.
   `Notifier` now lives in Core with an `id:` on every post; the copies in
   `MonitorExtension.swift` and `Enforcer.swift` are gone, and the Mac's three posts have stable
   identifiers instead of a fresh UUID each time. Nobody has seen any of these on a device.
6. **Small fixes.** The 19-span limit is done 2026-09-08, as `Shared/Core/ActivityLimit.swift`
   rather than `Policy.distinctSpans` (Policy was being edited in another session, and this is
   self-contained anyway): `spans(in:)` mirrors exactly what `Monitoring.register` collects,
   `projecting(_:appliedTo:in:)` applies the same tightening-lands / loosening-queues rule as
   `AppModel.assign`, and `reason(applying:to:in:)` is the sentence shown above Save.
   **The subtlety worth keeping**: a loosening is queued *beside* the target's current rule and
   `Monitoring.register` registers pending rules too, so for the length of the delay both sets of
   spans are live — counting only the new rule would let exactly the edit that overflows through.
   16 tests in `Tests/Core/ActivityLimitTests.swift`.
   Wired into `RuleEditorView` only: the `EffectBanner`, the Save button, the "Apply these
   windows to other apps" action, and `ApplyRuleSheet`'s own button, which re-checks against the
   targets actually ticked. **Deliberately not wired into `MacRuleEditor`**: the Mac has no
   DeviceActivity, so the limit does not exist there and gating on it would refuse valid Mac
   rules. The Mac browser poll at two seconds landed with step 7 (`Browsers.pollInterval`).
   Still open here: pending cards showing old rule → new rule, `widgetURL` and the
   `furlough://target/<id>` scheme, and iPad (ask Zach). `widgetURL` needs a target id on
   `Policy.Summary`, which today carries only names.
7. **Mac hardening**: the 45-second grace before force quit with a countdown on the panel, and
   every window of every running browser rather than only the front one, are both done
   2026-09-08 (`QuitGrace.swift`, `Browsers.snapshots()`, `Tests/Core/QuitGraceTests.swift`;
   the read script was run against Chrome on this Mac and the Safari variant compiles, but
   neither has been seen working by a person — they are on the Mac checklist in step 3).
   The `SMAppService` watchdog is done too (`FurloughMac/Model/Watchdog.swift`), after Zach
   said yes on 2026-09-08. Still open here: Safari web apps saved to the Dock, which run under
   their own `com.apple.Safari.WebApp.<uuid>` bundle id and so bypass host rules entirely —
   there is no web app on this Mac to test against, so it needs one before it is worth writing.
   Nobody has yet watched the watchdog actually reopen Furlough after a Force Quit; that goes
   on the Mac checklist in step 3, along with checking that it does not steal focus.
8. **Anchor from anywhere**: `AnchorIntent`, `AppShortcutsProvider`, a Control Center
   `ControlWidget`, a `Button(intent:)` on the medium widget. Anchoring is tightening, so every
   surface is safe; release stays in the app behind the tag.
9. **Real usage on the phone**: a `FurloughReport` DeviceActivity report extension with a
   `budget` scene on the hero and in the rule editor, a `week` scene behind a History link, and
   quarter-mark threshold events if DeviceActivity accepts four events per target.
10. **Live Activity at window start**, if the iOS 26 ActivityKit swiftinterface has a
    scheduled-start `Activity.request`. If not, document the widget and the notification as
    the coverage and move on.
11. **Per-weekday budgets**: `budgetByWeekday: [Int]?`, `Rule.budget(on:)`, a "Same budget every
    day" toggle, one `budget:` event per distinct value, the monitor filtering by today's.
12. **Rules for categories** instead of always-blocked. Ask Zach first.
13. **Anchor the whole phone**: a scope on `AnchorProfile`, `.all(except:)` with an allowlist.
14. **A second tag**: `AnchorProfile.tagIDs`, pairing another queues as loosening.
15. **Tiers, and the warnings that come with them.** Done 2026-09-08. Zach asked for a delay
    scaled to how useful an app is, and for a warning before blocking one the phone needs — and
    the two are the same axis read in opposite directions, so they are one field, not two.
    `Utility` (`Shared/Core/Utility.swift`) has four cases, `essential`/`useful`/`idle`/`hazard`,
    multiplying the base delay by 0.25/1/2/4 (6 h to 4 days at the default 24 h) and floored at
    `Furlough.minimumLoosenDelayHours` = 1 h, which is Zach's call: essential is fast, never
    instant. `Config.delayHours(for:)` replaced `Config.loosenDelay` at every queueing site in
    `AppModel` and `MacModel`; `Config.longestDelay` is what lowering the *base* now waits out,
    since that loosens every target at once. Picker removals compute their date per target, so
    unpicking Messages and TikTok together does not make Messages wait for TikTok.
    **The invariant that matters**: raising a target toward essential shortens its delay, so it
    is itself a loosening — `PendingKind.setUtility` queues behind the delay the target has
    *today* (`Policy.classify(newUtility:against:)`, which reads `delayMultiplier` and never
    `Rule.isTighterOrEqual`, because a tier changes when a change lands, not what is allowed).
    So "mark it essential, then loosen it" in one save still waits the old, longer delay.
    Moving toward hazard lengthens the delay and lands immediately.
    `Target.utilityLevel` is stored optional — a synthesised `init(from:)` demands every
    non-optional key, and state written before tiers has none — and read through
    `Target.utility`, which answers `Utility.unset` (= `.useful`) so forgetting to choose is
    always the safe way round. `hasChosenUtility` is what tells the editor to offer a suggestion.
    `AppUtility` (`Shared/Core/AppUtility.swift`) is the table: bundle ids (exact, then longest
    vendor prefix), hosts (longest match through subdomains, so `maps.google.com` is essential
    where `google.com` is only useful), and names as the shield learns them. A table and not a
    model on purpose: on the Mac a target already *is* a bundle id or host so a lookup is exact
    and offline, and a server round-trip would make `PrivacyInfo.xcprivacy`'s "Data Not
    Collected" false, which step 19 is filing on. Nothing is applied behind anyone's back —
    the guess is a chip the editor offers, and `Target.utilityLevel` is only ever Zach's answer.
    Warnings: `UtilityText.blocking` for the rule editor (nil for idle and hazard, since
    blocking those is the point and nagging would teach him to swipe past the banner that
    matters), `UtilityText.anchoring` for the anchor. `UtilityPicker` and `CautionBanner` live
    in `Shared/UI`, so the phone and the Mac use one control and the wording cannot drift —
    the first piece of step 16 done early. Saving an essential block asks twice
    (`confirmBlockEssential`), and so does anchoring one; `Config.anchorWarning` picks the worst
    tier the anchor holds and names it. Its limit, and it is real: it can only name anchored
    kinds that are also targets, because an anchor may hold tokens Furlough has no name for.
    Tests: `Tests/Core/UtilityTests.swift`, 24 tests over the multipliers, the floor,
    `longestDelay`, both classify directions, the pending round trip, the table's three lookups,
    `anchorWarning`, and state written before tiers existed.
    **Not done**: the tier has no home on the home screen or in the widget, and nothing sorts by
    it. Zach has not seen any of this on a device.
16. **Unify the Mac duplicates** into `Shared/UI`, only while `Furlough/Views` is quiet.
17. **Imagery** with the Higgsfield MCP, only with Zach's go-ahead per item, preflighting every
    cost (balance was about 413). Reference the icon jobs by id: original
    `27b1c254-594f-46fe-9b3e-232c38a9e9d2`, toned-down (in use)
    `fd975516-80d9-4941-b0c4-6cd7be8fd92a`. Planned: a transparent-background hourglass for the
    shield icon and the hero, an onboarding hero, and short README clips.
18. **Sync the Anchor across devices** through CloudKit or the key-value store. Rules cannot
    sync (tokens versus bundle ids). Ask Zach whether he wants it at all.
19. **TestFlight, then the App Store.** Started 2026-09-08; `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md` is the map and the
    status table. Done so far: `Shared/PrivacyInfo.xcprivacy` (Data Not Collected; the two
    required-reason APIs are UserDefaults `1C8F.1`/`CA92.1` and system boot time `35F9.1` for
    `Clock.uptime`), carried as a resource by all four iOS targets and verified at the root of
    the app and each `.appex`; `scripts/ExportOptions.plist`; and a check that the Release
    configuration still compiles clean. **Blocked on Zach**: the Family Controls *distribution*
    entitlement is not yet requested, and it gates every upload, so it goes first. Also missing:
    an Apple Distribution certificate (this Mac has only the development one), the App Store
    Connect record, and a privacy-policy and support URL. Note for screenshots: the store wants a
    6.9-inch set, the phone is 6.3-inch, and Family Controls does not run in the Simulator, so the
    real screens have to be composed into full-size frames.

## Style rules

Swift 6 language mode with approachable concurrency, SwiftUI, `@Observable`, async/await, no
third-party dependencies. Keep it small: one app target plus the three extensions. Shared
code that the monitor extension uses must not import SwiftUI (memory limits).

## The Mac (added 2026-09-07)

Zach asked for windows, app blocking and website blocking on his Mac; NFC was explicitly
optional. Apple's Screen Time API is out: in the macOS 26.5 SDK, `AuthorizationCenter`,
`FamilyActivityPicker`, `FamilyActivitySelection`, `ManagedSettingsStore`, `ShieldSettings`,
`Token`, `DeviceActivityCenter` and `DeviceActivitySchedule` are all `@available(macOS,
unavailable)`, and FamilyControls is `@available(macCatalyst, unavailable)` too, so neither
a native nor a Catalyst build can shield anything. Running the iOS build on the Mac
("Designed for iPhone") would launch but could not enforce. So the Mac has its own
enforcement in a native target, `FurloughMac` (bundle `com.zachshort.furlough.mac`, product
name `Furlough`, macOS 26, non-sandboxed, hardened runtime with the
`com.apple.security.automation.apple-events` entitlement).

- Shared code compiles for both: `TargetKind` is `#if os(iOS)` tokens `#else`
  `.macApp(bundleID:)` / `.host(String)`; `Decision`/`Policy.decide` have a Mac variant
  (`blockedApps`, `blockedHosts` by string). `SharedStore.defaults` on the Mac is the App Group
  suite `Furlough.macAppGroupID` (`X9V4L6HR2R.com.zachshort.furlough`, added 2026-09-08 for the
  widget); it is team-prefixed rather than `group.`-prefixed on purpose, because on the Mac a
  `group.` identifier needs a Mac App Development profile, which needs this Mac registered
  with the team (xcodebuild refused with "Device isn't registered"), while a team-prefixed
  group needs neither. The first access that finds the group empty while `.standard` has
  state copies `furlough.state.v1`, the log, the usage ledger and the onboarded flag across
  once and leaves the old keys in place; `MacModel.start()` logs "moved the store into the App
  Group". So `defaults read com.zachshort.furlough.mac` now shows stale data: read the plist
  in `~/Library/Group Containers/X9V4L6HR2R.com.zachshort.furlough/Library/Preferences/`
  instead (a CLI without the entitlement cannot open the suite through `UserDefaults`).
  `ShieldReconciler.swift` and `ActivityNaming.swift` are excluded from the Mac targets in
  `project.yml`. `Shared/UI` (Theme, Hourglass) compiles unchanged. Fonts ship as a folder
  reference under `Resources/Fonts` with `ATSApplicationFontsPath: Fonts`; the activity log's
  first line says whether they loaded.
- `FurloughMac/Model/Enforcer.swift` ticks every second and on app launch/activate: applies due
  pending changes, decides, asks any running blocked app to quit and shows `ShieldPanel` (a
  floating NSPanel with the iOS `ShieldText` copy), reads the browsers through `Browsers`
  (NSAppleScript, `tell application id`, Safari `current tab`, Chromium `active tab`) only when
  some host has a rule, and redirects a blocked tab to `Resources/Shield.html?t=&s=`.
  `QuitGrace` (its own file, and tested) holds the pause between asking and forcing: 45 seconds
  for a process that has been running at least a minute, so a "Save changes?" sheet can be
  answered, and the old 2 seconds for one that has only just launched, so quitting and
  relaunching a blocked app cannot buy another 45 seconds. The panel counts the grace down;
  it is handed a duration rather than a date, because the card is drawn against the device's
  clock while Furlough runs on its own. `Browsers` reads *every* window of *every* running
  known browser, not just the front window of the front app, and redirects each window that
  is showing a blocked site; it caches each browser's read for `Browsers.pollInterval` (2 s)
  against `Clock.uptime`, so the extra windows do not cost an Apple Event round trip a second. Usage is counted
  in `UsageLedger` (`furlough.mac.usage.v1`, seconds per target per day) while the app or
  site is in front and the Mac has had input in the last 2 minutes; exhaustion and the
  5-minute warning set `runtime.exhausted`/`warned` exactly as the iOS monitor does, and post
  `UNUserNotification`s. `AppCatalog` lists apps in the usual folders plus running ones and
  excludes Finder, Dock, System Settings and Furlough itself.
- `MacAppDelegate` refuses Quit while `Enforcer.lastDecision.isAnythingShielded`, unless the
  quit Apple Event's `kAEQuitReason` says log out, restart or shut down. `SMAppService.mainApp`
  is registered when onboarding finishes (Settings toggle "Open at login"). Force Quit is the
  documented escape, and stays one — but since 2026-09-08 it no longer lasts until the next
  login: `Watchdog` registers `SMAppService.agent` from
  `Contents/Library/LaunchAgents/com.zachshort.furlough.mac.watchdog.plist` (copied in by a
  copy-files phase in `project.yml`), which runs `open -g -b com.zachshort.furlough.mac` every
  60 seconds. `open` hands off to a running copy instead of starting a second one, which is
  what a plain `KeepAlive` agent could not do — launchd and a user launch would race and leave
  two enforcers ticking against one store — and `-g` keeps the reopen out of the user's face.
  It is registered at `finishOnboarding` and again at every `start()` when onboarded, and
  Settings > Enforcement has "Reopen after a Force Quit". `Watchdog.isRefusedByUser` reads
  `.requiresApproval`, so a user who switched the agent off in System Settings > General >
  Login Items is not asked again on every launch.
- Views mirror the phone with a sidebar plus detail layout (`MacRootView`, `MacRuleEditor`,
  `MacSheets`, `MacOnboardingView`, `MenuBar`). The sidebar's + button shows the shared
  `AddChoicePopover` (an NSPopover), and Application or Website opens `AddAppSheet` or
  `AddSiteSheet`; seen working on this Mac on 2026-09-07. `MacComponents.swift` duplicates
  `ProminentButton`, `GhostButton`, `SectionLabel`, `Footnote`, `CardDivider`, `StatusChip`,
  `RowCopy` and `BudgetSlider` rather than moving them out of `Furlough/Views`, because that
  folder was being edited in another session at the time; unify into `Shared/UI` when quiet.
  Times are `DatePicker` fields; an end of 12:00 AM means midnight (1440). `MacRuleEditor`
  has the phone's "Use windows from another app" (a menu), "Apply these windows to other
  apps" (`ApplyRuleSheet` in `MacSheets.swift`, backed by `MacModel.apply`, same semantics as
  the phone's) and, since 2026-09-08, "Visualize windows": `MacWeekView.swift` is a copy of
  the phone's `WeekDraft`, `WeekGrid`, `DayColumn`, `WindowBlock`, `DayBar` and `DayEditor`,
  with `WeekSheet` swapping the grid for the day editor in place (a Back link, like
  `LogView`) instead of pushing. The Mac's `DraftWindow` has the phone's `sorted`/`tidy`;
  rows are joined at Save and when Apply to other days runs, not as time fields change,
  because the fields commit as you type and a row that moved mid-edit would leave the cursor.
  `Watchdog.swift` (the login agent) and `QuitGrace.swift` (the pause before a force quit,
  tested in `Tests/Core/QuitGraceTests.swift`) are their own files, out of `Enforcer.swift`.
  `MacHero.swift` holds `TargetHero` (the phone's `HeroPage` for the selected app, at the top
  of the editor, with "n of m min used today" from `MacModel.usedSeconds`) and a copy of the
  phone's `HomeGroups` (no Anchored section) that the sidebar uses.
- Debug builds carry Settings > Testing > Reset everything (`MacModel.resetEverything`,
  `Enforcer.resetUsage`, both `#if DEBUG`), like the phone.
- The desktop widget: target `FurloughMacWidgets` (bundle `com.zachshort.furlough.mac.widgets`,
  sandboxed, same App Group), `MacStatusWidget.swift` is the phone's `StatusWidget` without
  the lock-screen family, small and medium only; `FurloughMacWidgetsBundle` registers the
  bundled fonts with `CTFontManagerRegisterFontURLs` because a Mac appex does not honour
  `ATSApplicationFontsPath`. `MacModel.enforce` and the enforcer's `onChange` call
  `WidgetCenter.shared.reloadAllTimelines()`. No Live Activity: ActivityKit is iOS-only.
- Verified on this Mac: 2026-09-07, Release build clean, installed to `/Applications`, a
  target blocked all day was quit within a second of launching and logged. 2026-09-08, from
  screenshots of a Debug build driven by a temporary env-var hook and a seeded demo suite
  (see the memory note on Mac screenshots): the hero with its countdown, the six sidebar
  sections, the week grid, the day editor with the locked day, Settings; and the store
  migration on the real state (log line present, keys in the group plist). Not yet seen by a
  person: the shield panel, the browser redirect (it needs the one-time Automation prompt),
  budget counting, the login item, and the widget itself placed on the desktop (nothing here
  can click Edit Widgets; `pluginkit -m -i com.zachshort.furlough.mac.widgets` shows it is
  registered). Ask Zach.
- Build check for the Mac: the README's `xcodebuild … -scheme FurloughMac` line; keep it
  warning-free like the phone.
