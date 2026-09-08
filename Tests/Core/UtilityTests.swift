import Foundation
import Testing

@Suite("Utility tiers and the delay they buy")
struct UtilityDelayTests {
    @Test("The tier scales the base delay")
    func scalesTheBase() {
        var config = makeConfig([], delayHours: 24)
        config.targets = [
            makeTarget("Messages", rule: .unrestricted),
            makeTarget("Mail", rule: .unrestricted),
            makeTarget("YouTube", rule: .unrestricted),
            makeTarget("TikTok", rule: .unrestricted),
        ]
        config.targets[0].utilityLevel = .essential
        config.targets[1].utilityLevel = .useful
        config.targets[2].utilityLevel = .idle
        config.targets[3].utilityLevel = .hazard

        #expect(config.delayHours(for: config.targets[0]) == 6)
        #expect(config.delayHours(for: config.targets[1]) == 24)
        #expect(config.delayHours(for: config.targets[2]) == 48)
        #expect(config.delayHours(for: config.targets[3]) == 96)
        #expect(config.delay(for: config.targets[3]) == 96 * 3600)
    }

    @Test("A target with no tier of its own gets the base")
    func unsetGetsTheBase() {
        let config = makeConfig([makeTarget("Mail", rule: .unrestricted)], delayHours: 24)
        #expect(config.targets[0].hasChosenUtility == false)
        #expect(config.targets[0].utility == .useful)
        #expect(config.delayHours(for: config.targets[0]) == 24)
        #expect(config.delayHours(for: nil) == 24)
    }

    @Test("However short the base, a loosening still waits an hour")
    func floorsAtAnHour() {
        var config = makeConfig([makeTarget("Messages", rule: .unrestricted)], delayHours: 2)
        config.targets[0].utilityLevel = .essential
        // 2 × 0.25 rounds to 1 anyway; 1 × 0.25 would round to 0 without the floor.
        #expect(config.delayHours(for: config.targets[0]) == 1)
        config.loosenDelayHours = 1
        #expect(config.delayHours(for: config.targets[0]) == Furlough.minimumLoosenDelayHours)
        #expect(config.delayHours(for: config.targets[0]) >= 1)
    }

    @Test("Lowering the base has to wait out the slowest target")
    func longestDelayIsTheSlowestTarget() {
        var config = makeConfig([
            makeTarget("Messages", rule: .unrestricted),
            makeTarget("TikTok", rule: .unrestricted),
        ], delayHours: 24)
        config.targets[0].utilityLevel = .essential
        config.targets[1].utilityLevel = .hazard
        #expect(config.longestDelay == 96 * 3600)
    }

    @Test("With nothing to compare against, the longest delay is the base")
    func longestDelayWithNoTargets() {
        #expect(makeConfig([], delayHours: 24).longestDelay == 24 * 3600)
    }
}

@Suite("What the anchor is about to take away")
struct AnchorWarningTests {
    func config(_ tiers: [(String, Utility)], anchoring: [String]) -> Config {
        var config = makeConfig(tiers.map { makeTarget($0.0, rule: .unrestricted) })
        for (index, tier) in tiers.enumerated() { config.targets[index].utilityLevel = tier.1 }
        config.anchor.kinds = config.targets
            .filter { anchoring.contains($0.displayName) }
            .map(\.kind)
        return config
    }

    @Test("An anchor holding only what Furlough exists to block says nothing")
    func hazardsAreSilent() {
        let config = config([("TikTok", .hazard)], anchoring: ["TikTok"])
        #expect(config.anchorWarning == nil)
    }

    /// Changed 2026-09-08: anchoring is instant and only the tag lifts it, so it warns one tier
    /// wider than blocking does. Idle used to be silent here and now speaks; hazard still does not.
    @Test("Idle speaks before an anchor, though it says nothing before a rule")
    func idleWarnsBeforeAnchoring() {
        let config = config([("TikTok", .hazard), ("Reddit", .idle)], anchoring: ["TikTok", "Reddit"])
        let warning = try! #require(config.anchorWarning)
        #expect(warning.utility == .idle)
        #expect(warning.names == ["Reddit"])
    }

    @Test("The worst tier in the anchor is the one that speaks, and names its own")
    func worstTierWins() {
        let config = config(
            [("Messages", .essential), ("Phone", .essential), ("Mail", .useful), ("TikTok", .hazard)],
            anchoring: ["Messages", "Phone", "Mail", "TikTok"]
        )
        let warning = try! #require(config.anchorWarning)
        #expect(warning.utility == .essential)
        #expect(warning.names.sorted() == ["Messages", "Phone"])
    }

    @Test("Only what the anchor actually holds counts")
    func onlyWhatIsHeld() {
        let config = config([("Messages", .essential), ("TikTok", .hazard)], anchoring: ["TikTok"])
        #expect(config.anchorWarning == nil)
    }

