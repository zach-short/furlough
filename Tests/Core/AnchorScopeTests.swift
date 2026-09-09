import Foundation
import Testing

/// The anchor's second scope, added 2026-09-09: everything on the phone except an allowlist.
/// Under `.chosen` the list is what goes; under `.everythingExcept` it is what stays, and the
/// engine has to read it the right way round everywhere it looks. This bundle builds for
/// macOS, so the decision it reads is the Mac's; the flag both decisions carry and the
/// statuses are what the phone's reconciler builds its `.all(except:)` policies from.
@Suite("Anchor scope")
struct AnchorScopeTests {
    @Test("the scope starts as the chosen list")
    func defaultScope() {
        #expect(AnchorProfile().scope == .chosen)
        #expect(!AnchorProfile().anchorsEverything)
    }

    @Test("under the chosen scope the list is what goes; under everything-except it is what stays")
    func holdsReadsTheListBothWays() {
        let tiktok = TargetKind.host("tiktok.com")
        let messages = TargetKind.macApp(bundleID: "com.apple.MobileSMS")
        var anchor = AnchorProfile(kinds: [tiktok])
        #expect(anchor.holds(tiktok))
        #expect(!anchor.holds(messages))
        anchor.scope = .everythingExcept
        anchor.kinds = [messages]
        #expect(anchor.holds(tiktok))
        #expect(!anchor.holds(messages))
        // `contains` still answers about the list itself, whichever way round it is read.
        #expect(anchor.contains(messages))
        #expect(!anchor.contains(tiktok))
    }

    @Test("nothing is blocked until the anchor is down")
    func blocksNeedsTheAnchorDown() {
        var anchor = AnchorProfile()
        anchor.scope = .everythingExcept
        #expect(!anchor.blocks(.host("tiktok.com"), at: at(8, 12)))
        anchor.isAnchored = true
        #expect(anchor.blocks(.host("tiktok.com"), at: at(8, 12)))
    }

    @Test("an empty allowlist can anchor; an empty chosen list cannot")
    func canAnchorWithAnEmptyAllowlist() {
        var anchor = AnchorProfile(tags: [PairedTag(id: Data([1]), name: "Home")])
        #expect(!anchor.canAnchor)
        anchor.scope = .everythingExcept
        #expect(anchor.canAnchor)
        // Still nothing without a key, whatever the scope: there has to be a way back.
        anchor.tags = []
        #expect(!anchor.canAnchor)
    }

    @Test("the line of copy says what is held")
    func heldDescription() {
        var anchor = AnchorProfile(kinds: [.host("a.com")])
        #expect(anchor.heldDescription == "1 item")
        anchor.kinds.append(.host("b.com"))
        #expect(anchor.heldDescription == "2 items")
        anchor.scope = .everythingExcept
        #expect(anchor.heldDescription == "Everything except 2")
        anchor.kinds = []
        #expect(anchor.heldDescription == "Everything")
    }
}

