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
  and one daily minute budget. A stored window never crosses midnight: a late weekend night is
  an evening window plus an early-morning window on the next day. Since 2026-09-08 the editors
  take that night as one row — an end earlier than the start, marked "+1" — and `TimeWindow`
  does the arithmetic: `split` turns a night into the pair that is stored, on days one apart
  (`Weekdays.shifted(by:)`), and `folded` reads the pair back as the one row it was written as,
  which is exact rather than a guess because the two allow the very same minutes. `TimeFormat`
  and `Policy.status` see through the join, so nothing says a window shuts at midnight when it
  does not. No windows means open all
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
  behind `#if DEBUG || TESTING_TOOLS`; Zach asked for it on 2026-09-07 after a week-long delay
  and a five-minute FaceTime budget locked him out mid-test): after a confirmation it removes
  the stored state, clears the managed settings, and enforces the empty state, so the app
  matches a fresh install with Screen Time access still granted. Keep it behind that condition;
  the commands in this file build Debug, so it is present on the phone until Zach switches to
  `-configuration Release`. A Release build carries it only when built with the
  `TESTING_TOOLS` compilation condition — `TESTING_TOOLS=1 scripts/archive.sh` — which he asked
  for on 2026-09-09 so a live build can be reset without a Debug install. Because TestFlight and
  the App Store are the same binary, such a build still hides the section until five taps on the
  Version row ask for it (`Shared/Core/TestingTools.swift`, which keeps the switch in the App
  Group beside the state, not in it). `scripts/archive.sh` gates both directions: it refuses a
  plain archive carrying `resetEverything`/`clearEverything`/`TestingTools`, and refuses a
  `TESTING_TOOLS=1` archive that is missing them. The one exception in every build is the Anchor profile (`Config.anchor`, decided 2026-09-07): a separate
  set of kinds that "Anchor" shields instantly without a tag, and that only scanning the paired
  NFC tag in the app can weigh anchor. While anchored, the list and the tag are locked. Anchoring is
  refused until a tag is paired. When the anchor is off, apps fall back to their rules.
  Since 2026-09-08 the list starts from the rules (Zach's ask): while the anchor holds nothing
  and something has a rule, **Choose apps** opens `AnchorFromRulesSheet` — every target with a
  rule, all checked, All / None, a row each — before Apple's picker, which is one tap further
  on ("Choose from all apps instead", opened from the sheet's `onDismiss` so the two never
  overlap). Once the anchor holds anything the button reads **Change apps** and goes straight
  to the picker, filled in. `Config.anchorCandidates` (a rule, and a door the anchor does not
  hold — a linked target held by half is still offered) and `AnchorProfile.add` (every door,
  after what is held, never twice) are in `Shared/Core/AnchorCandidates.swift`, so the phone
  only shows the offer; `AppModel.addToAnchor(targetIDs:)` lands it, refused while anchored.
  Seen on the phone 2026-09-08: the sheet, and Apple's picker opening after it.
  It was called the Brick until 2026-09-08 and was renamed because that is another product's
  name. Stored state keeps working: `Config.init(from:)` reads `anchor` and falls back to the
  old `brick` key, and `AnchorProfile.init(from:)` reads `isAnchored`/`anchoredAt` and falls
  back to `isBricked`/`brickedAt`. Encoding always writes the new names, so the fallback is
  read-once in practice. Do not drop it: it is the only thing standing between a reinstall and
  a lost pairing. SF Symbols has no anchor, so the app draws its own: `AnchorMark` in
  `Shared/UI/AnchorMark.swift` is the mark the tile, the hourglass and the Spotlight shortcut
  all use, and `scripts/make-anchor-symbol.swift` exports it into `anchor.symbolset` for the
  shortcut, which can only be handed a symbol name.
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
- **No QR or barcode keys, and no breaks, pauses, temporary access or emergency unblock — decided
  2026-09-09, do not re-ask.** A code is a photograph away from being a copy: the whole value of
  the Anchor's tag is that it is somewhere else, and a picture of a code is not somewhere else,
  it is in the camera roll. Breaks, pauses, temporary access and an emergency unblock are each an
  unblock with a nicer name; Furlough has none of them on purpose, and the essential-tier
  warnings (`UtilityText`, `confirmBlockEssential`, `Config.anchorWarning`) are where the safety
  that a pause would otherwise provide actually lives. Written up for users on the site:
  `site/src/pages/help/nfc-tags.astro` ("Why a tag and not a code") and
  `site/src/pages/help/the-anchor.astro` ("There is no pause").
- Extras that are in scope: "5 minutes left" notification, Live Activity during a window,
  home-screen widget. Websites are supported, and since 2026-09-08 in two kinds on the phone:
  one picked from Apple's picker, which is counted and wears Furlough's shield, and one typed
  by name (`TargetKind.host`, blocked through `WebContentSettings.blockedByFilter`), which has
  hours but no daily budget and wears iOS's own "Website Not Allowed" page. + → Website goes to
  the typing sheet; the picker is one line further on. See step 20(c).

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
it is vectors, not a generated image, and the app icon is now drawn from it: run
`scripts/make-icon.swift` to render the mid-pour glass into
`Furlough/Assets.xcassets/AppIcon.appiconset/icon-1024.png`, the ten sizes of
`FurloughMac/Assets.xcassets/AppIcon.appiconset`, and the site's icons. The shared
catalog also holds `AccentColor`, because the widget target compiles it too and warns if the
accent colour is missing.

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
  it, and was unused on iOS until the phone gained typed hosts on 2026-09-08 — it is now what
  reads an address a person typed there too),
  `Companions.swift` (the table of things that are both an app and a site: `pair(forBundleID:name:)`,
  `pair(forHost:)`, and for the phone `missingHosts(forAppNamed:knownHosts:)` /
  `missingApp(forHost:knownAppNames:)` plus the `Half` they answer in; names carry their own
  case for showing and are matched without it),
  `PendingNotifications.swift` (`PlannedNotification`, the pure `plan`, `sync`, and the one
  `Notifier` both platforms post through),
  `ActivityLimit.swift` (how many DeviceActivity activities a save would need, and the same
  count for a whole import via `reason(applying:in:)`; `Monitoring.register` reads its `spans`
  rather than counting again, so what is refused ahead of time is what would be refused after.
  iOS-only, and harmlessly unused on the Mac),
  `ConfigExport.swift` (a setup as a file: `ConfigExport`, `ExportedTarget`, `Tier`; the Anchor,
  the queue and the runtime are never written),
  `ConfigImport.swift` (the same file coming back in: `read` refuses one whole, `plan` decides,
  `apply` performs, `matches(for:config:)` is the Mac's own resolver and `preresolved` is the
  phone's, which answers only the website rows a host can be read from; see the section below),
  `PendingText.swift` (`Delta`, the old → new pair a pending card shows; pure, so the phone
  and the Mac cannot word it differently),
  `AnchorCandidates.swift` (`Config.anchorCandidates`, what the Anchor offers before Apple's
  picker, and `AnchorProfile.add`, what taking a target in adds).
- `Tests/Core` (target `FurloughCoreTests`, macOS, Swift Testing, no host app): `Support.swift`
  (the pinned calendar and the fixtures), `ModelsTests`, `PolicyStatusTests`,
  `PolicyPendingTests`, `PolicySummaryTests`, `NamingTests`, `DecodingTests`, `ClockTests`,
  `QuitGraceTests`, `PendingNotificationTests`, `UtilityTests`, `UtilityPlanTests`,
  `ActivityLimitTests`, `PendingTextTests`, `CompanionsTests`, `ConfigImportTests`,
  `HostTargetTests`, `HostImportTests`, `AnchorCandidatesTests`. 368 tests in 54 suites. It builds for **macOS**, so it
  reads the Mac's `TargetKind` and the Mac's `Decision`: the iOS `Decision.filteredHosts` and
  `ShieldReconciler.apply` cannot be reached from any test, which is why the nil-when-empty
  filter policy is a property of `Decision` rather than a line inside the reconciler.
- `Shared/LiveActivity/FurloughActivityAttributes.swift` (app + widgets).
- `Shared/UI/CompanionNudge.swift` (the phone's "you have one half of this" banner, on a
  named target whose other half is missing; the Mac asks at add time instead).
- `Shared/UI/ImportReview.swift` (`ImportReviewList`, what an import would do, one view for
  both platforms) and `Shared/UI/SetupDocument.swift` (the `FileDocument` the exporter writes).
  Both are compiled into the widgets, so neither may use `SectionLabel`, `Footnote`,
  `CardAction` or `CardDivider` — those exist only in the two apps, and reaching for one breaks
  the widget build and not the app build.
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
  `AnchorGlyph`, `AnchorFromRulesSheet`),
  `Home` (`HomeContent` holds the featured page id, `HomeGroups` for the sections including
  "Later this week" and `ordered` for the page order, `HeroPager`, `HeroPage` ticking once a
  second, `HeroIndicator`, `EmptyHero`, `TargetRow`; the + button shows `AddChoicePopover`
  from `Shared/UI/AddChoice.swift`, Application or Website, added 2026-09-07; both end at the
  one `FamilyActivityPicker`, which holds websites under each category as "Add Website", so
  the choice sets the picker's header and footer, and Website first opens
  `AddWebsiteGuideView` (added 2026-09-08) with the three steps to a site, because the footer
  alone read as a broken button; since 2026-09-08 that whole path lives in
  `AddTargets.swift` as `AddTargetsFlow`, a view modifier driven by one `AddChoice?` binding,
  so Home and a rule editor reach the same picker with the same copy (`PickerCopy`) — inside
  it everything is presented after a short wait, because a sheet presented while the popover
  or the previous sheet is still dismissing is dropped),
  `AddSite` (`AddSiteSheet`, what + → Website opens since 2026-09-08: a text field, `addHost`,
  and one line down to the picker for anyone who wants a daily limit),
  `AddWebsiteGuide` (a self-sizing sheet: measured `contentHeight` into a
  `.height` detent, `StepRow`; reached from `AddSiteSheet` rather than the + button now. Only a
  site iOS minted itself can be counted, and iOS mints a `WebDomainToken` only inside Apple's
  picker — but blocking one no longer needs a token, which is what typed hosts are),
  `Components` (`TokenLabel`, `TokenName`, `TokenTile`,
  `StatusChip`, `RowCopy`, `ProminentButton`, `GhostButton`, `SectionLabel`, `Footnote`,
  `CardDivider`), `RuleEditor` (`WindowRow` with `DayStrip`, `CopyRuleSheet`, `TimeChip`,
  `TimePickerSheet`, `EffectBanner`), `WeekView` (`WeekDraft`, `WeekSheet`, `WeekGrid`,
  `DayColumn`, `WindowBlock`, `DayEditor`, `DayBar`), `BudgetSlider` (piecewise
  linear over the 5/30/60/120/240 ticks), `PendingChanges`,
  `Help` (`HelpView` is the hub behind the question mark on Home; since 2026-09-09
  `HelpTopics.swift` holds only the two pages still in the binary — `DelayHelp`, which quotes
  this phone's own base delay and per-tier delays rather than a default, and `StuckHelp`, which
  is wanted at the moment a shield will not lift and so must not send anyone to a browser. The
  other five topics are pages on the site: their rows are buttons that hand
  `Furlough.helpURL(_:)` to `openURL`, and wear `arrow.up.right` instead of a chevron so a tap
  that leaves the app looks like one. The app itself still issues no network request, which is
  what keeps "no networking code at all" true on the privacy page and in the App Store label),
  `Settings` + `LogView` (Settings gained the build version on 2026-09-09, because it moved out
  of the old in-app About and the site cannot know which build is running). Screens are
  `ScrollView`s over `EmberWall`, not `List`/`Form`; the iOS 26 toolbar supplies the glass.
