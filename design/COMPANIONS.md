# Hand-off: one habit, one row — linking an app to its website

Written 2026-09-08 by the session that rebuilt the usage page, for the session that will link
companions. Zach runs Furlough (a personal iOS Screen Time blocker; see `HANDOFF.md` and
`design/DESIGN.md`). Read those two, then this. Ask Zach when a decision is his; there are four
questions at the end.

## The one-line goal

Blocking the YouTube app and leaving youtube.com open is the gap everyone finds a week later,
from a browser tab. Furlough should offer the other half while the first is still in hand — and
when the offer is taken, the two halves must become **one thing**: one row, one rule editor, one
schedule, one budget, one removal delay. The app is the face; the website rides along.

## The honest evaluation Zach asked for

### What is most convenient?

One row called YouTube. Add either half, be asked once whether to cover the other, say yes, and
never think about it again. Two doors into one habit should not cost two rules to close, and a
budget spent in the browser should be a budget spent.

### Are we doing it?

**The offer: yes, and it is good work.** `Shared/Core/Companions.swift` is a table of 33 pairs
with name/bundle-ID/host matching, subdomain rules, Catalyst normalisation, and lookups in both
directions (`missingHosts`, `missingApp`). `Shared/UI/CompanionNudge.swift` shows it on a target
whose other half is absent, with Add and Not now, and `AppModel.companionDismissed` remembers a
dismissal so the nudge is not a nag. Tests in `Tests/Core/CompanionsTests.swift`. Keep all of it.

**The link: no. This is the whole job.** Accepting the offer calls the ordinary add path and
produces a **second, independent `Target`**. What Zach then has:

* two rows in the Home list, two hero pages in the pager, two status chips
* two rule editors, and no way to keep them in step but typing the same windows twice
* **two budgets** — 45 minutes on the app *and* 45 in the browser, so the rule is 90
* two removal delays, and two things to remember to remove
* two entries in an exported setup

`Policy.decide` (`Shared/Core/Policy.swift:265`) switches on a single `target.kind`, and
`Monitoring.include` (`Furlough/Model/Monitoring.swift`) builds one `DeviceActivityEvent` per
target from that one kind. Everything downstream assumes one target is one kind. That assumption
is the bug, and it is a small one to change — see below.

### Can we do the convenient thing?

**Mostly yes, and better than I expected.** The load-bearing fact, verified in the iOS 26.5 SDK
rather than assumed (`DeviceActivity.swiftinterface`):

```swift
public init(applications: Set<ApplicationToken> = [],
            categories: Set<ActivityCategoryToken> = [],
            webDomains: Set<WebDomainToken> = [],
            threshold: DateComponents,
            includesPastActivity: Bool)
```

**One event takes an app token and a web domain token under one threshold.** So a linked pair
genuinely shares a budget: 45 minutes across the app and the site together, counted by iOS, with
no arithmetic of our own. `Monitoring.include` already names the event by target id
(`ActivityNaming.budgetEvent(targetID:minutes:)`), so a linked target is still one event with one
name and the monitor extension needs no change at all.

### Where we cannot, and how close we get

Three walls, none of them movable:

1. **An app token can only be minted inside Apple's `FamilyActivityPicker`.** So
   website → app can never be one tap. The best possible is: name the app, open the picker,
   link whatever comes back.
2. **A typed host (`.host`) has no token, and a threshold event needs one.** A site added by
   name can share the windows but cannot draw down the budget — browser time is invisible.
   `Monitoring.include` already documents this for standalone hosts.
3. **A Screen Time token says nothing about what it is.** Today the name arrives only when the
   shield first covers the thing (`SharedStore.learnName`), which is why the nudge arrives late
   and why Zach's Anchor screen says "This app and This app".

Wall 3 is much lower than the code currently assumes, on the path Zach is on. With data access
(iOS 26.4, `UsageReader.hasDataAccess`), `FamilyActivityData.shared.installedApplications` hands
back objects carrying **both `bundleIdentifier` and `token`**, and `visitedWebDomains` carries
both `domain` and `token`. `UsageReader.encodedKinds()` already walks exactly these lists — I
wrote it this session for the usage cards. That gives two things this feature wants:

* **a token → bundle identifier map**, so a picked app can be matched against `Companions` the
  moment it is added, not a week later once the shield has learned a name;
* **a domain → `WebDomainToken` map**, so a host string like "youtube.com" can become a *real
  tokenised* `.webDomain` **without the picker** — for any site the person has actually visited.

That last one is the difference between a shared budget and windows-only, so it is worth
verifying on the device early. **Unverified:** whether a token from `visitedWebDomains` shields
and counts identically to one minted by the picker. It is the same type, so it should; prove it
before designing around it.

So the ladder, best rung first. Build all three; which one a person gets is decided at runtime.

