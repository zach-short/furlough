import Foundation
import Testing

/// One habit, one row: an app and the website it is also at as a single target. Rests on
/// everything downstream reading `Target.kinds` rather than `Target.kind`, so one status,
/// schedule, budget and removal delay cover both halves — and pins what must *not* follow: the
/// face can never be unlinked away, and linking must never shorten a wait.
///
/// Builds for macOS, so a target here is a bundle identifier or host, via the shared engine
/// (`Policy.decide`, `Config.target(host:)`, `anchorWarning`, the pending queue). The iOS-only
/// half (`Monitoring.include`, combining tokens into one `DeviceActivityEvent`) can't be reached
/// from a test bundle and is checked on the phone.

// MARK: - The model

@Suite("A target with more than one door")
struct LinkedTargetModelTests {
    func pair() -> Target {
        var target = Target(kind: .macApp(bundleID: "com.google.Chrome"), nickname: "YouTube", rule: .unrestricted)
        target.also = [.host("youtube.com")]
        return target
    }

    @Test("Every door is readable, the face first")
    func kindsReadFaceFirst() {
        let target = pair()
        #expect(target.kinds == [.macApp(bundleID: "com.google.Chrome"), .host("youtube.com")])
        #expect(target.isLinked)
        #expect(target.covers(.host("youtube.com")))
        #expect(target.covers(.macApp(bundleID: "com.google.Chrome")))
        #expect(!target.covers(.host("vimeo.com")))
    }

    @Test("An unlinked target is exactly what it always was")
    func unlinkedIsUnchanged() {
        let alone = makeTarget("TikTok", rule: .unrestricted)
        #expect(alone.kinds == [alone.kind])
        #expect(!alone.isLinked)
        #expect(alone.also == nil)
    }

    @Test("Both halves are named, and the app half is the face")
    func facesAndHalves() {
        let target = pair()
        #expect(target.coversApp)
        #expect(target.coversSite)
        #expect(target.hosts == ["youtube.com"])
        // `host` is still the face's host and so is empty here; `hosts` is the one to read.
        #expect(target.host.isEmpty)
        #expect(target.hasHost)
    }

    // A typed site alone has no budget event; linked to an app it shares that app's real one.
    @Test("A linked pair has a real budget; the typed half is the part nothing counts")
    func countedAndUncounted() {
        let target = pair()
        #expect(target.isCounted)
        #expect(target.uncountedHosts == ["youtube.com"])

        let siteAlone = makeTarget("Reddit", rule: .unrestricted)
        #expect(!siteAlone.isCounted)
        // Whole target uncounted: the editor says so with `hostBudgetNote` instead.
        #expect(siteAlone.uncountedHosts.isEmpty)
    }
}

// MARK: - Lookups

@Suite("Finding a target through any of its doors")
struct LinkedLookupTests {
    func config() -> Config {
        var app = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        app.also = [.host("youtube.com")]
        return makeConfig([app, makeTarget("Reddit", rule: .unrestricted)])
    }

    @Test("A linked site answers through the app's row, subdomains included")
    func hostFindsTheLinkedRow() {
        let config = config()
        #expect(config.target(host: "youtube.com")?.displayName == "YouTube")
        #expect(config.target(host: "m.youtube.com")?.displayName == "YouTube")
        #expect(config.target(host: "reddit.com")?.displayName == "Reddit")
        #expect(config.target(host: "vimeo.com") == nil)
    }

    // A subdomain row beats a whole-domain row, whichever happens to be linked.
    @Test("The most specific host wins, linked or not")
    func longestHostWins() {
        var app = Target(kind: .macApp(bundleID: "com.google.ios.youtubemusic"), nickname: "YT Music", rule: .unrestricted)
        app.also = [.host("music.youtube.com")]
        let config = makeConfig([makeTarget("YouTube", rule: .unrestricted), app])
        #expect(config.target(host: "music.youtube.com")?.displayName == "YT Music")
        #expect(config.target(host: "youtube.com")?.displayName == "YouTube")
    }

    // Stops the picker/import adding a second row for an already-covered half.
    @Test("A linked kind is already managed, so nothing adds it twice")
    func kindLookupSeesLinkedHalves() {
        let config = config()
        #expect(config.target(kind: .host("youtube.com"))?.displayName == "YouTube")
        #expect(config.target(kind: .macApp(bundleID: "com.google.ios.youtube"))?.displayName == "YouTube")
        #expect(config.target(kind: .host("vimeo.com")) == nil)
    }
}