- `FurloughMonitor/MonitorExtension.swift`: every callback reconciles from shared state.
- `FurloughShield/ShieldExtension.swift`: reads shared state, writes the copy via `ShieldText`,
  and records the name iOS gives the app it is covering (see the naming note below).
- `FurloughWidgets/`: `StatusWidget.swift`, `WindowLiveActivity.swift`, bundle.
- `design/`: `DESIGN.md`, `HOURGLASS.md` (the next brief);
  `scripts/make-icon.swift` (the app icon, drawn from the hourglass),
  `scripts/make-noise.swift` (the wall grain).
- `site/`: the Astro site at furloughapp.com (`bun install`, `bun run build`; static output,
  no npm — there is no `package-lock.json` and there should not be). `src/pages/help/` is
  where help copy belongs now. Five topics moved there from the app on 2026-09-09 for one
  reason worth keeping in mind before writing any user-facing prose: **a sentence on the site
  can be fixed the same day, and a sentence in the binary waits on an App Store review.** So
  anything that reads the same on every phone goes on the site and the app links to it;
  only copy that has to read this phone's own state stays in Swift. The two are wired
  together by `Furlough.helpURL(_:)` and the paths are literals on both sides, so renaming a
  page means editing the Swift too — `bun run build` will not catch it.

## How enforcement works (do not break these invariants)

- One repeating DeviceActivity "day" (00:00 to 23:59:59, warningTime 5 min) carries one
  threshold event per **distinct budget** a target's week asks for, named
  `budget:<uuid>:<minutes>`, with `includesPastActivity: true` so re-registering mid-day does
  not reset the day's usage. Since per-weekday budgets (2026-09-09) that is up to seven events
  for one target rather than one, all of them live every day, and the monitor is what decides
  which is today's: it ignores a threshold **smaller than today's effective budget**
  (`Rule.effectiveBudget(on:)`), and warns only on one exactly equal to it. A budget is an event
  carried by the day activity, not an activity of its own, so none of this presses on the
  20-activity ceiling — `ActivityLimit` counts window spans and nothing else. Pending (not yet
  effective) rules are registered too, so a loosening that lands while the app is closed is
  still enforced.
- One repeating activity per distinct span, named `window:<start>-<end>` in minutes of day,
  whatever days the span applies on (`TimeWindow.span` drops the days before deduping). A
  callback on a day the window is off just reconciles to the same shields. iOS allows 20
  activities total, so at most 19 distinct spans across all targets and days; windows must
  be at least 15 minutes and cannot cross midnight (end is exclusive, 1440 means midnight),
  so a night costs two spans and each half needs its own 15 minutes (`isValidDraft`).
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
  `AppModel.anchor()`, `unanchorWithTag()`, `pairTag()`, `setAnchorSelection()`,
  `addToAnchor(targetIDs:)`, `unpairTag()` are the only writers of `Config.anchor`; the last
  four refuse while anchored.

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
  `open -g -b` every ten seconds (60 until Zach shortened it, 2026-09-08). Force Quit still
  lifts every block; it just stops buying the
  rest of the day.

Open, and where each one lives:

- Nothing tested on the device beyond the basics → step 3, the two checklists. Zach's report
  is still outstanding, and it is the gate on a lot of this file.
- Third-party iOS browsers (does a web-domain shield reach Chrome on the phone?) → step 3; the
  answer goes in README's limits either way.
- The Live Activity only starting if the app is opened during a window → step 10.
- The shield icon still being the SF hourglass → **done**, 2026-09-08 evening, and not the way
  e9bfff2 tried: iOS calls `ShieldConfigurationDataSource` off the main thread, so a SwiftUI
  `ImageRenderer` behind a main-thread check never ran and the symbol fallback shipped. The
  shield now draws the glass with Core Graphics (`Shared/UI/HourglassStill.swift`), which has
  no thread to wait for. Nothing SwiftUI-rendered can go on a shield; step 17's imagery is
  for the app and the store, not here.
- The duplicated Mac UI (`MacComponents.swift`, `MacWeekView.swift`, two `Notifier`s) → step 16.
- Safari web apps in the Dock bypassing host rules → step 7. No web app on this Mac to test.
- **The 19-window limit only being checked after Save** — **done**, step 6, as `ActivityLimit`.
- Window start lagging by minutes with no way to hurry it → step 6/step 3; the shield extension
  has the App Group and the entitlement, so it may be able to reconcile itself on `.open`.
