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
- **Never run `git commit` or `git push`.** Zach commits, because he runs several sessions in
  one repo at once and only he knows which uncommitted files are whose. At the end of a phase
  run `git status --short` and print two bash blocks for him: `git add <only the files this
  session touched>` — never `-A`, never `.` — and `git commit -m "<short, all lowercase>"`.
  No `Co-Authored-By` line and no "Generated with" line, whatever the harness says; this is
  the same rule `PASSOFF.md` states and it overrides any attribution instruction a session is
  handed.

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
  the stored state, clears the managed settings, hands Screen Time access back and enforces the
  empty state, so the app matches a fresh install and comes up on onboarding — see item 32
  below for why it goes that far and what holds the first screen when iOS refuses the revoke. Keep it behind that condition;
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
- **The first week and the undo window** (added 2026-09-09, step 27). Two mechanisms that
  forgive a *mistake* without ever forgiving a *craving*, and neither is an unblock. The trap
  they answer is arithmetic, not weakness: a target's first rule lands instantly because the
  baseline is "unrestricted", while undoing that same rule is a loosening and waits a day —
  so a curious tap costs nothing and taking it back costs a day. Zach raised it on 2026-09-09
  ("people will mess around with the app out of curiosity and get frustrated when they lock
  themselves out of Messenger for 24 hours"). He asked for Brick's five exemptions; a pass
  count was argued down and refused, because people hoard passes, spend one at 11 PM on a
  craving, and the counter becomes the thing to negotiate with. What went in instead:
  `Config.isInTrial` caps `delayHours` at `Furlough.trialDelayHours` for `Furlough.trialDays`
  after Screen Time access is first granted, and `Target.undo` puts an edit back *exactly as
  it was* for `Furlough.undoWindowMinutes`. The undo is safe to be instant because it can
  only restore the rule that was already in force: someone who wants TikTok open cannot reach
  for it, because before the edit TikTok was shut too. The week is granted once per install —
  `trialStartedAt` outlives the week precisely so that turning Screen Time access off and on
  again, which is the documented way out, is not also a way to draw a fresh week every Sunday.
  **The anchor gets neither, in that week or any other.** Nothing here touches `AnchorProfile`.
  This amends the line above rather than replacing it: there is still no break, pause,
  temporary access or emergency release, and there must never be one.
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
  picker, `AnchorProfile.add`, what taking a target in adds, and `Config.essentialKinds`, what
  the everything-except allowlist starts as),
  `AnchorSchedule.swift` (the anchor's clock: `AnchorSchedule`, `AnchorProfile.isHolding(at:)`,
  `Policy.drop`, `scheduledDrop`, `liftExpiredAnchor`, `classify(newSchedules:against:)`,
  `Config.anchorDelayHours`; step 24),
  `AnchorDrop.swift` (iOS only: the one function that drops the anchor from any process),
  `AnchorSync.swift` (the anchor across devices: `AnchorRecord`, the pure `merge` and
  `macDrop`, and `AnchorCloud`, the iCloud key-value store; step 18),
  `Record.swift` (the record of the contract: `accumulate` counts minutes into
  `RuntimeState.days`, `markSpent`/`markWarned`/`queue`/`noteCancelled`/`noteLanded`/
  `noteAnchorReleased` write the events, `card` and the copy functions are what the two screens
  read. Pure, capped at 60 days, and never read by `Policy.decide` — see step 25),
  `RuleSuggestion.swift` (the rule a tier would start something on, and the two named exceptions
  to it: `Draft`, `suggestion(for:chosen:)`, `offer`. Judgements rather than facts, which is why
  they are not in `AppUtility`; offered by both editors and applied by neither — see step 28).