    @Test("A useful anchor warns, but not as the essential one does")
    func usefulWarnsQuietly() {
        let config = config([("Mail", .useful)], anchoring: ["Mail"])
        let warning = try! #require(config.anchorWarning)
        #expect(warning.utility == .useful)
        let text = try! #require(UtilityText.anchoring(names: warning.names, utility: warning.utility, detail: warning.detail))
        #expect(text.contains("paired tag"))
        #expect(text.contains("not with you") == false)
    }
}

@Suite("Policy.classify for tiers")
struct UtilityClassifyTests {
    func target(_ level: Utility?) -> Target {
        var target = makeTarget("Thing", rule: .unrestricted)
        target.utilityLevel = level
        return target
    }

    @Test("Moving toward hazard lengthens the wait, so it lands now")
    func towardHazardIsTightening() {
        #expect(Policy.classify(newUtility: .hazard, against: target(.essential)) == .tightening)
        #expect(Policy.classify(newUtility: .idle, against: target(.useful)) == .tightening)
        #expect(Policy.classify(newUtility: .useful, against: target(nil)) == .tightening)
    }

    @Test("Moving toward essential shortens the wait, so it queues")
    func towardEssentialIsLoosening() {
        #expect(Policy.classify(newUtility: .essential, against: target(.hazard)) == .loosening)
        #expect(Policy.classify(newUtility: .useful, against: target(.idle)) == .loosening)
        #expect(Policy.classify(newUtility: .essential, against: target(nil)) == .loosening)
    }

    @Test("The same tier changes nothing, so it is not a loosening")
    func sameTierIsTightening() {
        #expect(Policy.classify(newUtility: .hazard, against: target(.hazard)) == .tightening)
        #expect(Policy.classify(newUtility: .useful, against: target(nil)) == .tightening)
    }

    @Test("An unknown target is judged against the default tier")
    func noTargetUsesTheDefault() {
        #expect(Policy.classify(newUtility: .hazard, against: nil) == .tightening)
        #expect(Policy.classify(newUtility: .essential, against: nil) == .loosening)
    }
}

@Suite("Pending tier changes")
struct UtilityPendingTests {
    @Test("A due tier change lands on the target it names")
    func appliesWhenDue() {
        let id = UUID()
        var state = makeState(
            [makeTarget("TikTok", rule: .unrestricted, id: id)],
            pending: [PendingChange(kind: .setUtility(targetID: id, level: .essential), effectiveAt: at(8, 9))]
        )
        #expect(state.config.targets[0].utility == .useful)

        #expect(Policy.applyDuePending(&state, now: at(8, 8)) == false)
        #expect(state.config.targets[0].hasChosenUtility == false)

        #expect(Policy.applyDuePending(&state, now: at(8, 10)) == true)
        #expect(state.config.targets[0].utility == .essential)
        #expect(state.pending.isEmpty)
    }

    @Test("A tier change for a target that is gone is dropped, not crashed on")
    func missingTargetIsHarmless() {
        var state = makeState([makeTarget("TikTok", rule: .unrestricted)])
        state.pending = [PendingChange(kind: .setUtility(targetID: UUID(), level: .essential), effectiveAt: at(8, 9))]
        #expect(Policy.applyDuePending(&state, now: at(8, 10)) == true)
        #expect(state.config.targets.count == 1)
        #expect(state.pending.isEmpty)
    }

    @Test("A pending tier change carries its target's id")
    func carriesTheTargetID() {
        let id = UUID()
        let change = PendingChange(kind: .setUtility(targetID: id, level: .idle), effectiveAt: at(8, 9))
        #expect(change.targetID == id)
    }
}

@Suite("AppUtility's table")
struct AppUtilityTests {
    @Test("Hosts match through their subdomains, longest rule first")
    func hostsMatch() {
        #expect(AppUtility.byHost("tiktok.com")?.utility == .hazard)
        #expect(AppUtility.byHost("https://www.TikTok.com/foo")?.utility == .hazard)
        #expect(AppUtility.byHost("m.youtube.com")?.utility == .idle)
        // "maps.google.com" is essential even though "google.com" alone is only useful.
        #expect(AppUtility.byHost("maps.google.com")?.utility == .essential)
        #expect(AppUtility.byHost("google.com")?.utility == .useful)
        #expect(AppUtility.byHost("some-site-nobody-listed.example") == nil)
        #expect(AppUtility.byHost(nil) == nil)
    }

    @Test("Bundle identifiers match exactly, then on the longest prefix")
    func bundleIDsMatch() {
        #expect(AppUtility.byBundleID("com.apple.MobileSMS")?.utility == .essential)
        #expect(AppUtility.byBundleID("com.zhiliaoapp.musically")?.utility == .hazard)
        #expect(AppUtility.byBundleID("com.1password.1password")?.utility == .essential)
        // A vendor prefix reaches a member nobody listed by name.
        #expect(AppUtility.byBundleID("com.ubercab.UberClient")?.utility == .essential)
        #expect(AppUtility.byBundleID("com.nobody.knows.this") == nil)
        // A prefix must stop at a dot: "com.ubercabbage" is not Uber.
        #expect(AppUtility.byBundleID("com.ubercabbage.app") == nil)
    }