@Suite("Anchor scope: stored state")
struct AnchorScopeDecodingTests {
    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @Test("state written before the scope existed reads as the chosen list")
    func missingScopeIsChosen() throws {
        let json = #"{"targets":[],"loosenDelayHours":24,"anchor":{"kinds":[],"isAnchored":true}}"#
        let config = try decoder.decode(Config.self, from: Data(json.utf8))
        #expect(config.anchor.scope == .chosen)
        #expect(config.anchor.isAnchored)
        // And a config with no anchor at all.
        let bare = try decoder.decode(Config.self, from: Data(#"{"targets":[],"loosenDelayHours":24}"#.utf8))
        #expect(bare.anchor.scope == .chosen)
    }

    @Test("a stored scope comes back, and is written under its own name")
    func scopeRoundTrips() throws {
        var config = Config()
        config.anchor.scope = .everythingExcept
        config.anchor.kinds = [.host("wm.edu")]
        let data = try encoder.encode(config)
        #expect(String(decoding: data, as: UTF8.self).contains(#""scope":"everythingExcept""#))
        let back = try decoder.decode(Config.self, from: data)
        #expect(back.anchor.scope == .everythingExcept)
        #expect(back.anchor.kinds == [.host("wm.edu")])
    }
}

@Suite("Anchor scope: the decision")
struct AnchorScopeDecisionTests {
    let noon = at(8, 12, 30)
    let openAllDay = Rule(windows: [], dailyBudgetMinutes: 30)
    let evenings = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30)

    func anchored(_ scope: AnchorProfile.Scope, _ kinds: [TargetKind]) -> AnchorProfile {
        var anchor = AnchorProfile(kinds: kinds)
        anchor.scope = scope
        anchor.isAnchored = true
        anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        return anchor
    }

    func decide(_ config: Config) -> Decision {
        Policy.decide(config: config, runtime: RuntimeState(), now: noon, calendar: cal)
    }

    @Test("everything-except anchors every target off the list and leaves the list on its rules")
    func everythingExcept() {
        let messages = makeTarget("Messages", rule: openAllDay)
        let youtube = makeTarget("YouTube", rule: evenings)
        let tiktok = makeTarget("TikTok", rule: openAllDay)
        var config = makeConfig([messages, youtube, tiktok])
        config.anchor = anchored(.everythingExcept, [messages.kind, youtube.kind])
        let decision = decide(config)
        #expect(decision.shieldsEverything)
        #expect(decision.isAnythingShielded)
        #expect(decision.statuses[messages.id] == .open(until: 1440))
        // On the list, so its own rule speaks: shut by its window at noon, not by the anchor.
        #expect(decision.statuses[youtube.id] == .closed(nextOpen: NextOpen(minuteOfDay: 1200, daysAhead: 0)))
        #expect(decision.statuses[tiktok.id] == .anchored)
        #expect(decision.blockedHosts == ["youtube.com", "tiktok.com"])
        // Rule shields still apply on top: the same list with the window open lets YouTube through.
        let evening = Policy.decide(config: config, runtime: RuntimeState(), now: at(8, 20, 30), calendar: cal)
        #expect(evening.statuses[youtube.id] == .open(until: 1320))
        #expect(evening.blockedHosts == ["tiktok.com"])
    }

    @Test("the chosen scope is what it always was, and never says everything")
    func chosen() {
        let messages = makeTarget("Messages", rule: openAllDay)
        let tiktok = makeTarget("TikTok", rule: openAllDay)
        var config = makeConfig([messages, tiktok])
        config.anchor = anchored(.chosen, [tiktok.kind, .macApp(bundleID: "com.apple.Safari")])
        let decision = decide(config)
        #expect(!decision.shieldsEverything)
        #expect(decision.statuses[messages.id] == .open(until: 1440))
        #expect(decision.statuses[tiktok.id] == .anchored)
        #expect(decision.blockedHosts == ["tiktok.com"])
        #expect(decision.blockedApps == ["com.apple.Safari"])
    }

    @Test("with the anchor up, the scope changes nothing")
    func anchorUp() {
        let tiktok = makeTarget("TikTok", rule: openAllDay)
        var config = makeConfig([tiktok])
        config.anchor.scope = .everythingExcept
        let decision = decide(config)
        #expect(!decision.shieldsEverything)
        #expect(decision.statuses[tiktok.id] == .open(until: 1440))
        #expect(!decision.isAnythingShielded)
    }

    @Test("everything-except with an empty list still shields, so app removal stays denied")
    func emptyAllowlistStillShields() {
        var config = makeConfig([])
        config.anchor = anchored(.everythingExcept, [])
        let decision = decide(config)
        #expect(decision.shieldsEverything)
        #expect(decision.isAnythingShielded)
        #expect(decision.blockedApps.isEmpty)
        #expect(decision.blockedHosts.isEmpty)
    }

    @Test("a linked target is held whole when one door is off the list")
    func linkedTargetHeldWhole() {
        var pair = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), nickname: "YouTube", rule: openAllDay)
        pair.also = [.host("youtube.com")]
        var config = makeConfig([pair])
        // The app is let through and the site is not: one door held is the whole of it held,
        // exactly as it is under the chosen scope.
        config.anchor = anchored(.everythingExcept, [pair.kind])
        #expect(config.isAnchored(pair, at: noon))
        let decision = decide(config)
        #expect(decision.statuses[pair.id] == .anchored)
        #expect(decision.blockedApps == ["com.google.ios.youtube"])
        #expect(decision.blockedHosts == ["youtube.com"])
        // Both doors on the list, and it is back on its rule.
        config.anchor.kinds = [pair.kind, .host("youtube.com")]
        #expect(!config.isAnchored(pair, at: noon))
        #expect(decide(config).statuses[pair.id] == .open(until: 1440))
    }

    @Test("the summary says the anchor is over everything")
    func summarySaysEverything() {
        var state = makeState([])
        state.config.anchor = anchored(.everythingExcept, [.host("a.com")])
        let summary = Policy.summary(state: state, now: noon, calendar: cal)
        #expect(summary.isAnchored)
        #expect(summary.anchorsEverything)
        #expect(summary.anchoredCount == 1)
        #expect(!summary.isEmpty)
        state.config.anchor.scope = .chosen
        #expect(!Policy.summary(state: state, now: noon, calendar: cal).anchorsEverything)
        state.config.anchor.scope = .everythingExcept
        state.config.anchor.isAnchored = false
        let up = Policy.summary(state: state, now: noon, calendar: cal)
        #expect(!up.anchorsEverything)
        #expect(up.isEmpty)
    }

    @Test("said aloud, everything-except is an exception and not a count")
    func speech() {
        var state = makeState([])
        state.config.anchor = anchored(.everythingExcept, [.host("a.com"), .host("b.com")])
        let summary = Policy.summary(state: state, now: noon, calendar: cal)
        let sentence = StatusSpeech.sentence(summary, hasTargets: false, now: noon, calendar: cal)
        #expect(sentence.hasPrefix("Anchored: everything except 2 things is locked until you scan your tag."))
        state.config.anchor.kinds = []
        let bare = Policy.summary(state: state, now: noon, calendar: cal)
        #expect(StatusSpeech.sentence(bare, hasTargets: false, now: noon, calendar: cal)
            .hasPrefix("Anchored: everything is locked until you scan your tag."))
    }
}