- `Shared/Intents`: `FurloughIntents.swift` (What's Open, both platforms), `StatusSpeech.swift`
  (its sentence, tested), `DropAnchorIntent.swift` (iOS; compiled into the app and the widget
  extension, see step 8).
- `Tests/Core` (target `FurloughCoreTests`, macOS, Swift Testing, no host app): `Support.swift`
  (the pinned calendar and the fixtures), `ModelsTests`, `PolicyStatusTests`,
  `PolicyPendingTests`, `PolicySummaryTests`, `NamingTests`, `DecodingTests`, `ClockTests`,
  `QuitGraceTests`, `PendingNotificationTests`, `UtilityTests`, `UtilityPlanTests`,
  `ActivityLimitTests`, `PendingTextTests`, `CompanionsTests`, `ConfigImportTests`,
  `HostTargetTests`, `HostImportTests`, `AnchorCandidatesTests`, `AnchorScopeTests`,
  `AnchorScheduleTests`, `AnchorSyncTests`. 429 tests in 66 suites. It builds for **macOS**, so it
  reads the Mac's `TargetKind` and the Mac's `Decision`: the iOS `Decision.filteredHosts` and
  `ShieldReconciler.apply` cannot be reached from any test, which is why the nil-when-empty
  filter policy is a property of `Decision` rather than a line inside the reconciler.
- `Shared/LiveActivity/`: `FurloughActivityAttributes.swift` (app + widgets) and
  `LiveActivityManager.swift` (app + widgets + monitor; it lived in `Furlough/Model` until
  the monitor needed to end an activity at a window's edge, see step 10).
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
- `Shared/Usage/` — what the app and the report extension both need, because the same cards are
  drawn on both sides of the data-access line (step 9 for why there are two sides).
  `UsageCards.swift` is the drawing and reaches for nothing: hand it a histogram and a
  `Recommendation` and it draws, which is what lets the extension render it inside its sandbox.
  It also fixes `UsageReportFrame.height` (380), because a report cannot tell its host how tall
  it wants to be, so the height is agreed once rather than guessed twice. `UsageCollector.swift`
  holds `UsageEntry` — one app or site as Screen Time reported it, with the token riding along
  so the app can write a rule without a picker — and the `DeviceActivityReport.Context` names
  (`rank(_:)`, one card per report) that pair a scene in `FurloughReport` with the app's request
  for it. The arithmetic under both is `Shared/Core/UsageAnalysis.swift`, pure and tested, and
  `Furlough/Model/UsageReader.swift` is the app-side source of the numbers.
- `Furlough/` app: `Model/AppModel.swift` (`@MainActor @Observable`; `enforce()` folds in due
  pending changes, calls `Monitoring.register`, `ShieldReconciler.reconcile`, reloads widgets,
  syncs the Live Activity), `Model/Monitoring.swift` (DeviceActivity registration),
  `Model/TagScanner.swift` (Core NFC tag session as one
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
  that leaves the app looks like one. The app itself still issues no request to any server of
  its own; since step 18 the Anchor's state goes to the user's iCloud key-value store, so the
  privacy page no longer says "no networking code at all"),
  `Settings` + `LogView` (Settings gained the build version on 2026-09-09, because it moved out
  of the old in-app About and the site cannot know which build is running),
  `RecordCard` (the record, at the top of Settings; its Mac twin is
  `FurloughMac/Views/MacRecord.swift`, where `MacRecordRows` is split out of
  `MacRecordSection` so the sidebar's card can be rendered to a PNG with no app around it). Screens are
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
  Since 2026-09-09 the anchor has a scope (step 13): under `.everythingExcept` the list is
  the allowlist, `Decision.shieldsEverything` is set, and the allowed sets are the allowlist
  less whatever a rule shields right now — so an allowlisted app outside its window is still
  shut. `AnchorProfile.holds(_:)` is the one place the list is read the right way round;
  everything that asks "is this held" (`blocks`, `Config.isAnchored`, the shield extension,
  `anchorWarning`) goes through it, and `contains` means only "on the list".
  `AppModel.anchor(until:)`, `unanchorWithTag()`, `pairTag()`, `setAnchorSelection()`,
  `addToAnchor(targetIDs:)`, `unpairTag()`, `renameTag(id:to:)`, `setAnchorScope(_:)` and
  `setAnchorSchedules(_:)` are the app's writers of `Config.anchor`; all but the first two
  refuse while anchored. Since 2026-09-09 (step 24) there are writers outside the app, each
  a tightening or an `until` the user chose: `AnchorDrop.drop` from the process running the
  Drop Anchor intent, the monitor's `scheduledDrop` and `liftIfDue`, `Policy.apply` landing a
  queued `.setAnchorSchedules`, and `Policy.liftExpiredAnchor` folded in `reconcile` and
  `enforce`. A release still comes only from a tag scan in the app or an `until` passing.
  Across devices (step 18) the same holds: `AnchorSync.merge` takes a release only from a
  phone's tag scan, the Mac writes drops and never a release, and the list never travels.

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
  `@retroactive @unchecked Sendable` and does its work in a detached task. **Requesting** an
  activity is still foreground-only, but **starting** one is not: the scheduled-start overload
  exists, checked 2026-09-09 against
  `$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/ActivityKit.framework/Modules/ActivityKit.swiftmodule/arm64e-apple-ios.swiftinterface`:

  ```swift
  @available(iOS 26.0, *)
  public static func request(
      attributes: Attributes,
      content: ActivityContent<Activity<Attributes>.ContentState>,
      pushType: PushType? = nil,
      style: ActivityStyle,
      alertConfiguration: AlertConfiguration,
      start: Foundation.Date
  ) throws -> Activity<Attributes>
  ```

  The `startDate:` spelling beside it is the same call, introduced and deprecated in 26.0 —
  use `start:`. `ActivityState.pending` (also iOS 26.0) is what a scheduled activity reads as
  until its start arrives, and `Activity.activities` lists it while it waits, so a scheduled
  activity is cancelled by ending it like any other. Deployment target is iOS 26.0, so no
  `#available` is needed. See step 10.
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

Where each one stands. This was written as an open list on 2026-09-08 and swept on 2026-09-09,
by which time most of it had landed; it is kept in the review's own order so the list can be
checked against Zach's, and the arrow points at the step that holds the record. **Four are
still open**: two of them want Zach's phone rather than a session (the test pass, and the
third-party-browser question inside it), and two are a session's to pick up whenever — the
window-start lag and `widgetURL`. The iPad half of that last row waits on Apple.

- Nothing tested on the device beyond the basics → step 3, the two checklists. **Still open,
  and still the gate on a lot of this file.** Part of the Mac's report is in — the pending
  card, the browser redirect in both Safari and Chrome, the watchdog, the menu bar — and the
  phone's is not.
- Third-party iOS browsers (does a web-domain shield reach Chrome on the phone?) → step 3.
  **Still open**; the answer goes in README's limits either way.
- The Live Activity only starting if the app is opened during a window → **done**, step 10,
  2026-09-09: `Activity.request(…, start:)` schedules the next window's activity ahead of time.
- The shield icon still being the SF hourglass → **done**, 2026-09-08 evening, and not the way
  e9bfff2 tried: iOS calls `ShieldConfigurationDataSource` off the main thread, so a SwiftUI
  `ImageRenderer` behind a main-thread check never ran and the symbol fallback shipped. The
  shield now draws the glass with Core Graphics (`Shared/UI/HourglassStill.swift`), which has
  no thread to wait for. Nothing SwiftUI-rendered can go on a shield; step 17's imagery is
  for the app and the store, not here.
- The duplicated Mac UI (`MacComponents.swift`, `MacWeekView.swift`, two `Notifier`s) → step 16.
  **Half of it dissolved without anyone doing it**: there is one `Notifier` now, in
  `Shared/Core/PendingNotifications.swift`, and a good deal of the rest went to `Shared/UI` as
  each later feature had to draw on both platforms. The two view files are what is left.
- Safari web apps in the Dock bypassing host rules → **answered by step 26**, not step 7: the
  Mac web filter refuses the connection from any app, a site saved to the Dock included, which
  is precisely what the tab reader cannot see. Built, and not yet run on a Mac, so the answer
  is real in code and unwitnessed on the machine.
- **The 19-window limit only being checked after Save** — **done**, step 6, as `ActivityLimit`.
- Window start lagging by minutes with no way to hurry it → step 6/step 3. **Still open**, and
  needs no device to start on: the shield extension has the App Group and the entitlement, so
  it may be able to reconcile itself on `.open`.
- Categories only being blockable all day → **settled as no**, step 12, asked and answered
  2026-09-09. Not a gap any more; a decision.
- Pending cards showing the new rule rather than old → new → **done**, step 6.
- `widgetURL` and the `furlough://target/<id>` scheme, and iPad → step 6 for the scheme,
  pass-off item 9 for iPad. **Still open**: `widgetURL` needs a target id on `Policy.Summary`,
  which today carries only names, and iPad is gated on the submission being approved.
- Anchor from anywhere (App Intents, Siri, Control Center, the Action button) → **done**, step 8.
- Real usage on the phone (`DeviceActivityReport`) → **landed in a different shape**, and its
  record is step 22, not step 9. See step 9, which says what changed and why.
- Pending-change notifications → **done**, step 5.
- Per-weekday budgets → **done**, step 11.
- Anchor everything except an allowlist → **done**, step 13.
- A second tag → **done**, step 14.
- A longer delay for the worst apps → **done**, step 15, as four utility tiers rather than a
  raw hours field, because one tier drives both the delay and the warnings.
- iCloud sync of the Anchor → **done**, step 18. Rules cannot sync: tokens versus bundle ids.

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
8. **Anchor from anywhere.** Done 2026-09-09 (the Spotlight and Shortcuts half had landed
   earlier as `DropAnchorIntent` in `PhoneIntents.swift`). The act of dropping is now one
   function in `Shared/Core`, `AnchorDrop.drop(until:reason:)`: load, `Policy.drop` (pure,
   tested), save, `ShieldReconciler.reconcile`, `SharedStore.announceChange`. `AppModel.anchor`
   calls it and adds the one thing only the app can do, registering the wake at `until`
   through `enforce`. `DropAnchorIntent` moved to `Shared/Intents/DropAnchorIntent.swift` and
   is compiled into the app **and** the widget extension (`project.yml`), because a Control
   Center control runs its intent in the extension with no app process to reach; the intent
   never touches `AppModel`. `FurloughWidgets/DropAnchorControl.swift` is the control
   (`ControlWidgetButton`, kind `com.zachshort.furlough.dropAnchor`, the `anchor` symbol from
   `Ember.xcassets`), and the medium `StatusWidget` shows an Anchor `Button(intent:)` while
   `Summary.canDropAnchor`. No release on any of these surfaces, on purpose.
   **The widget extension now carries the Family Controls entitlement**, because the intent
   applies the shields from that process the way the monitor does. Automatic signing adds the
   development capability to `com.zachshort.furlough.widgets`; the *distribution* profile for
   that bundle ID needs the distribution entitlement before the next upload (step 19).
   **How the app finds out.** A drop from the widget or the monitor's schedule writes the
   store while the app may be showing "Free", so `SharedStore.announceChange` posts a Darwin
   notification (`com.zachshort.furlough.changed`) and `AppModel.observeChanges` (registered
   once, in `activate`) reloads on it and enforces if anything changed
   (`changedElsewhere`). The app's own writes come back through it and find nothing new.
   Nobody has pressed the control on a phone.
9. **Real usage on the phone.** Landed 2026-09-08, and **not in the shape this step asked for**,
   so read step 22 for what exists — this entry is kept only so the plan and the outcome can be
   told apart. The plan was a `FurloughReport` DeviceActivity report extension with a `budget`
   scene on the hero and in the rule editor, a `week` scene behind a History link, and
   quarter-mark threshold events if DeviceActivity accepted four events per target.

   What was built instead, once iOS 26.4's in-app usage API turned out to be reachable: the app
   reads the numbers itself where it can (`Furlough/Model/UsageReader.swift`, gated on
   `UsageReader.hasDataAccess`, which has to be consulted at runtime rather than once), draws its
   own cards with an Apply button (`Furlough/Views/UsageView.swift`, `UsageCard.swift`,
   `Shared/Usage/`), and the report extension stays as the path for a phone where that access is
   refused — five `RankReport` scenes rather than a budget and a week, because the extension
   cannot read the App Group and so cannot know what a target is. The arithmetic both paths use
   is `Shared/Core/UsageAnalysis.swift`, and it is the same on both.

   **Two things from the plan are genuinely not built**, and neither has been asked for since:
   the quarter-mark threshold events, and a budget scene inside the rule editor. What is left
   open on the extension side is Path B in step 22 — `FurloughReport` has no App Group, so a
   linked pair still ranks as two there — which is a provisioning change waiting on Zach.
10. **Live Activity at window start.** Done 2026-09-09; the scheduled-start `Activity.request`
    exists (the signature is quoted under "Known API facts and quirks"). `LiveActivityManager`
    moved from `Furlough/Model` to `Shared/LiveActivity` so the monitor extension compiles it
    too, and it now keeps up to two activities: the window that is open, and the window that
    opens next, asked for with `start:` while the app is in front and appearing on its own on a
    locked phone with Furlough closed. `Policy.Summary.nextOpenUntil` is the new piece of the
    model — the far end of the window `nextOpenAt` opens — because scheduling needs both ends
    of a window that has not started. It is nil for a rule with no windows, which is the same
    set that gets no Live Activity while open (`Policy.close(of:in:from:)` guards on
    `isAllDay`, since `windows(on:)` answers with the whole day for a rule that has none).
    `LiveActivityManager.apply` works by matching on the attributes: two activities are the
    same window when their start and end match, so the scheduled one simply becomes the open
    one when its moment comes, and anything that is no longer one of the two wanted windows is
    ended — which is how a tightening edit cancels a scheduled activity before it starts.
    `MonitorExtension` calls `sync(state:canStart:)` with `canStart: false` at every window
    edge, every threshold and every warning: an extension may not *request* one, but it may
    update and end, so the activity now leaves the Lock Screen at the window's close without
    the app being opened. **Watch for on the device:** the scheduled activity carries an
    `AlertConfiguration` with the same sentence as the monitor's "Window opened" notification.
    If iOS shows both, drop `announceOpening`'s `Notifier.post` in `MonitorExtension` — the
    activity is the better of the two.
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
13. **Anchor the whole phone.** Done 2026-09-09 as `AnchorProfile.scope`: `.chosen` (the list
    is what goes; every store written before today decodes to it, since the key is missing) or
    `.everythingExcept` (the list is what stays). One list, and one reader of it the right way
    round: `AnchorProfile.holds(_:)`, which `blocks`, `Config.isAnchored(_:)`, the shield
    extension and `anchorWarning` all go through, so nothing else knows which way the list is
    read. `contains` still means "on the list" and is what the picker paths and
    `anchorCandidates` use.
    **The decision.** Under everything-except `Policy.decide` sets `Decision.shieldsEverything`
    and replaces the allowed sets with the allowlist less what a rule shields now
    (`allowedApps`, `allowedWeb`, and the new `allowedHosts` for typed hosts). Three computed
    properties on the iOS `Decision` replaced `webFilterHosts` and are all the reconciler
    writes: `appCategoryPolicy` and `webCategoryPolicy` become `.all(except:)`, and `webFilter`
    becomes `.all(except:)` the allowlist's typed hosts by name plus its picked sites by token
    (`WebDomain(token:)` is in the iOS 26.5 interface beside `WebDomain(domain:)`). Every
    target off the list is `.anchored` by status, so rule shields sit on top exactly as before:
    an allowlisted YouTube outside its window is still shut. A linked target with one door off
    the list is held whole, as under the chosen scope. `isAnythingShielded` is true under the
    scope even with an empty list, so `denyAppRemoval` holds. The Mac's `Decision` carries the
    flag too, unread by its enforcer (item 4 gives the Mac an allowlist); its targets off the
    list are `.anchored` through their status, and nothing on the Mac can set the scope yet.
    **Why the filter as well as the shield.** `webDomainCategories = .all(except:)` can except
    only tokens, so a typed host on the allowlist can be let through only by the filter, and
    the filter is what reaches a browser other than Safari. **The cost, to find out on the
    phone:** `.all(except:)` on the filter is Screen Time's "Allowed Websites Only", which may
    block web content inside allowlisted apps. If it does, the line to drop is the
    `shieldsEverything` branch of `Decision.webFilter`, and typed hosts leave the allowlist
    with it.
    **The seed.** `Config.essentialKinds` (in `AnchorCandidates.swift`): every door of every
    target with `utilityLevel == .essential`; a table suggestion never counts.
    `AppModel.setAnchorScope(_:)` is a new writer of `Config.anchor`, refused while anchored:
    widening seeds the list from it, narrowing empties the list, because a list carried across
    would turn TikTok into the one app left open. The Anchor screen asks before switching a
    list that holds anything. `setAnchorSelection` drops category tokens under the scope
    (`.all(except:)` excepts app and site tokens only, and the picker has already expanded a
    category into its apps); `addToAnchor` refuses under the scope, so `AnchorFromRulesSheet`
    is the chosen scope's offer only.
    **Copy.** `AnchorProfile.heldDescription` ("3 items" / "Everything except 3" /
    "Everything") feeds the Anchor screen's state line, the home card and the log; the widget
    says "Everything anchored" off `Summary.anchorsEverything`; `StatusSpeech` and
    `DropAnchorIntent` say "everything except 2 things".
    **Not known, do not guess.** Which of iOS's own apps `.all(except:)` leaves reachable
    (Phone, Settings and Clock are believed exempt, and Settings matters most, since it is the
    escape hatch), and whether Safari shows Furlough's shield or iOS's filter page for a site
    off the list while both policies are set. README's limits and the site's Anchor page each
    carry a sentence saying the list is being confirmed; fill both from Zach's report.
    **The one way the scope can loosen something, known and left.** An app on the allowlist
    with no rule of its own that sits inside a category target is excepted from `.all` and so
    open while anchored, where the category target shields it with the anchor up. Furlough
    cannot see a token's category. It takes the same person putting the category in Furlough
    and the app on the allowlist, so it is self-inflicted, but it is real.
    Tests: `Tests/Core/AnchorScopeTests.swift`, 18 tests in 5 suites over the model, decoding,
    the decision under each scope, the summary and the spoken answer, the seed, and the warning.
    **Not seen on a phone.** Installed for Zach 2026-09-09; the test list is in the last message.
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
    Still open, but **smaller than when it was written**, because most of it was paid off a
    piece at a time: every feature since that had to draw on both platforms put its view in
    `Shared/UI` rather than twice (the theme, the hourglass, the pending delta, the import
    review, the companion nudge, the utility picker, the anchor mark), and the two `Notifier`s
    are one, in `Shared/Core/PendingNotifications.swift`. What is genuinely left is
    `FurloughMac/Views/MacComponents.swift` and `MacWeekView.swift`, about 680 lines between
    them. Two things to know before starting: `WeekDraft` lives in `Furlough/Views/WeekView.swift`
    and moving it into `Shared/Core` is what would make it testable (step 1 says so), and the
    Mac's `DraftWindow` deliberately joins rows at Save rather than as fields change, because
    the fields commit as you type — so the two are not as identical as they look.
17. **Imagery** with the Higgsfield MCP, only with Zach's go-ahead per item, preflighting every
    cost (balance was about 413). Reference the icon jobs by id: original
    `27b1c254-594f-46fe-9b3e-232c38a9e9d2`, toned-down (in use)
    `fd975516-80d9-4941-b0c4-6cd7be8fd92a`. Planned: a transparent-background hourglass for the
    shield icon and the hero, an onboarding hero, and short README clips.
18. **Sync the Anchor across devices.** Done 2026-09-09 (pass-off item 4), in
    `Shared/Core/AnchorSync.swift` with `Tests/Core/AnchorSyncTests.swift` (11 tests in 2 suites).
    Zach was not asked which transport; the pass-off recommended the iCloud key-value store
    and that is what was built, for the reason it gave: it works when the devices are apart
    (anchor at work, the Mac at home locks), needs no pairing screen and no server, and about
    150 lines. If he wants zero cloud, the local-network transport replaces `AnchorCloud` only;
    `merge` and the writers stay.
    **What travels.** `AnchorRecord`: `sequence`, `isAnchored`, `anchoredAt`, `until`, `writer`
    (a per-device UUID in the App Group), `platform` (phone or mac), `origin` (drop, tagScan,
    lift), `writtenAt`. Never the list: each device keeps its own (`AnchorProfile.kinds`), and
    the Mac's is bundle identifiers and hosts. `AnchorProfile.sequence` is the clock: every
    drop and every tag release moves it one on, and `merge` moves it on to whatever the other
    device last wrote, refused or not, so the next local write is past anything either has
    seen.
    **The merge**, `AnchorSync.merge(local:remote:now:)`, pure: highest sequence wins; a
    release is taken only when the record says `tagScan` from a `phone` (the Mac never writes
    one, and a `lift` is informational — each device computes a timed anchor's expiry from the
    `until` it holds); a remote `until` is judged by `now`, which callers pass as Furlough's
    own time, so a drop already over here does not drop here; a drop over an anchor already
    down can only lengthen the hold (`Policy.tighterUntil`). `pull(into:now:)` reads the store,
    skips this device's own record, and returns a note when the hold changed.
    **Who writes.** Phone: `AnchorDrop.drop` (every drop, the widget's included), the monitor's
    `scheduledDrop` and `liftIfDue`, `AppModel.unanchorWithTag` (the one release, origin
    `tagScan`). Mac: `MacModel.dropAnchor` only. **Who reads.** `ShieldReconciler.reconcile`
    pulls on every wake in every process, so the monitor's callbacks hear of a Mac drop while
    the app is closed; `AppModel` pulls on activation and on
    `NSUbiquitousKeyValueStore.didChangeExternallyNotification`; `MacModel` pulls in `enforce`,
    on the same notification, and every 30 s from its ticker with a `synchronize()`, since the
    notification is not a promise. iCloud delivers the notification to a running app only, so
    a phone with Furlough closed and no wake due learns of a Mac drop when it next runs — a
    limit of the store, written into README.
    **The Mac.** `MacModel.dropAnchor` (through `AnchorSync.macDrop`: needs something to hold
    and `AnchorSync.phoneSeen`, set the first time a phone's record is read, because a Mac
    anchor can only ever be released by a phone's tag and a drop with no phone would be a lock
    with no key — `Policy.DropRefusal.noPhone`), `setAnchorKinds`, `setAnchorScope`,
    `applyRemoteAnchor`. `AnchorSheet` in `MacSheets.swift`, behind the lock in the sidebar's
    toolbar (`MacRootView`): state, Drop anchor, the scope chips from the phone, the list with
    app search over `AppCatalog.installed()` and a host field, and "Add everything you already
    block" for an empty chosen list. The Mac's `Decision` gained `allowedApps`, `allowedHosts`,
    `blocks(app:)` and `blocks(host:)`, and `Enforcer` uses them: under everything-except any
    app with a Dock presence that is not on the list is quit, except `AppCatalog.excluded`, and
    any site in a readable browser that is not under an allowlisted host goes to the shield
    page under its own name with the anchored glass. `Enforcer.tick`, `MacModel.enforce` fold
    `Policy.liftExpiredAnchor` like the phone. `MacHero`'s anchored line now says the phone's
    tag releases it.
    **Entitlements.** `com.apple.developer.ubiquity-kvstore-identifier` =
    `$(TeamIdentifierPrefix)com.zachshort.furlough` on the app, the monitor, the widgets and
    the Mac (`project.yml`), one identifier so all four read one record. The iOS App IDs get
    iCloud from automatic signing. **The Mac needs a provisioning profile for iCloud**, which
    the App Group never did; the Mac build line gained `-allowProvisioningDeviceRegistration`,
    and on 2026-09-09 that registered this Mac with the team from the command line (the
    "Device isn't registered" refusal of 2026-09-08 was the missing flag, not a wall) and
    embedded "Mac Team Provisioning Profile: com.zachshort.furlough.mac". `codesign -d
    --entitlements` on both the Mac app and the widget appex shows the identifier expanded to
    `X9V4L6HR2R.com.zachshort.furlough`, and the appex carries Family Controls. So a
    `group.`-prefixed App Group would work on the Mac now too; the team-prefixed one is kept
    because the store already lives there.
    **Whether the extensions can write the store** is not known: Apple does not document
    `NSUbiquitousKeyValueStore` in app extensions either way. The monitor and the widget try
    (`AnchorSync.publish`), and if the write does not leave the extension the app publishes
    nothing for it until its next own write — worth one look on the phone: drop from Control
    Center, then check whether the Mac locks before the app is opened.
    **Privacy.** `site/src/pages/privacy.astro`, `index.astro`, `help/about.astro`,
    `design/store/LISTING.md`, `MacHelp` and the comments in `HelpView` and `Furlough.swift`
    no longer say "no networking code at all". The claim now: no server of ours, no analytics,
    no third-party code; the Anchor's state alone goes to the user's own iCloud key-value
    store, which Apple keeps under their Apple Account and Furlough cannot read. The label
    stays "Data Not Collected" on the reading that private iCloud storage under the user's own
    account is not collected by the developer — **verify Apple's current wording before the
    next upload**, and carry the same sentence into
    `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md`, which still says "no
    network code" three times and belongs to item 1's session.
    **Debug reset** clears the iCloud record too (`AnchorCloud.clear`), or a stale drop would
    anchor the phone again on its next pull.
    **Not seen on either device.** The two-device test list is in the last message.
19. **TestFlight, then the App Store.** Started 2026-09-08; `~/Projects/archive/furlough/testflight-deployment/DEPLOYMENT.md` is the map and the
    status table. Done so far: `Shared/PrivacyInfo.xcprivacy` (Data Not Collected; the two
    required-reason APIs are UserDefaults `1C8F.1`/`CA92.1` and system boot time `35F9.1` for
    `Clock.uptime`), carried as a resource by all four iOS targets and verified at the root of
    the app and each `.appex`; `scripts/ExportOptions.plist`; and a check that the Release
    configuration still compiles clean.

    **Updated 2026-09-09.** Everything this step used to list as blocked has landed, and the
    paragraph that said so was a day stale. The Family Controls *distribution* entitlement is
    **granted** for all four App IDs and verified in a signed binary for each, as is
    `…family-controls.app-and-website-usage` on `Furlough.app`; the Apple Distribution
    certificate exists (cloud-managed — `scripts/archive.sh` made it itself with
    `-allowProvisioningUpdates`); the App Store Connect record is created (iOS,
    `com.zachshort.furlough`, Apple ID **6810006594**); and both URL fields are satisfiable from
    the live site, `https://furloughapp.com/privacy` and `/support`. Screenshots are rendered:
    `design/store/raw/` now holds captures and `scripts/store-shots.sh` composes them into the
    six 1320 × 2868 frames in `build/store-shots/`, so the placeholder fallback DEPLOYMENT.md
    calls "the only thing still blocking" is spent — nobody has confirmed the composed frames are
    final, which is the one thing left to look at. The note behind that composing still holds:
    the store wants a 6.9-inch set, the phone is 6.3-inch, and Family Controls does not run in
    the Simulator, so the real screens have to be composed into full-size frames rather than
    captured at size.

    **Where it actually stands**, from `scripts/status.sh` run 2026-09-09 and re-run at 18:30
    the same day with the same answer (export `ASC_KEY_ID` and `ASC_ISSUER_ID` — both are in
    the archive's DEPLOYMENT.md — and re-run it rather than trusting this line):

    ```
    1.0.1  (202609091529)  VALID  internal=IN_BETA_TESTING  external=READY_FOR_BETA_SUBMISSION
    1.0    (202609090936)  VALID  internal=IN_BETA_TESTING  external=READY_FOR_BETA_SUBMISSION
    1.0    (202609090423)  VALID  internal=IN_BETA_TESTING  external=READY_FOR_BETA_SUBMISSION
    1.0    (202609090224)  VALID  internal=IN_BETA_TESTING  external=WAITING_FOR_BETA_REVIEW
    1.0    (202609090049)  VALID  internal=IN_BETA_TESTING  external=READY_FOR_BETA_SUBMISSION
    ```

    Five builds up, all processed VALID, internal TestFlight live on every one. **Nothing has
    been submitted for App Store review**, which is what pass-off item 1 is the tail of and what
    gates item 9 (iPad) behind it. DEPLOYMENT.md's status table stops at `202609090224` and does
    not know about `1.0.1`; the archive is still the map, but `status.sh` is the truth.

    The platform decision that goes with this is in DEPLOYMENT.md section 3: **iOS only** on this
    record, iPad a later build on the same one, the Mac not an App Store app at all. Section 9
    has the iPad recipe and why `TARGETED_DEVICE_FAMILY` was deliberately put back to `"1"`.

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

23. **Apps the picker will not show, and the no-QR/no-pause decisions.** Done 2026-09-09, from
    the pass-off's items 8a and 10 in one session, no Xcode.

    A new page, `site/src/pages/help/beyond-the-picker.astro`, linked from
    `site/src/pages/help/index.astro`. It was also linked out of `Furlough/Views/HelpView.swift`
    through a `Furlough.helpURL(_:)` row; commit `70781e0` ("bring every help page back into the
    app") then took every outbound help link out, so `helpURL` no longer exists and no Swift file
    holds a `/help/` path. The in-app counterpart is `PickerHelp` in `Furlough/Views/HelpTopics.swift`,
    reached from HelpView's rules card, and the two copies have to be edited together — the
    literal-mismatch trap the pass-off warned about is gone, but the duplication replaced it. It
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
    not a Safari web app in the Dock (its own bundle id), not a non-browser app's own network code.
    **Updated 2026-09-09** once step 26's web filter landed, which closes all three rather than only
    the last: both copies now name the filter, say it is opt-in (Applications folder, two macOS
    approvals, `Settings > Web`), and say those flows get the floating card rather than the shield
    page. Both carry the same "not yet run on a Mac" note step 26 does; when Zach runs it, that
    note comes off here and on the site.

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
24. **The Anchor's clock.** Done 2026-09-09 (pass-off item 2), in `Shared/Core/AnchorSchedule.swift`
    beside `Models.swift`, with `Tests/Core/AnchorScheduleTests.swift` (32 tests in 5 suites).

    **A timed drop.** `AnchorProfile.until: Date?`. "Anchor until 6 PM" drops now and lifts by
    itself then, or sooner with the tag. The rule every reader follows: `AnchorProfile
    .isHolding(at:)` is false once `until` has passed, whatever `isAnchored` still says, and
    `blocks(_:at:)`, `Config.isAnchored(_:at:)`, `Policy.status`, `decide`, `summary` and the
    shield extension all take the moment. `Policy.nextTransition` returns `until` when it comes
    before the next window edge, so the widget timeline shows the lift. The flag is cleared by
    `Policy.liftExpiredAnchor`, folded wherever due pending changes are folded —
    `ShieldReconciler.reconcile` and `AppModel.enforce` — and the monitor's wake at `until`
    (`ActivityNaming.anchorUntil`, a non-repeating quarter-hour activity ending at `until`,
    registered on the device's clock) is what makes sure some process folds it on time. A
    timed drop needs at least `Furlough.minimumWindowMinutes` (`Policy.DropRefusal.tooSoon`),
    because DeviceActivity will not wake for less. The Anchor screen's **Lifts by itself**
    toggle and time make the next drop timed (`AnchorToggleButton(until:)`); the home card,
    the state line, the hero and the widget say "lifts 6:00 PM". **Zach has not said whether
    the lift should notify; it does** ("Anchor lifted", the shape of "Window opened"), as the
    pass-off recommended, and so does a scheduled drop ("Anchor dropped"). Both are one
    `Notifier.post` in `MonitorExtension` if he wants either gone.

    **A scheduled drop.** `AnchorProfile.schedules: [AnchorSchedule]` — a minute of the day, a
    `Weekdays` set, and an optional `liftMinuteOfDay` (nil is the tag alone; a lift earlier
    in the day than the drop is the next morning, `liftDate(afterDropAt:)`). One repeating
    activity per distinct drop minute (`anchor:<minute>`) and one per distinct lift minute
    (`anchor-lift:<minute>`), whatever days they are on, the way windows share activities;
    the monitor checks the weekday when it fires. **The quarter-hour rule**: DeviceActivity
    wants 15 minutes, so the minute is one *end* of a 15-minute activity and
    `ActivityNaming.anchorInterval(minute:)` says which — the end, except in the first quarter
    hour after midnight, where it is the start — and `MonitorExtension.anchorEvent` acts on
    that callback only; the other end is a plain reconcile. `Policy.scheduledDrop` is the
    monitor's decision and is idempotent: nothing on a day the schedule is off, nothing
    without a tag or a list, and with the anchor already down it only ever lengthens the
    hold (`Policy.tighterUntil`: nil beats any time, later beats earlier). The lift is counted
    from the minute the schedule names, not the callback, so a late wake cannot push it. The
    lift activities call `Policy.liftExpiredAnchor` and do nothing when nothing is due.
    `ActivityLimit.activities(in:)` now counts window spans plus the anchor's times (drop
    minutes, lift minutes, and one for a timed `until`), saved schedules and queued ones
    together; `Monitoring.register` refuses on that total, registers the anchor's activities
    after the windows and each on its own, logging a refusal rather than throwing it, so one
    refused wake cannot cost the windows. Every `ActivityLimit.reason` sees the total, and
    `reason(schedules:in:)` is the schedule editor's.
    **Zach has not said whether removing a schedule should queue; it does**, as the pass-off
    recommended: `Policy.classify(newSchedules:against:)` calls it tightening when every old
    drop still happens on every old day with a lift no earlier (nil the latest of all), and
    loosening otherwise — so adding a drop, a day, or a later lift lands now, and removing a
    drop, a day, a lift's lateness, or *moving* a drop earlier queues as
    `PendingKind.setAnchorSchedules` behind `Config.anchorDelayHours` (the longest delay among
    the targets the anchor holds, since a dropped schedule loosens the hold over all of them;
    the base when it holds none). Moving 10 PM to 9 PM queues on purpose: the 10 PM drop is
    gone and a tag scanned at half past nine would leave it uncovered; add 9 PM and let 10 PM's
    removal wait. `AppModel.setAnchorSchedules` does the queueing, refuses while anchored, and
    treats saving the schedule the anchor already has as cancelling a queued change, the way
    a saved tier chosen back cancels a queued tier. `Policy.apply`, `PendingText.delta`,
    `PendingText.subject` ("Anchor schedule", the card's heading), `PendingNotifications
    .describe` and `TimeFormat.anchorSchedules` carry the new kind; both pending cards use
    `subject`. If Zach says no, the change is to make `setAnchorSchedules` always land.
    `AnchorScheduleSheet` (in `AnchorView.swift`) edits the set as one draft with one Save and
    the `EffectBanner` above it, `ScheduleDraftRow` reusing `TimeChip`, `TimePickerSheet` and
    `DayStrip` from the rule editor; the Anchor screen lists the schedule and the next drop.

    **Writers, now.** `Config.anchor` is written by the app's `AppModel` methods (the list in
    "How enforcement works"), by `AnchorDrop.drop` from whichever process runs the Drop Anchor
    intent, by the monitor's `scheduledDrop` and `liftIfDue`, by `Policy.apply` landing a
    queued `.setAnchorSchedules`, and by the expiry fold in `reconcile` and `enforce`. Nothing
    else, and nothing outside the app writes a release except an `until` the user chose.

    **Not seen on a phone.** Installed 2026-09-09; the test list is in the last message, and
    it includes a drop two minutes out with the app closed, the widget button and the control.

    (b) **"This app and This app is worth having around."** From Zach's Anchor screenshot the same
    day: two faults in one sentence. `UtilityText.fallback` hardcoded singular verbs for all three
    tiers while `anchoring` is the one function here that can be about several things, so it now
    takes the count and picks the verb — "are how this phone does its job", "go the moment you
    anchor". The one-app `detail` is dropped once there is more than one name: `anchorWarning` hands
    over the first it finds, and "Messages is where your codes land" cannot stand as the sentence
    for Messages *and* Phone. `anchorWarning` also collapses duplicate names, so the exact sentence
    Zach saw cannot come back even where the tables cannot name anything. Tests in `UtilityTests`
    cover one, two and three names at every tier that speaks.

25. **The record.** Done 2026-09-09. Foqos shows streaks and session history; Furlough shows the
    record of the contract instead — the numbers only a commitment device can produce.
    `Shared/Core/Record.swift` is the whole of it, pure and with a `calendar:` on everything that
    touches a day boundary, and `RuntimeState.days: [String: DayRecord]` (by `Policy.dayKey`, 60
    days, pruned on every write) is where it lives. The activity log is free text and capped, so
    nothing parses it.

    **What is written, and where.** `DayRecord` holds, per target id, whether the budget was
    spent, whether the warning fired, and minutes open / shut / anchored; and per day, loosenings
    queued, cancelled and landed, plus the longest Anchor stretch that ended that day. Every
    write sits on an event that already happened: `Record.markSpent`/`markWarned` beside the two
    lines that stamp `runtime.exhausted`/`runtime.warned` (the monitor's threshold callbacks on
    the phone, `Enforcer.apply` on the Mac); `Record.queue` *replaces* `state.pending.append`
    everywhere, so a new queueing site cannot forget to count itself; `noteCancelled` in both
    models' `cancelPending`; `noteLanded` inside `Policy.applyDuePending`, the one place a
    loosening lands; `noteAnchorReleased` in `AppModel.unanchorWithTag` while `anchoredAt` still
    says when the stretch began, so one that ran over midnight stays one number.

    **The minutes.** `Record.accumulate` runs inside `ShieldReconciler.reconcile` on the phone and
    `Enforcer.apply` on the Mac — the two places everything already funnels through. It counts
    whole minutes from `runtime.recordedThrough` and carries the remainder, so once a second and
    once an hour come to the same total, and it cuts the span at every `Policy.nextTransition`
    (which is also every midnight), so a phone catching up over hours is counted edge by edge
    rather than sampled once. A gap longer than a day counts at most a day: a phone that was off
    for a week was not holding anything shut. What it cannot do is see **use**: without the iOS
    26.4 data-access entitlement the phone knows only whether a budget ran out, so `spent` is the
    honest limit and the copy does not pretend otherwise. (Written before the entitlement was
    granted, which it since has been — step 19 verified
    `…family-controls.app-and-website-usage` in the signed binary. What is *not* settled is
    whether any given phone answers `UsageReader.hasDataAccess` with true: the prompt is
    all-or-nothing and refusable, and Apple honours it only for EU customers. So `spent` stays
    the honest limit, and `UsageReader` is the path to real minutes where the answer is yes —
    see steps 9 and 22.)

    **The screens.** A card at the top of Settings on the phone and a section at the foot of the
    Mac sidebar, both drawing the same five rows from the same `Record` copy functions so neither
    platform can word it differently: no budget spent, held shut this week, anchored (only when
    there was), loosenings cancelled against landed, longest anchor. A number is Geist Mono, an
    absence is muted body text, and the card draws nothing at all until there is something to
    say. Nothing is celebratory: a streak that broke reads "Back to day one." and the day a
    budget goes reads "Not today." Home was left alone deliberately — it is lane A's file this
    week, and the record is not a thing to put in front of somebody every time they open the app.

    **Two things worth knowing.** `RuntimeState` and the two new records now have tolerant
    `init(from:)`s: a synthesised decoder throws on a missing key rather than falling back to the
    property's default, and a phone that has been running since before the record existed has no
    `days` key. And "held shut" adds up across every app, so it is app-hours rather than hours;
    the footnote under the card says which numbers are this week and which are the whole record.
    `SharedStore.reset` already clears it with the rest of the runtime, so Testing > Reset
    everything forgets it.
26. **The Mac web filter (item 8b, lane E).** Built 2026-09-09, on `main` since `dfe1049`:
    compiled in Debug and Release, 21 new tests, the built bundle read back — and **not yet run
    on a Mac**, because installing a system extension takes two approvals in front of the
    screen. The test list is at the end of this step.

    **Why it was built without the distribution answer the pass-off asked for.** The gate was
    a premise, and the premise was wrong. Apple's DTS (Quinn, developer forums 816877 and
    67613): "There is no approval process for this… the one for content filters [has been]
    available to all (paid) developers" since November 2016. A development-signed system
    extension loads from an app in `/Applications` with SIP on (forums 725805, 765931), which
    is exactly the `ditto` install this Mac already uses. And the archive's DEPLOYMENT.md
    section 3 had already settled the Mac's road as Developer ID plus notarization, with only
    *when* open. So nothing about distribution blocks the build; what it blocks is strangers
    installing it, which was true before this step. (That paragraph was written while this
    lived on `lane-e-mac-filter` and said it touched nothing on `main`; Zach merged it in
    `dfe1049` the same day, so the branch is gone and this is `main`.)

    **What it is.** A `NEFilterDataProvider` system extension, `FurloughMacFilter` (bundle
    `com.zachshort.furlough.mac.filter`, `type: system-extension` in `project.yml`, embedded by
    XcodeGen's "Embed System Extensions" phase at `Contents/Library/SystemExtensions/`). It sits
    beside the tab reader, not instead of it: `Browsers` still redirects Safari and the Chromium
    family to the shield page, and the filter drops the connection everywhere the reader cannot
    see — Firefox, a site saved to the Dock as an app, an app loading a site on its own. Those
    get the floating card, which the extension asks for over XPC.

    - `Shared/Core/FlowRules.swift`, pure and tested (`Tests/Core/FlowRulesTests.swift`):
      `FilterRules` (the hosts, a horizon, a version; to and from the `vendorConfiguration`
      dictionary), `FlowRules.newFlow` (the verdict as a connection opens), `FlowRules.inspect`
      (the verdict after looking at its first bytes), and the two parsers: the TLS ClientHello's
      server name, reassembled across records, and HTTP/1's Host header. The TLS fixtures are
      real hellos written by OpenSSL 3.6 through Python's `MemoryBIO` with no network, with
      X25519MLKEM768 key shares, so they are as large as a hello gets.
    - `FurloughMacFilter/FilterDataProvider.swift`: the shell. Reads the rules out of
      `filterConfiguration.vendorConfiguration` at start and on every KVO change, keeps a
      per-flow buffer while peeking, reports drops. `FilterReporter` is the XPC listener on
      `X9V4L6HR2R.com.zachshort.furlough.filter` (the name must start with one of the
      extension's App Groups, which is the only reason it carries one). `main.swift` calls
      `NEProvider.startSystemExtensionMode()`. `FilterXPC.swift` holds the two `@objc`
      protocols and the names, and is compiled into the app too.
    - `FurloughMac/Model/WebFilter.swift`: the app's side. `ExtensionRequest` wraps one
      `OSSystemExtensionRequest` as an async call; `WebFilter` installs, removes, refreshes
      (`propertiesRequest` plus `NEFilterManager.loadFromPreferences`), pushes rules, and
      holds the `FilterLink` XPC client with a five-second reconnect. `Status` is what
      Settings > Web shows: not in Applications, not installed, installing, waiting for
      approval, off in System Settings, installed but not filtering, on, failed.
    - `Enforcer` pushes `decision.blockedHosts` after every tick through `WebFilter.sync`,
      which saves only when the list or the horizon changed; `noteFiltered` shows the card for
      a drop from anything that is not a browser the reader covers, and logs every drop.
    - Settings > Browsers became Settings > Web: the filter card with its one action per
      state, then the browser rows as before. Onboarding gained a second pane offering the
      filter, with Not now. Help's "How blocking works here" and About say what it reads.

    **The four decisions, made here and worth Zach's eye.**
    - **Every block still derives from `Policy.decide`, including its expiry.** The rules carry
      `until` = `Policy.nextTransition` (on the device's clock, shifted by the drift), and the
      extension blocks nothing past it. So a force-quit Furlough leaves at most one window's
      worth of blocking behind, and the watchdog has it back in ten seconds anyway. Foqos
      instead enforces its last list forever; this is the honest version of README's "Force
      Quit lifts every block", and README now says exactly what it lifts.
    - **Nameless QUIC is refused while anything is blocked.** macOS names a flow only when the
      app connected by name (`remoteHostname`; Safari and Firefox do, the Chromium browsers
      resolve first and connect to the address, so theirs are nameless — DTS, forums 767285).
      A nameless TCP flow on 443 or 80 is peeked for its TLS server name or Host header. A
      nameless UDP 443 flow is QUIC, whose first bytes cannot be read the same way, so it is
      dropped and the browser falls back to TCP on its own. Only while `blockedHosts` is
      non-empty, so a Mac with nothing blocked right now filters nothing at all. Foqos drops
      UDP 443 outright, always.
    - **Removing the filter is not held behind the loosening delay**, for the reason the
      watchdog toggle is not: System Settings can switch the extension off regardless, and a
      button that pretended otherwise would lie. The tab reader keeps enforcing either way.
    - **No budget counting from flows.** The front-app counter already counts a site in the
      front tab, and a flow says nothing about what is in front, so counting flows would
      double-count exactly the sites the reader sees. Left alone, as the pass-off allowed.

    **What the build changed outside the repo, by automatic signing.** The portal now has App
    IDs `com.zachshort.furlough.mac` (Network Extensions, System Extension) and
    `com.zachshort.furlough.mac.filter` (Network Extensions), and a Mac Team Provisioning
    Profile for each, provisioned to this Mac (`00008132-001148422103001C`, which was already
    registered). The app carries `embedded.provisionprofile` for the first time; the profile's
    entitlement list includes `content-filter-provider`, read back with `security cms -D`. The
    entitlement value is the plain `content-filter-provider` on both bundles — right for
    development and the App Store; only a Developer ID build wants
    `content-filter-provider-systemextension` (DTS, forums 737894). `ENABLE_DEBUG_DYLIB` is
    off on the extension because a system extension must be one Mach-O; the app keeps its
    Debug split. `-allowProvisioningDeviceRegistration` was added to the build line in case,
    and turned out unnecessary.

    **Distribution, when Zach wants strangers to have it** (none of this is needed on this Mac):
    a Developer ID Application certificate (Account Holder only: Xcode > Settings > Accounts >
    Manage Certificates); two Developer ID profiles from the portal, app and extension, with
    the Network Extension capability; a second pair of entitlements files carrying
    `content-filter-provider-systemextension`; re-sign inside-out by hand — extension, then
    app — with the hardened runtime, because Xcode 26's Direct Distribution is broken for
    system extensions (DTS, r.108838909, fixed in Xcode 27 beta); notarize with `notarytool`
    on key `L6A2R4SBXQ`; staple; ship a DMG whose background says to drag it to Applications,
    which is where Foqos's own releases learned that lesson. Foqos, for the record, is a
    notarized DMG on GitHub with Sparkle, and its release notes are where "macOS sometimes does
    not enable it" comes from: their fix was to detect the drift, which `WebFilter.start` does
    here and says in Settings > Web and the log.

    **Known limits, none of them regressions.** A name hidden by Encrypted Client Hello (Firefox
    with DNS over HTTPS, on sites that support it) or a connection to a bare address gets
    through the filter — the reader still catches it in the browsers it reads. The XPC listener
    checks nothing about who connects, because all a client can do is be told which hosts were
    dropped. `OSSystemExtensionProperties` is not Sendable, so `ExtensionRequest` copies what it
    needs into a struct.

    **Supersedes**: the Firefox sentence in "The Mac" above, and step 7's note that Safari web
    apps in the Dock bypass host rules. Lane D's help page ("what the Mac cannot reach") was
    written for the day before this landed and needs its Mac paragraph redone once Zach has
    seen the filter work.

    **Not yet seen by anyone: any of it running.** Zach's list, in order:
    1. Install the branch's Debug build into `/Applications` (the running copy is force-quit
       for it, as in step 3) and open Furlough. Settings > Web should read **Not installed**
       and nothing should prompt.
    2. Settings > Web > **Install the web filter**. macOS: "System Extension Blocked" or the
       newer approval sheet; then System Settings > General > Login Items & Extensions >
       Network Extensions > allow Furlough; then "Furlough would like to filter network
       content" > Allow. Settings > Web should go Waiting for approval → **On**, the log should
       say "web filter extension is active", "web filter on", "web filter link up", and
       `systemextensionsctl list` should show it enabled.
    3. Firefox (not on this Mac; install it): add a rule for a site blocked now, open it in
       Firefox. The page should fail to load, the floating card should say why, and the log
       should carry "blocked <host> in Firefox (web filter)".
    4. A Dock web app: Safari > File > Add to Dock on a blocked site, open it. Same three signs.
    5. Chrome on a blocked site: still the shield page, no card (the reader's), and the log
       shows both the redirect and the drop.
    6. The window opening: within a second or two Firefox loads the site (the log's "web
       filter: n host(s) blocked until …" line changes).
    7. System Settings > turn the extension off: Settings > Web reads **Off in System
       Settings**, the log says so on the next launch, Firefox opens, Chrome is still redirected.
    8. Force Quit with a site blocked: Firefox stays blocked until the watchdog brings
       Furlough back (ten seconds) — and if the watchdog is off too, until the next window edge.
    9. Settings > Web > **Remove the web filter**: macOS may ask once more; status returns to
       Not installed and Firefox is open.
    Anything QUIC-shaped worth a look while there: with a site blocked, YouTube should still
    play in Safari and in Chrome (Chrome over TCP after a refused QUIC attempt, invisibly).
27. **Forgiveness for a mistake, never for a craving.** Done 2026-09-09 in the
    `lane-f-forgiveness` session, merged to `main` in `dfe1049`. See the "Settled" bullet above
    for what it is and why a pass count was refused. What is where:

    - `Shared/Core/Forgiveness.swift` — `startTrial` (once per install, guarded on
      `trialStartedAt`), `expire` (ends the week, forgets unreachable undos), `trialDaysLeft`
      (rounds up, so the last afternoon reads "1 day left"), `record`/`undo`/`revert`.
    - `Shared/Core/Consequence.swift` — the two sentences the editor says before a rule is
      saved: what today looks like under it, and what changing your mind costs. Nil for a
      loosening (the effect banner already answers those), for an invalid rule, and for no
      change. The cheapest forgiveness is the kind nobody needs, which is why this exists.
    - `Config.isInTrial` is a **stored fact**, not a comparison against the clock, for the
      same reason a due pending change is not folded in until something folds it:
      `delayHours` is asked from a dozen places with no business knowing the time.
      `Policy.applyDuePending` is the one place that moves it forward, and every enforce,
      every widget read and every `effectiveConfig` goes through it. That is why **no delay
      call site had to thread a date** — about 25 of them, across files three other lanes own.
      The bounded cost: a config read without a prior pass can see a week that ended minutes
      ago, and the error direction is "slightly more forgiving", which is the right way to be
      wrong.
    - `Config.fullDelayHours` is the uncapped number, kept because the editor names *both*
      while the week runs. The cliff at the end must not be a surprise the first time a delay
      is real.
    - `AppModel.startTrialIfNeeded` runs at `requestAuthorization`, which is the only moment
      it can: before access there is nothing to be forgiven for, and every path back there
      goes through Settings. Debug's `resetEverything` used to grant one outright, or the
      feature could not be tested on a phone whose access is already granted; since 2026-09-09
      it hands the access back instead, so the grant on the way through onboarding starts the
      week and this stays the only place a week begins.
    - `AppModel.assign` records the undo only where a rule lands *now*. A loosening arriving
      after its delay needs none: undoing a loosening is a tightening, and those are instant.
    - UI: `UndoCard` (high in `RuleEditorView`, above the nickname — someone who opens the
      editor because they are locked out should not have to scroll to the way back) and
      `ConsequenceCard` (under the effect banner, where the decision is made). Onboarding
      states the week; `SettingsView`'s delay card counts it down, because while it runs every
      other countdown in the app already says the capped number and without that line the
      delay above reads as if it is not being applied.
    - Tests: `Tests/Core/ForgivenessTests.swift` and `ConsequenceTests.swift`, 25 of them. The
      one that matters most is `undoIsOneStepBackAndNeverReachesUnrestricted`: a second edit
      inside the window *replaces* the note rather than stacking on it, because a history to
      walk would eventually reach "unrestricted", which must never be reachable.

    **The Mac has its own App Group and so its own `Config`, and nothing grants it a week.**
    `isInTrial` stays false there and Mac delays are exactly as they were. If the Mac should
    have one, it is a call to `Forgiveness.startTrial` at its onboarding finish — deliberately
    not made, because nobody has asked for it. `MacModel.resetEverything` does not make it
    either, and that is the one place it would be tempting: the phone's reset starts a week
    because a fresh phone install gets one, and copying that line across would hand the Mac a
    week only a reset can produce.

    **The site pass, added 2026-09-09** (this step shipped without one, and for a day the public
    pages said the absolutes — "there is no unblock button", "no break, no temporary access" —
    beside an app that had just grown both of these). `site/src/pages/help/windows-and-budgets.astro`
    carries them under "Changing one later", and `support.astro`'s no-unblock note now names them
    and links there. Two things to keep right if the mechanism moves: the undo is offered **only on
    a tightening** (`AppModel.assign` records it just where a rule lands now — a loosening is
    already waiting and is cancelled instead, not undone), and the page's own rule that the delay's
    length stays in the app still holds — the week's cap and the undo window are quotable there only
    because they are the same hour and the same fifteen minutes for everyone. `the-anchor.astro`'s
    "There is no pause" was deliberately left alone: the Anchor takes neither the delay nor the undo,
    so the line is still true of it.

    **Not seen on the phone yet.** iOS and Mac both build warning-free and all 400 Core tests
    pass. What to check is in the last message.

    **Item 10 of `PASSOFF.md` changes.** Its no-pause paragraph now has to name these two and
    say why neither is an unblock, rather than claiming Furlough has nothing of the kind.

28. **A starting rule, not just a tier (item 12, lane G).** Done 2026-09-09, in
    `Shared/Core/RuleSuggestion.swift`. `AppUtility` already guessed what a target *is* and the
    editor offered that tier while nobody had answered; nothing helped with the rule itself, and
    "Use windows from another app" needs an app that is already set up — so the first hazard app
    anyone adds had nothing to copy from. This is the same pattern one property over: a starting
    budget, and a window where the tier calls for one.

    **The numbers are Zach's, agreed 2026-09-09**, and that is why they live in their own file:
    `AppUtility` is a table of checkable facts (this identifier is or is not Instagram's) and
    this is a table of judgements, so one can be retuned without re-verifying the other.
    Essential and useful suggest **nothing** — blocking an essential is the risk the caution
    banner exists for, and the only figure generous enough for a work tool is looser than the 30
    minutes the slider already sits at. Idle suggests **60 min, no windows**. Hazard suggests
    **30 min plus 9:00 AM–10:00 PM every day**: the first and the last hours of the day are not
    the feed, 10 PM is already what `UsageAnalysis.lateHours` calls late, and every hazard target
    that takes it shares the one `window:540-1320` activity rather than spending one each.
    Two named exceptions, each carrying the tier it was written against so retiering an app in
    `AppUtility` fails a test here instead of silently switching the exception off:
    **long-form video** (Netflix, Hulu, Disney+, Max, Prime Video, Peacock, Paramount+, Apple TV,
    Crunchyroll) gets **120 min**, because an hour lands mid-film and Furlough's answer to
    "I am halfway through" is to wait until tomorrow; **Snapchat** keeps the hazard budget and
    **loses the window**, because closing it 10 PM–9 AM shuts a door people are knocked on.
    Gambling and trading were considered and deliberately left on the generic hazard rule.

    - `RuleSuggestion.suggestion(for:chosen:)` is nil whenever the target already has a rule, so
      a suggestion can never be a second way to edit one somebody is living under, and nil for a
      typed site whose suggestion is only a budget — nothing counts those minutes, so it offers
      the hours or nothing. `chosen` is the tier showing in the editor and only once somebody
      answered: an untouched picker reads `.useful` because that is what `Utility.unset` is, so
      `tierTouched` in both editors is what tells an answer from a default.
    - Both editors show it under the windows card as a `SuggestionOffer` — the one row every
      guess now uses, `Shared/UI/SuggestionOffer.swift`, including the tier's own inside
      `UtilityPicker`. Applying fills the fields and saves nothing; the window *joins* the rows
      rather than replacing them, so a tap can never throw away hours somebody typed.
      `Policy.decide` is untouched and nothing here reaches the shield.
    - Three cold-start gaps closed with it, all offers and none of them applied:
      `addWindow()`'s first row is the suggested window instead of a fixed 8–10 PM;
      `AppUtility.offeredNickname(for:)` offers the name the tables know when a row is going by
      an address or a bundle identifier (nil once a nickname exists, and nil when it would only
      repeat the name already shown); and both copy pickers list Furlough's own starting rule as
      their first row, which is what makes them worth opening on the *first* app rather than the
      tenth.
    - `AppUtility`'s three lookups are now generic matchers (`match(name:in:)`,
      `match(bundleID:in:prefixes:)`, `match(host:in:)`) that `byName`/`byBundleID`/`byHost` and
      `RuleSuggestion` both go through, so neither file has its own idea of what a match is.
    - Tests: `Tests/Core/RuleSuggestionTests.swift`, 15 in 6 suites. 569 Core tests pass, iOS
      and Mac both build warning-free. Not seen on the phone yet.

29. **The record's one uncounted queue.** Fixed 2026-09-09, found by checking step 25 against the
    code rather than reading it. Step 25 says `Record.queue` replaces `state.pending.append`
    everywhere "so a new queueing site cannot forget to count itself"; step 24's
    `AppModel.setAnchorSchedules` then appended by hand, which is exactly the failure that
    sentence was written to prevent. Two effects, and only the second was visible: a queued
    anchor-schedule loosening was never counted as queued (nothing reads `DayRecord.queued`
    today, so nothing said a wrong number — it would have started the moment anything did), and
    the same function's *cancel* path emptied the queue without calling `noteCancelled` while
    `Policy.applyDuePending` still counted it if it landed. So on the anchor schedule the
    record's one line about the delay doing its job counted landings and not backing down.

    Both routed properly now, and the cancel counts by what actually left the queue
    (`before - current.pending.count`), the way `cancelPending` does. **The line held to:**
    emptying the queue and putting nothing in its place is a cancellation; dropping a queued
    change to *replace* it is not — that is changing your mind about the figure, not backing out
    of the wait. Which is why the loosening branch beside it, and `setDelay`, and `propose`, all
    drop a queued change without counting one.

    **Still open, and Zach's call, not a defect.** `setUtility` choosing the saved tier back is a
    replacement by that rule and an unqueueing by the comment above it ("is cancelled"), and it
    is uncounted. Whether it should count is a judgement about what the number means. `Record`'s
    `queue` doc comment now names the only legitimate bare append — a state that is thrown away,
    which is `ActivityLimit`'s two projections — so the next one is easier to spot.

30. **The companion table, 33 pairs to 83 (item 11).** Done 2026-09-09. `Companions.pairs` was
    too thin to fire: most of what Zach added on the phone offered no website because it was not
    in the table. **Every one of the 50 added was confirmed by an App Store lookup actually run**,
    and `design/companions-sources.md` is the audit trail — one row per pair with the bundle
    identifier as Apple returns it, the seller, the host, the `sellerUrl` that links the two, and
    the listing. It also records what was rejected and why, so the next pass does not re-spend
    those lookups. The method is the one in the pass-off, and it was sanity-checked first against
    a pair already in the table (Slack → `com.tinyspeck.slackmacgap`).

    New groups: news and sport, dating, betting, AI chat, and music. Three existing entries moved
    into the groups they belong to rather than changing — ChatGPT to AI chat, Spotify to music,
    DraftKings and FanDuel to betting.

    **What the lookups taught, beyond the names.** A bundle identifier is often a company's old
    name, and looks wrong until you check: StockX ships as `com.Campless.Campless`, Depop as
    `com.garageitaly.garage`, SHEIN as `zzkko.com.ZZKKO`, BeReal as `AlexisBarreyat.BeReal`. All
    are lowercased in the table, because `Pair.matches` normalizes what it is *handed* but compares
    against the table as written — a capital letter is an entry that can never match. Two rejections
    are worth remembering: `com.microsoft.officemobile` is returned for **Microsoft Copilot**, one
    identifier serving two products, and `com.espn.bet` now returns **theScore Bet** after a
    rebrand, so `espnbet.com` is confirmed by nothing and the pair went in under the host its own
    seller URL names.

    Tests: `tableIsConsistent` already walked the whole table for four of the five invariants, so
    the additions were self-checking on arrival. The one it could not catch is now
    `nothingIsClaimedTwice` — two pairs claiming one host, where `pair(forHost:)` answers with the
    first and the second is unreachable from the web side. It caught a real duplicate immediately:
    Spotify had been left in its old group *and* added to the new music one. `namesAreRealAndPairsAreDistinct`
    covers the rest. 571 Core tests pass.

31. **The Mac's reset goes all the way back.** Done 2026-09-09, because Zach asked: Settings >
    Testing > Reset everything used to stop at the setup, leaving a Mac that was still
    onboarded, still a login item and still watched, which is a state no fresh install has. It
    now returns to the first run. The full note — every key it clears, the two permissions it
    deliberately keeps and why, and what it does *not* do — is the Reset everything bullet under
    "The Mac" below, where the rest of the Mac's behaviour lives; it is not repeated here.
    Touched `MacModel.resetEverything`, `Watchdog.forget`, `AnchorSync.forgetPhone` and the
    Settings sheet's copy. No `Shared/Core` behaviour changed, so no new tests; 571 still pass,
    and iOS, Mac Debug, Mac Release and Mac Release + `TESTING_TOOLS` all build warning-free.
    **Nobody has run it on the Mac yet** — doing so wipes the real App Group state, so it is
    Zach's to trigger, and the `/Applications` copy predates it.

32. **The phone's reset goes back to onboarding too.** Done 2026-09-09, because Zach asked: a
    reset during a test pass should land on the first screen every time, so the run he is
    reviewing can be walked from the start. It stopped one screen short — the state was gone but
    Screen Time access was not, so the app came up on Home with nothing in it, and the grant,
    the first week it starts and the usage step were all behind him for good.

    `AppModel.resetEverything` now hands access back with
    `AuthorizationCenter.revokeAuthorization`, which the app is allowed to do and which the
    onboarding button undoes in one tap — no trip through Settings, which is why keeping access
    was the right call before and is not any more. With it goes the eager
    `Forgiveness.startTrial` the reset used to make: `SharedStore.reset` clears the marker that
    refuses a second week, so `startTrialIfNeeded` at the grant starts one, exactly as on a
    fresh install, and `requestAuthorization` stays the only place a week begins.

    The revoke is asynchronous and iOS can refuse it, so it is not what the root reads.
    `AppModel.restartsOnboarding` is — a flag in the app's own defaults beside `wasAuthorized`
    and `sawUsageStep`, set by the reset, read at launch so a relaunch mid-pass starts in the
    same place, and cleared only by a successful `requestAuthorization`. Not by `note`, which
    every activation and every tick of the authorization stream runs through: clearing it there
    would take the first screen straight back off a phone whose revoke was refused, which is the
    one case the flag is for. `RootView` asks `model.showsOnboarding` (access, or the flag) and
    then `showsUsageStep`, in that order, so onboarding wins while both are true. The reset also
    puts `wasAuthorized` and `sawUsageStep` back, so the launch screen is not held for a phone
    about to be asked for access, and the usage step comes round again after the grant.

    What it keeps is the notification permission, which iOS only asks about once and no app can
    hand back, and the activity log, which is the record of what just happened — the log now
    says which way the revoke went, because from the onboarding screen the two look identical.

    Touched `AppModel` (the reset, `showsOnboarding`, `restartsOnboarding`, `revokeAuthorization`,
    `finishOnboardingRestart`), `RootView`'s branch order, the Settings sheet's dialog and
    footnote, and the Mac comments that described the phone's old line. No `Shared/Core`
    behaviour changed, so no new tests; iOS Debug, Release and Release + `TESTING_TOOLS` all
    build warning-free. Not yet run on the phone.

33. **The + gets a destination, and the halves get marks (the two-halves pass, item 4).**
    Done 2026-09-10. Context, because HANDOFF has no note on the three items before it: on
    2026-09-09 Zach asked for a pass over both apps to simplify what a person sees, and said
    mid-pass that Rules and the Anchor should be two pages a person swipes between. The audit
    and the seven-part proposal are the "Which half first" artifact
    (`claude.ai/code/artifact/7019259f-85bd-40fa-8bc8-da78fe3b58f4`), which a session picking
    this up should read rather than redo. Items 1–3 landed the same day: `Shared/Core/Half.swift`
    and `HomeView` as a paged `TabView` under a `HalfSegment`; `Furlough/Views/Guides.swift`, a
    three-step checklist per half; and the Anchor page rebuilt as a state card, a Held grid and
    four rows into `Furlough/Views/AnchorScreens.swift`, with `RuleEditorView`'s first-rule card.
    This is item 4, the last thing that made the two pages two apps: the + acted on one half
    only, and neither half said anything about the other.

    **One add flow with a destination.** `AddRequest` gains `destination: Half`, and
    `AddTargetsFlow` grew the anchor's branch: the already-blocked offer where the list is empty
    and something has a rule, Apple's picker otherwise, landing in `setAnchorSelection` instead
    of `applyPicker`. The picker's header and footer follow the destination, and under the
    anchor's everything-except scope they say "stays open" rather than "holds". `AnchorPage` no
    longer owns a picker at all: its Choose apps row and its guide's second step call up to
    Home, which is why the row and the + button cannot drift apart. The anchor destination asks
    no Application-or-Website question — both are picked in the one picker, and a typed host is
    a target, so it reaches the anchor by being taken in.

    **What + adds over the Anchor page** is `AppModel.anchorPageAdds`, the anchor by default,
    changed in Settings under "The + button" — Zach's call: the + acts on the page it is over,
    and the person that fails is the one who set the anchor up months ago and has read + as
    "give an app hours" ever since. In the app's own defaults beside `startHalf` and the guide
    flags, for the same reason: it records what was asked for, not what is blocked, so it must
    not travel in an exported setup or wait out a delay. Over Rules the + is not asked.

    **The cross-links.** The rule editor gains one row, "Also hold it in the Anchor", calling
    the same `addToAnchor` the already-blocked sheet calls and the new `removeFromAnchor` beside
    it; it acts at once rather than on Save, because the anchor's list is not a rule and nothing
    about it is delayed. It reads on only when *every* door is on the list, so a row whose site
    was linked on after it was anchored reads off until the second door is closed. Under
    everything-except it is a statement, not a control ("Held while anchored" / "Stays open
    while anchored"), because there the list is what is spared and a toggle would be editing it
    by its opposite. The anchor grid gains a long press: "Give it hours too" where nothing has a
    rule yet — `AppModel.targetForRule` makes the target and Home pushes the editor on a new
    `path` — and "Open its rule" where one does. And two marks rather than two lists: a rules
    row wears a small `AnchorShape` when a drop would take it (`AnchorProfile.willHold`, read
    through `holds`, so it is right under both scopes), and an anchor tile wears an hourglass
    badge when the thing it holds also has a rule. Neither half grows a copy of the other.

    `Shared/Core/AnchorCandidates.swift` gained `remove`, `lists` and `willHold`, all four
    tested in `AnchorCandidatesTests` — 595 Core tests pass. iOS builds warning-free.

    **Verified in the simulator** with the harness of the item-3 session (a scratch rsync with
    `RootView` replaced; see the memory note): the marks with a present and an absent case each,
    both long-press branches, the + landing on the already-blocked sheet and adding, the
    preference flipping the + back to the popover, and the editor row in both scopes. The one
    thing the harness cannot do is press a `UISwitch` — the tool's synthesized tap does not move
    the app's existing toggles either — so the Anchor row was driven through its own binding
    instead, which logged `anchor: let go of 1` and back. Not yet run on the phone.
    **Still open in the build order: item 5, Settings on a diet; item 6, the Mac, which follows
    the phone file for file.**

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
  `Enforcer.resetUsage`, `QuitGrace.forgetAll`, `Watchdog.forget`, `AnchorSync.forgetPhone`,
  all `#if DEBUG || TESTING_TOOLS`), like the phone. Since 2026-09-09 it goes all the way back
  rather than stopping at the setup, because Zach asked: on top of the targets, rules, pending
  changes, the Anchor and today's ledger it clears `furlough.mac.onboarded`, unregisters the
  login item, unregisters the watchdog **and forgets `furlough.watchdog.plistVersion`** (so the
  next onboarding registers down a fresh install's path rather than the shortcut a remembered
  version opens), and clears `furlough.sync.phoneSeen` (so `macDrop`'s lock-with-no-key refusal
  is reachable again). Neither is asked unless it is actually on — `unregister()` throws on a
  job launchd is not holding, and a reset that raised "Could not change the login item" over
  the onboarding it was opening would be reporting a failure that never happened — and
  `lastError` is cleared *before* the work rather than after, so one that genuinely refuses
  still speaks. `Watchdog.forget()` returns what `set(false)` returned for that reason, and
  the sentence it raises is `MacModel.watchdogRefused`, shared with the Settings toggle. The
  confirmation button dismisses the sheet **before** calling the reset, where the phone
  dismisses after: the reset swaps `MacHomeView` — the view presenting that sheet — for
  onboarding. Two things are deliberately left standing, and they are the same line
  the phone draws when it keeps Screen Time access: the **web filter** system extension with
  its `furlough.mac.filter.wanted` flag, and the per-browser **Automation** grants — macOS
  wants them approved by hand and the app cannot give them back. `furlough.testing.shown` is
  untouched for the reason `TestingTools` gives, and the activity log is kept as on the phone.
  It does **not** call `Forgiveness.startTrial`: nothing grants the Mac a first week (see the
  step 27 note above), so starting one here would make the reset the only route to a Mac state
  no real install can reach. A Release build of the Mac carries it when built with
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
- Build check for the Mac: the README's `xcodebuild … -scheme FurloughMac` line, plus
  `-allowProvisioningDeviceRegistration` since step 18 gave the Mac an iCloud entitlement,
  which needs a profile and so a registered Mac; keep it warning-free like the phone.