| | Situation | What Furlough can do | Shared budget |
|---|---|---|---|
| **A** | Data access, and the site has been visited | Add the site as a tokenised `.webDomain`, linked, no picker | **Yes** |
| **B** | No data access, or the site never visited | Add the site as a typed `.host`, linked | No — windows only |
| **C** | Website added first, app missing | Nudge → picker → link what comes back | Yes, once picked |

Rung B is the honest-failure rung and its card must say so in one line, not pretend. Something
like: *"Blocked in the browser too, on the same schedule. Browser time does not count against
the budget — nothing on iOS can count a site added by name."*

## What to build

### 1. The model (`Shared/Core/Models.swift`)

```swift
struct Target {
    var kind: TargetKind          // the face: the app, where there is one
    var also: [TargetKind]?       // the other doors into the same thing
    var kinds: [TargetKind] { [kind] + (also ?? []) }
}
```

`also` is optional for the same reason `systemName` and `utilityLevel` are: a synthesised
`init(from:)` demands every non-optional key, and state Zach already has on his phone has none.
Read it through `kinds` everywhere.

**The face is the app.** When a website target gains an app half, the app becomes `kind` and the
site moves into `also`, so the row shows the app icon and Apple's app name. That is Zach's ask
and it is also the only half with real artwork.

### 2. Enforcement — the whole of it, and it is short

* `Policy.decide` (`Policy.swift:265`): iterate `target.kinds`, not `target.kind`. One status
  per target, applied to every kind. Windows, budget, exhaustion and anchoring then cover both
  halves for free, because they were only ever computed per target.
* `Monitoring.include`: gather tokens across `kinds` into **one** event — applications into
  `applications:`, web domains into `webDomains:`. Skip `.host` (it has no token) and `.category`.
* `Config.anchorWarning` and `AnchorProfile.contains`: match on any of `kinds`.
* `Config.target(forHost:)` (`Models.swift:533`): search `kinds`.

### 3. Everything that iterates kinds today

`grep -rn "\.kind" --include='*.swift'` — the counts that matter: `RuleEditorView` 12,
`AppModel` 11, `ConfigImport` 6, `Models` 5, `AnchorView` 5, `Policy` 4, `HomeView` 4,
`UsageView` 3, `ConfigExport` 1. Most are `isCategory` / `isHost` checks that stay as they are.
The ones that must change are the ones that build sets from targets:
`AppModel.pickerSelection` and `AppModel.applyPicker`.

**`applyPicker` is the sharp edge.** It schedules a removal for every target whose kind it does
not see in the selection. A linked `.host` is already excluded by `!target.kind.isHost`, but a
linked *tokenised* web domain is not — so unless `applyPicker` checks `kinds`, the first trip
through the picker after linking will schedule the removal of every linked site. Write the test
before the code.

### 4. The offer, and taking it

* Match at add time where possible: resolve a fresh token to its bundle identifier via
  `installedApplications`, then `Companions.pair(forBundleID:name:)`. Fall back to the existing
  learned-name path everywhere else. Keep `CompanionNudge` for the fallback; it is good.
* Accepting adds to `also` on the existing target rather than appending a new one.
* Adding a half is a **tightening** — more is blocked — so it applies now. Removing one is a
  **loosening** and waits out `Policy.classify`. Do not carve an exception; a linked site is a
  blocked site.

### 5. The surfaces

* **Home row**: one row, app icon and name, with a small globe or "+ youtube.com" beside the
  rule line. Not a second row, not a second hero page.
* **Rule editor**: one editor. A "Also blocks" card listing the linked halves with a way to
  unlink each (loosening → delay, say so).
* **Usage page**: `UsageAnalysis` keys on bundle id and `web:` domain separately. A linked pair
  should rank as one, summing both histograms — otherwise the redesigned cards will show YouTube
  twice, which is the bug the usage hand-off spent a whole section killing.
* **Export/import**: `ConfigExport`/`ConfigImport` must round-trip `also`; a file written before
  this must still import.

## The second job: "This app and This app **is** worth having around"

From Zach's Anchor screenshot, 2026-09-08. Two separate bugs in one sentence.

**Verb agreement.** `UtilityText.anchoring` (`Shared/Core/Utility.swift:131`) joins names with
`list(_:)` and hands the joined string to `fallback(name:utility:)`, which hardcodes singular
verbs for all three tiers:

* `.essential` — "\(name) **is** how this phone does its job."
* `.idle` — "\(name) **goes** the moment you anchor."
* default — "\(name) **is** worth having around."

`blocking(name:...)` is fine — it is always one name. Only `anchoring` can be plural. Pass the
count (or a `plural: Bool`) into `fallback` and pick the verb. **The house pattern already
exists**: `Shared/UI/ImportReview.swift:58` does exactly this inline. Match it. Add a test —
`Tests/Core/UtilityTests.swift` is already there.

Also check the `detail` path: `AppUtility.suggestion(for:)?.detail` is written about one app
("TikTok is designed to be hard to put down") and `anchorWarning` will happily use it as the
sentence for several. Either suppress `detail` when there is more than one name, or only use it
when it belongs to all of them.