// MARK: - Enforcement

@Suite("One rule, every door")
struct LinkedEnforcementTests {
    /// An 8–10 PM window on the pair, and the clock inside it.
    func config(windows: [TimeWindow]) -> Config {
        var app = Target(
            kind: .macApp(bundleID: "com.google.ios.youtube"),
            nickname: "YouTube",
            rule: Rule(windows: windows, dailyBudgetMinutes: 45)
        )
        app.also = [.host("youtube.com")]
        return makeConfig([app])
    }

    @Test("Blocked out of hours, both halves at once")
    func bothHalvesShielded() {
        let config = config(windows: [window(20 * 60, 22 * 60)])
        let decision = Policy.decide(config: config, runtime: RuntimeState(), now: at(8, 15), calendar: cal)
        #expect(decision.blockedApps == ["com.google.ios.youtube"])
        #expect(decision.blockedHosts == ["youtube.com"])
        #expect(decision.isAnythingShielded)
    }

    @Test("Open in hours, both halves at once")
    func bothHalvesOpen() {
        let config = config(windows: [window(20 * 60, 22 * 60)])
        let decision = Policy.decide(config: config, runtime: RuntimeState(), now: at(8, 21), calendar: cal)
        #expect(decision.blockedApps.isEmpty)
        #expect(decision.blockedHosts.isEmpty)
    }

    // One status per target; linking only widens what it applies to.
    @Test("A spent budget shuts the browser half as well")
    func exhaustionCoversBothHalves() {
        let config = config(windows: [window(20 * 60, 22 * 60)])
        var runtime = RuntimeState()
        let id = config.targets[0].id
        runtime.exhausted[id.uuidString] = Policy.dayKey(at(8, 21), calendar: cal)
        let decision = Policy.decide(config: config, runtime: runtime, now: at(8, 21), calendar: cal)
        #expect(decision.blockedApps == ["com.google.ios.youtube"])
        #expect(decision.blockedHosts == ["youtube.com"])
    }

    @Test("Anchoring either half anchors the whole thing")
    func anchorReachesThroughLinkedHalves() {
        var config = config(windows: [window(0, Furlough.minutesPerDay)])
        // Only the website is in the anchor, and the app is open all day by its rule.
        config.anchor.kinds = [.host("youtube.com")]
        config.anchor.isAnchored = true
        #expect(config.isAnchored(config.targets[0], at: at(8, 21)))
        let decision = Policy.decide(config: config, runtime: RuntimeState(), now: at(8, 21), calendar: cal)
        #expect(decision.statuses[config.targets[0].id] == .anchored)
        #expect(decision.blockedApps == ["com.google.ios.youtube"])
        #expect(decision.blockedHosts == ["youtube.com"])
    }

    @Test("An anchor warning speaks for a row held by its website half")
    func anchorWarningSeesLinkedHalves() {
        var config = config(windows: [window(0, Furlough.minutesPerDay)])
        config.targets[0].utilityLevel = .useful
        config.anchor.kinds = [.host("youtube.com")]
        let warning = try! #require(config.anchorWarning)
        #expect(warning.names == ["YouTube"])
    }
}

// MARK: - Taking a half back off

