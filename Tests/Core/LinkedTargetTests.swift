import Foundation
import Testing

/// One habit, one row: an app and the website it is also at as a single target.
///
/// The whole feature rests on everything downstream reading `Target.kinds` rather than
/// `Target.kind`, so that one status, one schedule, one budget and one removal delay cover both
/// halves. These tests pin that, and pin the two things that must *not* follow from it: the face
/// can never be unlinked away, and linking must never shorten a wait.
///
/// This bundle builds for macOS, so a target here is a bundle identifier or a host. That is the
/// engine both platforms share — `Policy.decide`, `Config.target(host:)`, `anchorWarning` and the
/// pending queue are one piece of code — and it is the only place they can be reached from a test.
/// The iOS-only half is `Monitoring.include`, which puts both tokens in one `DeviceActivityEvent`;
/// nothing in a test bundle can reach DeviceActivity, so that one is checked on the phone.

// MARK: - The model

@Suite("A target with more than one door")
struct LinkedTargetModelTests {
    /// YouTube the app, with youtube.com linked onto it.
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

    /// The rung-B honesty check. Nothing counts a site typed by name, so a site on its own has no
    /// budget at all — but linked to an app it shares that app's budget event, and the app's
    /// minutes are real. So the pair is counted, and the site is the part that is not.
    @Test("A linked pair has a real budget; the typed half is the part nothing counts")
    func countedAndUncounted() {
        let target = pair()
        #expect(target.isCounted)
        #expect(target.uncountedHosts == ["youtube.com"])

        let siteAlone = makeTarget("Reddit", rule: .unrestricted)
        #expect(!siteAlone.isCounted)
        // Nothing to be honest about: the whole target is uncounted, and the editor says so
        // instead with `hostBudgetNote`.
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

    /// The longest matching host still wins across rows, so a row claiming a subdomain beats one
    /// claiming the whole domain whichever of them happens to be linked.
    @Test("The most specific host wins, linked or not")
    func longestHostWins() {
        var app = Target(kind: .macApp(bundleID: "com.google.ios.youtubemusic"), nickname: "YT Music", rule: .unrestricted)
        app.also = [.host("music.youtube.com")]
        let config = makeConfig([makeTarget("YouTube", rule: .unrestricted), app])
        #expect(config.target(host: "music.youtube.com")?.displayName == "YT Music")
        #expect(config.target(host: "youtube.com")?.displayName == "YouTube")
    }

    /// This is what stops the picker and an import adding a second row for a half that is already
    /// covered — the bug that would split every pair back into the two rows linking exists to join.
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

    /// One status per target was always the shape; linking only widens what it applies to. So a
    /// spent budget shuts the browser tab too, which is the gap the whole feature exists to close.
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
        #expect(config.isAnchored(config.targets[0]))
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

    /// The face is what the row *is*. Unlinking it would leave a target with no identity rather
    /// than a looser one, so it is refused where it is queued and again where it is performed —
    /// a change can sit in the queue across an edit that swaps which half is the face.
    @Test("The face is never unlinked away")
    func faceSurvives() {
        var state = state()
        let id = state.config.targets[0].id
        let face = state.config.targets[0].kind
        Policy.apply(PendingChange(kind: .unlink(targetID: id, kind: face), effectiveAt: at(9)), to: &state.config)
        #expect(state.config.targets[0].kind == face)
        #expect(state.config.targets[0].also?.count == 2)
    }

    /// A loosening, so it queues like every other one — and the card has to say what it costs
    /// while there is still time to cancel.
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

/// The sharpest edge in the whole feature, and the reason the rule is pure rather than a line
/// inside `applyPicker`: the picker reads a selection as the whole truth, so anything it cannot
/// see looks unpicked, and anything that looks unpicked is queued for removal.
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

    /// The bug that shipped once already, before typed hosts had this guard: a site added by name
    /// is in no selection, so one visit to the picker would have queued the removal of every one.
    @Test("A site added by name is in no selection and is never removed")
    func typedHostIsNeverRemoved() {
        let site = makeTarget("Reddit", rule: .unrestricted)
        #expect(!Policy.picker(removes: site, selected: []))
        #expect(!Policy.picker(removes: site, selected: [app, other]))
    }

    /// The bug this change would otherwise have introduced. A linked pair's typed half is invisible
    /// to the picker; if the whole row were judged on that, every trip would queue every pair's
    /// removal. The row survives on its app half.
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

    /// Unpicking one half of a pair is not how a pair is broken. Breaking one is a loosening and
    /// waits out the delay; a removal queued from the picker would take the whole row instead, and
    /// would do it without the confirmation the editor asks for.
    @Test("The picker cannot break a pair, only remove the whole of it")
    func pickerCannotUnlink() {
        var bothTokens = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), rule: .unrestricted)
        bothTokens.also = [.macApp(bundleID: "com.google.ios.youtubemusic")]
        // Only the face is still picked, and the linked half is not. Nothing is removed: the row
        // is still wanted, and the half that is not comes off in the editor.
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

    /// A file written before linking existed has no `alsoBlocks`, and must still open.
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

    /// The halves land on the row the file's face maps to, and at once: more is blocked than a
    /// moment ago, so there is no delay to wait out.
    @Test("Halves land on an existing row immediately")
    func halvesLandOnAnExistingRow() {
        let existing = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: .unrestricted)
        var state = makeState([existing])
        var exported = ExportedTarget(existing)
        exported.alsoBlocks = ["youtube.com"]

        let match = ImportMatch(exported: exported, resolution: .existing(existing.id))
        let plan = ConfigImport.plan(file(exported), matches: [match], state: state, now: at(8))
        #expect(plan.edits.contains(.link(targetID: existing.id, hosts: ["youtube.com"])))
        // Said out loud in the review rather than folded in silently: it changes what is blocked.
        #expect(plan.items.contains { $0.subject == .half && $0.outcome == .now })

        ConfigImport.apply(plan, to: &state, now: at(8))
        #expect(state.config.targets[0].also == [.host("youtube.com")])
        #expect(state.config.targets.count == 1)
    }

    /// A site the file wants to link is already a row of its own here. An import only ever adds,
    /// so the row it has is left exactly as it is rather than being blocked a second time.
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

    /// A row the file brings with it arrives linked, and gets one line, not two: its halves are
    /// part of what "added" means.
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
    /// The reason `also` is optional: a synthesised `init(from:)` demands every non-optional key,
    /// and the state already on Zach's phone has none.
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
    /// The essentials each carry their own detail sentence, so exactly one display name maps to
    /// each identifier's advice and the bridge between the two tables is unambiguous.
    @Test("An essential is named from its bundle identifier")
    func essentialsAreNamed() {
        #expect(AppUtility.name(forBundleID: "com.apple.mobilesms") == "Messages")
        #expect(AppUtility.name(forBundleID: "com.apple.mobilephone") == "Phone")
        // The casing the lowercased key cannot recover on its own; see `properNames`.
        #expect(AppUtility.name(forBundleID: "com.apple.facetime") == "FaceTime")
        #expect(AppUtility.properName("1password") == "1Password")
        #expect(AppUtility.properName("google maps") == "Google Maps")
    }

    /// The quieter tiers share a bare advice between many apps, so the table genuinely cannot
    /// tell which one an identifier is. Saying nothing is right: a wrong name would go on the
    /// shield, which is worse than "This app".
    @Test("An ambiguous identifier is not guessed at")
    func ambiguousStaysUnnamed() {
        // Nothing in the table at all.
        #expect(AppUtility.name(forBundleID: "com.nobody.at.all") == nil)
    }
}