@Suite("Anchor scope: the essential seed")
struct AnchorScopeSeedTests {
    @Test("the allowlist starts as every door of every target tiered Essential, in the list's order")
    func seed() {
        var tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        tiktok.utilityLevel = .hazard
        var messages = makeTarget("Messages", rule: .unrestricted)
        messages.utilityLevel = .essential
        var maps = Target(kind: .macApp(bundleID: "com.apple.Maps"), nickname: "Maps", rule: nil)
        maps.utilityLevel = .essential
        maps.also = [.host("maps.apple.com")]
        let mail = makeTarget("Mail", rule: .unrestricted)
        let config = makeConfig([tiktok, messages, maps, mail])
        #expect(config.essentialKinds == [messages.kind, maps.kind, .host("maps.apple.com")])
    }

    @Test("a tier that was never chosen does not count, however the table would tier it")
    func onlyChosenTiersCount() {
        // Messages is essential in the table; nobody has said so on this target.
        let messages = makeTarget("Messages", rule: .unrestricted)
        #expect(!messages.hasChosenUtility)
        #expect(makeConfig([messages]).essentialKinds.isEmpty)
        var useful = makeTarget("Mail", rule: .unrestricted)
        useful.utilityLevel = .useful
        #expect(makeConfig([useful]).essentialKinds.isEmpty)
    }
}

@Suite("Anchor scope: the warning")
struct AnchorScopeWarningTests {
    func tiered(_ name: String, _ tier: Utility) -> Target {
        var target = makeTarget(name, rule: .unrestricted)
        target.utilityLevel = tier
        return target
    }

    @Test("anchoring everything warns about the essential app the list leaves out, not the one it keeps")
    func warnsForWhatGoes() throws {
        let messages = tiered("Messages", .essential)
        let tiktok = tiered("TikTok", .hazard)
        var config = makeConfig([messages, tiktok])
        config.anchor.scope = .everythingExcept
        config.anchor.kinds = [messages.kind]
        #expect(config.anchorWarning == nil)
        config.anchor.kinds = []
        let warning = try #require(config.anchorWarning)
        #expect(warning.utility == .essential)
        #expect(warning.names == ["Messages"])
    }

    @Test("the chosen scope still warns about what is on the list, and only that")
    func chosenWarnsForTheList() throws {
        let messages = tiered("Messages", .essential)
        let tiktok = tiered("TikTok", .hazard)
        var config = makeConfig([messages, tiktok])
        config.anchor.kinds = [tiktok.kind]
        #expect(config.anchorWarning == nil)
        config.anchor.kinds = [tiktok.kind, messages.kind]
        #expect(try #require(config.anchorWarning).names == ["Messages"])
    }
}