**The missing names.** "This app" is `Target.defaultName` before the shield has ever covered
that target. Two ways out, and this is a question for Zach:

* draw the name with `Label(token)` in the view, the way `TokenName` already does on Home — real
  and always right, but it cannot be put in a `String`, so it cannot be interpolated into these
  sentences at all; it would mean rebuilding the nudge as a view that composes tokens with text;
* on the data-access path, resolve the token to a bundle identifier and read the display name out
  of the `Companions` / `AppUtility` tables — a real name, in a `String`, for anything in the
  tables, and "This app" only for things that are in neither.

## Acceptance

* Adding the YouTube app and accepting the offer leaves **exactly one row** on Home, one hero
  page, one rule editor, one status chip.
* One budget: with both halves tokenised, 45 minutes is 45 across app and site together — check
  the registered event in the log (`registered day + N window(s), M budget event(s)`) and then on
  the phone by spending the budget in Safari and watching the app shield.
* Where the budget cannot be shared (rung B), the editor says so in one plain line.
* A trip through the picker after linking schedules **no** removals.
* The anchor covers both halves.
* Export/import round-trips a linked target, and a setup file written before this still imports.
* The usage page ranks a linked pair once, summing both halves.
* `UtilityText.anchoring` agrees in number for one, two and three names, at every tier.
* `FurloughCoreTests` pass; new pure logic has tests.

## How to build, test, and put it on the phone

XcodeGen output: run `xcodegen generate` after adding a file, and again if a sibling session
deletes one — a stale project reference fails the build with "Build input file cannot be found".
Grep build logs rather than trusting a wrapper's exit code.

```
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedDataTests > build/test.log 2>&1; grep -E "error:|✘|Test run" build/test.log | sort -u
```

```
xcodebuild -project Furlough.xcodeproj -scheme Furlough -configuration Debug -destination 'platform=iOS,id=00008150-0010050A0247801C' -allowProvisioningUpdates -derivedDataPath build/DerivedData build > build/build.log 2>&1; grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" build/build.log | grep -v appintentsmetadata | sort -u
```

```
xcrun devicectl device install app --device 00008150-0010050A0247801C build/DerivedData/Build/Products/Debug-iphoneos/Furlough.app && xcrun devicectl device process launch --terminate-existing --device 00008150-0010050A0247801C com.zachshort.furlough
```

Nothing on the Mac sees the phone's screen: tell Zach exactly what to open and wait for his
screenshots (HEIC; `sips -s format png`).

## Traps this session hit

* **The phone drops off CoreDevice constantly.** `devicectl list devices` says `unavailable`,
  and `xcodebuild` then fails with "Unable to find a destination matching the provided
  destination specifier" — which is *not* a `BUILD FAILED` line, so a grep for that alone reports
  nothing and looks like success. `devicectl device info details` returns success even when the
  device is unavailable; do not use it as a readiness check. Grep the `available` state instead,
  or build to `generic/platform=iOS` (still device-signed, still installable) and retry only the
  install.
* **`FamilyActivityData` queries are unreliable.** `installedApplications` answers, comes back
  empty, or throws, and you cannot tell which in advance. Ask again rather than caching the first
  answer — but stop as soon as it answers at all, because an answer that resolves only some keys
  is it working, and the rest are simply not installed. See `UsageView.nameApps`.
* **`FamilyActivityData` and its arrays are not Sendable.** Read them in an `@concurrent`
  function and pass results back encoded; `TargetKind` is Codable. See `UsageReader.encodedKinds`.
* **One `TokenTile` constant does not fit every kind.** Apple's icon view is 32 pt for all of
  them, but an app icon fills 0.655 of it while a category runs edge to edge. Only scale past
  padding you have measured.
* **Never run `git commit`.** Print `git add <exact files>` and `git commit -m "..."` (lowercase,
  no `Co-Authored-By`, no `🤖 Generated with`) and let Zach run them. Sibling Claude sessions edit
  this repo at the same time, so stage only your own files.

## Questions for Zach before building

1. **Does a linked site get its own nickname and tier, or does it inherit the app's?** One tier
   is simpler and is probably right — it is one habit — but it means anchoring the pair warns
   with the app's tier for both.
2. **When the budget cannot be shared (rung B, a typed host), is that acceptable, or should
   Furlough refuse to link and keep them separate so at least the site gets its own budget?**
   Nothing counts a typed host at all, so "its own budget" would be zero enforcement either way —
   but he should choose knowingly.
3. **Should linking be retroactive?** He may already have YouTube and youtube.com as two targets.
   Offer to merge them, or only link from now on?
4. **On the nudge names:** the `Companions`-table route gives a real name in a `String` today, for
   anything in the table. Is "This app" acceptable for anything outside it, or should the nudge be
   rebuilt as a view that composes `Label(token)` with text so it is always right?
