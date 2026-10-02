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
  **Superseded in part 2026-09-24 (step 55):** the drop itself still needs no tag at the model
  layer (`AppModel.anchor(until:)`, still what the widget, Control Center, Siri and Shortcuts call,
  and still instant) — but the hand-press **Anchor** button now puts a tag scan in front of itself
  by default, the same ritual `unanchorWithTag()` already required, because testers said the two
  felt mismatched without it. `AppModel.requiresTagToAnchor` (on by default, off in Tags) is the
  toggle; `AnchorToggleButton.drop()` is where it branches.
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
- `design/`: `DESIGN.md`, `HOURGLASS.md` (the next brief), `MAC-FIRST-RUN.md` (the script for
  watching the Mac's first run on a clean account, written 2026-09-16 for pass-off item 34 —
  the ordered prediction, the exact macOS prompt wording read off this Mac's frameworks, and
  what to bring back; `/mac`'s permissions copy gets rewritten from what it produces);
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

1. **A test target for the rules engine.** Done 2026-09-08. Body folded 2026-10-02.
2. **The rename: Brick became Anchor.** Done 2026-09-08. Body folded 2026-10-02.
3. **The device test pass.** Done 2026-09-07. Body folded 2026-10-02.
4. **The clock cannot be an unblock button.** Done 2026-09-08. Body folded 2026-10-02.
5. **Notifications.** Done 2026-09-08. Body folded 2026-10-02.
6. **Small fixes.** Done 2026-09-08. Body folded 2026-10-02.
7. **Mac hardening** Done 2026-09-08. Body folded 2026-10-02.
8. **Anchor from anywhere.** Done 2026-09-09. Body folded 2026-10-02.
9. **Real usage on the phone.** Done 2026-09-08. Body folded 2026-10-02.
10. **Live Activity at window start.** Done 2026-09-09. Body folded 2026-10-02.
11. **Per-weekday budgets.** Done 2026-09-09. Body folded 2026-10-02.
12. **Rules for categories.** Done 2026-09-09. Body folded 2026-10-02.
13. **Anchor the whole phone.** Done 2026-09-09. Body folded 2026-10-02.
14. **More than one tag.** Done 2026-09-08. Body folded 2026-10-02.
15. **Tiers, and the warnings that come with them.** Done 2026-09-08. Body folded 2026-10-02.
16. **Unify the Mac duplicates** Body folded 2026-10-02.
17. **Imagery** Body folded 2026-10-02.
18. **Sync the Anchor across devices.** Done 2026-09-09. Body folded 2026-10-02.
19. **TestFlight, then the App Store.** Done 2026-09-08. Body folded 2026-10-02.
20. **Both halves of the same thing.** Done 2026-09-08. Body folded 2026-10-02.
21. **A setup as a file.** Done 2026-09-08. Body folded 2026-10-02.
22. **One habit, one row.** Done 2026-09-08. Body folded 2026-10-02.
23. **Apps the picker will not show, and the no-QR/no-pause decisions.** Done 2026-09-09. Body folded 2026-10-02.
24. **The Anchor's clock.** Done 2026-09-09. Body folded 2026-10-02.
25. **The record.** Done 2026-09-09. Body folded 2026-10-02.
26. **The Mac web filter (item 8b, lane E).** Done 2026-09-09. Body folded 2026-10-02.
27. **Forgiveness for a mistake, never for a craving.** Done 2026-09-09. Body folded 2026-10-02.
28. **A starting rule, not just a tier (item 12, lane G).** Done 2026-09-09. Body folded 2026-10-02.
29. **The record's one uncounted queue.** Done 2026-09-09. Body folded 2026-10-02.
30. **The companion table, 33 pairs to 83 (item 11).** Done 2026-09-09. Body folded 2026-10-02.
31. **The Mac's reset goes all the way back.** Done 2026-09-09. Body folded 2026-10-02.
32. **The phone's reset goes back to onboarding too.** Done 2026-09-09. Body folded 2026-10-02.
33. **The + gets a destination, and the halves get marks (the two-halves pass, item 4).** Done 2026-09-10. Body folded 2026-10-02.
34. **Settings on a diet (the two-halves pass, item 5).** Done 2026-09-10. Body folded 2026-10-02.
35. **The Mac follows (the two-halves pass, item 6 — the last one).** Done 2026-09-10. Body folded 2026-10-02.
36. **The web filter leaves the first run and is offered at the first website.** Body folded 2026-10-02.
37. **The link is opted into, per device, and what you add can cross it.** Done 2026-09-10. Body folded 2026-10-02.
38. **The usage page stops waiting on Screen Time, and then stops asking twice.** Done 2026-09-10. Body folded 2026-10-02.
39. **The twelve seconds of patience were not twelve seconds.** Done 2026-09-11. Body folded 2026-10-02.
40. **Settings becomes a menu.** Done 2026-09-11. Body folded 2026-10-02.
41. **Release notes, and a rule for the version number.** Done 2026-09-12. Body folded 2026-10-02.
42. **The six proposed features: five built, one settled as no.** Done 2026-09-12. Body folded 2026-10-02.
43. **An update stops costing the web filter, and the Mac gets a release pipeline.** Done 2026-09-13. Body folded 2026-10-02.
44. **The week grid is where windows are edited now (pass-off item 22).** Done 2026-09-14. Body folded 2026-10-02.
45. **The link contract, in a form that is not Swift (pass-off item 13).** Done 2026-09-14. Body folded 2026-10-02.
46. **The rules engine as vectors.** Done 2026-09-14. Body folded 2026-10-02.
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

50. **The site sends a Mac visitor to the Mac build, not to the App Store.** Done 2026-09-16.
    Zach installed 1.2.0 from the App Store on his Mac and found it was not the Mac app. It is
    not: the listing at `apps.apple.com/app/id6810006594` carries a **Mac** compatibility
    heading — "Requires macOS 15.0 or later and a Mac with Apple M1 chip or later", read off the
    page's own markup on 2026-09-16 — so "available on Mac with Apple silicon" is switched on in
    App Store Connect and Macs are being served the iPhone build. Step 43's "The Mac" section
    called that outcome on 2026-09-07 and nobody had connected it to the store listing: "Running
    the iOS build on the Mac ('Designed for iPhone') would launch but could not enforce."

    **The site half is what this step changed.** The DMG existed but lived in exactly one place,
    the `#download` card at the foot of the homepage, while the nav CTA and the hero button both
    went straight to the App Store on every platform — so a Mac visitor's first two chances to
    act both led to the build that cannot enforce. There is now `site/src/pages/mac.astro`, the
    page step 43 said this needed ("The equivalent is Developer ID plus notarization, from a
    page on furloughapp.com"): the download, why it is not on the Mac App Store (the sandbox),
    and the three permissions macOS asks for. It is in the nav, the footer, and the support
    page's Mac line, which pointed only at GitHub before.

    **The platform swap is CSS over one class, and the class already existed.**
    `Base.astro`'s inline `<head>` script has stamped `html.is-mac` before first paint since
    before this step, with the right iPadOS guard (iPadOS reports `Macintosh`, so it also
    requires `maxTouchPoints <= 1`); the only thing reading it was one `order: -1` rule. The
    rules now live in `global.css` beside it: `.only-ios`/`.only-mac` **only ever hide**, never
    restore a display value, so each element keeps the display its own classes give it, and
    `[data-plat]` paints whichever button is the visitor's. Shipped as plain glass and painted,
    rather than carrying `prominent` in the markup, because CSS can add a look but cannot take
    a class away.

    **One bug worth keeping.** The old ordering rule was `:global(html.is-mac) .cactions >
    :nth-child(2)` inside `index.astro`. Astro scopes the *child* half of such a selector to the
    page's own cid, so the moment both buttons moved into `StoreButton.astro` it silently
    stopped matching and the Mac button led on colour but not on position. Ordering is keyed on
    `[data-plat]` in `global.css` now. Any page-scoped rule reaching into a component's children
    has this failure mode, and it fails quietly.

    **Every Mac call to action points at `/mac`, not at the `.dmg`.** One download route, so the
    first-run explanation is always on the path — which matters once the walkthrough below is
    written. `/mac` itself is the only direct link to the file.

    **What is not verified, and what is still owed.** The site builds clean (16 pages, `/mac`
    among them) and was walked in the browser pane at 1280×900 and at 375×812: the swap, the
    ordering, the hidden twin, no console errors, and every internal link 200 including the
    `.dmg`. The detection guard was replayed against five real user-agent/touch pairs — macOS
    true, iPadOS false, iPhone false, Windows false. **Not** seen: the DMG downloaded and
    installed from the deployed site on a clean Mac. Nothing is deployed; `furlough deploy` is
    Zach's to run. Still owed, and deliberately out of this step's scope (Zach's call,
    2026-09-16): the first-run walkthrough as an ordered, watched sequence — this page names the
    three permissions but not the order of the prompts, because that flow has never been watched
    on a clean Mac (step 43 says so). And the thing no site copy can fix: **the App Store
    Connect checkbox above.**

    **One stale line found, not edited.** "The Mac" section says `FurloughMac` is "macOS 26".
    `project.yml:6` and every per-target `MACOSX_DEPLOYMENT_TARGET` say 15.0, and the store
    listing agrees. `site.ts`'s `macMinimumOS` uses 15.0. Left for whoever owns that section.

51. **A copy outside /Applications no longer spends the filter offer (pass-off item 35).** Done
    2026-09-23, in `FurloughMac/Views/MacFilterOffer.swift` alone. Found 2026-09-16 while item
    34's walkthrough was being written. `WebFilterOfferSheet` is asked once, ever (step 36), and
    a copy that could never take it could still raise it and spend it. `WebFilter.isInApplications`
    (`WebFilter.swift:315`) is false for a copy run from anywhere but `/Applications` — most
    likely straight from the mounted DMG — and `refresh()` and `install()` both report
    `.notInApplications` there (`WebFilter.swift:419-421`, `452-454`). `shouldOfferWebFilter`
    (`MacModel.swift:478`) still raises the sheet in that state, since it asks only that the
    filter be neither wanted nor on. The sheet then showed a prominent Done, the same button as
    "the filter is on"; skipped the two paragraphs that make the case for the filter; and
    counted the offer when it closed, so the same person moving the app into `/Applications`
    afterwards was never asked.

    What changed, all in the sheet:
    - **The offer is not spent outside /Applications.** `onDisappear` calls
      `noteWebFilterOffered()` only when `canTakeOffer`, which is `status != .notInApplications`.
    - **`.notInApplications` has its own button branch**: one Done, not prominent, like the
      in-flight states. It had shared `.on`'s prominent one — at `MacFilterOffer.swift:73`
      before this step. The pass-off cited `:61`, which is the Install branch; its `:20` was
      right.
    - **The two paragraphs show whenever the filter is not on**, not only when it is not
      installed. The status line now sits under them in every state but `.notInstalled`, where
      before it showed only in their place.
    - **The footnote "… Furlough will not ask again." is withheld outside /Applications.** That
      copy no longer spends the offer, so the sentence would be untrue there. Withheld rather
      than reworded, because new copy is Zach's call (AGENT-PRACTICES R7); the variants went
      to him in the hand-back. To reverse: remove the `if canTakeOffer` around the `Footnote`.

    **Where the guard lives, and why the sheet.** The item left it open between the sheet's
    `onDisappear` and `noteWebFilterOffered` itself. The sheet, for three reasons.
    `noteWebFilterOffered` has one caller (`grep -rn noteWebFilterOffered FurloughMac Shared`
    finds the definition at `MacModel.swift:501` and the sheet's call, 2026-09-23). The sheet
    draws its buttons from the same `filter.status` in the same file, so "could this offer be
    taken" sits beside the switch that decides what was offered. And `MacModel.swift` is the Mac
    file most lanes touch, so leaving it alone is one less merge. The argument against, written
    down so it is not rediscovered: a second caller added later would not inherit the guard. If
    one appears, move the `guard` into `noteWebFilterOffered`, reading
    `enforcer.webFilter.status`, and it covers both.

    **Which states spend it — the item's triage, answered.**
    - `.installing` and `.awaitingApproval` spend it. When the sheet closes they are an offer
      taken: `install()` sets `isWanted` before `.installing` (`WebFilter.swift:456-457`), and
      `shouldOfferWebFilter` refuses once `isWanted` is set, so it could not be raised again
      anyway. An `.awaitingApproval` found when the sheet opens, with the flag unset, is a
      request an earlier copy left pending. This copy is in `/Applications` and can finish it,
      and Settings > Web carries it.
    - `.failed` spends it. It reaches the sheet two ways, and both could take the offer. In
      one, Install was pressed here and refused, or macOS wanted a restart
      (`WebFilter.swift:474-480`): the offer was taken, and `isWanted` is set. In the other,
      the sheet opened on a properties query macOS never answered (`WebFilter.swift:424-430`).
      The sheet shows Install in that state (the `.notInstalled, .failed` branch), Install
      sends a fresh request, and the failure text itself says that often clears it. So "Not
      now" there answers a real offer. Compare `.notInApplications`, where `install()` returns
      before it asks macOS anything.
    - `.disabledInSettings`, `.filterOff` and `.filterDenied` spend it. An extension is already
      on this Mac, this copy is in `/Applications`, and the directions finish the job.
    - `.notInApplications` does not.

    **When it comes back.** At the next *website* added, not at the next launch.
    `offerWebFilter()` (`MacRootView.swift:284`) runs only after a new host is added
    (`MacRootView.swift:174`, `185`), and the guidance's third step already sends someone who
    has moved the app to Settings > Web. Two consequences, which went to Zach as questions
    instead of being decided. A copy that stays outside `/Applications` raises the sheet again
    for every new website, since nothing spends the offer there. And the reopened copy in
    `/Applications` waits for a website before it asks, rather than asking at launch.

    **Settings > Web was checked against the same three questions, and needs nothing**
    (`MacSheets.swift:777-792` and `1001-1043`, read 2026-09-23). It never calls
    `noteWebFilterOffered`. Its button switch groups `.notInApplications` with `.installing`,
    which show no action (`:1017`), not with `.on`, which offers Remove (`:1014`). Its status
    row paints `.notInApplications` in Ember (`:1040`). And `WebFilter.explainer` with the
    directions already shows whenever `!status.isOn` (`:781`), the same gate this step gave the
    sheet.

    Nothing about enforcement changed. The filter stays out of the first run, and the offer
    stays once-only in every state that could take it (step 36). No `Shared/Core` change, so no
    tests. The Mac Debug build is green and warning-free in our code (2026-09-23); its one
    warning is Apple's `appintentsmetadataprocessor`, the line the iOS gate greps out. **Not
    seen on a Mac.** The walk from the mounted DMG is Zach's and is in the hand-back.

    **Two stale lines found, not edited** (not this item's): `README.md:109` says "Onboarding
    offers it and Settings > Web installs it", and `README.md:113` says the first launch covers
    "the web filter if you want it". Both predate step 36, which took the filter out of
    onboarding.

52. **A fresh 1.3.0 build cut and gated, upload left for Zach.** Done 2026-09-23, no code
    changed. Build `202609232009` (`1.3.0`, HEAD `4c3ad02`) was archived and exported with
    `scripts/archive.sh` (no `--upload`): both REFUSING TO SHIP gates passed (the control-string
    probe and the per-bundle Screen Time entitlement check across all five bundles),
    `** EXPORT SUCCEEDED **`, and no warnings in Furlough's own code — the two Apple-tooling
    warnings that appear (`appintentsmetadataprocessor`'s missing-AppIntents notice, and an
    ExtensionKit embed-path notice for FurloughReport) are pre-existing, the same ones already in
    `build/last-archive.log` and `build/resubmit-archive.log`. It carries commits `4731526`,
    `8cad7e5` and `013b327`, none of which are in the build already sitting in TestFlight
    (`202609150033`, cut 2026-09-14 ~20:33 EDT). The `--upload` call to `xcrun altool` was
    refused by Claude Code's auto mode as a production deploy before it ran, and this session did
    not try to route around that — see the memory note on the App Store Connect write block. The
    archive is at `build/Furlough-202609232009.xcarchive`, the `.ipa` at
    `build/export/Furlough.ipa`, the full log at `build/archive-local.log` (all gitignored).
    **Zach ran the upload himself** the same day:
    ```
    xcrun altool --upload-app -f build/export/Furlough.ipa -t ios --apiKey L6A2R4SBXQ --apiIssuer 04f9fe5a-56e5-460f-80ac-c57e788fbdc6
    ```
    `UPLOAD SUCCEEDED with no errors`, delivery UUID `62f0fe92-7505-45d2-807b-d6e3110ba4e2`,
    2026-09-23 16:18:38 ET. It appears in TestFlight once Apple finishes processing it — not
    confirmed read back from the ASC API this session. Submitting 1.3.0 for App Store *review*
    is a separate, still-unstarted step: section 9's 13-inch iPad screenshot set (2064 × 2752)
    still does not exist. Asked in chat, Zach scoped this session to the upload alone, not
    review submission.

53. **The Mac in /Applications is plain Release again (pass-off item 1, step 4).** Done
    2026-09-23. Zach's answer to the step's question, in chat that day: **plain Release, no
    testing button**, so no `TESTING_TOOLS`. The step's premise was wrong twice over, and both
    are recorded where they matter.
    - **It was not Debug.** Step 3's "a Debug build of `2851824`" went stale on 2026-09-10, when
      step 35 installed a Release build (`HANDOFF.md`, step 35's "A Release build was installed
      to `/Applications`"). The last copy's filter was `1.2.0/202609141817`, a stamped build
      number, which only `furlough mac` and `archive-mac.sh` produce, and both build Release.
    - **It was not there at all.** On 2026-09-23 `/Applications/Furlough.app` was missing, and
      so were the App Group store and the watchdog. The unified log has the running copy ending
      at 2026-09-22 14:55:01 on SIGTERM (`termination reported by launchd (2, 15, 15)`), with
      no watchdog reopen after it. A session Zach ran, titled "Remove Furlough from Mac", did
      the uninstall. Zach then chose reinstall over leaving the Mac without Furlough.

    **What ran:** `scripts/furlough mac` with no arguments (`scripts/furlough:185-202`). Log at
    `build/mac-release-reinstall.log`: `** BUILD SUCCEEDED **`, no `error:` and no `warning:`,
    `-configuration Release`, and no `TESTING_TOOLS` anywhere in it. The code is exactly
    `4c3ad02`, item 35 included (step 51). The two commits after it touch only `README.md`.

    **Verified on this Mac, not by a person:**
    - Build `1.3.0 (202609232012)`: `CFBundleShortVersionString` and `CFBundleVersion` of the
      app, and the same stamp on the filter `.systemextension` and `FurloughMacWidgets.appex`.
    - One 9.6 MB Mach-O and no `Furlough.debug.dylib`, so it is not Debug's split shape.
    - `archive-mac.sh`'s own probe (`scripts/archive-mac.sh:214-222`): `nm -a` finds none of
      `resetEverything`, `clearEverything` or `TestingTools`. The same probe finds 8 in
      `build/mac-testing/…/Release/Furlough.app`, a Release + `TESTING_TOOLS` build, so the
      probe can tell the difference. The control string `no unblock button` is present.
    - `codesign --verify --deep --strict` passes, team `X9V4L6HR2R`.
    - Running from `/Applications`. The window (captured on its own with `screencapture -l`)
      is onboarding's first pane, "No unblock button.", because the store is new.
    - The new store's activity log: `fonts: ok`, `iCloud at launch: reachable`,
      `reconcile (launch): blocked apps=0 sites=0`, `menu bar: item added`, then
      `web filter: macOS says Failed` eleven seconds after it asked.

    **Not seen:** Help > About's Version row, which reads those same two keys
    (`FurloughMac/Views/MacHelp.swift:638-639`) and should say `1.3.0 (202609232012)`. It is
    behind onboarding, and onboarding's Start raises the Notifications prompt, so it is Zach's.

    **What this costs, stated plainly.** There is **no Settings > Testing > Reset everything**
    on this install (Debug and `TESTING_TOOLS` only; see the Reset everything bullet under "The
    Mac"). Getting this Mac back to a first run now means uninstalling by hand, the way the
    2026-09-22 session did. And **the old rules are gone**: they lived in the App Group store
    that the uninstall removed. This Mac starts from onboarding.

    **The uninstall left residue.** Zach asked for it cleared in the same step. Claude Code's
    auto mode refused the removal as irreversible local destruction, and this session did not
    route around it. **Nothing below was removed.**
    - The filter extension, `com.zachshort.furlough.mac.filter (1.2.0/202609141817)
      [activated disabled]`. SIP is enabled, so `systemextensionsctl uninstall` cannot take it,
      and removing a system extension is a system-setting change a session does not make. It is
      inert. A fresh store does not want the filter, so `repair()` leaves it alone
      (`WebFilter.swift:398-413`). The new copy reads it as `Failed` (the unanswered-query
      signature of a replaced bundle, step 43), and Settings > Web shows **Install the web
      filter** in that state (`MacSheets.swift:1008-1010`). Installing should replace it with
      this build's extension, by the replacement path in step 43. That is predicted, not tried.
      Settings > Web offers **Remove** only when the filter is on (`:1014-1016`).
    - `~/Library/Containers/com.zachshort.furlough.mac.widgets` (2026-09-09). The widget's
      state comes from the shared App Group ("The Mac", desktop widget bullet), not from this
      container.
    - `~/Library/Application Support/Furlough`. It holds only `review-status.state`
      (`READY_FOR_SALE`), which belongs to the review poller, not to the Mac app.
    - The LaunchAgent `com.zachshort.furlough.reviewstatus`: every 3 hours it runs
      `scripts/check-review-status.sh`, and it was written 2026-09-10 during the 1.0 review.
      **The script is permanent; the agent is Zach's call.** The script is in-repo, is
      `furlough review` (`scripts/furlough:289`) and is DEPLOYMENT.md's live review readout
      (`:28`). The agent is a machine-local plist that no doc mentions. It reads
      `get_app_store_versions.first`, so it follows whatever version is newest. With 1.3.0
      uploaded (step 52) and its review still ahead, it will earn its keep again.
    - Not in Zach's list and not touched: `~/Library/Containers/com.zachshort.furlough` and
      `~/Library/Group Containers/group.com.zachshort.furlough` (2026-09-16, the iPhone build
      installed from the App Store, step 50), `~/Library/Preferences/X9V4L6HR2R.com.zachshort.furlough.plist`,
      `~/Library/Preferences/furlough.harness.onboarding.plist`, and `~/Library/Logs/Furlough`.

    **The rest of item 1.** Steps 1–3 were already closed: DEPLOYMENT.md's rows for the
    privacy manifest (`:49`) and label (`:38`), the review notes (`:60`) and the replies
    (`:35`), and step 19 here. Step 5's premise was false (item 9 shipped in `e253fc6` without
    waiting), and step 19 already carries the corrected note. So item 1 is Done.

    **Stale lines found, not edited.** DEPLOYMENT.md's "Review state" row (`:33`) still says
    `WAITING_FOR_REVIEW`, stale since 1.2.0 went live 2026-09-15. `design/MAC-FIRST-RUN.md`
    Step 0 expects the filter `[activated enabled]` and removable from Settings > Web. It is
    `[activated disabled]` now, and Remove is offered only when the filter is on.

54. **`PASSOFF.md` consolidated: completed prompts moved to the archive.** Done 2026-09-24. Of
    the board's 35 items (36 rows, with 8 split into 8a/8b), every one but 34 was Done or
    settled as no — confirmed against the board table, not re-derived. `PASSOFF.md` had grown to
    2,363 lines carrying every full prompt ever written for it, most now unrunnable history. The
    35 prompt bodies for items 1–33 and 35 (33 and 34 never had one; 33's work is narrated in the
    board prose, 34's is `design/MAC-FIRST-RUN.md`) moved verbatim, unedited, to
    `~/Projects/archive/furlough/passoff-completed/PROMPTS.md` — a new archive folder, indexed in
    `~/Projects/archive/furlough/INDEX.md` under a new "Board history" heading. `PASSOFF.md`
    itself now holds only the intro, the board table, every correction and disproof it has
    recorded, and the session rules: 213 lines. Nothing about status changed — the board table,
    which was already the authoritative record over any individual prompt's header, is
    untouched, and no HANDOFF step citation moved. `git ls-files | xargs grep -l PASSOFF`
    (`AGENT-PRACTICES.md`, `CLAUDE.md`, `HANDOFF.md`, `design/MAC-FIRST-RUN.md`,
    `patch-notes.md`) confirmed nothing reads `PASSOFF.md` at runtime or cites a line number that
    would go stale.

55. **Anchoring by hand asks for the tag too, by default; a haptic on anchor and unanchor.**
    Done 2026-09-24. Tester feedback (Zach and a friend, a few days into daily use): the plain
    **Anchor** button locking with no ceremony felt mismatched against **Unanchor**, which has
    always needed the tag — "it just makes the routine/usage loop feel more complete." Both
    changes are opt-out settings under Anchor > Tags > Scanner/Feedback, on by default, stored
    locally like `autoArmsReader` (not synced — a per-device preference, not part of
    `Config.anchor`, so no `Shared/Core` or `Tests/Core` change was needed).
    `AppModel.requiresTagToAnchor` (default true) branches `AnchorToggleButton.drop()`
    (`Furlough/Views/AnchorView.swift`): off, or on a reader-less iPhone
    (`!TagScanner.isAvailable`), it still calls `anchor(until:)` straight through, exactly as
    before; on, it calls the new `AppModel.anchorWithTag(until:)`, which scans (mirroring
    `unanchorWithTag()`), refuses an unrecognized tag (`.wrongTag`, same message as the unanchor
    side) rather than offering to pair it, and otherwise calls `anchor(until:)`. The widget,
    Control Center, Siri and Shortcuts still call `anchor(until:)` directly and stay instant —
    none of them can hold a tag up — and a tag scanned proactively at the Anchor page (the
    existing `droppingWithTag` flow) is untouched, since that already involves a tag by the
    user's own choice. `AppModel.anchorHaptics` (default true) gates a `.sensoryFeedback(trigger:
    anchor.isAnchored)` on `AnchorPage` itself (`.success` either way, Apple Pay's blip), guarded
    on `isCurrent` so the pre-built adjacent page in the pager doesn't double it — this catches
    every path that flips `isAnchored` (the button, a tag-initiated drop, weighing anchor) in one
    place rather than wiring each call site. Both settings' UI lives in `AnchorTagsScreen`
    (`Furlough/Views/AnchorScreens.swift`): `requireTagCard` under a new "Scanner" second card,
    `hapticsCard` under a new "Feedback" section. `resetEverything()` clears both keys back to
    `true`. This amends "Settled: what Furlough is" above (2026-09-07): the drop itself is still
    tag-free at the model layer, but the hand-press default is not any more — recorded there,
    dated, rather than left to read as still current.
    **Left for Zach:** `site/src/pages/help/nfc-tags.astro` and `the-anchor.astro` still describe
    tapping Anchor as always instant/no-tag (they were not touched — public site copy is a
    bigger, more opinionated rewrite than this step's code change, and better done as its own
    pass); `README.md`'s Anchor section was updated in place since `HANDOFF.md`'s own read-first
    list points at it. Gates green (`build/build.log`, `build/test.log`); not walked on a phone.

56. **A second 1.3.0 build cut, carrying step 55, and uploaded.** Done 2026-09-24. Same version
    as step 52's build — 1.3.0 was still `unreleased`, so this step folded step 55's two changes
    into that entry's `changes` array (`release-notes.json`) rather than bumping the version,
    per `patch-notes.md` §4 ("top entry is unreleased: append, don't invent a bump"); validated
    with `python3 -m json.tool` and `scripts/version.sh` ("The notes cover this version."), then
    the full `Tests/Core` suite (811 tests, 120 suites, passed) since `ReleaseNotesTests.swift`
    holds the file to its shape. `scripts/archive.sh` (no `TESTING_TOOLS`) produced
    `build/Furlough-202609242030.xcarchive` and `build/export/Furlough.ipa` (8,703,854 bytes);
    its own checks passed (no testing-only code, every Screen Time framework entitled). Zach ran
    the upload himself, same command as step 52:
    ```
    xcrun altool --upload-app -f build/export/Furlough.ipa -t ios --apiKey L6A2R4SBXQ --apiIssuer 04f9fe5a-56e5-460f-80ac-c57e788fbdc6
    ```
    `UPLOAD SUCCEEDED with no errors`, delivery UUID `4de60180-9b4f-4747-9885-12627deed84f`,
    2026-09-24 16:44:37 ET. As with step 52, App Store *review* submission is still unstarted
    (the 13-inch iPad screenshot set), and this session did not attempt it. Also unrun: the Mac
    and site builds — nothing in step 55 touches `FurloughMac` or `site/`, so neither gate says
    anything about them.

57. **The 13-inch iPad screenshot set (section 9, named unstarted since step 52) exists now.**
    Done 2026-09-25, commit `cfdfb73`. No real iPad was on hand to shoot from and Screen Time does
    not run in the Simulator (`raw/README.md`'s reason the phone set had to come off a real
    iPhone), so each of the ten `design/store/raw/NN.png` was reflowed to iPad width with
    Higgsfield (`gpt_image_2_5`, `3:4`, quality `high`, `2k`) — same text, numbers, icons, colors,
    genuinely widened rather than a phone screenshot padded into a bigger frame. The model
    invented its own status bar with a different wrong date per frame, so the top 130px is cropped
    off each before saving to the new `design/store/raw-ipad/`, plus 70px of matched-color padding
    re-added on top after the first render showed header buttons touching the device's top edge.
    `design/store/board.html`'s `?device=ipad` slot now shows these via each frame's
    `data-ipad-src` attribute (swapped in by the script at the file's end) instead of the `.mock`
    CSS placeholder it fell back to before; the placeholder still covers a missing file.
    `scripts/store-shots-ipad.sh` (already present, untracked) rendered all ten to
    `build/store-shots-ipad/` at the required 2064×2752, no alpha channel, flattened to `.jpg`.
    **Settled 2026-09-24, recorded in `design/store/raw-ipad/README.md`: this is a stopgap, not a
    verified capture — reshoot from a real iPad when one exists**, same as the phone set's own
    rule. Zach uploaded these to App Store Connect once already from the wrong folder
    (`raw-ipad/`'s bare 1744×2276 AI output, not the composited `build/store-shots-ipad/` frames)
    and got a dimension-mismatch error; corrected the same session, no code change needed.

58. **The anchor's confirmation gained a sound to match its haptic, and a third 1.3.0 build was
    cut for this submission.** Done 2026-09-25. Zach asked whether the anchor lock/unlock
    confirmation already had a sound "like Apple Pay" alongside its haptic — it did not;
    `AppModel.anchorHaptics` (step 55, line ~3971 above) only ever gated
    `AnchorView.swift`'s `.sensoryFeedback`, despite its own doc comment already saying "the way a
    payment confirms." Added the sound half: a sibling `.onChange(of: anchor.isAnchored)` next to
    that `.sensoryFeedback` block, same `isCurrent && model.anchorHaptics` gate, calling
    `AudioServicesPlaySystemSound(1057)` — "Tink", the community-verified short single-tone
    system sound id (Apple documents no ID list for this API); it respects the mute switch like
    any other UI sound. No new setting: reused `anchorHaptics`, and updated its doc comments
    (`AppModel.swift`) and its `AnchorScreens.swift` toggle label/subtitle ("Haptic on anchor and
    unanchor" → "Haptic and sound on anchor and unanchor") so the one setting's description
    matches what it now does. Folded into 1.3.0's still-`unreleased` `changes` array in
    `release-notes.json` (`kind: "better"`) rather than bumping the version — same reasoning as
    step 56, the version has still never been submitted for review. Validated: Debug build green,
    `python3 -m json.tool` on the notes file, `scripts/version.sh` ("The notes cover this
    version."), the full `Tests/Core` suite (811 tests, 120 suites, passed — `ReleaseNotesTests`
    covers the notes-file edit; nothing here touches `Shared/Core` itself). `scripts/archive.sh`
    (no `TESTING_TOOLS`) produced `build/Furlough-202609251416.xcarchive` and
    `build/export/Furlough.ipa` (8,704,258 bytes); its own checks passed (no testing-only code,
    every Screen Time framework entitled). **Upload not run this time** — Zach said he would
    attach this `.ipa` himself rather than the `xcrun altool` steps 52/56 used. App Store *review*
    submission itself (now that step 57 closes the iPad screenshot gap) is still unstarted by any
    session.

59. **The anchor's sound/mark step aside for the system NFC sheet's own native checkmark,
    instead of a bigger custom animation.** Done 2026-09-25. After step 58 shipped, Zach asked
    for something much bigger — the anchor growing center-screen, a boat, a drop past the bottom
    edge — scoped properly first (`/scope`, doc written, gate asked) since it's a frequent,
    repeated interaction and a wrong guess is expensive. Mid-answering the gate, Zach cut to what
    he actually wanted: **Apple's own NFC-sheet checkmark**, not a custom one. Verified against
    Apple's documented behavior (not memory, after getting the system sound ID wrong once
    already this session): `TagScanner.swift`'s existing `session.alertMessage = "Tag read."`
    then `session.invalidate()` (no error) already triggers it automatically — nothing was
    broken there. The actual redundancy: every unlock and most locks go through a tag scan
    (`AppModel.unanchorWithTag()` always; `anchorWithTag()` whenever `requiresTagToAnchor` and a
    reader are both true — the default), so step 58's sound and mark were firing a *second*
    confirmation moments after the system's own. Fixed with a self-expiring signal rather than a
    manual flag (a boolean risked going stale the moment a proactive scan's "Anchor now?" dialog
    is dismissed with "Not yet"): `AppModel.lastTagScanAt` (`Date?`, `@ObservationIgnored`,
    line ~40) is stamped in the three places that call `scanner.scan(...)` — `readTag`,
    `anchorWithTag`, `unanchorWithTag` — and `AnchorView.swift`'s `.onChange(of:
    anchor.isAnchored)` skips the sound and `showConfirmMark` when that stamp is under 3 seconds
    old, letting an abandoned scan age out on its own rather than needing to be cleared on every
    cancel path. The haptic (`.sensoryFeedback` just above it) is untouched and still
    unconditional — it predates this session (step 55) and was never the redundant part; only
    the sound and the visual mark, both new this session, needed the gate. The full-scene scope
    document is not deleted — moved to
    `~/Projects/archive/furlough/anchor-confirm-animation/BRIEF.md` with a superseded note at
    its top, per R5 (a considered-and-dropped direction stays findable). Debug build green after
    this change; no archive cut yet — Zach also asked, same message, for the Anchor page's UI to
    simplify while anchored, since most of it is disabled anyway, and that is still open,
    unscoped, as of this step.

60. **Two settings rows stop pretending to be live while anchored.** Done 2026-09-25, closing
    step 59's open item. Checked which of the Anchor page's four settings rows actually still do
    something while anchored, rather than guessing: `AnchorScheduleScreen` and `AnchorScopeScreen`
    both refuse every change and show only "Unanchor with your tag to change this"
    (`AnchorScreens.swift:115`, `:486-488`) — a `NavigationLink` into a screen whose one message
    is already on the row's own detail line is a tap that goes nowhere. `AnchorTagsScreen` still
    does something (renaming or forgetting an already-paired tag stays live, only *pairing a new
    one* hides — `AnchorScreens.swift:167`) and `AnchorMacScreen` has no anchored-gate anywhere
    in it — both left exactly as they were. `AnchorView.swift`'s `settingsCard` now swaps Schedule
    and Scope for a new `lockedRow(title:detail:)` while `anchor.isAnchored` — same title and
    detail text, no `NavigationLink`, a `lock.fill` glyph instead of the chevron, one accessible
    element with a hint carrying the message the destination screen used to be the only place to
    read. `appsCard`'s per-tile "Open its rule" was left reachable on purpose — a rule set while
    anchored takes effect the moment it lifts, so that one is a real, not a dead, action. Debug
    build green. **Not yet built:** an archive carrying both this and step 59 — ask Zach first,
    same as every archive this session has.

61. **Step 59's native-checkmark claim was wrong. Reverted the same day.** Zach built step 59+60
    to his phone and tested with the ringer at max: scanning the tag showed no checkmark and
    played no sound, contradicting the "invalidate() with no error shows one automatically"
    claim step 59 built on. That claim came from web search summaries, not Apple's own page —
    `developer.apple.com/documentation/corenfc/...` is a JS-rendered SPA this session's `WebFetch`
    could not actually read, so "verified" in step 59 meant secondhand sources agreeing with each
    other, not a primary source, and they were wrong (or right about `NFCNDEFReaderSession` and
    silently inapplicable to the `NFCTagReaderSession` `TagScanner.swift` actually uses — still
    unconfirmed either way). **`AnchorView.swift`'s `.onChange(of: anchor.isAnchored)` no longer
    reads `AppModel.lastTagScanAt`** — the sound and `showConfirmMark` fire unconditionally again,
    the way step 58 originally shipped them, since there is no confirmed native confirmation to
    avoid stacking on top of. `lastTagScanAt` itself is untouched (still stamped by the three
    scan sites) in case a real fix needs it later. `TagScanner.swift` itself was not touched —
    the existing `alertMessage`/`invalidate()` call was never edited this session, so whatever
    Zach's phone is doing (or not doing) with it predates all of this. Debug build green. Not
    attempted: any change to `TagScanner.swift` itself (e.g. a short delay before `invalidate()`,
    which some secondhand reports suggest matters) — this session has no NFC hardware to verify
    against and had already been wrong once from secondhand sources; that one needs Zach's phone
    to iterate on, not another guess.

62. **Tried the delay, on Zach's "try it" — `tagReaderSession(_:didDetect:)` now waits 500ms
    before `invalidate()`.** Done 2026-09-25, unverified, explicitly experimental. Hypothesis:
    invalidating in the same tick as detection may leave CoreNFC no time to animate a checkmark
    before the sheet is told to close. `finish(.success(identifier))` — the app's own state
    change — now runs *before* the sleep, so "press answers at once" holds regardless of whether
    this helps; only the system sheet's own dismissal moved later. `Task { try await
    Task.sleep }` and `DispatchQueue.main.asyncAfter` were both tried first and both refused to
    compile under Swift 6 strict concurrency (`sending 'session' risks causing data races` —
    `NFCTagReaderSession(..., queue: nil)` delivers this delegate callback on a private queue,
    not the main actor, confirmed by the compiler's own isolation note, so handing `session` to a
    main-actor closure is a real cross-isolation violation, not a false positive to silence).
    Settled on `Thread.sleep(forTimeInterval: 0.5)`, staying on that same private queue the whole
    time rather than crossing into another one. Debug build green. **Needs Zach's phone**: build
    to device, then from the Anchor page either drop the anchor (if `requiresTagToAnchor` is on)
    or weigh it — does the system NFC sheet now show a checkmark, and is there any sound? Report
    back either way; if this doesn't do it, the 500ms figure was a guess and the next move is
    probably reading Apple's actual documentation some other way (Xcode's offline docs, a
    physical dev's blog with a working code sample) rather than tuning the number further blind.

63. **Settled 2026-09-25: there is no native checkmark to chase. `TagScanner.swift` reverted to
    exactly its pre-step-62 form.** Zach's phone: `alertMessage` ("Tag read.") displays correctly
    even with the delay, so the sheet is genuinely responding to this code — and still no
    checkmark, no sound. That the text updates but nothing else does is real evidence against a
    timing theory; a checkmark that only needed a beat to animate would still be a checkmark, not
    nothing. Checked one real production NFC SDK whose whole UX is tap-to-confirm
    (`Tangem/tangem-sdk-ios`, a hardware-wallet reader — `NFCReader.swift`, fetched and read
    directly, not summarized): it does not attempt a success checkmark either, despite having
    every reason to want one if the API made it easy. Likeliest explanation, unconfirmed but
    consistent with everything above: the Brick screenshot Zach sent earlier this session (a
    circle icon, "Ready to Scan," "Tap the top of your phone to your Brick," an "or hold" hint,
    a styled Cancel button) is not Apple's system NFC sheet at all — that sheet's own layout does
    not support a custom title plus subtitle plus a second hint line, so what Brick shows is
    almost certainly its own drawn screen made to resemble one. There was nothing to unlock via
    API because the reference was never native to begin with. `TagScanner.swift`'s
    `didDetect tags:` is back to its original three lines (`git diff` against the commit before
    step 62 is empty); step 61's revert (sound and mark unconditional, no `lastTagScanAt` gate)
    stands as the real, working confirmation — `AnchorConfirmMark`, `Furlough/Sounds/ba-dink.wav`,
    the existing haptic. Debug build green. `lastTagScanAt` on `AppModel` is unused dead weight
    now (nothing reads it) but left in place rather than pulled mid-conversation; worth removing
    next time this file is touched for something else, not on its own.

64. **The anchored page is a different, much smaller page now, not the free page with things
    disabled.** Done 2026-09-25, replacing step 60's approach rather than extending it — Zach
    asked for this after seeing step 60 land, previewed first (a standalone `swiftc` render, the
    established way to check a `Shared/UI`-style view without a device), approved the direction,
    then set the one rule for what's on it: "only show information if it is actually useful."
    `AnchorPage.setUpPane` now branches on `anchor.isAnchored` (`AnchorView.swift:162`): free
    shows exactly what it always has (`stateCard`, `appsCard`, `settingsCard` — step 60's locked
    rows still apply there); anchored shows the new `anchoredPane` instead of any of them.
    `anchoredPane` is: a new `AnchoredHero` (bare ember `AnchorShape`, glowing, ringed by a faint
    full circle plus a brighter arc that rotates slowly and continuously for as long as the page
    is up — under Reduce Motion it holds still), the existing `stateLine` text, and up to three
    pills, each gated on being genuinely true right now rather than always shown: "View held
    apps" / "View exceptions" only if `!anchor.kinds.isEmpty` (opens `appsCard` unmodified, in a
    sheet — nothing about that card changes while anchored, so nothing needed rebuilding), a
    "Devices" pill only if `model.link.isLinked && !model.devices.isEmpty` (a link to *another*
    device has to actually exist — Zach's own example, "devices doesn't matter if they don't have
    a link"), and a "Lifts H:MM" pill only if `anchor.until != nil`. All three absent shows just
    the hero and the state line, which is deliberate, not an empty state to fill.
    `AnchorToggleButton` gained `heroStyle: Bool = false`: true renders `AnchoredHero()` as the
    button's label instead of the small "Unanchor" pill, same `unanchor()` underneath either way
    — tapping the hero *is* unanchoring, standing in for a 4th button Zach's list never mentioned
    (flagged back to him as a design call rather than assumed silently). Locking's own visual
    confirmation is now this hero growing in via spring on appear, not the small
    `AnchorConfirmMark` badge from step 58 — that badge's glyph (`stateCard`) is no longer even
    on screen the instant `isAnchored` flips true, since the page swaps to `anchoredPane` in the
    same render pass. Unanchoring still lands back on the free page and the small badge, so
    nothing about step 58/61 needed touching — the haptic/sound/mark trigger in
    `AnchorView.swift`'s `.onChange(of: anchor.isAnchored)` is untouched, it just now only ever
    visibly matters for one direction. Debug build green. **Needs Zach's phone, still unverified
    on a device**: lock the anchor and watch the hero grow in and the ring start turning; check
    each pill appears/disappears correctly against its own condition (easiest to test "Devices"
    by toggling whether this phone is linked, since that one depends on state that isn't the
    anchor itself); confirm the hero itself lifts the anchor when tapped, same tag ritual as the
    old "Unanchor" pill if `requiresTagToAnchor`-equivalent applies to unanchor (it always does —
    see step 55, "The only unblock in Furlough").

65. **`AnchorConfirmMark` clipped to its own tile; the confirmation sound replaced after Zach
    heard nine synthesized candidates; the haptic switched to one he can actually feel.** Done
    2026-09-25, on Zach's phone-tested feedback after step 64. Three separate fixes:
    - **The overflow bug**: `ringScale`'s entrance spring (`dampingFraction: 0.68`) overshot past
      1.0 at its peak, the ordinary way an underdamped spring bounces — drawing the mark larger
      than the 44pt tile it sits on for a frame. Damping raised to `1` (critically damped, no
      overshoot) and `.clipShape(Circle())` added as a hard guarantee regardless of how the
      spring is ever tuned again.
    - **The sound**: Zach said the original `ba-dink.wav` (step 58) lacked character. Nine more
      candidates followed, across genuinely different synthesis techniques, not just new
      melodies — plain two/three-tone chimes, a metallic anchor-drop (noise thud + ring), a soft
      shimmer bell, a ship's-bell watch pattern (paired dings, inharmonic partials) alone and
      with a chain-link texture, a Pirates-of-the-Caribbean-style horn fanfare, a punchier double
      stab, and two takes adding soft-clip distortion plus a crude algorithmic reverb for
      "space" once melody alone stopped moving the needle. None of the fuller ones won: **the
      three-note ascending chime from the second batch (`A-three-note-chime.wav`) is what
      shipped**, renamed on the way in — `Furlough/Sounds/ba-dink.wav` → `anchor-confirm.wav`
      (a name that describes what it's for, not what any one version of it sounds like, so it
      doesn't go stale the next time the sound changes). `AnchorConfirmSound.id` in
      `AnchorView.swift` points at the new filename; `xcodegen generate` re-run after the file
      swap (rule 3). Honest note for later: pure additive-sine synthesis, even with distortion
      and reverb layered on, has a real ceiling well below an actual recorded/sampled instrument
      — if "more character" comes up again, a licensed or recorded sample is the next real step,
      not another synthesis pass.
    - **The haptic**: Zach reported feeling nothing from the existing `.sensoryFeedback(.success)`
      (step 55) — SwiftUI's `.success` is a light, notification-style double-tap, easy to miss.
      Replaced with `UIImpactFeedbackGenerator(style: .heavy).impactOccurred()`, called directly
      inside the same `.onChange(of: anchor.isAnchored)` block that already plays the sound and
      shows the mark, rather than as a separate `.sensoryFeedback` modifier — one trigger, one
      gate (`isCurrent && model.anchorHaptics`), all three confirmations. Needs `import UIKit`,
      added to `AnchorView.swift`. Haptics need no entitlement, no Info.plist key, no permission
      prompt — confirmed for Zach when he asked, this is not like NFC.

    Debug build green. **Needs Zach's phone**: does the mark now stay inside its tile on every
    lock/unlock, is the new chime actually more characterful, and — the one most likely to
    surprise — does `.heavy` impact read as a real, felt vibration rather than the same
    not-quite-there tap `.success` gave him.

66. **A fourth 1.3.0 build cut and uploaded, carrying the anchored-page redesign (steps 59–65)
    to TestFlight for the first time.** Done 2026-09-26. Everything from step 59 on — the
    reverted NFC-checkmark chase, the anchored page's redesign into a small hero-and-pills view
    (60, 64), and today's overflow/sound/haptic fixes (65) — had only ever been Debug-build or
    `swiftc`-preview verified; none of it had reached an archive or a device. Asked Zach directly
    rather than guessing whether to hold for his own on-device pass first: he chose to cut and
    upload now, so TestFlight (him and one friend) is this redesign's first real device.
    Before cutting, added the one release note the four prior builds' worth of changes were
    missing: `release-notes.json`'s 1.3.0 entry had step 58's "plays a sound" line but nothing
    about the anchored page itself becoming a different, smaller page — a `better`/`iphone`
    entry, "The anchored page shows only what's true", added ahead of the archive so the shipped
    build's own Help > What's New carries it. Validated first: a fresh Debug build
    (`** BUILD SUCCEEDED **`) and the full `Tests/Core` suite (811 tests, 120 suites, passed,
    twice — once before the notes edit, once after) rather than trusting the "Debug build green"
    scattered across seven separate steps. `scripts/archive.sh` (no `TESTING_TOOLS`) then produced
    `build/Furlough-1.3.0-testflight.log` and `build/export/Furlough.ipa` (8,832,499 bytes, build
    `202609261639`); its own checks passed — no testing-only code, every Screen Time framework
    entitled, only the two pre-existing Apple-tooling warnings from step 52. **Built from the
    working tree, not a commit**: `HEAD` was still `d1e5941` at archive time, with step 65 and the
    new release-notes bullet both uncommitted underneath it — flagged to Zach before he uploaded,
    since nothing else uncommitted that session (site/Mac changes) touches the iOS app. Claude
    Code's auto mode refused the `xcrun altool` upload itself, same as steps 52/56 (see the memory
    note on the App Store Connect write block); Zach ran it:
    ```
    xcrun altool --upload-app -f build/export/Furlough.ipa -t ios --apiKey L6A2R4SBXQ --apiIssuer 04f9fe5a-56e5-460f-80ac-c57e788fbdc6
    ```
    `UPLOAD SUCCEEDED with no errors`, delivery UUID `4588115d-f4ec-4e1e-9a1c-6c15601ed2a1`,
    2026-09-26 13:12:32 ET. It appears in TestFlight once Apple finishes processing — not
    confirmed read back from the ASC API this session. App Store *review* submission is still a
    separate, unstarted step, same as every build since 52.


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