@Suite("Unlinking a half")
struct UnlinkTests {
    func state() -> SharedState {
        var app = Target(
            kind: .macApp(bundleID: "com.google.ios.youtube"),
            nickname: "YouTube",
            rule: Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 45)
        )
        app.also = [.host("youtube.com"), .host("m.youtube.com")]
        return makeState([app])
    }

    @Test("The named half comes off and the rest of the row is untouched")
    func unlinkDropsOneHalf() {
        var state = state()
        let id = state.config.targets[0].id
        Policy.apply(PendingChange(kind: .unlink(targetID: id, kind: .host("youtube.com")), effectiveAt: at(9)), to: &state.config)
        #expect(state.config.targets[0].also == [.host("m.youtube.com")])
        #expect(state.config.targets[0].kind == .macApp(bundleID: "com.google.ios.youtube"))
        #expect(state.config.targets[0].rule?.dailyBudgetMinutes == 45)
    }

    @Test("The last half off leaves no empty list behind")
    func lastHalfClearsAlso() {
        var state = state()
        let id = state.config.targets[0].id
        for host in ["youtube.com", "m.youtube.com"] {
            Policy.apply(PendingChange(kind: .unlink(targetID: id, kind: .host(host)), effectiveAt: at(9)), to: &state.config)
        }
        #expect(state.config.targets[0].also == nil)
        #expect(!state.config.targets[0].isLinked)
    }

    // Unlinking the face would leave the target with no identity, not just a looser one — refused
    // both when queued and when performed, since an edit can swap the face while queued.
    @Test("The face is never unlinked away")
    func faceSurvives() {
        var state = state()
        let id = state.config.targets[0].id
        let face = state.config.targets[0].kind
        Policy.apply(PendingChange(kind: .unlink(targetID: id, kind: face), effectiveAt: at(9)), to: &state.config)
        #expect(state.config.targets[0].kind == face)
        #expect(state.config.targets[0].also?.count == 2)
    }

    @Test("A queued unlink reads as what it takes away")
    func pendingCardWordsIt() {
        let state = state()
        let id = state.config.targets[0].id
        let change = PendingChange(kind: .unlink(targetID: id, kind: .host("youtube.com")), effectiveAt: at(9))
        #expect(change.targetID == id)
        let delta = PendingText.delta(for: change, in: state.config, calendar: cal)
        #expect(delta.now.contains("youtube.com"))
        #expect(delta.becomes == "youtube.com no longer blocked")
        let described = PendingNotifications.describe(change, in: state.config, calendar: cal)
        #expect(described == "youtube.com stops being blocked with YouTube.")
    }
}

// MARK: - The picker

/// Why the rule is pure rather than a line inside `applyPicker`: the picker reads a selection as
/// the whole truth, so anything it cannot see looks unpicked, and unpicked means removed.
@Suite("What a trip through the picker may remove")
struct PickerRemovalTests {
    let app = TargetKind.macApp(bundleID: "com.google.ios.youtube")
    let other = TargetKind.macApp(bundleID: "com.zhiliaoapp.musically")

    func linked() -> Target {
        var target = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        target.also = [.host("youtube.com")]
        return target
    }

    @Test("An app left out of the selection is removed, as it always was")
    func unpickedAppIsRemoved() {
        let plain = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), rule: .unrestricted)
        #expect(Policy.picker(removes: plain, selected: [other]))
        #expect(!Policy.picker(removes: plain, selected: [app]))
    }

    // Shipped once already: a typed site is in no selection, so the picker would remove every one.
    @Test("A site added by name is in no selection and is never removed")
    func typedHostIsNeverRemoved() {
        let site = makeTarget("Reddit", rule: .unrestricted)
        #expect(!Policy.picker(removes: site, selected: []))
        #expect(!Policy.picker(removes: site, selected: [app, other]))
    }

    // A linked pair's typed half is invisible to the picker; judged on that alone every trip
    // would remove every pair, so the row survives on its app half instead.
    @Test("A linked pair survives on its app half")
    func linkedPairSurvivesOnItsAppHalf() {
        #expect(!Policy.picker(removes: linked(), selected: [app]))
        #expect(!Policy.picker(removes: linked(), selected: [app, other]))
    }

    @Test("A linked pair whose app is unpicked goes, halves and all")
    func unpickingTheAppTakesTheRow() {
        #expect(Policy.picker(removes: linked(), selected: [other]))
        #expect(Policy.picker(removes: linked(), selected: []))
    }

    // Breaking a pair is a loosening that waits out the delay; the picker must not do it as an
    // unconfirmed whole-row removal.
    @Test("The picker cannot break a pair, only remove the whole of it")
    func pickerCannotUnlink() {
        var bothTokens = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), rule: .unrestricted)
        bothTokens.also = [.macApp(bundleID: "com.google.ios.youtubemusic")]
        // Only the face is picked; nothing is removed, the unpicked half comes off in the editor.
        #expect(!Policy.picker(removes: bothTokens, selected: [app]))
    }
}

// MARK: - Travelling

@Suite("A linked pair in a setup file")
struct LinkedExportTests {
    @Test("The halves a name can carry travel; a token cannot and is left out")
    func exportsHostsOnly() {
        var app = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        app.also = [.host("youtube.com")]
        let exported = ExportedTarget(app)
        #expect(exported.kind == .app)
        #expect(exported.identifier == "com.google.ios.youtube")
        #expect(exported.alsoBlocks == ["youtube.com"])

        // Nothing linked, nothing written: the key is absent rather than an empty list.
        #expect(ExportedTarget(makeTarget("Reddit", rule: nil)).alsoBlocks == nil)
    }