    @Test("Names, as the shield learns them, are matched case-insensitively")
    func namesMatch() {
        #expect(AppUtility.byName("Messages")?.utility == .essential)
        #expect(AppUtility.byName("  tiktok ")?.utility == .hazard)
        #expect(AppUtility.byName("") == nil)
        #expect(AppUtility.byName(nil) == nil)
    }

    @Test("Essentials say what blocking them actually costs")
    func essentialsCarryADetail() {
        for (key, advice) in AppUtility.names where advice.utility == .essential {
            #expect(advice.detail?.isEmpty == false || key == "health", "\(key) has no detail")
        }
        #expect(AppUtility.byName("Messages")?.detail?.contains("reach you") == true)
    }

    @Test("A target is suggested from whatever identity it has")
    func suggestsFromTheTarget() {
        // On the Mac a target is its host or bundle id, so the guess is exact.
        #expect(AppUtility.suggestion(for: makeTarget("TikTok", rule: nil))?.utility == .hazard)
        #expect(AppUtility.suggestion(for: Target(kind: .macApp(bundleID: "com.apple.MobileSMS")))?.utility == .essential)
        // Nothing is guessed for a host nobody listed, whatever it is nicknamed.
        #expect(AppUtility.suggestion(for: makeTarget("Messages", rule: nil)) == nil)
        #expect(AppUtility.suggestion(for: Target(kind: .macApp(bundleID: "com.nobody.at.all"))) == nil)
    }

    @Test("A Mac app falls back to what Zach called it")
    func nicknameIsTheLastResort() {
        var app = Target(kind: .macApp(bundleID: "com.unknown.vendor.app"))
        app.nickname = "TikTok"
        #expect(AppUtility.suggestion(for: app)?.utility == .hazard)
    }
}

@Suite("What Furlough says before blocking")
struct UtilityTextTests {
    @Test("Only the tiers worth keeping interrupt")
    func onlyHighTiersWarn() {
        #expect(UtilityText.blocking(name: "TikTok", utility: .hazard, detail: nil) == nil)
        #expect(UtilityText.blocking(name: "YouTube", utility: .idle, detail: nil) == nil)
        #expect(UtilityText.blocking(name: "Mail", utility: .useful, detail: nil) != nil)
        #expect(UtilityText.blocking(name: "Messages", utility: .essential, detail: nil) != nil)
    }

    @Test("An essential warning names the consequence and the fact there is no way out")
    func essentialWarningIsSpecific() {
        let text = UtilityText.blocking(
            name: "Messages",
            utility: .essential,
            detail: AppUtility.byName("Messages")?.detail
        )
        #expect(text?.contains("codes texted to you") == true)
        #expect(text?.contains("no emergency unblock") == true)
    }

    @Test("The anchor warning says the tag is the only way back")
    func anchorWarningNamesTheTag() {
        let text = UtilityText.anchoring(names: ["Messages", "Phone"], utility: .essential, detail: nil)
        #expect(text?.contains("Messages and Phone") == true)
        #expect(text?.contains("paired tag") == true)
        #expect(UtilityText.anchoring(names: ["TikTok"], utility: .hazard, detail: nil) == nil)
    }

    @Test("Names read as a sentence")
    func namesReadAsASentence() {
        #expect(UtilityText.list([]) == "This")
        #expect(UtilityText.list(["Messages"]) == "Messages")
        #expect(UtilityText.list(["Messages", "Phone"]) == "Messages and Phone")
        #expect(UtilityText.list(["Messages", "Phone", "Maps"]) == "Messages, Phone and Maps")
    }
}

@Suite("Stored state written before tiers existed")
struct UtilityDecodingTests {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }

    @Test("A target with no tier decodes, and reads as the default")
    func oldTargetDecodes() throws {
        let json = #"{"id":"6C1E0000-0000-0000-0000-000000000001","kind":{"host":{"_0":"tiktok.com"}},"nickname":"TikTok","addedAt":"2026-09-01T00:00:00Z"}"#
        let target = try decode(Target.self, json)
        #expect(target.hasChosenUtility == false)
        #expect(target.utility == .useful)
        #expect(target.utility == Utility.unset)
    }

    @Test("A tier survives a round trip")
    func tierRoundTrips() throws {
        var target = makeTarget("TikTok", rule: .unrestricted)
        target.utilityLevel = .hazard
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(target)
        let back = try decode(Target.self, String(decoding: data, as: UTF8.self))
        #expect(back.utilityLevel == .hazard)
        #expect(back.hasChosenUtility)
    }

    @Test("A queued tier change survives a round trip")
    func pendingRoundTrips() throws {
        let id = UUID()
        let change = PendingChange(kind: .setUtility(targetID: id, level: .essential), effectiveAt: at(8, 9))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(change)
        let back = try decode(PendingChange.self, String(decoding: data, as: UTF8.self))
        #expect(back.kind == .setUtility(targetID: id, level: .essential))
    }
}