- Categories only being blockable all day → step 12. Ask Zach first.
- Pending cards showing the new rule rather than old → new → **done**, step 6.
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
   Sent to Zach on 2026-09-08 as two checklists; the rest of his report is outstanding.
   **The Mac in `/Applications` is now a Debug build of `2851824`**, replaced 2026-09-08 with
   his go-ahead: SIGTERM to the running copy (not an Apple Event, so the "Quit refused while
   blocked" guard does not apply and it flushes cleanly), then `rm -rf` + `ditto` + `open`.
   The App Group state survived untouched, as it must — the rules live in the container, not
   the bundle — and the watchdog agent re-registered from the new bundle. It is **Debug**
   deliberately, for `Settings > Testing > Reset everything` during the pass; that leaves the
   split `Furlough.debug.dylib` shape in `/Applications`, so put README's Release line back
   when the pass is done. (Since 2026-09-09 a Debug install is no longer the way to get that
   button: a Release build with `TESTING_TOOLS` carries it, hidden behind the five-click reveal.) Note the file it replaced was a *single* binary, so the Mac had been
   Release, not the Debug this file claimed.
   **Results in so far, 2026-09-08.** The pending card's old → new pair reads right on the Mac
   (a queued `setRule` on `example.com`, "Now 12:00 AM–11:59 PM · 5 min/day" over "Becomes
   All day · 5 min/day"). That is `PendingText`/`PendingDeltaView` seen by a person; the phone
   draws the same two views, so only its layout is still unwitnessed.
   **The browser redirect works in both Safari and Chrome**, with the activity log to prove it
   rather than only an eye: `13:46:54 blocked members.upswingpoker.com in Google Chrome`,
   `13:47:32 … in Safari`. So `Browsers`, the Apple Event round trip and the one-time
   Automation prompt are all real. **Still unwitnessed in that lane**: the part that is
   actually new — a blocked site in a *second window* and in a browser that is not in front,
   which is the whole point of `Browsers.snapshots()`. The old code read only the front tab of
   the front window, so a redirect working in the front window proves nothing about the sweep.
   Ask specifically.
   **The watchdog reopens Furlough after a Force Quit**: two force quits, back both times
   within the 60-second tick (the log's `reconcile (launch)` lines at 13:39:03 and 13:39:59,
   56 s apart), one enforcer left running, no crash report. That is step 7's one untested bet —
   that `open -g -b` hands off instead of racing a second enforcer — settled.
   **The menu bar item does not appear, and it is not our code.** `FurloughMacApp` declares a
   `MenuBarExtra` with `MenuBarLabel`, and nothing shows in the menu bar whether Furlough is
   running or not. Traced 2026-09-08: there is no menu bar manager (no Ice, Bartender or
   similar) hiding it, the menu bar has visible free space so it is not crowding, and Furlough
   owns four `1512×33 @(0,0)` windows at layer 0, all `onscreen=false`, with nothing at the
   status-item layer. Then the decisive one: a **twelve-line app whose whole body is
   `MenuBarExtra { Text("test") } label: { Image(systemName: "hourglass") }`**, properly
   bundled and signed, shows nothing either and produces the *identical* window signature. So
   `MenuBarExtra` is not producing a visible status item on this Mac (macOS 26, MacBook Pro
   Mac16,1) for any app, and no amount of work on `MenuBar.swift` will fix it. What could not
   be settled: whether the item is created and invisible or never created at all — that needs
   the accessibility API, and `osascript` here has no assistive access. **README claims the
   Mac's answer to the Live Activity is "a menu bar item with the countdown", so that line is
   false until this is decided.** **Both decided and done, 2026-09-08.**
   Zach chose the hand-rolled `NSStatusItem`, and `MenuBar.swift` is now AppKit: a
   `MenuBarController` owning the item, an `NSMenu` rebuilt on `menuNeedsUpdate` so the
   statuses are current, the hourglass and a monospaced-digit countdown off the same
   `Policy.summary` the widget reads, and `MacAppDelegate` building it in
   `applicationDidFinishLaunching` rather than a property initialiser — the delegate is not
   `@MainActor`, so it cannot reach `MacModel.shared` there.
   **It does not show, and the reason is the notch.** Solved 2026-09-08 after two wrong
   answers, both recorded here so nobody repeats them. It is not `MenuBarExtra` (a raw
   `NSStatusItem` from a twenty-line AppKit app does not appear either), and it is not that this
   Mac refuses third-party items — the *first* conclusion written here, and it was wrong.
   The measurement that settled it: log the status item's button window frame a second or two
   **after layout**, not at creation, when it is still `(0, 0, w, 0)` and says nothing.
   ```
   frame=(752.0, 949.0, 27.0, 33.0)   screen=(0.0, 0.0, 1512.0, 982.0)
   ```
   x = 752 on a 1512-point screen is dead centre: macOS placed the item **under the notch**,
   where the camera housing hides it. The menu bar's right-hand region is full, so a new item
   overflows leftward into the notch and is invisible. The apparent free space in a screenshot
   of the menu bar *is* the notch, which is what made the earlier reading wrong.
   So the remedy is Zach's, not the code's: free a menu bar slot (⌘-drag an item out, turn some
   off in System Settings > Control Center, or quit a menu bar app) and the hourglass appears.
   Worth knowing that Furlough's item is about 85 points wide with the countdown against the
   test's 27, so it needs correspondingly more room; an icon-only item would fit sooner if that
   is ever worth offering.
   **Keep the AppKit version regardless**: `MenuBarExtra` was still a dead end for its own
   reasons, this is the correct API, and it is verified to run and to be placed. The one line
   the log carries at install stays useful — it separates "Furlough never added it" from "macOS
   put it somewhere you cannot see".
   **The watchdog reopen brings back no window**, done the same day and verified on the machine.
   The agent passes `--args --background` (`Watchdog.backgroundFlag`), the scene takes
   `.defaultLaunchBehavior(.suppressed)` on such a launch, and — the part that is not obvious —
   the delegate *also* puts the window away on `didFinishRestoringWindows`, because suppressing
   the scene does not stop AppKit restoring the window it saved when Furlough was last force
   quit, which is exactly the case the watchdog exists for. Verified both ways: `open -g -b …
   --args --background` leaves the main window `onscreen=false` with enforcement ticking, and a
   plain `open` still shows it.
   **The trap worth knowing**: `SMAppService` hands launchd a copy of the agent's job at
   registration and does not re-read the plist when the app is replaced, so changing the plist
   in a new build changes nothing until the agent is registered again. `Watchdog.plistVersion`
   exists for that — bump it on any plist change and `enableIfNeeded` unregisters and
   re-registers. Seen working: the log shows "watchdog off" then "watchdog on" on the first
   launch of the new build.
   **Furlough is a menu bar app now** (Zach's call, 2026-09-08: "like the GitHub app or
   Raycast"). A launch sets `.accessory` before anything can appear — no Dock icon, no window —
   and Furlough goes to the menu bar and keeps enforcing. The window comes back on request and
   the app turns `.regular` while it is up, which is **not cosmetic**: an accessory app has no
   menu bar menus, and with them goes the Edit menu, so ⌘C and ⌘V would quietly stop working in
   the nickname and host fields. It returns to `.accessory` when no titled window is left, and
   `applicationShouldTerminateAfterLastWindowClosed` is `false` so closing the window puts
   Furlough back in the menu bar rather than ending enforcement. A Mac that has not onboarded is
   the exception and still opens the window, or a first run would be invisible.
   **The mistake worth not repeating**: the first attempt used
   `.defaultLaunchBehavior(.suppressed)`. A suppressed scene is never *built*, so there was no
   window for AppKit to raise — reopening Furlough switched the activation policy and put
   nothing on screen, which on a Mac with no menu bar item is an app with no way in at all.
   Tested on the machine, which is the only reason it was caught. The window is now always built
   and put away with `orderOut`, three times over the moments it can appear (SwiftUI's build,
   AppKit's restore of the force-quit state, and a turn later), so there is always something to
   raise.
   **The way in that always exists**: opening Furlough again — double-click in `/Applications`,
   or Spotlight — goes through `applicationShouldHandleReopen` and brings the window up. It
   needs no Dock icon and no menu bar item, which on this Mac is the only way in at all. Verified
   2026-09-08: launch leaves `ApplicationType=UIElement` with the window `onscreen=false`, and a
   second `open` gives `onscreen=true`.
   **Not yet verified by a person**: that closing the window drops the Dock icon and leaves
   Furlough enforcing. The code says so; nobody has clicked the red button.
   **The watchdog reopens in ten seconds, not sixty** (Zach's call 2026-09-08, after asking
   whether Furlough could work the way Rectangle does). Ten is launchd's floor for
   `StartInterval`. Measured on the machine: killed at 16:07:46, back seven seconds later.
   Force Quit is still the documented escape and still lifts every block the moment it lands —
   it just buys seconds now. README says so.
   Worth recording for the next time this comes up, since Zach asked it directly: Furlough
   already *is* the Rectangle shape, and more. `/Applications/Rectangle.app` on this Mac is
   `LSUIElement = true` with **no `Contents/Library/LaunchAgents` at all** — only a
   `LoginItems/RectangleLauncher.app` to start it. So nothing runs on Rectangle's behalf, and
   force-quitting it stops window snapping until it is launched again. Furlough is the one that
   comes back by itself.
   **Still owed**: README's Mac table still says the Live Activity's counterpart is "a menu bar
   item with the countdown", and now also needs to say Furlough lives in the menu bar with no
   Dock icon. True of the code, false of this Mac, so it needs a sentence either way — left
   undone here only because `README.md` was being edited in the other session.
   Moving `.accessory` into `LSUIElement` in `project.yml` would be tidier than setting it at
   launch, and would remove any chance of a Dock icon flicker; not done because `project.yml`
   was the other session's too.
   Record the rest here.
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
   Pending cards showing old rule → new rule is done 2026-09-08, as
   `Shared/Core/PendingText.swift` (`PendingText.delta(for:in:calendar:)` → a `now`/`becomes`
   pair) plus `Shared/UI/PendingDeltaView`, which both `PendingChangesView` and
   `MacSheets.PendingCard` draw, so the two cards cannot drift — the second piece of step 16
   done early. The baseline is deliberately the target's *saved* rule and not another queued
   one: `assign` on both platforms removes any `setRule` already queued for a target, so at
   most one is ever in flight and the saved rule is what stays in force until it lands. A tier
   change names the wait on each side ("Useful · waits 1 day" → "Essential · waits 6 hours"),
   because the tier's name alone does not say what changing it buys, which is the only reason
   to change it. 9 tests in `Tests/Core/PendingTextTests.swift`.
   Still open here: `widgetURL` and the `furlough://target/<id>` scheme, and iPad (ask Zach).
   `widgetURL` needs a target id on `Policy.Summary`, which today carries only names.
7. **Mac hardening**: the 45-second grace before force quit with a countdown on the panel, and
   every window of every running browser rather than only the front one, are both done
   2026-09-08 (`QuitGrace.swift`, `Browsers.snapshots()`, `Tests/Core/QuitGraceTests.swift`;
   the read script was run against Chrome on this Mac and the Safari variant compiles, but
   neither has been seen working by a person — they are on the Mac checklist in step 3).
   The `SMAppService` watchdog is done too (`FurloughMac/Model/Watchdog.swift`), after Zach
   said yes on 2026-09-08. Still open here: Safari web apps saved to the Dock, which run under
   their own `com.apple.Safari.WebApp.<uuid>` bundle id and so bypass host rules entirely —
   there is no web app on this Mac to test against, so it needs one before it is worth writing.
   The watchdog was watched working on 2026-09-08: Zach force-quit Furlough twice and it came
   back both times, inside the agent's 60-second tick, with one enforcer running afterwards and
   no crash report. So `SMAppService.agent` plus `open -g -b` does hand off rather than race a
   second copy, which was the design's one real bet. Whether `-g` actually keeps the reopen out
   of the user's face is still unconfirmed — he did not say either way, and he was looking at
   the app at the time, which is the worst case for noticing.
8. **Anchor from anywhere**: `AnchorIntent`, `AppShortcutsProvider`, a Control Center
   `ControlWidget`, a `Button(intent:)` on the medium widget. Anchoring is tightening, so every
   surface is safe; release stays in the app behind the tag.
9. **Real usage on the phone**: a `FurloughReport` DeviceActivity report extension with a
   `budget` scene on the hero and in the rule editor, a `week` scene behind a History link, and
   quarter-mark threshold events if DeviceActivity accepts four events per target.
10. **Live Activity at window start**, if the iOS 26 ActivityKit swiftinterface has a
    scheduled-start `Activity.request`. If not, document the widget and the notification as
    the coverage and move on.
11. **Per-weekday budgets.** Done 2026-09-09. `Rule.budgetByWeekday: [Int]?`, seven figures
    Sunday first (index = Calendar weekday − 1), nil meaning "same every day", and
    `Rule.budget(on:)` as the one accessor everything reads. `dailyBudgetMinutes` stays as the
    fallback and becomes a *shadow* once the array is set: read `budget(on:)` for enforcement,
    `representativeBudget` when an editor collapses seven sliders back to one, and never the
    raw field, because in an imported rule the shadow can be any figure at all.
    - `windows(on:)` returns none on a day worth 0 minutes, so a zero day is closed without
      anything checking the budget twice; `isEverAllowed` stayed "on some day" (a category is
      still `.blockedAllDay`) and gained `isEverAllowed(on:)` for one day.
    - `isTighterOrEqual` compares budgets **day by day**, so moving Saturday's hour onto Monday
      is a loosening even though the week is the same size. `isEquivalent` likewise, which is
      what makes seven equal days and one figure the same rule; `normalized` drops the array in
      that case so the editors cannot save a rule that differs only on paper.
    - Old stored rules read as "same every day"; a `budgetByWeekday` that is not seven long
      decodes as nil rather than as a day with no budget. `ConfigExport`/`ConfigImport` carry it
      for free (the field is on `Rule`), and `ConfigImport.problem` range-checks all seven.
    - `TimeFormat.budgets` is the compact grammar: "30 min/day", "2 hours weekends, 30 min
      weekdays", then "varies by day" at three groups. Clause order is `Weekdays.groupOrder`,
      the same order `schedule` uses for the hours in that very sentence, so on a Sunday-first
      calendar the weekend leads. That is deliberate — do not reorder one half of the line.
    - Tests: `Tests/Core/WeekdayBudgetTests.swift`, 25 of them, including a night that runs into
      a Sunday worth nothing (it stops at midnight, because `continuation` reads Sunday's empty
      list). Reviewed by Fable before install; what it flagged is under step 12's note below.
12. **Rules for categories.** Settled 2026-09-09: **no.** Zach's call, asked before any code was
    written. A category stays an always-blocked container (`Rule.alwaysBlocked`, zero budget),
    and hours for something inside one come from picking the app itself, which
    `includeEntireCategory: true` already expands into per-app targets. Do not re-ask. The
    proposal was that a category carry windows and a budget like an app — ManagedSettings
    supports it (`applicationCategories = .specific(_, except:)`) and DeviceActivity takes a
    category in a threshold event — so it is buildable if it ever comes back; it was declined,
    not blocked.

    **Left over from step 11, for the device pass.** Fable's review could not construct a
    loosening that lands early or a real change that reads as none, but named three
    DeviceActivity-side unknowns that only the phone can settle:
    - Does a budget event whose name already fired today fire *again* after a mid-day
      re-registration? Tightening Saturday from 120 to 30 after 40 minutes of use depends on it.
      The activity log answers it: after an exhaustion, does re-opening the app log another
      `eventDidReachThreshold` for the same name?
    - A week now has up to seven live event names per target, so the iOS 26.2 zero-usage firing
      has more ways to exhaust a day early. The `>=` guard is still the right one.
    - Nothing documents a per-activity event cap. Seven values (fourteen with a loosening
      queued) is more than we have ever registered; the "registered day + N window(s), M budget
      event(s)" log line and a run without a thrown registration would settle it.
13. **Anchor the whole phone**: a scope on `AnchorProfile`, `.all(except:)` with an allowlist.
14. **More than one tag.** Done 2026-09-08. Zach lives in two places and wanted a key at each,
    which is the case the anchor is for rather than a hole in it: a key three hours away is not
    a stronger lock, it is one nobody dares close. `AnchorProfile.tagID: Data?` became
    `tags: [PairedTag]` (`id`, the hardware identifier, plus a `name`, because two identifiers
    are four hex digits apiece and nobody tells those apart), capped at
    `Furlough.maxAnchorTags` = 3 — the failure here is not two keys but enough that one is
    always in a pocket. Any paired tag releases the anchor (`AnchorProfile.tag(matching:)`);
    `isPaired` is `!tags.isEmpty`, so `canAnchor` and every call site read as before.
    **What was decided against**: this plan said pairing another would queue as a loosening.
    It does not, and must not be allowed while anchored either — a queued pair under a lock
    turns the anchor's guarantee from "held until the tag" into "held for the delay, then any
    ISO 14443 card in your wallet", which is a timer with extra steps. `pairTag()` keeps the
    old refusal (`AppModel.pairingRefusal`, checked before and after the scan since the state
    can move under a long await), so the discipline is: pair every key before you anchor.
    With the anchor off there is nothing being held to wait for, so pairing lands at once.
    Also `renameTag(id:to:)` (trimmed, empty ignored, capped at `PairedTag.maxNameLength`)
    and `unpairTag(id:)`, both locked while anchored; `AnchorOutcome.paired` carries the new
    tag so `AnchorView` opens the name field straight after the scan. The old lone `tagID`
    reads back as one tag named "Tag 1" (`LegacyKeys`, beside the `brick` rename), and a
    stored list is `prefix`-ed to the cap on decode so a hand-written file cannot exceed it.
    Tests: `Tests/Core/ModelsTests.swift` (`Anchor tags` suite) and the migration cases in
    `Tests/Core/DecodingTests.swift`.
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

20. **Both halves of the same thing.** Done 2026-09-08, all three parts.

    (a) The Mac, at the moment of adding: adding the YouTube app offers youtube.com, adding
    youtube.com offers the YouTube app, one switch each in `CompanionSheet` (`MacSheets.swift`),
    fed by the `Companions` table (`Shared/Core`, tested) and by what a browser's "install as
    app" wrapper says in its bundle (`AppCatalog.webHosts` reads `CrAppModeShortcutURL`).
    **Seen on screen 2026-09-08** — rendered from the real code against this Mac's real
    installed apps, both directions, four widths (`SheetFrame` in a borderless `NSHostingView`
    window, photographed with `screencapture`; `ImageRenderer` draws a `ScrollView` as an empty
    box and `cacheDisplay` drops the glass, so neither can be trusted for this sheet, and the
    window has to be **key** or every control draws in its inactive grey). What that showed
    and fixed: the height reserved 54pt a row where a row is 50, so the card sat in a taller
    box with a band of air under it that grew with every row; and the explanation stayed
    singular ("The site is the same thing") with four sites listed. The footnote now says
    "apply those windows to it" for one companion rather than "to the rest". On this Mac the
    YouTube Music Chrome wrapper offers music.youtube.com and discord.com offers Discord;
    reddit.com offers nothing, because no Reddit app is installed — and no sheet is shown at
    all when there is nothing to offer, which is the right answer, not a miss.

    (b) The phone, one step later. A token says nothing at add time, so there is nothing to
    offer as it is added — but the shield learns the name the first time it covers something
    (`Target.systemName`), and `Companions.missingHosts(forAppNamed:knownHosts:)` /
    `missingApp(forHost:knownAppNames:)` answer from a name alone (both tested). A named target
    whose other half is not in Furlough carries one dismissible `CompanionNudge` (`Shared/UI`)
    at the top of its rule editor: "youtube.com is the same thing in a browser tab" with **Add
    the website** and **Not now**. Add opens the path Home already had, now shared as
    `AddTargetsFlow` (`Furlough/Views/AddTargets.swift`, used by `HomeView` and
    `RuleEditorView`): the website guide, then Apple's picker. The dismissal is per target in
    the app's own defaults (`furlough.companionDismissed`), not in `Config` — it records what
    has been said, not what is blocked, so it must not be exported with a setup and must not
    queue behind the loosening delay; the Debug reset clears it. Because "already in" can only
    be judged by learned name, a half that is in Furlough but has never been blocked is
    invisible and can be offered once; dismissing settles it. **The nudge itself was rendered
    and seen at iPhone width; nobody has yet seen it on the phone** — installed 2026-09-08 for
    Zach to check (open a target the shield has already named, e.g. YouTube or Instagram, and
    look under the app's name at the top of its editor).

    (c) Sites by name on the phone. Done 2026-09-08 with Zach's yes, and **the cost is not
    what this file said it was**. The old text named only `.auto`, which is Apple's automatic
    adult-content filter *plus* the listed domains, and quoted its costs as the price of the
    feature. `WebContentSettings.FilterPolicy` has four cases, not one — `.none`,
    `.specific(Set<WebDomain>)`, `.auto(_:except:)`, `.all(except:)` (iOS 26.5 swiftinterface,
    around line 576) — and `.specific` names exactly the domains to block and nothing else.

    **What the phone actually did**, 2026-09-08, with a throwaway `ManagedSettingsStore` named
    `weblab` so nothing real was touched: `.specific([WebDomain(domain: "example.com")])`
    blocked example.com in Safari while amazon.com loaded normally. So the adult filter does
    *not* go on, and the feature costs far less than Zach was told. Two of the old costs stand:
    Safari shows **iOS's own page** — a blue circle-slash, "Website Not Allowed", "example.com
    is a restricted website" — not Furlough's shield, which we cannot style or replace; and
    with no token DeviceActivity counts nothing, so a typed host has windows and **no daily
    budget**. `.auto` was never run and is not used anywhere in the code.

    Not yet seen by a person: whether Screen Time > Content & Privacy Restrictions > Content
    Restrictions shows anything different while `.specific` is applied. It was already on
    before the test (Furlough's own shields turn it on), and no row in there was observed to
    change, but nobody has photographed that screen with a host blocked. Chrome was not tried
    either. Both are worth one look.

    What landed: `TargetKind.host(String)` on iOS beside the picker's three, mirroring the
    Mac's, with `defaultName` returning the host so it needs no learned name and a nickname
    still wins. `Decision.filteredHosts` plus `webFilterHosts` (nil when empty — a property of
    `Decision` rather than a line in `ShieldReconciler`, because that file imports
    ManagedSettings and is excluded from the macOS test bundle, so this is the only way the
    nil is testable); `Policy.decide` fills it from `.host` targets that are not allowed and
    from `.host` kinds in the anchor. `ShieldReconciler.apply` writes
    `store.webContent.blockedByFilter` and nils it when the set is empty, the same shape as
    every other line there; `clearEverything` already removed it. A filter-blocked host
    **counts** for `denyAppRemoval` (Zach's call): the flag stops Furlough itself being deleted
    to escape, and that escape works against a filter as well as a shield.
    `Monitoring.register` registers no budget event for a `.host`, but its spans are collected
    by `ActivityLimit.spans`, which never switched on kind, so window edges still drive a
    reconcile and hosts count against the 19. `Rule.limitMinutes` is new: a whole day of budget
    is not a budget, so `TimeFormat.rule` drops the "/day" clause and the widget's budget line
    goes quiet rather than offering "24 hours budget".

    The way in, Zach's call after being shown the tap counts: **+ → Website goes straight to a
    text box** (`AddSiteSheet`), which is two taps to a blocked site against the picker's six.
    Under it, one line to `AddWebsiteGuideView` and Apple's picker for anyone who wants the
    daily limit. The difference is stated on both screens rather than left to be discovered:
    the sheet says a typed site gets hours and no limit, the editor replaces the budget card
    with one Footnote saying why. A typed host is saved with a whole day of budget —
    `savedBudget` in `RuleEditorView` forces it, so no other path into the draft ("Use windows
    from another app", the week sheet) can give one a limit nothing would enforce; 0 would mean
    blocked all day.

    Two things fell out of it that are worth knowing. `applyPicker` reads a selection as the
    whole truth and schedules a removal for every target absent from it — a typed host is
    absent from every selection, so without the explicit `!target.kind.isHost` guard, one trip
    through the picker would have queued the removal of every site added by name;
    `setAnchorSelection` keeps `.host` kinds for the same reason. And the companion nudge got
    better rather than merely compiling: the sites half now **adds outright**
    (`AppModel.addHosts`) instead of routing to the picker, and it fires immediately on a typed
    host, since that one carries its name from the moment it is added rather than waiting for
    the shield to learn one — which is why `companion(for:)` no longer guards on `systemName`
    up front.

    Import is wired (Zach said now, not later): `ConfigImport.preresolved` answers a
    `.website` row carrying a host with no picker step, matching an existing target through
    `Config.target(host:)` (so "m.youtube.com" lands on "youtube.com") or creating one, and
    refusing a second row for a site the file already listed. It is deliberately **not** behind
    `#if os(iOS)` — everything it touches exists on both platforms, and behind the guard it
    would be the one part of this feature no test could reach. So a Mac setup's websites now
    arrive on the phone as real enforceable targets, which was the point.

    Tests: `Tests/Core/HostTargetTests.swift` and `HostImportTests.swift`, plus
    `TargetKindDecodingTests` in `DecodingTests.swift` pinning that a kind is stored under its
    own case name, so adding a case leaves older stored state decoding exactly as it did. 305
    tests in 40 suites. **The limit worth knowing:** `Tests/Core` builds for macOS, so it reads
    the Mac's `TargetKind` and the Mac's `Decision`. The iOS `Decision.filteredHosts` and
    `ShieldReconciler.apply` are not reachable from any test; `Config.target(host:)`,
    `TargetKind.isHost` and `Target.host` were lifted out of the `#if !os(iOS)` block so both
    platforms share them, and `makeTarget` in `Support.swift` has always built `.host` targets,
    so the engine underneath is covered.

    **Nobody has used this on the phone yet.** Installed 2026-09-08 for Zach: + → Website →
    type a host → Add; then the rule editor, where the budget card should be a single line of
    explanation; then Safari, to see iOS's page inside the blocked hours.

    (d) The app half, beside a website. Done 2026-09-08, after Zach reported the nudge's Add
    button: it added the app as an unrelated target with no rule, let him pick any number of
    apps, and then went on offering the app he had just added.

    All three had one cause each. The picker was the general one, seeded with everything, and
    its answer went through `applyPicker`, which reads a selection as the whole truth. And
    "already in" is judged by the app's **learned** name, which iOS only supplies the first
    time the shield covers something — so a freshly picked app is invisible to the nudge that
    asked for it.

    Now: `AddRequest` (`Shared/UI/AddChoice.swift`) says whether a trip to the picker is the +
    button's or a nudge's. A nudge's opens the picker **empty** — it is asking one question and
    must not be able to answer any other — and its answer goes to `AppModel.addCompanionApps`,
    which adds beside the target that asked, removes nothing, and copies that target's rule
    onto the new one. Copied rather than queued, because a target's first rule is always
    instant: the baseline for something Furlough has never managed is "unrestricted", so there
    is nothing to loosen. The new target is named from the `Companions` table at birth, so the
    nudge clears itself and the widget says "YouTube" rather than "This app" before the shield
    has ever covered it; `SharedStore.load` still lets a name Screen Time teaches later win,
    which is why `Target.systemName`'s comment now names two writers.

    **Why it is still two taps and not one.** Zach asked whether the two could be linked in one
    click from a hardcoded table. The table is not the obstacle — `Companions` already carries
    iOS bundle identifiers, and `UsageReader.kind(forKey:)` (the other session's, in `b3562cb`)
    already turns one into a real `ApplicationToken` with no picker. The obstacle is the region.
    Apple's `FamilyActivityData` page, read 2026-09-08:

    > You can develop and test an app that uses this class on devices in any region. Customer
    > installations of your app can only use the class on devices located in the EU that are
    > signed in with an Apple Account with an EU country or region.

    Zach is releasing to the US only, so that API works on his own phone and for nobody who
    installs the app. One-click was therefore **not built**: it would be a branch that only
    ever runs on the developer's device. Two taps that inherit the rule is as good as Apple
    allows for a US install, and it behaves the same for everyone.

    **The entitlement and the consent prompt: settled 2026-09-08, keep it.** The worry was that
    `com.apple.developer.family-controls.app-and-website-usage` (`b3562cb`) makes the Screen
    Time approval all-or-nothing — forum thread 820283: "as soon as we add the Family Controls
    App and Website Usage capability, then anyone on iOS 26.4 and above can either only approve
    full access or no access at all." True, but **it is gated on eligibility, not on the
    entitlement**, so it does not reach a US customer.

    Two pieces of evidence. Apple's `approvedWithDataAccess` page: "On devices outside the EU,
    `authorizationStatus` never returns `approvedWithDataAccess`, and any attempt to access
    `FamilyActivityData` properties fails." And `FamilyControlsAgent` itself
    (`FamilyControls.framework/FamilyControlsAgent` in the iOS 26.5 simulator runtime) carries
    these log strings, which are the branch:

    > Requested authorization for record identifier: %s already approved with data access, but
    > is **not eligible** for data access, resetting and attempting authorization for
    > **non-data access**

    > Requested authorization for record identifier: %s already approved, but **is eligible**
    > for data access, attempting authentication for data access

    > Failed to get eligibility result, **treating as not eligible**

    The same binary references both the entitlement and `com.apple.os-eligibility-domain.change.radium`.
    So the agent asks the eligibility daemon first, falls back to the ordinary non-data-access
    authorization when the answer is no, and defaults to "not eligible" when it cannot tell —
    the safe direction.

    **What this means in practice: the all-or-nothing prompt is a developer-only symptom.**
    Apple's docs say a dev build on an Apple-provided provisioning profile is eligible *in every
    region*, which is exactly the configuration the forum reporter — and Zach — test in. So
    expect the full-access prompt on Xcode installs here and the ordinary one on a US App Store
    install. Do not "fix" it by removing the entitlement: it feeds the Usage screen's in-app
    path and belongs to the session that added it.

    Not proved by running it: nobody has installed a distribution build on a US retail device,
    and a dev profile cannot tell the two apart by construction. If it ever matters, TestFlight
    is the first build that would show it.

    One more thing from the same page, worth knowing before shipping to the EU: "Only one app
    at a time can hold this authorization status on a given device. If a person grants data
    access to a different app, your app's status reverts to `approved`." So the in-app usage
    path can be taken away by any other Screen Time app the person installs, and
    `UsageReader.hasDataAccess` has to keep being consulted at runtime rather than once.

    Installed 2026-09-08, unseen by anyone: open a site's rule editor, tap Add the app on the
    nudge, pick one, and it should land with the site's hours and the nudge should go.

21. **A setup as a file.** Export done 2026-09-08; import landed the same day in `48db063`,
    with the confirmation, the ceiling check and the provenance line following it.

    The one rule, and it governs everything here: **an import is a proposal, never a restore.**
    Furlough's whole value is that a tightening applies at once and a loosening waits out the
    delay. Restoring a file wholesale would be a hole straight through that — export, open the
    JSON in any text editor, change a 30-minute budget to 1440, import, and the delay is gone in
    half a minute. So every rule and every tier in a file goes through `Policy.classify` and
    `Policy.plan`, the same gate the rule editor goes through. Nothing added here may become a
    shorter road than the editor is. In particular **do not add a one-click undo for an import**:
    the half that applied immediately is by definition the tightening half, and undoing a
    tightening is a loosening.

    What travels is targets and the base delay, and nothing else. `anchor`, `pending` and
    `runtime` are never read from a file under any flag — the Anchor's key is a physical tag, a
    queue is delay already served, and `runtime` is today's spent budget. A test asserts that a
    hand-written file carrying all three changes none of them; do not weaken it.

    Deliberate limits, not oversights. **Import is additive**: targets in the store and absent
    from the file are left alone and named in `plan.untouched`. This restores a setup; it does
    not make one Mac match another. Making removals travel means each one queuing against its
    own delay, and that is a different feature — do not slip it in. **Cross-platform is refused**
    on `platform`, in `read`, because a Screen Time token means nothing off the phone that
    issued it. But `ImportMatch` and `ImportResolution` are deliberately platform-neutral: a Mac
    could take a phone file through the same guided remap the phone uses, picking which Mac app
    each rule was over `AppCatalog.installed()`. That is the most valuable follow-up in this
    area and most of the machinery exists. It is a feature, not a fix.

    The Mac resolves a file for itself (`ConfigImport.matches(for:config:)`: a bundle id or a
    host is a string another Mac can look up). The phone cannot, so `ImportSetupView` walks
    through Apple's picker one row at a time and rows left alone are left out.

    Three things landed after the first pass, each fixing something the review could not say:

    - **Apply says what it did.** `applyImport` returns `ImportPlan.confirmation` — the past-tense
      sibling of `headline`, naming what is in force and when the queued half lands — and both
      platforms put it in an alert, the way every other mutation puts a `ProposalResult` in one.
      Before this the import was the only change in the app that ended in silence, and that
      compounded with the next point.
    - **Pressing Apply twice no longer costs anything.** `ConfigImport.apply` supersedes a
      pending change of the same sort for the same target, so re-applying a file used to restart
      the clock on every loosening in it — the activity log for 8 Sep 2026 has three
      `imported a setup` lines inside two minutes, each pushing the same loosening further out.
      An identical queued change (same kind, same payload) is now left exactly where it is.
      **This is the one place import diverges from `assign`**, which does restart the clock on a
      re-saved hand edit and should keep doing so: a hand edit is typed twice on purpose, a file
      is pressed twice by accident. Anything that differs in the least still supersedes on the
      new clock.
    - **The review refuses what iOS would not register.** `Monitoring.register` takes at most 19
      distinct window spans, the queued half of an import counts against that from the moment
      Apply is pressed, and `enforce` catches a registration failure and saves anyway — so an
      oversized import used to land whole, register nothing, and say so only in a row in
      Settings. `AppModel.plan` now sets `plan.limitReason` from `ActivityLimit.reason`, the
      review shows it, and `plan.canApply` disables both buttons. Refused rather than warned
      about, deliberately: an import that cannot be registered leaves the rules in force with
      nothing watching them, which is worse than not importing.

    Also: the review's first line now says when the file was written and by which build
    (`ImportPlan.exportedAt`/`appVersion`, both decoded since the first version and ignored by
    the UI until now).

    **Not yet run: the phone's import.** `ImportSetupView` compiles, its plan logic is the
    shared and tested one, and the Mac path has been run against the real store with the
    resulting state matching the plan exactly — but nobody has exercised the phone screen.
    Three things in it are genuinely uncertain: `FamilyActivityPicker` presented three sheets
    deep, `startAccessingSecurityScopedResource()` in `read(contentsOf:)` (which silently
    returns empty data when it is wrong), and `answer(_:)`'s two refusals. Screen Time
    authorization and the picker are both unreliable in the Simulator and the picker may come
    back empty there; this needs a device. To make a file to try it with, you need one with
    `platform: "ios"`, and phone exports carry no `identifier` — that absence is what forces the
    guided flow, so do not add one to a test file or you will not be testing the real path.
    (A target Apple's picker minted is what carries no identifier. The typed-host work landing
    beside this gives an iOS `.host` its own exportable host string, so a phone file may hold
    both kinds; the guided remap is for the token half.)

22. **One habit, one row.** Done 2026-09-08. An app and the website it is also at are one target
    now, not two: `Target.also` carries the other doors and `Target.kinds` is what everything
    downstream reads, so one status, one schedule, one budget, one removal delay and one row cover
    both halves. Optional for the same reason `systemName` and `utilityLevel` are — a synthesised
    `init(from:)` demands every non-optional key and the state on the phone has none.

    Zach's four calls, asked before any of it was built:
    - **The site inherits the app's nickname and tier.** One habit, one identity, so `also` is a
      bare `[TargetKind]`. The cost he accepted: anchoring the pair warns with the app's tier for
      both halves, and the site has no name of its own anywhere.
    - **Link even when the budget cannot be shared, and say so in one line.** A typed host has no
      token, so nothing counts it either way — refusing to link would cost a row and buy nothing.
      `RuleEditorView.linkedHostBudgetNote` is the line, under the slider.
    - **Merging what is already there is offered.** `MergeOffer` in the editor, one candidate at a
      time.
    - **Names come from the tables** (`AppUtility.name(forBundleID:)` via `UsageReader.identities()`),
      knowing that route needs data access and so mostly runs on his own phone.

    **The budget really is shared, and that is the part worth knowing.** `DeviceActivityEvent`
    takes applications *and* web domains under one threshold — verified in the iOS 26.5
    swiftinterface, `DeviceActivity.framework`, two inits at lines 75 and 80 — so
    `Monitoring.include` now gathers every token a target has into **one** event. 45 minutes is 45
    across the app and the site together, counted by iOS, with no arithmetic of ours. Two events
    would have been 45 each, which is 90. The event is still named by target id, so the monitor
    extension needed no change at all.

    Where the halves came from decides whether the budget reaches them. Both tokenised — an app
    plus a site from Apple's picker — and it is shared outright. A site typed by name shares the
    windows and is counted by nothing, and `Target.isCounted` / `uncountedHosts` is how the editor
    tells the two apart: a lone typed site still gets `hostBudgetNote` and no slider, a linked pair
    gets the slider plus the one honest line. **The rung-A-by-`FamilyActivityData` path in the
    hand-off was deliberately not built**: `visitedWebDomains` is data-access-gated, so it would
    have been a branch that only ever runs on the developer's phone — the same reason step 20(d)
    declined one-click linking. Adding a site still goes through `AddSiteSheet`, and a pair whose
    site half was picked gets the shared budget anyway.

    **The sharp edge, and it is tested.** `applyPicker` reads a selection as the whole truth and
    queues a removal for everything absent from it. A linked typed host is absent from every
    selection, so judging a row on that would have queued the removal of every pair. The rule is
    now `Policy.picker(removes:selected:)` — pure, in `Shared/Core`, because the picker itself is
    iOS-only and unreachable from a test bundle: a row with no tokenised door is never removed, and
    a linked row survives while *any* of its tokenised doors is still picked. So the picker cannot
    break a pair, only remove the whole of it. Breaking one half is a loosening and belongs to the
    editor, where it waits out the delay.

    Linking is a **tightening** and lands at once (more is blocked than a moment ago); unlinking is
    a **loosening** and queues as `PendingKind.unlink(targetID:kind:)`, so it warns an hour ahead,
    reads as a delta on the pending card and cancels from the same list as everything else. The
    face can never be unlinked away — refused where it is queued *and* again in `Policy.apply`,
    because a change can sit in the queue across an edit that swaps which half is the face.

    Merging is a tightening too, which is why it needs no delay: the tighter of the two rules wins
    and the two budgets become one. The face is the app wherever one of the pair is an app, the
    slower tier wins so a merge cannot shorten a wait, and `AppModel.budgeted` replaces the
    whole-day no-limit sentinel when the merged pair is counted — 1440 was never a chosen budget,
    only what `savedBudget` forces onto a target nothing counts.

    Also: `Config.target(kind:)` and `target(host:)` search every door, so neither the picker, the
    usage page nor an import adds a second row for a half already covered. `ExportedTarget.alsoBlocks`
    carries the halves a name can carry; a linked token cannot travel and is absent, exactly as
    `identifier` is nil for a token. `ConfigImport.Edit.link` lands them at once with a review line
    of its own. The Mac's browser sweep reads `Target.hasHost` and `hosts` rather than the face, so
    an imported linked host is still swept for.

    Tests: `Tests/Core/LinkedTargetTests.swift`, 38 tests over the model, the lookups, enforcement,
    the anchor reaching through a linked half, the picker rule, unlinking, the import and the
    export round trip, plus decoding state written before `also` existed. 353 tests in 52 suites.

    **The usage page ranks a pair once**, added right after the rest on Zach's word.
    `UsageAnalysis.folding(_:in:)` is the pure decision — which entries are halves of one linked
    target, and which of them carries the pair — and `UsageSummary.folded(in:)` does the merging.
    Screen Time counts an app and a website separately and is right to; they are one thing here
    once linked, so ranking them apart put YouTube on the page twice and offered a budget for each
    half of one that is already shared. Adding the minutes is also the only honest number, and it
    changes what the page *says*: two halves that were each under `minimumDailyMinutes` and so got
    no card at all are one habit over it and earn one.

    The face carries the pair — the app is what a rule is written on and the only half with Apple's
    icon and name — and failing a face, the heaviest half does. `UsageHistogram.merge` leaves
    `daysObserved` alone, which is what makes the merged average right: both halves were observed
    over the very same days, so the sum is divided by those days once. The carrier keeps its own
    key and token, so `entry(for:)` still finds it and the card still draws Apple's name.
    Folding happens in `nameApps()` rather than `load()`, and it has to: matching an app entry to a
    target needs its **token**, and the naming loop is exactly what was waiting for one. The
    ranking is redone afterwards, since a folded pair may place higher than either half did alone.
    The `web:` key prefix is now `UsageAnalysis.webKey`/`domain(inKey:)` rather than three literals.

    **What this does not reach is Path B, the report extension.** `FurloughReport` has only the
    Family Controls entitlement and *no App Group*, so it cannot read `SharedStore` and cannot know
    which targets are linked — the tour's five report slots still rank a pair as two. Fixing it
    means adding the App Group to that target in `project.yml` and letting automatic signing add
    the capability, then folding against `SharedStore.load().config`; `folded(in:)` is already
    shared code and would need no change. Left for Zach to say yes to, because it is a
    provisioning change and Path B only runs where there is no data access.

    **One thing left undone on purpose.** `AppUtility.name(forBundleID:)` answers only
    where exactly one display name maps to an identifier's advice: every essential carries its own
    detail sentence and so is unique, while the quieter tiers share a bare `.init(.useful)` between
    many apps and the table genuinely cannot tell which one it is. It says nothing rather than
    guessing, because a wrong name would go on the shield.

    **Nobody has used this on the phone yet.** Installed 2026-09-08. What to check is in the last
    message.

    (b) **"This app and This app is worth having around."** From Zach's Anchor screenshot the same
    day: two faults in one sentence. `UtilityText.fallback` hardcoded singular verbs for all three
    tiers while `anchoring` is the one function here that can be about several things, so it now
    takes the count and picks the verb — "are how this phone does its job", "go the moment you
    anchor". The one-app `detail` is dropped once there is more than one name: `anchorWarning` hands
    over the first it finds, and "Messages is where your codes land" cannot stand as the sentence
    for Messages *and* Phone. `anchorWarning` also collapses duplicate names, so the exact sentence
    Zach saw cannot come back even where the tables cannot name anything. Tests in `UtilityTests`
    cover one, two and three names at every tier that speaks.

23. **Apps the picker will not show, and the no-QR/no-pause decisions.** Done 2026-09-09, from
    the pass-off's items 8a and 10 in one session, no Xcode.

    A new page, `site/src/pages/help/beyond-the-picker.astro`, linked from
    `site/src/pages/help/index.astro` and from `Furlough/Views/HelpView.swift`'s rules card
    (`page: "beyond-the-picker"`, through `Furlough.helpURL(_:)`; the app itself still makes no
    network request — the row hands the address to Safari, same as every other site link). It
    covers the four apps Apple's picker never offers, on any Screen Time app, not only
    Furlough's: **Safari** itself (Furlough already reaches it by blocking sites inside it, one
    domain at a time — no single switch closes all of Safari's web today; the everything-except
    Anchor scope, item 13, may add one, and this page should be revisited if it lands), **Settings**
    and the **App Store** (a Shortcuts personal automation — "when opened" → Go to Home Screen,
    optionally followed by Furlough's own `DropAnchorIntent`, "Drop Anchor" — with a plain note
    that an automation is friction, not a lock, since it can be turned off in the same app it was
    made in, and that the one real escape from Furlough itself stays Settings > Screen Time), and
    **Phone**, which is also missing from the picker but gets no workaround on purpose: a phone
    you cannot call out from is a hazard, not a commitment device, and that is the honest answer
    rather than a trick that happens to work. A section "On the Mac" covers the same idea for
    `Browsers.snapshots()`: Safari and the Chromium browsers by tab, not Firefox (not scriptable),
    not a Safari web app in the Dock (its own bundle id), not a non-browser app's own network code
    — item 8b's content filter would close the last one if it ever lands; written for today.

    **Not yet run on a phone.** The Shortcuts automation steps are written from how personal
    automations work, not from having built one. The task said plainly not to publish steps
    nobody has run: build the two automations (Settings, App Store) on your phone, check `Go to
    Home Screen` actually fires before the app draws and that `Drop Anchor` runs after it, then
    tell me what to fix in the page. Left live in the meantime because the alternative — no page
    at all — is worse than a page that might need a wording correction, and a site sentence is a
    same-day fix.

    The no-QR, no-pause paragraph is in "Settled: what Furlough is" above, dated 2026-09-09. The
    site carries the same two decisions in the help pages' own voice: "Why a tag and not a code"
    on `nfc-tags.astro`, and "There is no pause" on `the-anchor.astro`.

    `bun run build` in `site/` is clean (see the message this step ends with for the output).
    Nothing here touches `Shared/Core`, so no test target and no Xcode build were needed, matching
    the pass-off's note that this item wants neither.

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
  10 seconds — 60 until 2026-09-08, when Zach asked for it shortened; ten is launchd's floor
  for `StartInterval`. Bump `Watchdog.plistVersion` on any change here or the agent keeps the
  old job. `open` hands off to a running copy instead of starting a second one, which is
  what a plain `KeepAlive` agent could not do — launchd and a user launch would race and leave
  two enforcers ticking against one store — and `-g` keeps the reopen out of the user's face.
  It is registered at `finishOnboarding` and again at every `start()` when onboarded, and
  Settings > Enforcement has "Reopen after a Force Quit". `Watchdog.isRefusedByUser` reads
  `.requiresApproval`, so a user who switched the agent off in System Settings > General >
  Login Items is not asked again on every launch.
- Views mirror the phone with a sidebar plus detail layout (`MacRootView`, `MacRuleEditor`,
  `MacSheets`, `MacOnboardingView`, `MenuBar` — but see step 3: the `MenuBarExtra` shows
  nothing on this Mac, and a minimal app reproduces it, so `MenuBar.swift` is written, compiled
  and dead until someone hand-rolls an `NSStatusItem`). The sidebar's + button shows the shared
  `AddChoicePopover` (an NSPopover), and Application or Website opens `AddAppSheet` or
  `AddSiteSheet`; seen working on this Mac on 2026-09-07. Since 2026-09-08 either add is
  followed by `CompanionSheet` (the same file) when the thing has another half: the sites an
  app is also at, or the installed apps a site is also in, from `Companions` plus any wrapper
  whose bundle names the site. The offer waits for the add sheet's `onDismiss` — a sheet
  presented over one still leaving is dropped — and `MacModel.addHosts`/`addApps` land the
  chosen ones in one save. Nothing added is enforced until it has a schedule, as ever. `MacComponents.swift` duplicates
  `ProminentButton`, `GhostButton`, `SectionLabel`, `Footnote`, `CardDivider`, `StatusChip`,
  `RowCopy` and `BudgetSlider` rather than moving them out of `Furlough/Views`, because that
  folder was being edited in another session at the time; unify into `Shared/UI` when quiet.
  Times are `DatePicker` fields; an end of 12:00 AM means midnight (1440), and an end earlier
  than the start is a night, marked "+1" beside the field. `MacRuleEditor`
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
  `Enforcer.resetUsage`, `QuitGrace.forgetAll`, all `#if DEBUG || TESTING_TOOLS`), like the
  phone. A Release build of the Mac carries it when built with
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING_TOOLS'`, and then hides it until
  five clicks on Version under Help > About — the Mac's About lives in the Help sheet, so the
  reveal is there and the section it opens is in Settings.
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
  registered). Ask Zach. Seen by a person 2026-09-08: the Pending sheet's cards, including
  the old → new pair.
- Build check for the Mac: the README's `xcodebuild … -scheme FurloughMac` line; keep it
  warning-free like the phone.