    @Test("A linked pair survives the round trip")
    func roundTrips() throws {
        var app = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        app.also = [.host("youtube.com"), .host("music.youtube.com")]
        let file = ConfigExport(
            platform: .mac,
            exportedAt: at(8),
            appVersion: "1.0",
            loosenDelayHours: 24,
            targets: [ExportedTarget(app)]
        )
        let read = try ConfigExport.decode(try file.json())
        #expect(read.targets[0].alsoBlocks == ["youtube.com", "music.youtube.com"])
    }

    @Test("A file written before linking still reads")
    func olderFileStillReads() throws {
        let json = """
        {
          "version": 1,
          "platform": "mac",
          "exportedAt": "2026-09-08T12:00:00Z",
          "loosenDelayHours": 24,
          "targets": [{ "kind": "website", "identifier": "youtube.com" }]
        }
        """
        let read = try ConfigExport.decode(Data(json.utf8))
        #expect(read.targets[0].alsoBlocks == nil)
        #expect(read.targets[0].identifier == "youtube.com")
    }
}

@Suite("A linked pair arriving in an import")
struct LinkedImportTests {
    func file(_ exported: ExportedTarget) -> ConfigExport {
        ConfigExport(
            platform: .mac,
            exportedAt: at(8),
            appVersion: "1.0",
            loosenDelayHours: 24,
            targets: [exported]
        )
    }

    // More gets blocked than before, so there's no delay to wait out.
    @Test("Halves land on an existing row immediately")
    func halvesLandOnAnExistingRow() {
        let existing = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        var state = makeState([existing])
        var exported = ExportedTarget(existing)
        exported.alsoBlocks = ["youtube.com"]

        let match = ImportMatch(exported: exported, resolution: .existing(existing.id))
        let plan = ConfigImport.plan(file(exported), matches: [match], state: state, now: at(8))
        #expect(plan.edits.contains(.link(targetID: existing.id, hosts: ["youtube.com"])))
        // Said out loud in the review, since it changes what's blocked.
        #expect(plan.items.contains { $0.subject == .half && $0.outcome == .now })

        ConfigImport.apply(plan, to: &state, now: at(8))
        #expect(state.config.targets[0].also == [.host("youtube.com")])
        #expect(state.config.targets.count == 1)
    }

    // Import only ever adds, so an already-managed row is left as is, not blocked a second time.
    @Test("A site already managed on its own is not blocked twice")
    func alreadyManagedIsLeftAlone() {
        let app = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        let site = makeTarget("YouTube", rule: .unrestricted, id: UUID())
        var state = makeState([app, site])
        var exported = ExportedTarget(app)
        exported.alsoBlocks = ["youtube.com"]

        let match = ImportMatch(exported: exported, resolution: .existing(app.id))
        let plan = ConfigImport.plan(file(exported), matches: [match], state: state, now: at(8))
        #expect(!plan.edits.contains { if case .link = $0 { return true }; return false })
        ConfigImport.apply(plan, to: &state, now: at(8))
        #expect(state.config.targets[0].also == nil)
    }

    // Its halves are part of what "added" means: one line, not two.
    @Test("A new row arrives with its halves and one line")
    func newRowArrivesLinked() {
        var state = makeState([])
        var exported = ExportedTarget(Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted))
        exported.alsoBlocks = ["youtube.com"]

        let match = ImportMatch(exported: exported, resolution: .create(.macApp(bundleID: "com.google.ios.youtube")))
        let plan = ConfigImport.plan(file(exported), matches: [match], state: state, now: at(8))
        #expect(!plan.items.contains { $0.subject == .half })
        ConfigImport.apply(plan, to: &state, now: at(8))
        #expect(state.config.targets.count == 1)
        #expect(state.config.targets[0].also == [.host("youtube.com")])
        #expect(state.config.target(host: "m.youtube.com")?.displayName == "YouTube")
    }
}

