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
  `Notifier` both platforms post through. Since step 42 it also plans the weekly digest, whose
  on/off answer it keeps in the App Group at `digestPreferenceKey` so the monitor can read it),
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
  `AnchorLift.swift` (`Policy.liftDate`, the roll-to-tomorrow rule a lift named as a time of
  day resolves by, shared by the Anchor screen and the Drop Anchor intent; step 49),
  `AnchorOffer.swift` (the Drop anchor button on a notification: which kinds carry it, the
  category's registration, and `Notifier.reply`; step 49),
  `Clock.swift` (`ClockMark` and `Clock.read`/`stamp`, step 4; `ZoneMark`, `Clock.zone`/
  `stampZone` and `ZoneReading`, the time zone a device left held beside the one it is in, and
  `SharedState.zone(now:)`/`zoneHold`; step 49 — `Policy.tighter` and the `zone:` wrappers on
  `decide`, `statuses`, `status`, `summary`, `nextTransition` and `dayKey` live in `Policy.swift`),
  `AnchorSync.swift` (the anchor across devices: `AnchorRecord`, the pure `merge` and
  `macDrop`, and `AnchorCloud`, the iCloud key-value store; step 18),
  `DeviceLink.swift` (the roster: `LinkChoice`, `LinkPreferences`, `LinkedDevice`,
  `Revocation`, the pure `Roster`, joining, leaving, revoking and the grandfather rule; step 37),
  `SharedAdditions.swift` (what crosses when a linked device adds something: `SharedAddition`,
  `describe`, the ring, `unseen`, `landing` and `land`; step 37),
  `LinkFlow.swift` (the I/O around those from a model's side: awaiting, sending, resending on
  the first rule, and `takeArrivals`; step 37),
  `Record.swift` (the record of the contract: `accumulate` counts minutes into
  `RuntimeState.days`, `markSpent`/`markWarned`/`queue`/`noteCancelled`/`noteLanded`/
  `noteAnchorReleased` write the events, `card` and the copy functions are what the two screens
  read. `week` is the same days as bars for the Mac's menu, and `weeklyDigest` is two or three
  of those copy lines as a notification, both over whole days only — see step 42. Pure, capped
  at 60 days, and never read by `Policy.decide` — see step 25),
  `RuleSuggestion.swift` (the rule a tier would start something on, and the two named exceptions
  to it: `Draft`, `suggestion(for:chosen:)`, `offer`. Judgements rather than facts, which is why
  they are not in `AppUtility`; offered by both editors and applied by neither — see step 28),
  `Brand.swift` (what an app is known by before Screen Time says: `name(forKey:)` over
  `Companions` then `AppUtility`, `color(forKey:)`, `monogram`, `isLight`, `ink`. What lets a
  usage card be drawn offline while the token is still being asked for — see step 38),
  `WeekDraft.swift` (the week as one list of spans per day, both ways, plus the arithmetic a
  drag on the grid obeys: `room(in:at:)` — the neighbours' edges, which every clamp falls out
  of — `moved`, `resized`, `added`, `removed` and the 15-minute `snapped`. Hoisted out of the
  two week views in step 44),
  `TokenCache.swift` (the map from a usage key to the encoded `TargetKind` behind it, kept
  between visits: `entries`, `savedAt`, the pure `refreshed(with:now:)` that replaces rather
  than merges and refuses an empty answer, and `age(at:)` for the log line. Generic over
  `[String: Data]` because tokens are not Sendable and `TargetKind.application` is iOS-only —
  see step 38).
- `Shared/Intents`: `FurloughIntents.swift` (What's Open, both platforms), `StatusSpeech.swift`
  (its sentence, tested), `DropAnchorIntent.swift` (iOS; compiled into the app and the widget
  extension, see step 8; since step 49 with an optional "Lifts at" time of day),
  `AnchorFocusFilter.swift` (both platforms since step 49; a system Focus drops the anchor, and
  turning that Focus off does nothing at all — see step 42; on the Mac through
  `MacModel.dropAnchor`, refusals posted as a notification).
- `Tests/Core` (target `FurloughCoreTests`, macOS, Swift Testing, no host app): `Support.swift`
  (the pinned calendar and the fixtures), `ModelsTests`, `PolicyStatusTests`,
  `PolicyPendingTests`, `PolicySummaryTests`, `NamingTests`, `DecodingTests`, `ClockTests`,
  `QuitGraceTests`, `PendingNotificationTests`, `UtilityTests`, `UtilityPlanTests`,
  `ActivityLimitTests`, `PendingTextTests`, `CompanionsTests`, `ConfigImportTests`,
  `HostTargetTests`, `HostImportTests`, `AnchorCandidatesTests`, `AnchorScopeTests`,
  `AnchorScheduleTests`, `AnchorSyncTests`, `DeviceLinkTests`, `SharedAdditionsTests`,
  `BrandTests`, `TokenCacheTests`, `WeekDraftTests`, `ZoneTests`, `AnchorLiftTests`,
  `AnchorOfferTests`. 811 tests in 120 suites (2026-09-14, evening). It builds for **macOS**, so it
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
- `Shared/UI/WeekGrid.swift` (`WeekMetrics`, the map between a minute and a point down a day
  column; `WindowGrab`, which band of a block the pointer is in; `WeekGrid`, `DayHeader`,
  `DayEdits`, `DayColumn`, `WindowBlock`) and `Shared/UI/DayBar.swift` — the editable week,
  one view for both apps since step 44. `WeekSheet` and `DayEditor` stay per-platform.
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
  async call; the identifier is read at detection, no connect),
  `Model/NotificationDelegate.swift` (the app delegate: registers the Drop anchor button's
  category before launch finishes and handles its tap; step 49), `Views/`: `Root` (dark scheme,
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
  `TimePickerSheet`, `EffectBanner`), `WeekView` (`WeekSheet` and `DayEditor` only; the
  draft and the grid are shared since step 44), `BudgetSlider` (piecewise
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
  `Settings` + `LogView` (Settings is a menu of rows since 2026-09-11 — see item 40 — each one
  opening a screen in the same file; the build version is on the About row and behind it,
  because it moved out of the old in-app About on 2026-09-09 and the site cannot know which
  build is running), `RecordScreen` (the record, behind Settings' menu; its Mac twin is
  `FurloughMac/Views/MacRecord.swift`, where `MacRecordRows` is split out of
  `MacRecordSection` so the sidebar's card can be rendered to a PNG with no app around it; the
  weekly digest's toggle is on it, see step 42),
  `TagPlacement` (`TagPlacementView`, where to leave the tag: shown once when the first one
  pairs, and behind a row on the Tags screen after that). Screens are
  `ScrollView`s over `EmberWall`, not `List`/`Form`; the iOS 26 toolbar supplies the glass.
- `FurloughMonitor/MonitorExtension.swift`: every callback reconciles from shared state, and
  since step 42 re-plans the scheduled notifications too, so a week the app is never opened
  still ends with a digest whose numbers are yesterday's.
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
- `protocol/`: the contract in a form that is not Swift, for a port to be built against — what
  crosses between devices (step 45) and what one device decides (step 46). `README.md` is the
  whole of it in words; `schema/` is JSON Schema for the four values that cross plus the setup
  file; `fixtures/` is 90 test vectors with hand-written inputs and expectations generated from
  the code — 42 for the link, 48 in `policy/` for the rules engine; `tables/` is `Companions`,
  `AppUtility` and `RuleSuggestion` dumped as JSON. No Swift compiles from here —
  `Tests/Core/ProtocolFixturesTests.swift` is what runs it all, and regenerating is that test
  with `TEST_RUNNER_FURLOUGH_WRITE_FIXTURES=1`.

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
   redirect and its one-time Automation prompt, budget counting, the login item, the
   desktop widget placed on the desktop, and — added 2026-09-13 with step 43 — **the web filter
   surviving a reinstall**: install a build, replace it with another (`furlough mac` twice), and
   the activity log should carry `web filter: this copy of Furlough is not the one that installed
   the filter…` followed by `web filter on`, with no visit to Settings > Web.
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

    **Updated 2026-09-14 (evening). The submission is landed and in review; the two paragraphs
    above are five days stale and wrong in both directions.** Read back through the API at 21:45
    and 21:50 with the key in DEPLOYMENT.md, re-run it rather than trusting this:

    - **"Nothing has been submitted for App Store review" is false.** Version **1.0 was submitted
      2026-09-09 01:01 ET and was REJECTED on 2026-09-10 under Guideline 2.1**, asking for a demo
      video of the phone and the NFC tag filmed together on real hardware. That was answered: the
      video is live at `https://furloughapp.com/review/anchor` (HTTP 200, a 20.4 MB `video/mp4`,
      checked 2026-09-14) and the App Review notes were rewritten around it on 2026-09-13
      (`design/store/LISTING.md:425-455`). The record was renamed and resubmitted: **version
      1.2.0, build `202609140523`, is `WAITING_FOR_REVIEW`** as of 2026-09-14 21:50, submitted
      2026-09-14 17:29 UTC. Review submission `d1fe0e5e-be41-4aed-9377-7af5aaad2398`, its one item
      `READY_FOR_REVIEW`. It is the same version record throughout —
      `b60441f6-a8f1-4619-8e04-5584a68d46db`, created 2026-09-08, which has been 1.0 and is now
      1.2.0. **Nothing is waiting on a session here; it is waiting on Apple.**
    - **Five builds is now eleven**, newest `1.3.0 (202609150033)`, all VALID, internal TestFlight
      live on every one.
    - **The record is complete and was checked field by field**, not inferred from the state:
      release type `AFTER_APPROVAL` (approval publishes it with no second click), review contact
      Zachary Short / `support@furloughapp.com` / `+17576155959`, `demoAccountRequired` false,
      notes **3933 characters** — byte-identical in length to the block in
      `design/store/LISTING.md`, which strips to 3933 too, so what Apple holds is what the file
      says. Ten `APP_IPHONE_67` screenshots, all `COMPLETE`. Marketing URL `https://furloughapp.com`,
      support URL `https://furloughapp.com/support`, both 200. Content rights
      `DOES_NOT_USE_THIRD_PARTY_CONTENT`. A price schedule exists.
    - **The privacy manifest agrees with Data Not Collected, verified in the binary under review**
      rather than in the source: `PrivacyInfo.xcprivacy` is at the root of `Furlough.app` and in
      all four `.appex` of `build/Furlough-202609140523.xcarchive`, and its contents are
      `NSPrivacyCollectedDataTypes` empty, `NSPrivacyTracking` false, `NSPrivacyTrackingDomains`
      empty, with only the three required-reason codes this step already lists. Both entitlements
      are on that binary (`codesign -d --entitlements :-`). ~~**The one half that cannot be checked
      from here is the App Store privacy *label* itself.**~~ **Closed the same evening, 2026-09-14:
      Zach opened App Store Connect > App Privacy himself and it reads Data Not Collected**, which
      agrees with the manifest verified above, so the two sides of step 1 match and neither can
      bounce the review. The reason it had to be him stands and is worth keeping: the
      questionnaire has no API (`scripts/store-submit.sh:23-24`), so only the web form can show
      it, and the submission being accepted proves the questionnaire is *answered* rather than
      proving what it says. A session cannot reach this one; ask Zach.
    - **`UsageView` really does degrade when data access is refused**, which the review notes
      claim to Apple and which is therefore worth being sure of: `Furlough/Views/UsageView.swift:113-118`
      takes the `tour` branch when `hasDataAccess` is false, and `tour` (`:343-345`) hosts
      `DeviceActivityReport(.rank(position), filter: UsageReader.filter())` — the report-extension
      path. `UsageReader.hasDataAccess(_:)` (`Furlough/Model/UsageReader.swift:47-50`) is false
      below iOS 26.4 and for every status but `.approvedWithDataAccess`, so the degraded path is
      the default everywhere outside the EU. Verified by reading, not run with the capability
      refused.

    **The replies to the likely rejections are written, in `design/store/REVIEW-REPLIES.md`** —
    the three pass-off item 1 asked for (entitlement justification, "no way to unblock" read as a
    broken feature, the Screen Time escape undocumented), plus the 2.1 hardware letter that
    actually arrived and the usage-screen 2.3.1 that is likeliest next. Each is pasteable into
    Resolution Center as written, with its claims cited to the tree beneath it where Apple does
    not see them.

    **The iPad note pass-off item 1 asked for, with its premise corrected.** Item 9 did *not* wait
    for this approval — iPad shipped independently in `e253fc6` and is in 1.3.0. What that changes
    is the opposite of what the prompt assumed, and it matters: the build **in review** is
    iPhone-only (`UIDeviceFamily = [1]` in `Furlough-202609140523.xcarchive`, read 2026-09-14), so
    the submission in flight is safe and needs no iPad screenshots. The **1.3.0** build is
    `UIDeviceFamily = [1, 2]`. So **the next submission after this one will demand a 13-inch iPad
    screenshot set (2064 × 2752)**, which does not exist — `design/store/raw/` holds iPhone
    captures only — and which the Simulator cannot produce, because Family Controls does not run
    there (DEPLOYMENT.md section 9). That is a real piece of work standing between 1.3.0 and the
    App Store, and it is nobody's board item yet.

    **Confirmed 2026-09-14, the same evening: Zach checked App Store Connect > App Privacy
    directly and it reads Data Not Collected**, agreeing with the manifest side already verified
    against the binary in review. That closes the one half of step 1 that could not be checked
    from here, and with it every part of pass-off item 1 that did not need Apple.

    **Still Zach's, none of it a session's:** wait on Apple. The Mac Release rebuild that is the
    second half of pass-off item 1 stays correctly gated on approval and was not attempted — with
    the testing-button question in that prompt still unanswered and still due before it is run.

    **Approved. Version 1.2.0 went live on the App Store 2026-09-15** (Apple's own lookup:
    `currentVersionReleaseDate` `2026-09-15T23:59:07Z`, re-checked 2026-09-16 with
    `curl -s "https://itunes.apple.com/lookup?id=6810006594"`). Zach set `site/src/site.ts`'s
    `appStoreURL` to the live listing and redeployed the same day (`ac3c2bb`); `design/store/LISTING.md`'s
    hold-until-live note is closed out there. **What is still open, and still Zach's, not a
    session's:** the Mac Release rebuild above — the testing-button question has not been asked
    and answered, so it has not been run — and the 13-inch iPad screenshot set the 1.3.0
    submission will need (noted above), which is unowned work on no board yet.

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

34. **Settings on a diet (the two-halves pass, item 5).** Done 2026-09-10. The screen ran
    eleven controls and about 170 words of explanation, of which two were settings a person
    changes: the delay, and — since item 1 — which page the app opens on. The rest was
    diagnostics and prose. Five sections now, in this order, and the settings are the top two:

    - **Start.** "Opens on" (a Rules · Anchor chip pair on `AppModel.setStartHalf`, which keeps
      `wantsBothHalves`: moving the page you land on says nothing about the other half's guide),
      the + preference from item 33 folded in beside it, "Run the setup guide again", and
      "Where the time goes", which was buried under Enforcement.
    - **Rules.** The loosening delay and its first-week banner, unchanged.
    - **The record**, unchanged, moved below the two settings sections.
    - **Your setup.** Download and Restore under one footnote instead of two. Both dropped
      facts — that restoring has to ask which app each rule was, and that every restored rule
      goes through the delay — are already said on `ImportSetupView` itself, beside the pickers
      doing the asking.
    - **Diagnostics.** One row: a dot, whether anything is wrong, and the first thing that is if
      something is. Everything the Enforcement section listed is one push behind it in the new
      `DiagnosticsView` — the two permissions, the App Group, the two timestamps, Re-apply
      enforcement, Allow notifications, the Activity log.
    - **About.** Version (the five taps still live on it), About Furlough, and *If something
      gets stuck* as a link to `StuckHelp` rather than a second copy of its opening paragraph.
      Testing stays exactly as it was, behind its five taps.

    Prose: 43 words in three footnotes, from about 176 in six. `Shared/Core/Diagnostics.swift`
    is the summary line as a value — a `Reading` of four facts in, a line and a `Level` out —
    so it is tested rather than tangled in a view, and the Mac can hand it its own answers in
    item 6. Checks are ordered by what they cost, not by severity, so the line names the thing
    furthest upstream: fixing notifications on a phone with no Screen Time access would leave
    the row saying the same thing for a different reason. `AppModel` gained `setStartHalf`,
    `restartGuides` (writes an empty `finishedGuides`; only the last step of each guide is a
    flag, so a set-up half comes back showing step 3 live rather than pretending the apps were
    never picked) and a `diagnostics` reading. `StuckHelp`'s own pointers now say
    "Settings > Diagnostics", and the Devices page's stale "Settings > Save setup" says
    "Settings > Your setup".

    600 Core tests pass (five new for `Diagnostics`); iOS builds warning-free. **Verified in
    the simulator** on the item-3 harness: every section, both chip pairs, the guide row live
    and spent, "Opens on" set to Anchor and Home coming up on the Anchor page after a relaunch,
    the guide restarted from Settings and the checklist back on Home with "Drop it" live, the
    Diagnostics row in both its moss and ember states (the healthy line forced with a
    harness-only env var, since the simulator can never authorize Screen Time), the Diagnostics
    screen, and the stuck page opening from About. Not yet run on the phone.

35. **The Mac follows (the two-halves pass, item 6 — the last one).** Done 2026-09-10. The Mac
    was still the shape the phone had before this pass: one window built around Rules, with the
    Anchor behind an unlabelled SF padlock in the toolbar opening a sheet of eleven blocks. Now
    it is two halves under one segment, file for file with the phone:

    - **The segment.** `MacHalfSegment` (in `MacComponents.swift`, so the offscreen harness can
      draw it) sits under the sidebar headline rather than in the title's place — a Mac window's
      toolbar has no free slot. The sidebar and the detail pane both switch on `half`: Rules is
      the list of targets and the rule editor, the Anchor is what it holds and `MacAnchorPane`.
      The padlock is gone from the toolbar; the app's own anchor mark is on the pane's state card
      (`AnchorGlyph`, the phone's, copied into `MacAnchorPane.swift`). While the anchor is down
      the Rules header carries an ember "Anchored · 3 items", because that changes what every
      rule on the list means.
    - **`AnchorSheet` is `MacAnchorPane`.** The 366-line sheet is gone. What it holds moved to
      the sidebar, where the half's list belongs, so the pane is the state card, two rows —
      **Scope** and **Your iPhone** — and a footnote. Two rather than the phone's four: this Mac
      has no tag reader and no scheduled drops, so Tags and Schedule would be rows about nothing.
      Each row opens a screen in place with a Back link (`WeekSheet` and `LogView` do the same;
      the detail pane is not in a navigation stack), and each screen's lead is the footnote that
      used to sit under its card. The pane owns no picker: the sheet's own app search and host
      field are gone, and both halves add through the one flow.
    - **The guides.** `HalfGuide` moved to `Shared/Core/HalfGuide.swift`; the phone's two step
      lists stayed in `Furlough/Views/Guides.swift` (the first Rules step reads `UsageReader`)
      and the Mac's two are `macRules`/`macAnchor` under `#if os(macOS)` in that file, where
      they are pure and tested. The Anchor's first step is not *Pair a tag* — this Mac has no
      reader — but **"Drop it once from your iPhone"**, on `AnchorSync.phoneSeen`, with the link
      status under the button, which is the same fact from the other end and the thing
      `macDrop` refuses a drop without. `GuideCard` is copied into `MacGuides.swift` for the
      reason `MacComponents.swift` gives: `SectionLabel` and friends live in each app's own
      views, and Shared/UI is compiled into the iOS widget extension, which has none of them.
    - **Onboarding is three panes: promise, start, filter.** The Anchor pane — told rather than
      asked — is gone, and its sentences are in the guide steps they describe. The start pane is
      the phone's: the Anchor first, Rules second, "Both, the Anchor first" quieter underneath,
      committed on Continue. The promise pane keeps the Mac-only paragraph about there being no
      Screen Time API here, because it is the one thing to know before agreeing to anything.
    - **Settings, the same diet.** Start (Opens on, the + preference, Run the setup guide again
      — no "Where the time goes", since there is no usage API here), Rules, Web, Browsers,
      Enforcement (the two toggles, with *The one escape* shrunk from a paragraph to a
      footnote), Your setup (one sentence, from four lines), Diagnostics, Testing. The six-step
      web-filter walkthrough and its explainer now draw only while the status is not On: a page
      of directions under a status that reads On was the tallest thing on the screen.
      `MacDiagnosticsView` holds what Enforcement listed. About is not here — it is Help > About
      on the Mac, and the five-click reveal stays there.

    `Diagnostics` gained a `MacReading` and `macSummary`: different questions, because the Mac
    enforces on its own — a filter that was installed and switched off, a browser that refused
    Automation, the App Group, notifications, and an uninstalled filter last, since that one was
    offered and declined. `MacModel` gained `startHalf`/`wantsBothHalves`/`anchorHalfAdds`/
    `finishedGuides` in the App Group beside `furlough.mac.onboarded`, `chooseStart`,
    `setStartHalf`, `setAnchorHalfAdds`, `addDestination(on:)`, `finishGuide`, `restartGuides`,
    `seedFinishedGuides` (so an update does not put a checklist in front of a Mac that is set
    up), `addToAnchor(_:)` and a `diagnostics` reading; the testing reset forgets all four keys.
    Help's stale pointers now say "Settings > Diagnostics", "Settings > Diagnostics > Activity
    log" and "Settings > Your setup". The + over the Anchor half adds to the anchor by default
    (`anchorHalfAdds`, a Settings chip pair), but the half's *own* Choose apps row never asks
    that preference — it is about what the + means, not about a button that says what it does.
    Each of the three places that asks Application-or-Website has its own popover, because a
    popover pops from the control that was clicked.

    One copy fix that touches the phone: the Anchor guide's last step said
    "\(heldDescription) goes out of reach", which reads wrong half the time — a count takes a
    plural verb and "Everything except 3" a singular one. Both platforms now say
    "Out of reach: 3 items."

    619 Core tests pass (19 new: `MacGuideTests`, and the Mac half of `DiagnosticsTests`); both
    apps build warning-free. **Seen running on this Mac**, 2026-09-10, on Zach's real store (no
    rule targets, the anchor on the everything-except scope holding Discord, never yet heard
    from the phone): both halves with their guides, the segment, the toolbar with no padlock,
    Settings, and the Diagnostics screen. A Release build was installed to `/Applications` the
    way the README says — the launch hook cannot get a window while another copy of the same
    bundle id is running, and `opensWindowAtLaunch` is false on an onboarded Mac, so the window
    comes up with `open -b com.zachshort.furlough.mac` rather than by launching the binary.
    Two things that pass changed on the strength of seeing it:

    - The guide was pinned to the top left of a pane three times its height. Both halves now
      centre it, the way the hero and the empty state already did, and the anchor pane's column
      is `maxWidth: 620` centred, which is what `MacRuleEditor` uses — the two halves put their
      content in the same place.
    - `Footnote` on the Mac had no `fixedSize(horizontal:false, vertical:true)`, so a footnote
      in a stack that was measuring itself came out as one line and an ellipsis.

    **The link status forgot it had ever been linked.** Zach's own use, minutes after the
    handover, found it: `AnchorSync.LinkStatus.isLinked` asked only who wrote the record
    currently in iCloud, so his phone's tag release made the row "Linked" and his Mac drop three
    minutes later overwrote it and put the row back to an amber "Waiting to hear back" — under
    the sentence "there is nothing yet to prove it is hearing you", which `lastHeard` already
    knew was false. Worse on the phone, where every drop is a write of its own and the Mac can
    drop but never release, so the Your Mac row sat at a caution indefinitely after any drop.
    `isLinked` is now `record.writer != thisDevice || lastHeard != nil`, the headline in that
    case is "Linked · last heard 07:32", and the detail names both writes instead of denying the
    second. iCloud being unreachable still outranks all of it, and a device that has genuinely
    never heard the other still reads "Waiting to hear back" — both are tested. Zach's call,
    2026-09-10, from three options; the other two were keeping two states with better words, and
    a third "Linked · waiting" state.

    **Replacing `/Applications/Furlough.app` reset the web filter.** `systemextensionsctl` still
    lists the extension as activated and enabled, but `ExtensionRequest.properties()` comes back
    empty for the new bundle, so Furlough reports *Not installed* and does not connect its XPC
    link; `furlough.mac.filter.wanted` is still true. Settings > Web > Install the web filter
    puts it back, with macOS's approval. Worth knowing before the next install: any reinstall
    costs the filter, and the app cannot tell that from a filter nobody ever installed.

36. **The web filter leaves the first run and is offered at the first website.** Zach asked
    whether the filter step could be skipped for the many people who use only Safari and Chrome —
    ask up front which browsers they use, and walk only the Firefox minority through it. The
    premise does not hold, and the reason is worth keeping: `Browsers.known` is a **hardcoded
    allowlist of fifteen bundle identifiers**, and `snapshots()` skips any running app that is
    not on it — not blocked, not warned about, invisible. So the gap is not Firefox and a Dock
    web app, which is what the old copy named and what taught everyone the wrong model; it is
    everything off that list, including any Chromium fork, and closing it takes a sixty-second
    download. Furlough's adversary is the same person later, and somebody answering "just Safari"
    at onboarding is telling the truth about their habits and nothing about their workaround.
    Skipping the filter does not even skip System Settings: the tab reader needs an Automation
    grant per browser. And the reader lets the page load — `pollInterval` is 2 s, so a blocked
    site renders and is then replaced by the shield, where the filter refuses the connection.

    What was right in the question is that the step is asked at the wrong time, not of the wrong
    people. It was the last pane of the first run, which charges a System Settings trip up front
    for a benefit that does not exist yet — there are no rules on a first run — and asks somebody
    who will only ever block applications to answer for a feature that can never do anything for
    them. The filter does nothing until some host is blocked, which is the condition `Enforcer`
    already uses before it reads a browser at all. So: `MacOnboardingView` is two panes, promise
    and start, with `Continue` now reading "Start with the Anchor"/"Start with Rules" because it
    is the last button of the first run. `Config.hasAnyHost` (`Shared/Core/ConfigHosts.swift`,
    tested — a host target, a site linked to an app, or a host on the anchor's list) plus
    `MacModel.shouldOfferWebFilter` gate a new `WebFilterOfferSheet`, which arrives after a
    website is added, once every other sheet the add raised has gone (the `onDismiss` chain in
    `MacHomeView`: add → companion → filter). Named at the top with the site that caused it.
    Asked once, `furlough.mac.filterOffered`, because Settings > Web has the same buttons for
    anyone who changes their mind. Anybody who only blocks applications is never asked, and it
    costs them no question to get that. `WebFilter.explainer` and the sheet's own copy now say
    the gap is everything off the list rather than naming two examples as if they were all of it.

    Built and tested — 627 Core tests, five new on `hasAnyHost`, both apps warning-free, verified
    in a worktree at HEAD because another lane was mid-rename in `Shared/Core`. **Neither new
    screen has been seen on a Mac.** Two instances of one bundle id get no window, and outside
    `/Applications` the filter reports `.notInApplications`, so the offer sheet renders its wrong
    branch — a faithful look means replacing the installed copy, which was not worth doing to a
    Mac that was anchored at the time.

37. **The link is opted into, per device, and what you add can cross it.** Done 2026-09-10.
    Zach, having seen the anchor cross for the first time, did not want the default to be
    "anchor everything on both devices": a person should opt each device in, be told in steps
    how it works, choose which of several phones, iPads and Macs are on it, and — with the same
    three-way setting he asked for — have what they add on one device land on the others. And
    adding an app should block its website by default, with the site taken off by hand.

    **His four calls, asked before any of it was built:** the opt-in gates *everything*, the
    Anchor included, and the two devices he had linked that day are grandfathered — an install
    that has already heard the other (`lastHeard`, or the Mac's `phoneSeen` latch) enrolls
    itself on first launch and one that has not starts off the link
    (`DeviceLink.decideGrandfathering`, once, keyed `furlough.link.decided`); any device can be
    taken off from any other, refused while an anchor holds anywhere; on the phone, the site and
    the send both wait for the name to arrive rather than asking after the picker; and sending
    and accepting both default to Ask.

    **The roster.** `Shared/Core/DeviceLink.swift`. Each device writes its own entry to the
    key-value store under `furlough.device.<id>` (`LinkedDevice`: name, `platform`, `enrolledAt`,
    `lastSeen`, `canRelease`) and deletes it on leaving, so the roster is the set of entries and
    no blob is ever fought over. Revoking another device writes `furlough.revoke.<id>`; the named
    device un-enrolls on its next read (`obeyRevocation`, called from `AnchorSync.pull`, so it
    lands in whichever process reads first), and a revocation older than an entry's `enrolledAt`
    is spent, so a device can come back. `Roster.linked`, `hasKey(besides:)`,
    `othersDescription` are pure. Enrollment is App Group defaults (`furlough.link.enrolled`),
    read by every process. `AnchorRecord.Platform` gained `.pad` — an iPad runs the phone build
    and has no reader, so it is anchored and never releases; Core has no UIKit, so the app notes
    the idiom at launch (`AnchorSync.notePlatform`) and `platform` reads the note.

    **What the gate changes.** `AnchorSync.pull` reads nothing while off the link and refuses a
    record whose writer is not on it. `macDrop` takes `hasKey:` — an iPhone on the roster
    besides this Mac — where it took the `phoneSeen` latch, which stayed true after the phone
    left; `DropRefusal.noPhone` now says to link both. `LinkStatus` gained `enrolled`, with
    "Off the link" as its headline. `HalfGuide.macAnchor`'s first step is *Link this Mac and
    your iPhone*. Leaving or revoking is `DeviceLink.leaveRefusal(anchorHoldsHere:
    anchorHoldsOnLink:)` — the local profile or the shared record holding — and is otherwise
    instant, because with no anchor down the link holds nothing that leaving would let go of.

    **What crosses.** `Shared/Core/SharedAdditions.swift`. A `SharedAddition` is a *name* and
    every identifier and host a thing goes by — never a token — with `isApp`, the hosts the sender
    actually blocks, its `rule` if it has one, and the `half` it was added to. Each device
    publishes to its own ring `furlough.adds.<id>` (last 20, `id` = the sender's target id so a
    second write about the same thing replaces the first); receivers keep a watermark per source
    (`DeviceLink.watermarks`) and a declined set. `landing(for:in:installed:companion:)` is what
    an arrival would do here — a row already covering a door, the app this Mac has installed, the
    hosts not yet here (the table's too under Always), the rule where the row has none — and
    `land` does it as a tightening, the rule wearing the undo window like one saved by hand, and
    taken into the anchor's list when that is where it was added, unless the anchor is down or
    the scope is everything-except. **The shape differs by platform on purpose:** the phone
    links hosts onto the row (one habit, one row, step 22); the Mac has never drawn a linked
    half, so there each host is a row of its own and the app another, as its companion sheet adds
    them. A linked half the Mac's editor cannot show would be a block with no handle.

    **The phone's step later.** A picked app has no name until the tables (`nameUnnamedTargets`,
    data access) or the shield teach it one, so `LinkFlow.noteAdded` writes the target down as
    awaiting at the picker and `settleLink` — called from activation, `changedElsewhere`, the
    naming and every add — settles what it can: first `autoLinkCompanions` under Always (the
    site onto the app's row, one save), *then* the sends, so YouTube goes out with youtube.com
    beside it. Typed hosts and Mac apps name themselves and settle in the same breath. A rule
    landing on something already sent goes out again without asking (`resendIfSent`, from
    `propose`/`apply`); a target never sent is `settleAwaiting`'s question, not the rule's.
    Arrivals are taken in `applyRemoteAnchor` on both platforms (`LinkFlow.takeArrivals`; the
    Mac's `installed` closure walks Applications only when something is actually waiting):
    Always lands and enforces, Ask holds a `Landing` for a card, Never marks it seen. The phone
    lands the site at once and its editor's existing nudge offers the app through the picker.

    **The three settings**, `Config.link: LinkPreferences` (per device, `decodeIfPresent`, not
    exported): `companionSite` (Always), `sendAdditions` (Ask), `acceptAdditions` (Ask). None
    waits out a delay: turning one down blocks nothing that was blocked. Under Never the phone's
    site nudge is not shown either — a nudge is the Ask it was told not to make — and the Mac's
    `CompanionSheet` is skipped; under Always the Mac adds the sites inline in `addApp`.

    **Screens.** `Shared/UI/LinkCards.swift` (self-contained like `CompanionNudge`, because the
    widget extension compiles Shared/UI): `LinkNudge`, `LinkTrafficCard`, `LinkChoiceRow`,
    `LinkStepsCard` (the four things to know, from `DeviceLink.steps`), `LinkedDeviceRow`.
    Phone: `Furlough/Views/DevicesView.swift` — `DevicesScreen` (off the link: the four steps, a
    name, Link this iPhone; on it: the status card, the roster with Leave/Remove and their
    confirmations, the three settings) hosted by the Anchor page's row, now called **Devices**
    (`AnchorMacScreen` is a shell), and by a new Settings > Devices card; `LinkTraffic(half:)`
    on both pages. The editor says why an unnamed app has no site yet (`AppModel.awaitsName`).
    Mac: `FurloughMac/Views/MacDevices.swift` — `MacDevicesScreen`, hosted by the Anchor half's
    **Devices** row and by Settings' new Devices row (`MacDevicesSettingsView`, in place with a
    Back link like Diagnostics); `MacLinkTraffic(half:)` at the top of the sidebar. `MacHelp`
    and `HelpTopics` say the link is opted into and what the names carry; README, the site's
    privacy and about pages, `index.astro` and `LISTING.md` no longer say the Anchor's state is
    the one thing that leaves the device. Both resets (`DeviceLink.forget`, `LinkFlow.forget`)
    take the device off the link and its entry and ring out of iCloud.

    Tests: `Tests/Core/DeviceLinkTests.swift` (the roster, revocation, keys, entries,
    grandfathering, leaving, the guide, the defaults, the status off the link) and
    `SharedAdditionsTests.swift` (describing, the ring, unseen, the Mac's landings, the
    existing row, rules and undo, found by name, the anchor half, the offer's sentence). 652
    tests in 92 suites; both apps build warning-free in our own code.

    **Not seen on either device.** What to look at first: both devices should come up *on* the
    link (grandfathered — the phone only if it has ever read a Mac write; if not, its Devices
    row shows the guide and one tap links it) with the Devices row green and each other on the
    roster, and the Mac's Drop anchor still working. Then add an app on the phone with data
    access: youtube.com should appear on its row without asking and, since Send is Ask, a card
    on the Rules page offers to send it; taking it puts a card in the Mac's sidebar, and taking
    *that* lands youtube.com there with the phone's rule, undoable for a quarter of an hour.
    Then Leave on one device while the anchor is down, which should refuse with the tag
    sentence. Until both builds are installed the old build's writes are ignored by the new one
    (its writer is not on the roster), so update both before judging the crossing. Whether the
    extensions can write the store is still the open question from step 18; the roster and the
    rings are only ever written by the apps.
38. **The usage page stops waiting on Screen Time, and then stops asking twice.** Done
    2026-09-10, in two commits: "draw the usage cards from the tables and let screen time's
    icons catch up" (`3208f70`) and this one.

    **The problem.** With data access (item 9; iOS 26.4, development builds anywhere and App
    Store customers in the EU only) `UsageView` reads the fortnight itself — but Screen Time
    names an app there by bundle identifier and nothing else. Apple's own name, Apple's icon and
    the token a rule is written on all come from a *second* query,
    `FamilyActivityData.shared.installedApplications` + `visitedWebDomains` behind
    `UsageReader.encodedKinds`, which enumerates every app on the phone. It takes seconds when
    it answers, comes back empty, throws, or never returns at all — and the page used to wait on
    it, so "Where the time goes" sat under a running hourglass for minutes at a time.

    **Half one: don't wait.** `Shared/Core/Brand.swift` is the offline half — `name(forKey:)`
    (`Companions`, then `AppUtility`; a domain is its own name), `color(forKey:)`,
    `monogram`, and `isLight`/`ink` for the lettering. `UsageEntry.isNamed` is the test the page
    reads. `load()` draws the cards the moment the fortnight is folded; `MonogramTile`
    (`Furlough/Views/UsageCard.swift`) puts the first letter of the name on the brand's colour
    where the icon goes, and `Label(token)` takes over the instant a token lands. Every ask gets
    `UsageReader.patience` (12 s) through `within(_:_:)`, and `nameApps()` asks
    `namingAttempts` (3) times a second apart, breaking as soon as Screen Time answers at all —
    `Naming.answered` is false for an *empty* answer, which is a failed query and not a phone
    with no apps on it. An app neither the tables nor Screen Time could name is held back while
    the asking is going on (the "Asking Screen Time about N more apps…" line) and dropped at the
    end: it has no name to show and no token to write on, and a card like that is furniture. The
    colour and the letter, never the artwork — the icon is the app's trademark and `Label(token)`
    is the only source Furlough may draw it from.

    **Half two: don't ask twice.** The answer barely changes between visits — a token is stable
    for as long as the app is installed — so it is written down.
    `Shared/Core/TokenCache.swift`: `entries: [String: Data]` keyed the way `UsageCollector`
    keys an entry (a bundle identifier, or `web:` and a domain) against encoded `TargetKind`s,
    plus `savedAt`. One pure function decides what is worth keeping,
    `refreshed(with:now:)`, and it makes two judgements:
    - **Replaced, never merged.** An app deleted since the last visit is absent from the new
      answer, and merging would keep its token for ever.
    - **Nil for an empty answer**, so a failed query cannot wipe a good cache — the same
      judgement `Naming.answered` makes.

    `SharedStore.tokenCache()` / `save(_:)` under **`furlough.tokens.v1`** in the App Group
    defaults, logging the entry count and byte size on each save; `reset()` removes it beside
    the state and the learned names, so **Reset everything forgets the tokens too**. The whole
    map is kept, not the ranked five: `UsageReader.identities()` reads it to name targets no
    usage card ever mentioned. **Nobody has measured what that costs on a real phone yet** —
    that is what the `tokens: cached N entries, B bytes` line in Diagnostics is for. A few
    hundred apps at a token apiece should be tens of kilobytes; if it comes out over about a
    megabyte, say so here rather than trimming the map silently, because `identities()` needs
    all of it.

    `UsageReader.encodedKinds()` now wraps the `@concurrent` query (`queryKinds`) and saves on
    the way past. `cachedKinds()` reads it back. `fillingTokens(in:from:)` folds a map in with
    no query at all, and — the one behaviour change worth knowing — it resolves **every** entry
    rather than only the tokenless ones, clearing a token the map does not name. That is what
    lets a cached token be taken *away* again. `fillingTokens(in:)` therefore always queries
    now: a summary that looks complete is exactly the one whose tokens most need checking. And
    `identities()` reads the cache first and queries only where there is none, so
    `nameUnnamedTargets` costs nothing on most activations.

    In the view, `fillFromCache()` runs after the fortnight is read and folded and *before*
    `phase = .ready`: it fills, folds again (an app's half can now pair with its site's, which a
    key alone could not do), ranks again, and logs
    `usage: N of M tokens from the cache, written <age> ago`. `nameApps()` runs behind the
    cards exactly as before and corrects what it finds.

    **The stale window, and what was done about it.** A cached token for an app deleted since
    the last visit puts a card on the page for the seconds until the fresh answer removes it.
    **This was not observed on the phone — nobody has run the install-then-delete experiment,
    and it is worth running.** What is certain from the code is the part that outlives the
    screen: pressing Apply in that window would add a target on a token no shield will ever
    cover and nothing can name, and past `AppModel.undoWindow` (30 minutes) it is not undoable
    from the page. So cached tokens are held back from Apply until naming finishes —
    `fromCache` on `UsageView`, set by `fillFromCache` and cleared by the first answered pass,
    and one condition in `apply()` beside the tokenless case that already waited there. The
    cost is that Apply pressed in the first seconds shows "Applying…" until the answer lands,
    which is the wait a tokenless card already had; the drawing itself is not held back, so a
    blank tile for a few seconds is still possible and is the accepted price. If the experiment
    shows the drawn card is worse than a blank tile, that is a `MonogramTile` question, not an
    `apply()` one.

    **Deliberately not done:** looking bundle identifiers up over the network (the page promises
    nothing leaves the phone), bundling app artwork (trademark; `Label(token)` only), and
    prefetching the query on every launch (it enumerates every app, and the cache is what makes
    that unnecessary). The cache is iOS only — the Mac names apps from their bundle identifiers
    already.

    Tests: `Tests/Core/BrandTests.swift` and `Tests/Core/TokenCacheTests.swift` (round trip,
    replace-not-merge, an empty answer keeping the old cache, the age wording, and older/empty
    stored shapes decoding). 664 tests in 94 suites; the phone build, the Mac build and the
    test bundle are all warning-free in our own code.

    **Not seen on the phone.** Open Settings › Where the time goes once and let the real icons
    arrive. Leave, and open it again: the cards should come up with Apple's icons in the same
    instant as the cards themselves — no letters, no "Asking Screen Time…" line. Diagnostics
    should carry the "tokens from the cache" line. Then Reset everything and open it once more:
    letters first, icons after, as before.

39. **The twelve seconds of patience were not twelve seconds.** Zach, 2026-09-11: Apply on a
    usage card "stays in a permanent loading state". Fixed the same day.

    **The bug, and it is one line of Swift semantics.** `UsageReader.within(_:_:)` raced the
    question against `Task.sleep(for: limit)` inside a `withThrowingTaskGroup` and threw
    `Unanswered` when the sleeper won. But **a task group may not be returned from while a child
    of it is still running** — `cancelAll()` only *asks*, and
    `FamilyActivityData.shared.installedApplications` is precisely the question that sometimes
    never comes back and does not answer the asking. So `within` could not return before its own
    question did: `patience` was decoration, `nameApps()` never finished, `naming` stayed true,
    and `apply()`'s `while naming` — which item 38 widened to *every* card with a cached token —
    had nothing that could ever end it. The button spun for as long as Screen Time sulked.

    Three fixes, all in the query's own layer except the last:
    - **`within` leaves the straggler behind.** The question runs in a detached task and nothing
      joins it; a `Race` actor takes whichever of the answer, the failure and the deadline
      settles first and drops the rest. The outcome crosses as an `Outcome` enum because an
      error is not `Sendable` — hence `UsageReader.Refused`, which carries what the error said.
      The straggler is not even cancelled: it still fills the cache and still answers the next
      caller.
    - **One walk of the installed list at a time, shared** (`UsageReader.Enumeration`). That is
      what makes leaving a straggler safe rather than a way to stack three enumerations on a
      phone that is already struggling: the second attempt joins the first question instead of
      adding one. `kind(forKey:)` goes through it too, so a single-key lookup is a dictionary
      read of the shared answer rather than its own enumeration of every app on the phone —
      and `encodedKind(forKey:)` is gone. The cache is saved inside the shared question, so
      joining costs nothing. **Untested on a real phone; no test covers the actor.**
    - **`AppModel.anchorArrivalsFromTheTables`** asked `kind(forKey:)` once per owed bundle
      identifier with no limit at all — a full enumeration each, on every activation with a
      queued arrival, which is the likeliest thing the usage page was stuck behind. Now one
      `UsageReader.kinds(forKeys:within:)` for the whole queue.
    - **Apply stops waiting eventually.** `UsageView.applyPatience` (10 s), then it goes with
      the token it has and logs `usage: apply for <key> went ahead while Screen Time was still
      being asked`. This is the one place item 38's rule is relaxed: a rule written on a stale
      cached token is wrong for the half hour `undoWindow` allows and `undo` is on the card,
      and a button that never comes back is wrong for ever. Worst case Apply is now ~22 s
      (10 s waiting on naming, 12 s on its own lookup) and then says something definite.

    **Not seen on the phone.** 677 tests in 97 suites pass and the phone build is warning-free,
    but the failure itself has not been reproduced here — a wedged `installedApplications` is
    not something the simulator can be made to do, and FamilyControls cannot authorise there at
    all. What to check on the device: Apply while the "Asking Screen Time about N more apps…"
    line is still up, and confirm the button resolves — applied, or a card that says why —
    within about twenty seconds either way. Diagnostics carries the naming attempts and, if the
    wait ran out, the "went ahead" line.

40. **Settings becomes a menu.** Zach, 2026-09-11: the phone's Settings should be "just buttons
    to open the different sections instead of all being exposed", "especially as they grow".
    Done the same day.

    Seven cards down one scroll are eight rows in three cards, each opening a screen: Start,
    Rules, Devices | The record, Where the time goes | Your setup, Diagnostics, About. It is the
    move the Anchor page already made for its own four settings, down to the row (`sectionRow`,
    the twin of `AnchorView.settingsRow`) and the chrome behind it (`AnchorSettingScreen`), so
    the two screens are read the same way. Each row carries the one fact you would have scrolled
    to read — "Opens on Anchor", "A loosening waits 1 day", "Not linked · iCloud Drive is off",
    "No budget spent: 9 days in a row.", "Screen Time access is off", the build version — and
    each card's old footnote is the lead sentence of the screen its row opens. That chrome's
    `lead` is optional now: About and Diagnostics have nothing to say before their first card,
    and a paragraph written to fill the gap would be the prose item 34 took out.

    What moved rather than changed: the delay stepper, its footnote and the first-week banner
    are the Rules screen; the export and the import, with both file pickers and every alert,
    are `SetupScreen`; `RecordCard` is `RecordScreen` (file renamed with it), its range line the
    lead rather than a footnote, and the menu leaves the row out entirely while the record is
    empty, exactly as the card drew nothing; `DiagnosticsView` keeps its two cards and borrows
    the shared chrome. The Testing section follows the five taps on Version onto the About
    screen — what a gesture asks for should appear where it was asked for — and its Reset
    everything closes the sheet through a closure handed down from `SettingsView`, because a
    pushed screen's own `dismiss` only pops.

    The + preference is deliberately **not** on the Start row. Two facts wrapped the row onto a
    second line, and the short true version of the second one — "+ adds to the anchor" — is only
    true over the Anchor page, which is the misreading item 33 wrote the preference to undo. So
    it is said in full on the screen or not at all.

    No `Shared/Core` change, so no new tests; the phone build is warning-free. **Seen in the
    simulator** (the patched-`RootView` harness from the memory note, seeded with a phone nine
    days into a record): the menu, and all six screens behind its rows.

41. **Release notes, and a rule for the version number.** Zach, 2026-09-12: a patch-notes
    section in the website and the apps, backlogged, "ideally coinciding with the package
    numbers", and a standard for when the number moves. Done the same day.

    **One file.** `release-notes.json` at the root of the repo is the only copy. Both apps
    bundle it as a resource (`project.yml`, the `Furlough` and `FurloughMac` targets only — no
    extension shows a What's new screen) and read it through `Shared/Core/ReleaseNotes.swift`;
    the site imports the same file at build time for `site/src/pages/releases.astro`. The help
    pages are deliberately written twice, in the app and on the site, because they are prose in
    one voice; a changelog is not, and two copies of one would disagree the first time somebody
    edited one of them.

    **Where it shows.** Help > What's new on both devices, in the "If you need it" card beside
    About, its row carrying the version and its headline. On the phone, Settings > About has a
    second door to the same screen, because the version number is already on that screen and
    whoever is reading it back off a bug report is who wants this. Nothing interrupts: no sheet
    opens itself after an update, and there is no unread dot — the one dot the menu rows have
    means "something is wrong with this, untouched", and spending it on "you have not read this"
    would muddy the only signal that screen has.

    `ReleaseList` is in `Shared/UI` and drawn the same way on both, so it is self-contained the
    way `LinkCards` is — Ember and the theme helpers only, no `SectionLabel`, `Footnote` or
    `CardDivider`, because Shared/UI is compiled into extensions that carry none of each app's
    own components. The platform is **passed** to it rather than read from `Platform.current`,
    so a list filtered for the phone cannot badge its own rows "iPhone".

    **The backlog is what actually shipped**, read off the ten archives in `build/` rather than
    off the commit log: 1.0 (four builds, 8–9 Sep), 1.0.1 (two builds, 9 Sep), 1.1 (four builds,
    10–11 Sep). That accounting matters — the 1.0.1 *string* was in `project.yml` for a day and
    a half, but only two builds were cut under it, so the two-halves work that landed in that
    window went out as 1.1 and is written down as 1.1.0. The three 1.0/1.1 entries say
    `testflight`, because nothing has been released: version 1.0 was submitted and is
    `REJECTED` (the local `check-review-status` state file, still saying so on 2026-09-12).

    **Then Zach split 1.1 in two, the same day**, which is the rule being used on the case that
    produced it: 1.1's second day of feature work is now **1.2.0** (`scripts/version.sh minor`,
    dogfooding the tool). 1.2.0 is Settings becoming a menu, the usage step offering the Anchor
    rather than only a schedule, the Anchor page standing on Home's wall, the hourglass glow,
    the busy button's height, and the Apply spinner fix. 1.1.0 keeps the 9–10 Sep work and is
    re-dated 2026-09-10, the day of the only build that carried exactly what it lists. 1.2.0's
    channel is `unreleased` — the work went out on 11 Sep inside the last three 1.1 builds, and
    its lead says so, but no build exists under the number yet.

    That split turned up the one case the first cut of this got wrong: **1.2.0 is iPhone-only.**
    Filtering drops a release with nothing for a platform, which is right, but on the Mac it
    left 1.1.0 at the top of the list with no "This build" badge — reading as though the Mac
    were on 1.1.0. So `ReleaseNotes.bundleRelease()` returns this build's entry unfiltered, and
    the page says "You are on 1.2.0, which changed nothing on the Mac." Three cases in the lead,
    all true ones; the third is a Debug build off a branch the file has no entry for. The
    filtering also moved into `ReleaseNotes.filter(_:to:)`, pure and testable, because `all(on:)`
    reads a bundled resource the test bundle does not carry.

    **The standard** is README's new Versioning section. MAJOR.MINOR.PATCH, always three
    numbers; patch is nothing to learn, minor is something new to find, major is something you
    would want to be told before updating. Two rules of this app's own: a change to what
    `Policy.decide` shields is never a patch even when it is a fix, and one version means one
    batch — the number is bumped when a build is cut for other people, not on every merge.

    **It is enforced rather than documented.** `scripts/version.sh` (also `furlough version`)
    refuses a version that is not three numbers, one that does not rise, and one
    `release-notes.json` has no entry for, then rewrites the single line in `project.yml`.
    `scripts/archive.sh` runs `--check` before it archives, beside its other REFUSING TO SHIP
    guards, so a build cannot be cut whose What's new screen would not mention the version it
    is running. Neither commits anything.

    `MARKETING_VERSION` went `1.1` -> `1.1.0` on Zach's call, then `-> 1.2.0` with the split. No App Store version named 1.1
    exists, so nothing in review is disturbed; the one side effect is that the next TestFlight
    upload starts a new build train under `1.1.0` beside the existing `1.1` one. `Version`
    compares numerically, so `1.1` and `1.1.0` are one version and a 1.1 build still finds its
    own notes.

    `Tests/Core/ReleaseNotesTests.swift`, eleven tests, run against the real file found from
    `#filePath` rather than a fixture — a fixture would only prove that a copy is well formed.
    They hold it to three components, no duplicates, newest-first order, real dates, and
    agreement with `project.yml`. Both apps build warning-free. **Seen** at the real
    typography: `ReleaseList` rendered to PNG from a standalone `swiftc` harness over
    `Shared/UI` + `Shared/Core` (the memory note's trick), and the site page in headless Chrome.

42. **The six proposed features: five built, one settled as no.** `PASSOFF.md` items 15–20,
    proposed 2026-09-12 by a session that was asked what else might be nice rather than told
    what to build. None had Zach's go-ahead when they were written down; all six were put to him
    at the start of this session and answered. Built the same day, in one session rather than
    six, because none of them touches `Policy.decide` and only one adds a writer of
    `Config.anchor`.

    **15. The Apple Watch: no.** Zach's call, asked before any code, and recorded here so it is
    not re-proposed as an oversight. No `FurloughWatch` target exists and none should be added
    without a reason that answers this: watchOS is a separate device, not a second process
    sharing the phone's App Group, so a complication needs real transport (`WCSession`) and
    shows a status that is stale by whatever watchOS's delivery budget allows — beside a phone
    widget and a Control Center control that already drop the anchor in one tap. It could never
    release, either: Apple Pay's NFC is not open to third-party apps, so there is no tag reader
    on the wrist and Unanchor would stay phone-only. A watch face that says "anchored" when the
    phone knows better is worse than no watch face.

    **16. StandBy.** The proposal's first step — "add `.systemLarge`" — was wrong, and the
    documentation says so plainly: *"On iPhone in StandBy, the Lock Screen shows two widgets
    side by side on a dark background... WidgetKit uses your `systemSmall` widget and scales it
    to fit available space."* There is no StandBy family, no StandBy environment value and no
    new extension; `systemLarge` would have been a new Home Screen tile that never reached
    StandBy at all. So the families are unchanged and this is a layout pass inside the small
    widget, keyed on the one signal StandBy does give: `showsWidgetContainerBackground`, false
    wherever the system has taken the wall away (StandBy, the iPad Lock Screen, CarPlay). There,
    `StatusWidgetView` goes up a size — eyebrow 10 → 12, name 15 → 24, numerals 22 → 36, the
    glass 30 × 40 → 42 × 56 — and drops every secondary line except the anchor's, which is the
    one a glass alone could be mistaken about from across a room. Content margins shrink on
    their own.

    **The night tint has an API after all.** StandBy Night Mode renders widgets in the
    **vibrant** rendering mode (WWDC23 "Bring widgets to new places", in as many words), which
    desaturates the whole widget and re-colours it — so Ember's hues carry nothing there, and
    the question "does Ember Glass survive the tint" is answered before the phone is ever put on
    a stand: no, and it cannot, for anybody. What that costs is contrast, not colour: the dim
    and grey glasses are 4.5 % and 3.5 % white, chosen against the app's dark room, and under
    vibrant they come out as an outline with nothing in it. So under `.vibrant` only, the glass
    is drawn with the brightest preset already in the palette (`.cream`) and the ember halo is
    dropped, since a soft glow renders as a grey smudge there. No new colour was added — Zach
    was asked, 2026-09-12, and kept it. The Home Screen widget is untouched.

    **17. The Focus Filter.** `Shared/Intents/AnchorFocusFilter.swift`, iOS only, compiled into
    the app. A fourth caller of `AnchorDrop.drop` beside the app, the Control Center control and
    `DropAnchorIntent` — so the anchor's writers are now: the app, the intent, the control, the
    monitor's schedule, the Filter, and the tag. Nothing here can release.

    Two things about it are worth not re-deriving. First, **the system performs a Focus Filter
    twice** — once on activation with the parameters as configured, once on deactivation with
    every parameter back at its default (Apple's own sample says so: `alwaysUseDarkMode: false`,
    `status: nil`). So a Filter needs at least one parameter or it cannot tell the two calls
    apart, and `dropsAnchor` is that parameter as well as the switch. The off-case returns
    without writing anything, and the comment there says why: wiring it to a release is the one
    edit that would turn this into an unblock button on a schedule.

    Second, **there is no scope parameter**, Zach's call. The proposal had one — pick the
    chosen-apps list or everything-except at activation — but applying a shape means writing
    `Config.anchor.scope` from a new process, and chosen → everything-except is as easy to run
    backwards as forwards, which would let a Focus narrow what the anchor holds. The Anchor
    screen owns the list and the scope; the Filter only decides *when*.

    The essential-app warning was the other decision (also Zach's): `Config.anchorWarning`'s
    sheet cannot appear at activation, so it appears at **configuration** instead —
    `displayRepresentation` is an instance property, so the Filter's own row under Settings >
    Focus reads the live anchor and says "Anchors Everything except 3" with
    `UtilityText.anchoring`'s own sentence under it, naming the essential apps it would take.
    Not a static sentence, and not nothing.

    **18. The Mac's menu bar trend.** Zach said yes, with the measurement first. The numbers, 20
    runs each on this Mac after a warm-up: **0.17 ms** to read the week and build the section,
    against **2.1 ms** to render one hourglass image — and `menuNeedsUpdate` already renders one
    of those per target row. The chart is the cheapest thing in the rebuild, so it went in.

    `Record.week(_:upTo:calendar:)` is the whole of the arithmetic: seven `DayBar`s, oldest
    first, each with its weekday, its shielded minutes and a fraction against the tallest day of
    the seven. Relative rather than absolute, because there is no natural ceiling — a day can
    hold one app shut for an hour or everything shut for twenty-four. No new accumulation and no
    new `Config` field; it reads what `Record.accumulate` already counted. `MenuTrend` (in
    `MenuBar.swift`) draws it hand-rolled — seven capsules need no Swift Charts, and a menu that
    links a framework to draw them is a dependency bought for a row — hosted in an `NSMenuItem`
    through `NSHostingView`, because a status item's button takes an image and a menu item takes
    a view. It is drawn in `Color.primary`/`.secondary` rather than Ember's cream: a menu
    follows the system's theme, not the bar's, and cream on a light menu is a bar with nothing
    in it. The section is left out entirely until some day in the seven held something.

    **19. The weekly digest.** On by default (Zach's call), Monday at nine, through the existing
    planned-notification path rather than a one-off request.

    `Record.weeklyDigest(_:upTo:calendar:)` is pure and answers a title and two or three lines,
    each one a row of the record screen with that screen's own label — "No budget spent: 6 days
    in a row.", "Held shut: 7 hours · 3 h 30 min anchored", "Loosenings: 2 cancelled, 1 landed"
    — so the digest cannot word the week differently from the screen it came from. It is nil
    when the week held nothing shut and nothing waited, so a fresh install is never told
    anything. **Every number is about whole days**: `lastSevenDayKeys(before:)`, the seven days
    ending yesterday, and the streak counted back from yesterday rather than through today,
    because a local notification's words are fixed when it is *scheduled* and a streak counted
    through today would be claiming a day that has not happened.

    That last fact is the one that shaped the rest. A notification cannot compute anything when
    it fires, so the digest is re-planned on every enforce **and on every monitor reconcile**
    (`MonitorExtension.reconcile` now calls `PendingNotifications.sync`) — the day activity's
    callbacks come round every midnight, so a week nobody opens Furlough still ends with a
    digest whose numbers are yesterday's rather than last Wednesday's. Its identifier carries an
    FNV-1a fingerprint of its own copy, so a re-plan with different words replaces the request
    instead of being taken for the one already scheduled; Swift's own `hashValue` is seeded per
    process and would have rescheduled the same digest on every launch. `nextDigestDate` uses
    `Calendar.nextDate(after:matching:)`, so the clocks going back move it by an hour rather
    than by 604,800 seconds — tested both ways across a real New York DST boundary.

    The preference lives in the **App Group** (`PendingNotifications.digestPreferenceKey`), not
    in `Config`: the record is this device's own, so the preference about it is too — it must
    not travel in an exported setup or wait out a loosening delay — and an app extension does
    not share the app's `UserDefaults.standard`, which the monitor needs to read. The phone and
    the Mac keep separate answers about separate weeks, and each digest is about the device it
    fires on. The toggle is on the phone's Record screen and in the Mac's Settings > The record,
    each saying what will arrive and whether notifications are allowed at all. The hour and the
    weekday are two constants in `Furlough.swift` rather than a screen; a missed digest is not
    caught up, the same way a missed midnight callback is not.

    **20. Where to leave the tag.** `Furlough/Views/TagPlacementView.swift`, shown once, after
    the **first** tag pairs — `AppModel.pair(identifier:)` is the one place both pairing paths
    meet, so the screen is raised from the model rather than from two views, and presented from
    `RootView` because one of those paths is a screen pushed onto Home's own stack. Raised after
    350 ms for the same reason everything else in this app is: the other path is an alert, and a
    sheet asked for while an alert is dismissing is the one SwiftUI drops. The wait is also what
    lets the name typed into that alert land before the screen reads it.

    Four places — a drawer at home, work or a locker, someone you live with, something with a
    journey attached — each a different kind of distance, and a footnote for the one that is not
    a place: not your keyring and not your wallet, because a tag you carry is a button and not a
    lock. The why is the site's own reason for a tag over a code, condensed to a sentence.

    "First pairing, not any pairing" needs a flag, since forgetting a tag and pairing another
    puts the count back to one. `furlough.sawTagPlacement` sits beside `furlough.sawUsageStep`
    in the app's own defaults — what has been shown, not what is blocked — and the testing reset
    clears it with the rest. `AnchorProfile` and `Config` are untouched, which is what the
    "no new persisted state" in the prompt was protecting.

    The `?` link is a **Where to leave it** row under the card on the Tags screen, opening the
    same view, rather than a link to `furloughapp.com/help/nfc-tags/`. On main the app still
    carries all nine help topics in the binary and opens no URLs at all — there is no
    `Furlough.helpURL` here yet, whatever the code map above says — so a first outbound link
    invented in this file would have collided with the lane-D work when it lands. One copy of
    the advice, reachable from both places; when the help-to-site move lands, that row is where
    a site link goes.

    **What is not verified.** 715 tests in 102 suites pass, both builds are warning-free, and
    the Mac's trend was rendered to PNG in both appearances with the `swiftc` harness from the
    memory note. Nothing here has been seen on the phone: the StandBy layout, the Focus Filter's
    two calls, the digest actually firing and the placement screen all need the device, and the
    tests at the end of `PASSOFF.md` items 16–20 say what to do.

    **Fixed 2026-09-13: the digest could go stale on the Mac, in exactly the case it exists
    for.** A review of this step found that `PendingNotifications.sync` — the thing that keeps
    a planned digest converging on the truth as its target week actually happens — was reached
    on the Mac only from `MacModel.enforce()`, and `enforce()` runs only at launch and on a
    person's own edits. The phone gets a free correction the Mac never did: the DeviceActivity
    day boundary wakes `MonitorExtension` every midnight regardless of whether anyone opens
    Furlough, so its last replan before a Monday-morning fire always lands after the reported
    week is real. A Mac nobody touches a rule on between a Tuesday and the following Monday had
    nothing waking it the same way, and `Record.streak` reads a day with no entry as clean — so
    a digest last planned mid-week could fire having counted the rest of that week, still in the
    future when it was computed, as an unbroken run. `Enforcer` already runs a day-boundary
    check once a day for the usage ledger, on its own, whether Furlough is opened or not: it now
    exposes that moment as `Enforcer.onDayRollover(SharedState)`, and `MacModel.start()` wires it
    straight to `PendingNotifications.sync`. No new state, no change to `Record` or to the plan
    itself — the Mac now gets the same guaranteed pre-fire correction the phone already had.

43. **An update stops costing the web filter, and the Mac gets a release pipeline.** Zach,
    2026-09-13, after asking whether it was time to get the Mac ready for submission: fix the
    reinstall first, then start on distribution. Both landed the same day. Nothing here has been
    run on a Mac other than this one, and the second half cannot be run at all until a
    certificate exists — see "What is not verified" at the end.

    **(a) The filter survives being replaced.** Step 35's last paragraph recorded the defect and
    named it exactly: replacing `/Applications/Furlough.app` leaves `systemextensionsctl` still
    listing the extension as activated and enabled, while a properties request from the new
    bundle comes back empty, "and the app cannot tell that from a filter nobody ever installed".
    So it reported **Not installed** on a screen nobody had open and filtered nothing until
    somebody pressed Install. For one Mac that is a quirk to work around; for a release with any
    update mechanism it is a filter that quietly switches off on every update, for people who
    will not notice.

    Two things were wrong, and they compound. The first is that the app had nothing to compare:
    `start()` asked whether the installed extension's *version* differed from the bundled one,
    and `CURRENT_PROJECT_VERSION` is `1` in `project.yml` for every Mac build ever made, so that
    check compared `1` with `1` and answered "same" on a Mac whose extension had just been
    replaced out from under it. The second is that the repairable states were not repaired: the
    launch path handled `notInstalled` and a newer version, and left `.failed` — which is where
    a properties query that goes *unanswered* lands, the signature of a replaced bundle — to sit
    there until a person acted.

    - `Shared/Core/FilterRepair.swift`, pure and tested (`Tests/Core/FilterRepairTests.swift`,
      13 tests): `Presence` is what macOS says flattened to the facts a decision turns on,
      `decide` says whether this launch asks macOS again and `Reason` says why, in the sentence
      that goes in the activity log.
    - `WebFilter` now writes down **which build's extension macOS accepted**:
      `bundledIdentity` is the extension's `CFBundleVersion` plus the first six bytes of its
      code directory hash, read with `SecCodeCopySigningInformation`, and it is stored in the
      App Group beside `furlough.mac.filter.wanted` as `…filter.installed`. The hash is the
      point — it moves with every build whether or not anybody remembers to bump a number, which
      the version demonstrably does not. A launch that finds a different identity in its own
      bundle knows it was replaced rather than never installed.
    - `…filter.attempted` holds the identity a launch last asked for, so a stuck or refused
      activation is retried **once per build** rather than on every launch. It is written before
      the request, not after, because the launches this has to survive are the ones that do not
      come back.
    - What it will not do is argue. A filter switched off in System Settings is left off, and so
      is one somebody was asked about and declined — `FilterRepair.Presence` keeps `refused`
      (macOS said no on its own, usually a leftover configuration) apart from `declined` (a
      person said no), which the app already knew the difference between:
      `Status.filterDenied(_, prompted:)` and the 1.5-second timing behind it.
    - `furlough mac` now stamps `CURRENT_PROJECT_VERSION` with a UTC timestamp, the way
      `archive.sh` does for the phone. macOS compares an extension's `CFBundleVersion` when it is
      asked to replace one, so this is not bookkeeping: it is the other half of the same bug.
      Verified on a Release build — app and extension both came out `202609140307`.
    - Settings > Web > Copy diagnostics gained three lines: this build's extension, the one this
      app installed, and the one a launch last asked for. "Installed" disagreeing with "in this
      build" is the signature of a filter left behind by an earlier copy, and it is what the
      status alone could never show.

    **Measured, 2026-09-13**, with the same `SecCodeCopySigningInformation` call in a standalone
    `swiftc` harness over the real bundles on this Mac:

    ```
    1+7b74e1dfafcb            /Applications/Furlough.app … .systemextension   (the running one)
    1+7b74e1dfafcb            build/DerivedDataMac/…/Release/…                (the build it came from)
    202609140307+759c0f607c92 build/DerivedDataMacRelease/…/Release/…         (a build cut today)
    ```

    Both properties the repair needs, in three lines: the identity is **stable for the same
    code**, so reinstalling the same build asks macOS for nothing, and **different for a
    different build**, so an update is seen. And the left-hand side is the dead comparison the
    old code was making — `1` against `1`, across a fortnight of work.

    **(b) The Mac's road, and the script that walks it.** There is no Mac App Store submission
    and there will not be one — `FurloughMac` is unsandboxed, drives browsers through Apple
    Events, terminates processes, installs a `LaunchAgent` and carries a system extension, and
    the Mac App Store requires the sandbox without exception (DEPLOYMENT.md section 3, settled
    before any of this was built). The equivalent is Developer ID plus notarization, from a page
    on furloughapp.com.

    `scripts/archive-mac.sh` (`furlough mac-release`, and `furlough mac-check` for the preflight
    alone) is HANDOFF 26's recipe as a command. It builds Release with a stamped build number,
    runs the phone archive's promise checks against the Mac binary — the control string first,
    then no `resetEverything`/`clearEverything`/`TestingTools`, each probe reading a variable
    rather than a pipe for the SIGPIPE reason `archive.sh` documents — then signs **by hand,
    inside out** (extension, widget, app), because Xcode 26's Direct Distribution cannot sign an
    app embedding a system extension (DTS r.108838909, fixed in the Xcode 27 beta). Then
    notarize, staple, DMG with an /Applications symlink, sign and notarize that too, staple it,
    and print what Gatekeeper makes of both.

    Three of its checks are the ones worth keeping:
    - **The entitlement is read back off the signature**, not off the file handed to codesign. A
      Developer ID system-extension filter needs `content-filter-provider-systemextension` (DTS,
      forums 737894) and an entitlement the profile does not grant is dropped *silently* at
      signing — the filter then refuses to load on a stranger's Mac with nothing in the app to
      say why. New entitlements files carry it: `FurloughMac-DeveloperID.entitlements` and
      `FurloughMacFilter-DeveloperID.entitlements`, with every value literal and
      `application-identifier` and `team-identifier` written out, because codesign expands no
      build settings and adds nothing from a profile the way a build does.
    - **`get-task-allow` is refused.** It is what makes a development signature a development
      one, and notarization rejects it.
    - **A split binary is refused.** `Furlough.debug.dylib` means the probes above are reading a
      60 KB stub, and a system extension must be one Mach-O anyway.

    **What this Mac is still missing, which is what `furlough mac-check` prints:** a **Developer
    ID Application certificate** (Xcode > Settings > Accounts > Manage Certificates; Account
    Holder only, so nobody else can make it), and **two Developer ID profiles** — one for
    `com.zachshort.furlough.mac` with Network Extension *and* iCloud, one for
    `com.zachshort.furlough.mac.filter` with Network Extension — saved as
    `~/.furlough/signing/FurloughMac.provisionprofile` and `…/FurloughMacFilter.provisionprofile`
    (outside the repo, like the App Store Connect key; `FURLOUGH_SIGNING` moves them). The
    preflight decodes each profile rather than trusting its name: a development profile saved
    under the release name, or one made before the capability was added to the App ID, are the
    two ways this goes wrong quietly. The notary key is the TestFlight one and is already here.

    **What is not verified.** 729 tests in 103 suites pass, and the iOS and Mac builds are
    warning-free. The repair has not been watched happening on a Mac: doing that means
    installing a build, replacing it, and reading the activity log for `web filter: this copy of
    Furlough is not the one that installed the filter…` followed by `web filter on` — it is on
    the Mac checklist in step 3 and it is worth doing before any of this reaches somebody else.
    `archive-mac.sh` has been run only as `--check`, which is as far as it goes without a
    certificate; everything after the preflight is written and unexecuted.

    **Still owed before strangers have it**, none of it started: the download card on the site
    still says "Furlough for Mac is open source. Build it from GitHub.", there is no update
    mechanism (Foqos uses Sparkle over a notarized DMG on GitHub), and nothing on the site
    explains what macOS will ask for — the extension approval, the filter permission, Automation
    per browser — before somebody downloads it.

44. **The week grid is where windows are edited now (pass-off item 22).** Done 2026-09-14. The
    grid in the rule editor drew the week beautifully and could not change any of it: tapping a
    column pushed `DayEditor`, a list of pickers, which is where every edit happened. So the
    picture and the editing were two screens and the picture — the thing that makes a schedule
    obvious at a glance — was the one you could not touch. It is now direct: drag a window to
    move it inside its day, drag its top or bottom edge to resize, tap (click) empty track to add
    one, and the sentence under the grid rewrites itself while the block is still under the
    finger. Identical on the phone and the Mac, because it is now one view.

    **The hoist came first, and it deletes rather than adds.** `WeekDraft`, `WeekGrid`,
    `DayColumn`, `WindowBlock` and `DayBar` were duplicated verbatim in
    `Furlough/Views/WeekView.swift` and `FurloughMac/Views/MacWeekView.swift` (the Mac copy's
    header said it was "kept separate so that file stays untouched"). Two targets, so the names
    did not collide — and they would the moment one copy moved, so both copies went in the same
    change. `WeekDraft` is pure and is now `Shared/Core/WeekDraft.swift` with
    `Tests/Core/WeekDraftTests.swift`; the drawing is `Shared/UI/WeekGrid.swift` and
    `Shared/UI/DayBar.swift`, which both apps already compile. `WeekSheet` and `DayEditor` stay
    on each side: the sheet's chrome and the list of pickers are genuinely per-platform (the
    phone has a `NavigationStack`, the Mac a `SheetFrame`; each binds its own `DraftWindow`).
    `WeekGrid` takes a `Binding<WeekDraft>` and a `WeekMetrics` — the phone passes 19 and 40, the
    Mac 17 and 44, both the numbers they already drew at. The only two callers are those two
    sheets, so no read-only grid anywhere was made editable by accident.

    **The rules a drag obeys.** Snap to 15 minutes, which is `Furlough.minimumWindowMinutes` on
    purpose, so a snapped edit can never make a window too short to enforce. The clamp is one
    function, `WeekDraft.room(in:at:)`, returning the previous span's end and the next one's
    start; move, both resizes and the add all fall out of those two numbers, so two windows in a
    day can never overlap. Every edit is written back through `WeekDraft.set(_:on:)`, which
    joins — so a block dragged flush against its neighbour becomes one window, which is the house
    rule everywhere else (`TimeWindow.joined`). Mid-drag the column is drawn from the drag's own
    working copy, so the block keeps its identity under the finger and only merges when it is let
    go. Nothing else about the path changed: the grid edits the same `Binding<WeekDraft>` the day
    editor did, the editor still saves a draft, and a loosening still goes through
    `Policy.classify` and waits the delay.

    **Two things the Simulator caught that reading the code would not have.** Both are worth
    knowing before writing another gesture in this app. One: `.offset(y:)` moves what is drawn
    and leaves the view's coordinate space where the layout put it, so a gesture attached to an
    offset block read a grab near its top as one at its bottom edge — the blocks are positioned
    with `padding(.top:)` now, which is honest about where they are. Two, the subtler one: a
    `DragGesture` in `.local` measures against the view it is attached to, and that view is the
    thing being moved, so every frame subtracted the distance already travelled from the distance
    still to go and the block crept to exactly half of where the finger was. The drag is measured
    against the **column's** named coordinate space, which does not move. Related: the last
    position before a lift arrives only in `onEnded`, so the end of a drag is run through the same
    arithmetic before it is released, or the block lands a step short.

    **Where each gesture went, and why.** The column is a drawing surface now, so the way into the
    day's exact times moved to the **day's name** at the top of the column, which is a button on
    both platforms (and hovers on the Mac); a tap on a window opens that day too, and so does
    "Open Wednesday" in its context menu — three routes, because the old one was the whole column.
    Adding is on the **tap, not a long press**: a press is invisible, and the argument for it —
    a finger scrolling a page and stopping on the grid would leave a window behind — is small in
    a sheet, and it cost the discoverable gesture. Verified on the Simulator: a finger starting on
    empty track scrolls the page and adds nothing; a finger starting on a window drags it and the
    page stays put. Deleting is the context menu (long press, right click) rather than an × on the
    block: an hour of track is 19 points tall on the phone and there is no room for a control in
    it. A window tapped onto empty track is **two hours**, not the hour `TimeWindow.nextFree`
    starts one at in the day's list, because on the grid the block is the only answer you get and
    an hour is too short to print its own start time.

    **Not editable while the rule has no windows at all.** Every column then draws one all-day
    block that is not in the model, and dragging it would invent a window on one day and silently
    block the other six. The grid stays the picture it is today and the footnote points at the
    day's name, which opens the editor whose copy already explains that consequence.

    **VoiceOver and the keyboard.** Each block is an element with a label ("Window on Wednesday"),
    a value ("8 PM to midnight"), an adjustable action that moves it a quarter hour, and Remove
    and Open actions. The per-day label and value did not disappear with the column — they are on
    the day's header button, which also carries an "Add a window" action, since neither VoiceOver
    nor a keyboard can point at a place on the track; it adds at `TimeWindow.nextFree`, the same
    slot the day's "Add window" button uses. On the Mac a focused block moves with the arrow keys,
    resizes with shift-arrows and goes with delete, and the pointer turns into `resizeUpDown` over
    an edge (pushed and popped in pairs, or the whole app keeps the cursor). Haptics tick at each
    snap on the phone, gated on the drag the way `BudgetSlider` gates its own; nothing on the Mac.

    **Zach's two calls, answered on 2026-09-14 when he handed them over rather than asking.**
    Dragging a block **across days: no**, and deliberately so — a window belongs to the days it
    applies to, and the block drawn on Wednesday may be one face of a window that also runs Monday
    and Tuesday, so a sideways drag would have to split that window silently. Vertical only also
    means the drop target is never in doubt. `apply(from:to:)` — "Apply to other days" — stays the
    named, additive way to reach another day. The scheduled Anchor's drop and lift on this grid:
    **eventually yes, but as a different mark, not a block.** `AnchorSchedule` is a `minuteOfDay`
    and an optional `liftMinuteOfDay` — an instant, not a span — and it means the opposite of a
    window, so drawing it as amber would read as "allowed". What was built for it is `WeekMetrics`,
    the one map between a minute and a point down a column, so a line with the anchor glyph can be
    laid over the same geometry later without deriving it again. Nothing more; it is not this
    grid's screen.

45. **The link contract, in a form that is not Swift (pass-off item 13).** Done 2026-09-14, in
    `protocol/`. Zach is weighing Android, Windows and Linux (see the "Furlough Beyond Apple"
    assessment), and every port needs the same two things before a line of Kotlin is worth
    writing: the exact shape of what crosses between devices, and a way to prove a second
    implementation merges, drops and lands additions exactly as this one does. Both lived only in
    Swift and its tests. This is them written down. It builds no port, no relay and no transport,
    and it changes no existing Swift — the only new code is one test file.

    **`protocol/README.md`** is the contract in words: what crosses and what never does (tokens,
    and rules as such); the four keys and each entry's lifetime; every field of `AnchorRecord`,
    `LinkedDevice`, `Revocation` and `SharedAddition` with its meaning and its encoding; the
    merge rules branch by branch; the Mac-drop guard and why `noCloud` is checked before
    `noPhone`; the leave refusal; the ring, the watermark per source and the declined set; what a
    receiver does with an addition on each platform, and why the phone's shape and the Mac's
    differ; the three settings; the four things a transport has to provide and which of them
    iCloud gives for free; and a "not decided" list. The sentences are step 37's and the doc
    comments' — nothing in it is a rule that was not read in the code first.

    **`protocol/schema/`** is JSON Schema (draft 2020-12) for the four values plus
    `config-export.json` for the setup file, with `Rule` and `TimeWindow` as `$defs` the export
    schema refers back to.

    **`protocol/fixtures/`** is 42 vectors for the link, one JSON file each, `{name, function,
    input, expected}`: 11 for every branch of `merge`, 6 for `macDrop` (its four reachable
    refusals, the drop, and the expired anchor it lifts first — `nothingToAnchor` and `tooSoon`
    belong to `Policy.drop` and it cannot return them), 9 for the roster and the leave refusal,
    16 for the ring, `unseen` and the Mac's `landing`. **Inputs are written by hand and
    expectations by the code**, which is the whole point: with
    `TEST_RUNNER_FURLOUGH_WRITE_FIXTURES=1` every `expected` is rewritten from current behaviour
    instead of asserted, so a behaviour change fails the test until somebody regenerates on
    purpose and the diff of the fixtures is the review. (Plain `FURLOUGH_WRITE_FIXTURES=1` does
    nothing: `xcodebuild` does not hand its own environment to the test process, and without the
    prefix the run silently just asserts.)

    **`protocol/tables/`**: `companions.json` (83 pairs), `tiers.json` and
    `rule-suggestions.json`, dumped from `Companions`, `AppUtility` and `RuleSuggestion` by the
    same test under the same flag. `other-platforms.json` is keyed by pair title with an
    `android` and a `windows` column. **Zach's call, twice.** The `windows` column ships empty
    and stays empty: item 11's house rule is that every entry is confirmed from a vendor source,
    and most Windows executables cannot be confirmed from a vendor page at all, so what would
    even *count* as a confirmation there is the undecided part. The `android` column was the same
    until he asked for the groundwork a Kotlin port needs, and it is now filled for 82 of the 83
    — each confirmed against its own Play listing, which had to answer 200 **and** name the app
    in its `og:title`, since a 200 alone only proves some app owns that identifier. `theScore
    Bet` is the one left empty on purpose. Its test only checks that every key is a real pair
    title; the values are not a thing a machine can check, which is the reason for the rule.

    **`Tests/Core/ProtocolFixturesTests.swift`** loads every fixture with the real Codable types,
    runs the pure function and asserts. It finds the files from `#filePath` rather than adding
    resources, so `project.yml` is untouched. It also checks each schema against a real encode —
    every key the encoder writes is a property the schema names, every property the schema
    requires is one the encoder writes, and each enum's raw values equal the schema's `enum` list
    — by a small recursive walk over `properties`, resolving `$ref` within a file and across
    them. No JSON Schema library; this project takes no dependencies. The enum lists are guarded
    by exhaustive `switch`es whose only job is to stop compiling when a case is added.

    Expectations are whole objects where that is what the function produces (`merge` and
    `macDrop` give back an `AnchorProfile`) and projections where the whole object would be
    noise: `appended` is checked by the surviving ring's ids and sequences in order, because that
    is all it decides. Inputs are minimal — `Config` and `AnchorProfile` both decode tolerantly,
    so a fixture writes only the fields its case is about.

    **The mechanism did its job the first time it was asked to, which is the thing to know about
    it.** The vectors were written on 2026-09-10 and landed on 2026-09-14, and in between
    `SharedAdditions.landing` grew a `now:` and a `Landing.anchors`. Regenerating moved *only*
    the six landing fixtures — merge, `macDrop`, the roster, the ring and all 48 policy vectors
    came back byte-identical — so the drift was one function wide and the diff said so without
    anyone having to go looking. Closing it is what the five new landing vectors are
    (`landing-anchor-half-*`): an addition to the anchor's half takes a new door onto this
    device's list, is still the whole offer where the row is already blocked but off the list
    ("Hold it here too?"), is nothing at all where the row is already on it, is refused while the
    anchor holds — nothing changes the list under a lock — and never joins an everything-except
    list, where the list is what stays *open*. §8 of the README gained the `anchors` and
    `owesAnchoredApp` rules with it, including the one a port will get wrong if it is not told:
    `land` **re-checks** the anchor against the clock rather than trusting `landing.anchors`,
    because under Ask time passes between the offer and the answer.

    **What Zach should do:** read `protocol/README.md` once as if he were the Android engineer,
    and say what he could not build from it. Nothing to tap; there is no UI in this.

46. **The rules engine as vectors.** Done 2026-09-14, the second half of item 13. Step 45 pinned
    what *crosses*; this pins what one device *decides*, because an Android build that syncs the
    anchor perfectly and gets the windows wrong is not Furlough. Same mechanism, same test file,
    same flag: 48 vectors in `protocol/fixtures/policy/`, flat and named by prefix (`status-`,
    `transition-`, `classify-`, `pending-`, `night-`, `week-`, `spans-`), and §11 of
    `protocol/README.md`. No existing Swift changed.

    13 for `Policy.status` (the five-deep order, the anchor first, exhaustion keyed by the day,
    the next-open search wrapping past Saturday, and two nights); 6 for `nextTransition`
    (including a timed anchor's lift beating a window edge); 12 for `classify` — 10 for rules,
    2 for tiers; 6 for `applyDuePending`; 3 for splitting and folding a night; 5 for a week of
    per-weekday budgets; 3 for `ActivityLimit.spans`.

    **Three things the vectors pin that a port would otherwise get wrong.** A night is stored as
    two windows with the morning half's days shifted one day on, and read back as *one*: inside
    the evening the status says 1680, past 1440, because nothing shuts at the join — unless the
    morning is worth no minutes, and then it really does end at 1440. `isTighterOrEqual` is
    compared **day by day**, so a week the same size but rearranged is a loosening while writing
    one budget out as seven equal ones is not. And `applyDuePending` expires the undo window
    before anything else and counts the landing into the record — two side effects a port could
    implement halfway and still pass a naive test, so `landedToday` is in every expectation.

    **The calendar is pinned and has to be**: Gregorian, GMT, `en_US_POSIX`, Sunday first,
    weekday numbers 1…7 with 1 = Sunday, which is also how `TimeWindow.days` numbers its bits.
    Run these against a local time zone and half of them disagree for reasons that have nothing
    to do with the engine. Said in the README and in the suite's own doc comment.

    **`spans` carries a caveat rather than a rule.** The ceiling of 19 is Apple's — one of the 20
    DeviceActivity activities is the budget tracker — and a port should not inherit the number.
    What carries over is the decomposition: saved rules *and queued ones*, days stripped so the
    same hours on different days count once, nothing from a rule that never allows anything.
    Included because item 13 named `ActivityLimitTests` as a source; the README says plainly
    which half is Apple's.

    §11 also lists **what the vectors do not cover**, so the set is not mistaken for the whole
    engine: `Policy.decide` (two functions, one per platform, and a port writes its own),
    `Policy.summary`, the record, and the delay arithmetic.

47. **The largest text size, audited (pass-off item 31), and the automations that already work,
    written down (pass-off item 32).** Done 2026-09-14, no Shared/Core changes, so no new tests.

    **Item 31.** `EmberFont` scales with Dynamic Type because it is `Font.custom(_:size:)`; what
    did not scale was the box around some of that text. Walked every `.frame(width:)`/
    `.frame(height:)` in `Furlough/Views/` and `Shared/UI/` and fixed the ones that wrap a `Text`
    and would clip it at the largest accessibility size, leaving every purely decorative frame
    (icons, dots, dividers, the hourglass, sliders) untouched: the half tab bar's label
    (`HomeView.swift`'s `HalfTabBar`, the site named as the clearest example) and its column
    width now use `minHeight`/`minWidth` rather than a fixed size; the numbered step badge that
    repeats in four places (`AddWebsiteGuideView`, `HelpView`'s `HelpSteps`, `Guides.swift`,
    `LinkCards.swift`'s `LinkStepsCard`) grows the same way; so does the weekday letter in
    `RuleEditorView`'s `DayStrip` and the monogram letter in `UsageCard.swift`'s `MonogramTile`.
    `DayBar.swift`'s hour-axis labels are positioned by raw pixel offset inside a
    `GeometryReader` rather than a frame a box can grow to fit, so they got `lineLimit(1)` +
    `minimumScaleFactor(0.7)` instead — shrink rather than overlap, the same convention
    `WeekGrid.swift`'s `WindowBlock.label` already uses for exactly this reason.
    `WeekGrid.swift`'s own hour-gutter labels already carry `lineLimit(1)` and were left alone;
    `UsageReportFrame.height` is fixed for an unrelated reason (a `DeviceActivityReport`
    extension cannot report its own height) and was not touched. Nothing moves at the default
    text size — verify at Settings > Accessibility > Display & Text Size > Larger Text, dragged
    to the top, walking Home, the rule editor, the Anchor page, Pending and Settings.

    **Item 32.** `DropAnchorIntent` was already a Shortcuts action, a Control Center control, a
    widget button and (since step 42) a Focus Filter; nothing about dropping the anchor changed
    here; only the fact that four automations already work was written down. A new
    `AutomationsHelp` page in `HelpTopics.swift`, linked from `HelpView`'s Anchor card and a
    second small row under "Where to leave it" on `AnchorScreens.swift`'s `AnchorTagsScreen`, so
    the two pieces of advice about living with the Anchor sit in one place. A matching page at
    `site/src/pages/help/automations.astro`, linked from `help/index.astro`. Every recipe says
    plainly at the top that it drops and none of them lift, and why: a Shortcut that could lift
    is a Shortcut that could be deleted at 9:59 PM. **Not run on a phone** — like the Settings/App
    Store automation in step 23's `PickerHelp`, these are written from how Shortcuts automations
    and Focus Filters work rather than verified on this phone; ask Zach to build one from the page
    and say whether the taps are still right.

48. **Four Opus items in one session (pass-off 27, 28, 29, 30).** Done 2026-09-14. None of them
    changes what `Policy.decide` shields; each was a thing Furlough already knew and did not
    show, or a surface it did not use. Four decisions were put to Zach before any code and all
    four came back with the recommendation: the anchor supersedes the window activity, fourteen
    and sixty stay two numbers, the Mac's hero says nothing about what it measured, and the phone
    does not get search.

    **27. The Anchor on the Lock Screen.** A second `ActivityAttributes` type
    (`Shared/LiveActivity/AnchorActivityAttributes.swift`) and a second lifecycle, because
    `ActivityAttributes` is a *type* — a second kind of activity can never be a flag on the
    first. The attributes carry **nothing**: there is only ever one anchor, so the single
    activity of that type *is* the hold, which is what lets one scheduled ahead with
    `Activity.request(start:)` become the live one when its moment arrives, updated in place by
    the monitor rather than ended and re-requested by a process that may not request anything.
    Matching by a `droppedAt` in the attributes would have failed: `Policy.scheduledDrop` stamps
    `anchoredAt` with the callback time, which is minutes later than the minute it promised.

    What should be showing is decided in `Shared/Core/AnchorActivity.swift`, pure and tested:
    `Policy.anchorActivity(config:now:)` answers the hold that is on, or the one a schedule
    promises next — and promises nothing the schedule could not perform, checking the same two
    conditions `scheduledDrop` does (something to hold, a tag paired), because a promise on the
    Lock Screen at 11 PM that does not happen is worse than no promise. `AnchorText` in the same
    file is the one wording: `StatusWidget.anchoredLine` now reads it, so the widget and the Lock
    Screen cannot say the same fact two ways. A timed hold counts down to its lift; a tag-only
    hold counts up from its drop and carries the one sentence it has ("Only your tag lifts it.").

    The activity carries **no App Intent and must never gain one** — every button on a Live
    Activity runs an intent, and the only intent that could belong here is a release, which lives
    behind a tag scan in the app and nowhere else. The file says so.

    Ended on every release path, which is the half that matters: the tag (in-app, through
    `enforce`), a timed lift (`MonitorExtension.liftIfDue` now syncs, which it did not),
    and a release over the link (`applyRemoteAnchor` → `enforce`). Started on every drop path the
    process allows: the app, `DropAnchorIntent`, the Focus Filter, and the monitor's scheduled
    drop — which updates the activity the app asked for ahead. A drop from Control Center runs in
    the widget extension, which may not request one; the request is attempted, logged if refused,
    and the Lock Screen catches up at the next `enforce`.

    **Zach's call:** while the anchor holds, the window activity comes down (a window counting
    down under a total hold is a countdown to nothing). A *scheduled* anchor supersedes nothing —
    it is a promise, and the window is still open. The cost, stated when the call was made: a
    timed lift while the app is closed leaves no window activity until Furlough is next opened,
    because an extension may not start one.

    **28. A switch for every notification, and the last five minutes counted down.**
    `Shared/Core/NotificationKinds.swift` is new: `NotificationKind`, one case per notification
    actually posted, with the row's title and the line under it; and `NotificationPreferences`,
    the set that is *off*, in the App Group for exactly the reasons `digestPreferenceKey`'s
    comment gave (device-local, must not travel in an export or wait out a delay, and the monitor
    reads it outside `UserDefaults.standard`). Stored as the muted set rather than nine booleans,
    so a kind added later is on by default with no migration. The weekly digest's own preference
    is **folded in**, not left beside it: `NotificationPreferences.muted(stored:legacyDigest:)` is
    pure and tested, and honours an older build's `furlough.weeklyDigest` until this build writes
    its own answer. `plan` takes `muted:` and filters on it; `Notifier.post` takes the kind and
    returns without posting when it is off — silently, because the thing that would have been
    announced is already in the activity log. All ten call sites pass their kind.

    The screen is a Settings row on the phone (`Furlough/Views/NotificationsScreen.swift`) and a
    card in the Mac's Settings, each led by the sentence that is the point: muting blocks nothing
    and unblocks nothing, so it applies the moment it is tapped. The digest keeps its toggle on
    the Record screen as well — one value, two places that each have a reason to show it, and
    they cannot disagree because they read the same store. `setNotification` re-plans rather than
    calling `enforce`: nothing here moves a shield, so re-registering DeviceActivity for a muted
    "Window opened" was work for nothing.

    (b) `RuntimeState.warnedAt` was recorded, counted down by the Live Activity, and ignored by
    the two screens that had the same data: the home hero said "under 5 min left" as static text
    beside a countdown to the *window*, and the row said nothing. Both now count down to
    `warnedMoment + Furlough.warningMinutes` — the hero takes the earlier of that and the window's
    own close, and the row uses `Text(timerInterval:)` from the warning moment, which ticks by
    itself (the list's clock is `.everyMinute`). Where `warnedMoment` is nil — a warning that
    fired before the field existed — today's words are kept rather than a number invented.

    **29. The Mac keeps what it counts.** `Shared/Core/UsageHistory.swift`, pure and tested: days
    of seconds per target, `record`, `prune`, per-target and per-day minutes, a fortnight total,
    `bars(upTo:)` and `minutes(overLast:upTo:)`. The Mac files the finished ledger and prunes at
    the day boundary in `Enforcer.apply` — the once-a-day moment that happens whether or not
    anyone opens Furlough, which is why it is there and not on a second timer. Fourteen days for
    25 targets measured **2.8 KB**. `Enforcer.measured` is the history plus today's live ledger,
    since today's seconds are not filed yet.

    **Zach's call:** fourteen and sixty stay two numbers. The record is minutes held *shut* over
    sixty days; this is minutes *used* over a fortnight, matching the phone's usage page — the
    phone cannot reach past a fortnight, and a Mac claiming sixty days of used minutes would be
    claiming a span its other half has no answer for. The two cards sit next to each other at the
    foot of the sidebar (`FurloughMac/Views/MacUsage.swift`) and each says which number it is.
    The hero says nothing about it — also his call.

    The menu bar's trend gained used minutes beside shielded, over the **same seven days** (two
    numbers on one line have to be counted over one span). No second set of bars: used and
    shielded do not share a scale — a day can hold everything shut for twenty-four hours and be
    used for twenty minutes — so a bar drawn against the other's ceiling would be a picture of
    nothing. Cost, measured the way step 42 measured it (20 runs after a warm-up, `-O`, this
    Mac): `UsageHistory.minutes(overLast: 7)` **0.035 ms**, `Record.week` 0.039 ms in the same
    harness, against the 2.1 ms `menuNeedsUpdate` spends rendering *one* hourglass per target
    row. It went in.

    **30. The Mac grows a menu.** `FurloughMacApp.commands` was `CommandGroup(replacing:
    .newItem) {}` and a Help item — the whole menu bar, in an app whose Quit is refused while
    anything is blocked and whose window is hidden after onboarding. Now: **Anchor** (Drop Anchor,
    ⌘D, disabled with `Policy.DropRefusal`'s own sentence as the tooltip and its first sentence as
    a disabled row under it — and **no Weigh Anchor item ever**, because there is no tag reader on
    a Mac and a greyed-out release would imply one could exist), **Rules** (Add Application ⌘N,
    Add Website ⇧⌘N, Visualize Windows ⇧⌘V) and two **View** items for the halves (⌘1 / ⌘2).

    `MacMenuRoute` (`FurloughMac/Views/MacCommands.swift`) is how they reach the window: commands
    are built in the scene and inherit no window's environment, so each item sets a request and
    the window performs it through the path its toolbar already calls — never a second
    implementation. `HelpRoute` is the same idea, one menu older; the model is handed to
    `AnchorMenuItems` explicitly for the same reason. Visualize Windows is answered by
    `MacRuleEditor`, which owns that sheet, and is disabled when no rule is open.
    `MacModel.dropRefusal` answers "would this be refused" without performing it.

    (b) **The phone does not get search — Zach's call.** A home screen you have to search is a
    sign of too many rules, and the grouping by next opening is meant to make the list readable
    rather than navigable. The Mac's sidebar got a filter field, appearing only past eight rows
    (a list you can see all of does not need finding) and filtering whichever half is showing. A
    plain `localizedCaseInsensitiveContains` over the name the row already shows, so there is no
    matching logic to hoist into `Shared/Core`. The record and usage cards are about the whole
    Mac rather than the rows above them, so a filter hides them until it is cleared.

    **What is not verified.** 781 tests in 114 suites pass and all three builds are warning-free,
    but **nothing here has been seen running**. The Lock Screen, the Dynamic Island, the muted
    notifications and the countdown all need the phone; the Mac's new card, the menus and the
    filter need the Mac app installed. Two things to watch in particular: whether macOS shows the
    tooltip on a *disabled* menu item (if not, the refusal is readable only from the disabled row
    beneath it), and whether `Activity.request` succeeds from the widget extension's process when
    the control drops the anchor (the log line says if it did not).

    **Found and not fixed** (raised rather than folded into an unrelated change): the Mac posts
    its window-closing notification with the title "5 minutes left", while the monitor posts the
    same kind as "Window closing" — one notification kind, two titles across the two platforms.
    The new screen calls it "Window closing" on both.

49. **The time zone is the clock Furlough did not watch (pass-off item 23), a Drop anchor
    button on the notifications that tempt you (24), a lift time on the Drop Anchor intent (25),
    and the Focus Filter on the Mac (26).** Done 2026-09-14, the four Fable items, in one session,
    in a throwaway worktree while 27–30 were being built in this tree. **Gates green, not seen
    running**: nothing here has been on a phone or walked on the Mac. **The four calls the
    pass-offs name were not put to Zach first** — the session was non-interactive — so each was
    built on the pass-off's own recommendation and isolated to one line, named below, so a
    different answer is a one-line change. They are listed again at the end.

    **23. The zone.** `ClockMark` defends the wall clock by comparing `Date` against
    `CLOCK_MONOTONIC`; a time zone change moves neither number, so it read as nothing while
    every decision ran on `Calendar.current`. Three things followed from Settings > General >
    Date & Time > Time Zone, with no delay and nothing in the log: every window's local hours
    remapped at once (a 10 PM window opened at 9 AM once the zone said Tokyo), the day key
    rolled and a spent budget came back, and the Mac's `UsageLedger` was replaced at the rolled
    key. Closed on the same terms as step 4: the loosening half waits, the tightening half
    applies at once.

    - `ZoneMark { identifier, movedAt }` in `Shared/Core/Clock.swift`, `RuntimeState.zone`
      (tolerant decode; absent is trusted, as a missing `ClockMark` is). **Not the `since` the
      pass-off sketched**: the hold is measured from when the move was *first seen*
      (`movedAt`, written by the first save after it), because a hold measured from the last
      save is a hold a quiet day eats — the phone can go from one midnight callback to the next
      without saving. Keyed on the identifier, never the offset, so DST is invisible; tested
      across both New York boundaries.
    - `Clock.zone(mark:current:now:hold:)` answers a `ZoneReading` — `.settled`, or
      `.moved(from:until:)` — and `Clock.stampZone` stamps on the same terms as `Clock.stamp`:
      the old zone is kept while the move is held, let go once the hold has run out or the
      device has come back. `SharedStore.save` stamps it beside the clock mark and logs each
      crossing once, from whichever process saved first ("time zone is now X; keeping Y until
      …", "time zone back to …", "time zone hold over; now on …"), so Diagnostics shows it.
    - `Policy.tighter(_:in:_:in:now:)` is the whole defence and its truth table is in the doc
      comment: shielded beats open, the later reopening between two shut answers, the earlier
      close between two open ones, exhausted named over closed, a nil `nextOpen` (never) later
      than any date. Answered in the device's own frame — a minute or a `NextOpen` from the
      held zone is moved by way of the instant it names, so a 5 PM close in New York is 4 PM
      in Chicago. Folded at the *status* level: `decide` was split into `statuses(…)` and
      `decision(config:now:statuses:)` so the token arithmetic exists once, rather than a second
      `tighter(Decision, Decision)` that would have been the same rule written twice.
    - The wrappers every shield-deriving caller goes through, all taking `zone:` and building
      the two calendars themselves: `Policy.decide`, `statuses`, `status`, `summary`,
      `nextTransition` and `dayKey`. `SharedState.zone(now:)` is the reading (the mark,
      `TimeZone.current`, `zoneHold`). Converted: `ShieldReconciler`, `MonitorExtension` (the
      two announcements, the threshold and warning writes and their guards, `Record.markSpent`
      / `markWarned`), `Enforcer` (its ledger key, `usedSeconds`, both `decide`s, the warning
      and exhaustion writes, the web filter's `until`; it also ticks on
      `NSSystemTimeZoneDidChange` after `NSTimeZone.resetSystemTimeZone()`, as it does on
      `NSSystemClockDidChange`), `ShieldExtension`, `HomeView`, `MacRootView` (three),
      `MenuBar` (three), `MacRuleEditor`, `WhatsOpenIntent`, `LiveActivityManager`, both
      widget providers (the reading moves with the timeline's cursor, so the timeline settles
      when the hold does). **Left on the device's day, cosmetic**: `HourglassState.of`'s amber
      `warned`, and the "5 min left" eyebrow in `HomeView`'s and `MacHero`'s hero lines.
    - `Policy.decide`'s own signature is unchanged and it stays pure; the tests keep pinning one
      calendar. Nothing here writes `Config`, `ConfigExport` never carried the runtime,
      `SharedStore.reset()` drops the state key the mark lives in, and the mark waits out no
      delay. The one escape README documents is exactly what it was.
    - The banner: `ClockBanner(zone:until:now:)` beside the clock case, in both Pending screens
      (`PendingChangesView`, the Mac's `PendingSheet`). `Clock.describeMove` is the sentence
      ("Your time zone is now Japan Standard Time. Furlough is keeping Eastern Time until
      10:00 PM tomorrow."), `Clock.zoneName` the names, both tested. **Copy not put to Zach**;
      it follows the clock banner's register.
    - **The hold is the base loosening delay** — `SharedState.zoneHold`, `config.delayHours(for:
      nil)` hours, so the first week's cap applies. Built on the pass-off's recommendation (a
      zone change loosens every window at once, the argument `setDelay` already makes); the
      other candidate is a flat day, and that one property is the whole difference. No way to
      say "I really did fly", on the pass-off's reasoning: a button that shortens this is an
      unblock button with a passport, and the hold lapses on its own. A traveller gets a first
      day on the intersection of home hours and local hours.
    - **Raised, not built — the wake gap on iOS.** `Monitoring.register` schedules window
      activities in `Calendar.current`, so the monitor is woken at the *device* zone's edges
      only; a held-zone edge that falls between wakes is acted on at the next wake or the next
      app activation. For a large move that is harmless — the intersection of the two
      schedules is empty and everything stays shut. For a one-zone move it is a real leak in
      the loosening direction: 9–5 held in New York and read in Chicago should close at 4 PM
      Chicago, and nothing wakes the monitor until Chicago's 5 PM, so it stays open an hour.
      Closing it means registering the held zone's spans too during the hold (converted into
      device minutes, split at midnight) and living with the 19-span cap. The Mac has no gap;
      it ticks every second.
    - `Tests/Core/ZoneTests.swift`, 21 tests in 4 suites: the reading and the stamp, the DST
      boundaries, New York → Tokyo (shut at 9 AM, shut at 10 PM New York too, open on Tokyo's
      evening once the hold lapses), New York → Chicago (open where both agree, closed on the
      earlier close, the reopening rebased), Tokyo → New York (nothing already shielded
      released), the spent budget across the rolled key, two targets that disagree both shut,
      the sooner transition, settled equals plain, the truth table row by row, and decoding
      with and without a mark. README has a bullet under the clock one.

    **24. The button.** `Shared/Core/AnchorOffer.swift`: `carries(kind)` says which
    notifications carry **Drop anchor** — the four about a moment (`.windowOpened`,
    `.windowClosing`, `.budgetWarning`, `.budgetSpent`) and not the ones about a rule or about
    the anchor itself. **Built on the pass-off's proposal; that switch is the whole of it.**
    Keyed on step 48's `NotificationKind`, which landed in this tree in the same hours, rather
    than on an identifier prefix — 24 rebased on 28, as the board said whichever ran second
    would. `category(for:)` is what both choke points set `categoryIdentifier` from
    (`Notifier.post` and `PendingNotifications.apply`); `register()` registers the category,
    one action, no `.foreground` and no authentication, at every launch of both apps. The
    identifiers are `Furlough.anchorNotificationCategory` / `anchorNotificationAction`.
    iOS: `Furlough/Model/NotificationDelegate.swift`, an app delegate via
    `@UIApplicationDelegateAdaptor` so the notification center's delegate exists before launch
    finishes; the tap calls `AnchorDrop.drop(reason: "notification")` and then the intent's own
    follow-ups (the Lock Screen, the widget, the control), and a refusal comes back as a
    notification through `Notifier.reply`, which ignores the mutes because a reply to a tap
    that went silent would be a tap that looked like it worked. `willPresent` is deliberately
    not implemented on iOS, so foreground behaviour is what it was. Mac: `MacAppDelegate`
    handles the same action through `MacModel.dropAnchor()`, so `.noPhone` and `.noCloud` still
    refuse. **No lift branch on either, not even one that returns early.** The ordering hazard
    the pass-off named stands: categories are set per app, so the first notification the
    monitor posts after an update, before the app has run once, shows no button.
    `Tests/Core/AnchorOfferTests.swift` pins the four, that nothing `plan` schedules gets one,
    and that the identifiers are distinct.

    **25. The lift.** `Policy.liftDate(atMinute:from:calendar:)` in
    `Shared/Core/AnchorLift.swift` is the Anchor screen's roll-to-tomorrow rule lifted out —
    today at the minute if at least `Furlough.minimumWindowMinutes` away, else tomorrow — and
    `AnchorView.timedUntil` now calls it. `DropAnchorIntent.liftsAt: Date?` with `kind: .time`,
    **a time of day, built on the pass-off's recommendation** (a `Date` is the sharp edge that
    gets 11 PM wrong); resolved on Furlough's clock and passed to `AnchorDrop.drop(until:)`.
    `.tooSoon` still comes back through the dialog, though the roll rule makes it unreachable
    from here. The control, the widget button and the bare phrase pass nothing, which keeps
    meaning "the tag alone"; the `AppShortcut` phrases are untouched. The dialog says
    "Anchored. 3 items until 7:00 AM, or sooner with your tag."; a second run says "Already
    anchored." `Tests/Core/AnchorLiftTests.swift`: 11 PM → tomorrow, 6 AM → today, the
    fifteen-minute edge both sides, midnight, and the raw-date refusal.

    **26. The Mac's Focus Filter.** `AnchorFocusFilter.swift` is one file on two platforms
    now. The Mac's `perform` goes through `MacModel.dropAnchor()` on the main actor, refusals
    and all, and a refused activation is posted as a notification (`Notifier.reply`), because a
    Filter fires with no UI and silence would be a Focus a person believes is locking their Mac
    and is not. `displayRepresentation` on the Mac says the refusal *ahead of time*, in the
    refusal's own words (`macRefusalAhead`: `.noCloud`, then `.noPhone`, read the way
    `MacModel.refreshLink` reads them). **Offered and refused rather than hidden**: the question
    the pass-off asked has one answer, because a Focus Filter cannot be withheld from the list
    per device — the system lists every `SetFocusFilterIntent` the app declares. `project.yml`
    needed nothing: `Shared/Intents` was already in the Mac's sources, guarded by the `#if`
    that came off. `ControlCenter` stays under `#if os(iOS)`.

    **The four calls, each built on the recommendation and each one line to reverse.** (1) The
    zone hold is the base loosening delay, not a flat day — `SharedState.zoneHold`. (2) No
    traveller's button; nothing to remove. (3) The button rides the four moment notifications —
    `AnchorOffer.carries`. (4) The intent's lift is a time of day — `DropAnchorIntent.liftsAt`'s
    `kind`. And one the pass-off asked that has no second answer: the Mac's Filter is offered
    and refused, because it cannot be hidden.

    **What is not verified.** 811 tests in 120 suites pass and all three builds are
    warning-free (the Mac log's one line is the system extension's own AppIntents-metadata
    notice, there before this). Nothing has been seen running. The phone: pick an app whose
    window has not opened yet today, set the zone forward past its start under Settings >
    General > Date & Time, and watch it stay shut with the banner on the Pending screen saying
    why; set the zone back and watch the banner go; spend a small budget, roll the zone past
    midnight and confirm it is still spent; set a window to close six minutes out, lock the
    phone, and long-press the notification when it arrives — then check Diagnostics for
    `anchored (notification)`; build a Shortcut — Drop Anchor, Lifts at 7:00 AM — run it and
    read the dialog, then run it again. The Mac: configure the Filter under System Settings >
    Focus, turn that Focus on, watch the Mac lock and the phone follow, turn it off and confirm
    nothing lifts; with the phone off the link, watch the Filter's own row say why it will not.


## Style rules

Swift 6 language mode with approachable concurrency, SwiftUI, `@Observable`, async/await, no
third-party dependencies. Keep it small: as of 2026-09-14 that is nine targets — two apps
(`Furlough`, `FurloughMac`), six extensions (`FurloughMonitor`, `FurloughShield`,
`FurloughWidgets`, `FurloughReport`, `FurloughMacFilter`, `FurloughMacWidgets`) and the
`FurloughCoreTests` bundle. It read "one app target plus the three extensions" until then,
which was true before the Mac (2026-09-07) and stopped being true without anyone noticing.
Shared code that the monitor extension uses must not import SwiftUI (memory limits).

The process standard — how work is scoped, sized, handed off and closed — is
`AGENT-PRACTICES.md`, adopted 2026-09-14. There is deliberately no separate Swift conventions
file: with one author, no linter and no CI, these five lines plus the invariants above are the
whole standard (Zach's call, 2026-09-14).

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