@Suite("Stored state written before a target could have two doors")
struct LinkedDecodingTests {
    // A synthesized `init(from:)` demands every non-optional key, but old stored state has none.
    @Test("A target stored without `also` decodes as one door")
    func decodesWithoutAlso() throws {
        let json = """
        {
          "id": "6E1E4C7E-0000-4000-8000-000000000001",
          "kind": { "host": { "_0": "youtube.com" } },
          "nickname": "YouTube",
          "addedAt": "2026-09-08T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let target = try decoder.decode(Target.self, from: Data(json.utf8))
        #expect(target.also == nil)
        #expect(target.kinds == [.host("youtube.com")])
        #expect(!target.isLinked)
    }

    @Test("A linked target survives a save and a load")
    func encodesAndDecodes() throws {
        var app = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), rule: .unrestricted)
        app.also = [.host("youtube.com")]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(Target.self, from: try encoder.encode(app))
        #expect(back.also == [.host("youtube.com")])
        #expect(back.kinds == app.kinds)
    }
}

// MARK: - Naming what the shield has not covered

@Suite("A name from the tables rather than the shield")
struct TableNameTests {
    @Test("An essential is named from its bundle identifier")
    func essentialsAreNamed() {
        #expect(AppUtility.name(forBundleID: "com.apple.mobilesms") == "Messages")
        #expect(AppUtility.name(forBundleID: "com.apple.mobilephone") == "Phone")
        // The casing the lowercased key cannot recover on its own; see `properNames`.
        #expect(AppUtility.name(forBundleID: "com.apple.facetime") == "FaceTime")
        #expect(AppUtility.properName("1password") == "1Password")
        #expect(AppUtility.properName("google maps") == "Google Maps")
    }

    // A wrong guessed name on the shield is worse than the generic "This app", so ambiguous stays unnamed.
    @Test("An ambiguous identifier is not guessed at")
    func ambiguousStaysUnnamed() {
        #expect(AppUtility.name(forBundleID: "com.nobody.at.all") == nil)
    }
}

// MARK: - The usage page

/// Screen Time counts an app and a website separately, but once linked they're one row on one
/// shared budget, so the page must add their minutes rather than show YouTube twice.
/// `UsageSummary.folded(in:)` does the merging in `Shared/Usage` (imports DeviceActivity,
/// unreachable here); the pure decision it acts on is `UsageAnalysis.folding`, tested here.
@Suite("Folding the halves of a pair into one card")
struct UsageFoldingTests {
    let app = TargetKind.macApp(bundleID: "com.google.ios.youtube")

    func config() -> Config {
        var pair = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        pair.also = [.host("youtube.com")]
        return makeConfig([pair])
    }

    // A typed site has no token, so it's found by the domain in its usage key instead.
    @Test("A typed site folds into the app it is linked to")
    func typedSiteFoldsIntoTheApp() {
        let folding = UsageAnalysis.folding(
            [
                (key: "com.google.ios.youtube", kind: app, minutes: 300),
                (key: "web:youtube.com", kind: nil, minutes: 120),
            ],
            in: config()
        )
        // The app maps to itself too, so a caller can spot a folded row without a second lookup.
        #expect(folding["web:youtube.com"] == "com.google.ios.youtube")
        #expect(folding["com.google.ios.youtube"] == "com.google.ios.youtube")
    }

    // The app is what a rule is written on and the only half with an icon/name, so it's the face
    // even when the browser half weighs more.
    @Test("The app carries the pair even when the browser half is heavier")
    func faceWinsOverWeight() {
        let folding = UsageAnalysis.folding(
            [
                (key: "com.google.ios.youtube", kind: app, minutes: 5),
                (key: "web:youtube.com", kind: nil, minutes: 900),
            ],
            in: config()
        )
        #expect(folding["web:youtube.com"] == "com.google.ios.youtube")
    }

    @Test("A subdomain's minutes land on the row that covers it")
    func subdomainFolds() {
        let folding = UsageAnalysis.folding(
            [
                (key: "com.google.ios.youtube", kind: app, minutes: 300),
                (key: "web:m.youtube.com", kind: nil, minutes: 60),
            ],
            in: config()
        )
        #expect(folding["web:m.youtube.com"] == "com.google.ios.youtube")
    }

    @Test("Nothing that is not a pair is folded")
    func unrelatedEntriesStandAlone() {
        let folding = UsageAnalysis.folding(
            [
                (key: "com.zhiliaoapp.musically", kind: .macApp(bundleID: "com.zhiliaoapp.musically"), minutes: 300),
                (key: "web:vimeo.com", kind: nil, minutes: 90),
            ],
            in: config()
        )
        #expect(folding.isEmpty)
    }

    @Test("An unlinked target is not a group")
    func unlinkedTargetIsNotAGroup() {
        let alone = makeConfig([Target(kind: .macApp(bundleID: "com.google.ios.youtube"), rule: .unrestricted)])
        let folding = UsageAnalysis.folding(
            [
                (key: "com.google.ios.youtube", kind: app, minutes: 300),
                (key: "web:youtube.com", kind: nil, minutes: 120),
            ],
            in: alone
        )
        // youtube.com is not managed here at all, so it keeps its own card.
        #expect(folding.isEmpty)
    }

    @Test("The carrier is the same whichever order the halves arrive in")
    func orderDoesNotMatter() {
        let forwards = UsageAnalysis.folding(
            [(key: "com.google.ios.youtube", kind: app, minutes: 300), (key: "web:youtube.com", kind: nil, minutes: 120)],
            in: config()
        )
        let backwards = UsageAnalysis.folding(
            [(key: "web:youtube.com", kind: nil, minutes: 120), (key: "com.google.ios.youtube", kind: app, minutes: 300)],
            in: config()
        )
        #expect(forwards == backwards)
    }

    // With no app half to prefer as the face, the heaviest site carries the pair.
    @Test("With no app half the heaviest site carries the row")
    func heaviestWinsWithoutAFace() {
        var pair = Target(kind: .host("youtube.com"), nickname: "YouTube", rule: .unrestricted)
        pair.also = [.host("m.youtube.com")]
        let folding = UsageAnalysis.folding(
            [
                (key: "web:youtube.com", kind: nil, minutes: 30),
                (key: "web:m.youtube.com", kind: nil, minutes: 400),
            ],
            in: makeConfig([pair])
        )
        // Both keys resolve to the same row, and the heavier half carries it.
        #expect(folding["web:youtube.com"] == "web:m.youtube.com")
        #expect(folding["web:m.youtube.com"] == "web:m.youtube.com")
    }

    @Test("A website key is read and written in one place")
    func webKeysRoundTrip() {
        #expect(UsageAnalysis.webKey("youtube.com") == "web:youtube.com")
        #expect(UsageAnalysis.domain(inKey: "web:youtube.com") == "youtube.com")
        #expect(UsageAnalysis.domain(inKey: "com.google.ios.youtube") == nil)
    }

    // Both halves were seen over the same days, so merging must sum once, not average twice.
    @Test("Merged minutes average over the days once")
    func mergedAverageIsOverTheSameDays() {
        var appHalf = UsageHistogram(daysObserved: [Int](repeating: 2, count: 7))
        appHalf.add(weekday: 3, hour: 21, minutes: 140)
        var siteHalf = UsageHistogram(daysObserved: [Int](repeating: 2, count: 7))
        siteHalf.add(weekday: 3, hour: 22, minutes: 70)

        #expect(appHalf.averageDailyMinutes == 10)
        #expect(siteHalf.averageDailyMinutes == 5)
        appHalf.merge(siteHalf)
        #expect(appHalf.totalMinutes == 210)
        #expect(appHalf.averageDailyMinutes == 15)
        #expect(appHalf.daysObserved == [Int](repeating: 2, count: 7))
    }

    // Apart, each half is under the recommendation bar; merged, the habit clears it.
    @Test("Two halves under the bar are one habit over it")
    func togetherTheyPassTheBar() {
        var appHalf = UsageHistogram(daysObserved: UsageHistogram.oneWeek)
        appHalf.add(weekday: 3, hour: 21, minutes: 42)
        var siteHalf = UsageHistogram(daysObserved: UsageHistogram.oneWeek)
        siteHalf.add(weekday: 3, hour: 22, minutes: 35)
        #expect(UsageAnalysis.recommendation(key: "app", name: "YouTube", histogram: appHalf) == nil)
        #expect(UsageAnalysis.recommendation(key: "web:youtube.com", name: "youtube.com", histogram: siteHalf) == nil)

        appHalf.merge(siteHalf)
        let merged = try! #require(UsageAnalysis.recommendation(key: "app", name: "YouTube", histogram: appHalf))
        #expect(merged.averageDailyMinutes == 11)
    }
}
