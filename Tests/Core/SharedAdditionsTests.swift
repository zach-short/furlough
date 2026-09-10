import Foundation
import Testing

/// What crosses when a linked device adds something, added 2026-09-10. This bundle is built for
/// macOS, so the receiving side here is the Mac's — `.macApp` exists and the phone's tokens do
/// not — and the phone-only branches are pinned by their `isApp`/`appNeedsPicker` shape.
@Suite("Shared additions: saying what was added")
struct SharedAdditionsDescribeTests {
    let noon = at(8, 12, 0)

    @Test("a Mac app names itself, and the table fills in the rest")
    func macApp() throws {
        let target = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), systemName: "YouTube")
        let addition = try #require(SharedAdditions.describe(target, half: .rules, origin: "mac", platform: .mac, sequence: 3, now: noon))
        #expect(addition.id == target.id)
        #expect(addition.title == "YouTube")
        #expect(addition.isApp)
        #expect(addition.bundleIDs == ["com.google.ios.youtube"])
        // The table's hosts are not sent: the sender says what it blocks, the receiver decides
        // what to add beside it under its own setting.
        #expect(addition.hosts.isEmpty)
        #expect(addition.rule == nil)
        #expect(addition.half == .rules)
        #expect(addition.sequence == 3)
    }

    @Test("a linked row sends every host it blocks, and its rule")
    func linkedRow() throws {
        var target = Target(kind: .macApp(bundleID: "com.google.Chrome"), systemName: "Google Chrome")
        target.also = [.host("youtube.com"), .host("m.youtube.com")]
        target.rule = Rule(windows: [window(18 * 60, 20 * 60)], dailyBudgetMinutes: 45)
        let addition = try #require(SharedAdditions.describe(target, half: .anchor, origin: "mac", platform: .mac, sequence: 1, now: noon))
        #expect(addition.hosts == ["youtube.com", "m.youtube.com"])
        #expect(addition.rule == target.rule)
        #expect(addition.half == .anchor)
        #expect(addition.title == "Google Chrome")
    }

    @Test("a host names itself, and the table names the app it is also in")
    func host() throws {
        let addition = try #require(SharedAdditions.describe(Target(kind: .host("m.youtube.com")), half: .rules, origin: "mac", platform: .mac, sequence: 1, now: noon))
        #expect(addition.title == "m.youtube.com")
        #expect(!addition.isApp)
        #expect(addition.hosts == ["m.youtube.com"])
        #expect(addition.bundleIDs == ["com.google.ios.youtube"])
        let unknown = try #require(SharedAdditions.describe(Target(kind: .host("example.org")), half: .rules, origin: "mac", platform: .mac, sequence: 1, now: noon))
        #expect(unknown.bundleIDs.isEmpty)
    }

    @Test("the ring replaces a write about the same thing and keeps the last twenty")
    func ring() {
        func addition(_ id: UUID, _ sequence: Int) -> SharedAddition {
            SharedAddition(id: id, sequence: sequence, title: "\(sequence)", isApp: false, bundleIDs: [], hosts: [], rule: nil, half: .rules, origin: "mac", platform: .mac, addedAt: noon)
        }
        let same = UUID()
        var ring = SharedAdditions.appended([], addition(same, 1))
        ring = SharedAdditions.appended(ring, addition(UUID(), 2))
        ring = SharedAdditions.appended(ring, addition(same, 3))
        #expect(ring.map(\.sequence) == [2, 3])
        for sequence in 4...30 { ring = SharedAdditions.appended(ring, addition(UUID(), sequence)) }
        #expect(ring.count == SharedAdditions.ringSize)
        #expect(ring.first?.sequence == 11)
        #expect(ring.last?.sequence == 30)
    }
}

@Suite("Shared additions: hearing what was added")
struct SharedAdditionsHearTests {
    let noon = at(8, 12, 0)

    func addition(
        _ title: String,
        isApp: Bool = true,
        bundleIDs: [String] = [],
        hosts: [String] = [],
        rule: Rule? = nil,
        half: Half = .rules,
        origin: String = "phone",
        sequence: Int = 1,
        id: UUID = UUID()
    ) -> SharedAddition {
        SharedAddition(
            id: id, sequence: sequence, title: title, isApp: isApp, bundleIDs: bundleIDs, hosts: hosts,
            rule: rule, half: half, origin: origin, platform: .phone, addedAt: noon
        )
    }

    var roster: DeviceLink.Roster {
        var roster = DeviceLink.Roster()
        roster.devices = [
            DeviceLink.entry(id: "phone", name: "iPhone", platform: .phone, existing: nil, now: at(8, 9, 0)),
            DeviceLink.entry(id: "mac", name: "Mac", platform: .mac, existing: nil, now: at(8, 9, 0)),
        ]
        return roster
    }

    @Test("unseen is what is past each source's watermark, from devices on the link, oldest first")
    func unseen() {
        var first = addition("TikTok", sequence: 1)
        first.addedAt = at(8, 10, 0)
        let second = addition("YouTube", sequence: 2)
        let stranger = addition("Reddit", origin: "stranger", sequence: 9)
        let mine = addition("Mine", origin: "mac", sequence: 5)
        let rings = ["phone": [first, second], "stranger": [stranger], "mac": [mine]]
        let all = SharedAdditions.unseen(rings: rings, watermarks: [:], thisDevice: "mac", roster: roster)
        #expect(all.map(\.title) == ["TikTok", "YouTube"])
        let some = SharedAdditions.unseen(rings: rings, watermarks: ["phone": 1], thisDevice: "mac", roster: roster)
        #expect(some.map(\.title) == ["YouTube"])
        let declined = SharedAdditions.unseen(rings: rings, watermarks: [:], declined: [second.id.uuidString], thisDevice: "mac", roster: roster)
        #expect(declined.map(\.title) == ["TikTok"])
        #expect(SharedAdditions.unseen(rings: rings, watermarks: ["phone": 2], thisDevice: "mac", roster: roster).isEmpty)
    }

    /// This bundle is the Mac's, where every door is a row of its own: the app lands as one row
    /// and the site as another, the way the Mac's companion sheet has always added them.
    @Test("the Mac lands an installed app and the site as rows of their own")
    func macFindsTheApp() {
        var config = makeConfig([])
        let youtube = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"])
        let landing = SharedAdditions.landing(for: youtube, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon)
        #expect(landing.existing == nil)
        #expect(landing.appBundleID == "com.google.ios.youtube")
        #expect(landing.appName == "YouTube")
        #expect(landing.hosts == ["youtube.com"])
        #expect(!landing.appNeedsPicker)
        #expect(!landing.isNothing)
        let ids = SharedAdditions.land(landing, in: &config, now: noon)
        #expect(ids.count == 2)
        let app = config.target(id: ids[0])!
        #expect(app.kind == .macApp(bundleID: "com.google.ios.youtube"))
        #expect(app.systemName == "YouTube")
        #expect(app.rule == nil)
        #expect(app.addedAt == noon)
        #expect(config.target(id: ids[1])?.kind == .host("youtube.com"))
        #expect(!config.anchor.contains(.host("youtube.com")))
        // Landed once: the same addition again is nothing to do.
        #expect(SharedAdditions.landing(for: youtube, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon).isNothing)
    }

    @Test("with no such app installed, at least the site lands — under Always, the table's too")
    func macWithoutTheApp() {
        var config = makeConfig([])
        let youtube = addition("YouTube", bundleIDs: ["com.google.ios.youtube"])
        let always = SharedAdditions.landing(for: youtube, in: config, installed: [:], companion: .always, now: noon)
        #expect(always.appBundleID == nil)
        #expect(always.hosts == ["youtube.com"])
        let ids = SharedAdditions.land(always, in: &config, now: noon)
        #expect(ids.count == 1)
        #expect(config.target(id: ids[0])?.kind == .host("youtube.com"))
        // Under Never only what the sender blocks is taken, which here is nothing at all.
        let never = SharedAdditions.landing(for: youtube, in: makeConfig([]), installed: [:], companion: .never, now: noon)
        #expect(never.isNothing)
        #expect(SharedAdditions.land(never, in: &config, now: noon).isEmpty)
        // Under Ask the row's own nudge offers the site afterwards; the landing does not.
        let ask = SharedAdditions.landing(for: addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"]), in: makeConfig([]), installed: [:], companion: .ask, now: noon)
        #expect(ask.hosts == ["youtube.com"])
    }

    @Test("a row already covering a door is kept, and only what is missing is added")
    func keepsTheExistingRow() {
        let site = Target(kind: .host("youtube.com"))
        var config = makeConfig([site])
        let youtube = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com", "youtu.be"])
        let landing = SharedAdditions.landing(for: youtube, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon)
        #expect(landing.existing == site.id)
        #expect(landing.appBundleID == "com.google.ios.youtube")
        #expect(landing.hosts == ["youtu.be"])
        let ids = SharedAdditions.land(landing, in: &config, now: noon)
        #expect(ids.first == site.id)
        #expect(ids.count == 3)
        #expect(config.target(id: site.id)?.kind == .host("youtube.com"))
        #expect(config.target(bundleID: "com.google.ios.youtube") != nil)
        #expect(config.target(host: "youtu.be") != nil)
        #expect(config.targets.count == 3)
    }

    @Test("everything already here is nothing to do, and a rule comes only where there is none")
    func nothingAndRules() {
        var row = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), systemName: "YouTube")
        row.also = [.host("youtube.com")]
        var config = makeConfig([row])
        let same = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"])
        #expect(SharedAdditions.landing(for: same, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon).isNothing)
        // The sender's first rule arrives: the row here has none, so it takes it, with the undo
        // window open on it exactly as a rule saved by hand gets.
        let rule = Rule(windows: [window(18 * 60, 20 * 60)], dailyBudgetMinutes: 45)
        let ruled = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"], rule: rule)
        let landing = SharedAdditions.landing(for: ruled, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon)
        #expect(!landing.isNothing)
        #expect(landing.rule == rule)
        #expect(SharedAdditions.land(landing, in: &config, now: noon) == [row.id])
        #expect(config.target(id: row.id)?.rule == rule)
        #expect(config.target(id: row.id)?.undo == RuleUndo(rule: nil, savedAt: noon))
        // A rule of your own is never overwritten.
        let tighter = Rule(windows: [], dailyBudgetMinutes: 5)
        let again = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"], rule: tighter)
        #expect(SharedAdditions.landing(for: again, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon).isNothing)
        #expect(config.target(id: row.id)?.rule == rule)
    }

    @Test("a row is found by learned name when it has no host and no identifier in common")
    func foundByName() {
        var config = makeConfig([])
        config.targets = [Target(kind: .macApp(bundleID: "com.example.tv"), systemName: "YouTube")]
        let youtube = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"])
        let landing = SharedAdditions.landing(for: youtube, in: config, installed: [:], companion: .never, now: noon)
        #expect(landing.existing == config.targets[0].id)
        #expect(landing.appBundleID == nil)
        #expect(landing.hosts == ["youtube.com"])
    }

    @Test("what was added to the anchor is taken into the anchor, unless it is down")
    func anchor() {
        var config = makeConfig([])
        let held = addition("TikTok", isApp: false, hosts: ["tiktok.com"], half: .anchor)
        let landing = SharedAdditions.landing(for: held, in: config, installed: [:], companion: .always, now: noon)
        #expect(landing.hosts == ["tiktok.com"])
        SharedAdditions.land(landing, in: &config, now: noon)
        #expect(config.anchor.contains(.host("tiktok.com")))
        // Down: the row lands, the list does not change under a lock.
        var locked = makeConfig([])
        locked.anchor.kinds = [.host("reddit.com")]
        locked.anchor.isAnchored = true
        locked.anchor.anchoredAt = at(8, 9, 0)
        let twitch = addition("Twitch", isApp: false, hosts: ["twitch.tv"], half: .anchor)
        SharedAdditions.land(SharedAdditions.landing(for: twitch, in: locked, installed: [:], companion: .always, now: noon), in: &locked, now: noon)
        #expect(locked.target(host: "twitch.tv") != nil)
        #expect(!locked.anchor.contains(.host("twitch.tv")))
        // Everything-except: the list is what stays open, so nothing is taken in.
        var wide = makeConfig([])
        wide.anchor.scope = .everythingExcept
        SharedAdditions.land(SharedAdditions.landing(for: twitch, in: wide, installed: [:], companion: .always, now: noon), in: &wide, now: noon)
        #expect(!wide.anchor.contains(.host("twitch.tv")))
    }

    @Test("the offer says who, what and where, in one sentence")
    func summary() {
        let youtube = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"])
        let landing = SharedAdditions.landing(for: youtube, in: makeConfig([]), installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon)
        let text = landing.summary(from: "Your iPhone")
        #expect(text.hasPrefix("Your iPhone added YouTube."))
        #expect(text.contains("the YouTube app"))
        #expect(text.contains("youtube.com"))
        #expect(!text.contains("picker"))
        var withRule = youtube
        withRule.rule = Rule()
        let ruled = SharedAdditions.landing(for: withRule, in: makeConfig([]), installed: [:], companion: .always, now: noon)
        #expect(ruled.summary(from: "Your iPhone").contains("your iPhone's rule"))
    }

    @Test("the addition round-trips as JSON")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let one = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"], rule: Rule(), half: .anchor)
        #expect(try decoder.decode(SharedAddition.self, from: try encoder.encode(one)) == one)
    }
}

/// What crosses when a linked device anchors something, added 2026-09-10. The anchor's list is
/// kinds rather than targets, so it has its own way of saying what is on it; this bundle is
/// built for macOS, so what is described here is a bundle identifier or a host.
@Suite("Shared additions: what the anchor holds")
struct SharedAdditionsAnchorTests {
    let noon = at(8, 12, 0)

    func anchored(_ kinds: [TargetKind], targets: [Target] = [], scope: AnchorProfile.Scope = .chosen) -> Config {
        var config = makeConfig(targets)
        config.anchor.scope = scope
        config.anchor.kinds = kinds
        return config
    }

    func list(_ config: Config, names: [TargetKind: String] = [:], settled: Set<String> = []) -> [SharedAddition] {
        SharedAdditions.anchorList(
            in: config, names: { names }, settled: settled, origin: "mac", platform: .mac, now: noon
        )
    }

    @Test("something the anchor holds and no rule covers still says what it is")
    func heldAlone() throws {
        let config = anchored([.macApp(bundleID: "com.google.Chrome"), .host("tiktok.com")])
        let offers = list(config, names: [.macApp(bundleID: "com.google.Chrome"): "Google Chrome"])
        #expect(offers.map(\.title) == ["Google Chrome", "tiktok.com"])
        let chrome = try #require(offers.first)
        #expect(chrome.half == .anchor)
        #expect(chrome.isApp)
        #expect(chrome.bundleIDs == ["com.google.chrome"])
        // No rule to send: it is on the anchor's list and nowhere else.
        #expect(chrome.rule == nil)
        #expect(offers[1].hosts == ["tiktok.com"])
        #expect(!offers[1].isApp)
    }

    @Test("a name it has not learned keeps it here until it has one")
    func namelessWaits() {
        // The phone's case, in the shape this bundle can build: nothing names the kind, so the
        // table is asked and answers nothing better than the identifier itself.
        let config = anchored([.macApp(bundleID: "com.example.unknown")])
        #expect(list(config).map(\.title) == ["com.example.unknown"])
        #expect(list(config, names: [.macApp(bundleID: "com.example.unknown"): "Unknown"]).map(\.title) == ["Unknown"])
    }

    @Test("a kind a rule already covers crosses as that row, with its other doors and its rule")
    func heldAndRuled() throws {
        var row = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), systemName: "YouTube")
        row.also = [.host("youtube.com")]
        row.rule = Rule(windows: [window(18 * 60, 20 * 60)], dailyBudgetMinutes: 45)
        let config = anchored([.macApp(bundleID: "com.google.ios.youtube")], targets: [row])
        let offer = try #require(list(config).first)
        #expect(offer.id == row.id)
        #expect(offer.half == .anchor)
        #expect(offer.hosts == ["youtube.com"])
        #expect(offer.rule == row.rule)
    }

    @Test("the anchor's list is the ledger: sent and declined names are not offered again")
    func settledNames() {
        let config = anchored([.macApp(bundleID: "com.google.Chrome"), .host("tiktok.com")])
        let names: [TargetKind: String] = [.macApp(bundleID: "com.google.Chrome"): "Google Chrome"]
        #expect(list(config, names: names, settled: ["google chrome"]).map(\.title) == ["tiktok.com"])
        #expect(list(config, names: names, settled: ["google chrome", "tiktok.com"]).isEmpty)
    }

    @Test("two kinds the table calls the same thing are one offer, and a site is its own name")
    func oneOfferPerName() {
        // An Apple silicon Mac runs the iPhone app under its own identifier, so the same app
        // can be on the list twice. A name is what crosses, so it is asked once.
        let twice = anchored([
            .macApp(bundleID: "com.google.ios.youtube"),
            .macApp(bundleID: "maccatalyst.com.google.ios.youtube"),
        ])
        #expect(list(twice).map(\.title) == ["YouTube"])
        // The site is not folded into the app: a host names itself here exactly as it does on
        // the rules half, and blocking youtube.com is a thing to ask about in its own right.
        let both = anchored([.macApp(bundleID: "com.google.ios.youtube"), .host("youtube.com")])
        #expect(list(both).map(\.title) == ["YouTube", "youtube.com"])
    }

    @Test("under everything-except the list is what stays open, so none of it crosses")
    func allowlistNeverCrosses() {
        let config = anchored([.macApp(bundleID: "com.google.Chrome")], scope: .everythingExcept)
        #expect(list(config).isEmpty)
        #expect(list(anchored([])).isEmpty)
    }

    @Test("the id an unruled thing goes out under follows its name, and only its name")
    func derivedID() {
        #expect(SharedAdditions.anchorID(forTitle: "YouTube") == SharedAdditions.anchorID(forTitle: "YouTube"))
        // The same normalization the rest of the table matches on, so a ring entry does not
        // double over a difference nothing else here treats as one.
        #expect(SharedAdditions.anchorID(forTitle: "YouTube") == SharedAdditions.anchorID(forTitle: " youtube "))
        #expect(SharedAdditions.anchorID(forTitle: "YouTube") != SharedAdditions.anchorID(forTitle: "TikTok"))
        // Well-formed: version 4 and the RFC variant, so nothing downstream chokes on it.
        let text = SharedAdditions.anchorID(forTitle: "YouTube").uuidString
        #expect(text.dropFirst(14).first == "4")
        #expect("89AB".contains(text.dropFirst(19).first!))
    }

    @Test("a ring entry about the same held thing replaces the one before it")
    func ringReplaces() throws {
        let config = anchored([.host("tiktok.com")])
        let first = try #require(list(config).first)
        let again = try #require(list(anchored([.host("tiktok.com"), .host("reddit.com")])).first)
        #expect(first.id == again.id)
        #expect(SharedAdditions.appended([first], again).count == 1)
    }
}

/// The receiving end of an anchored addition: what it does that a rules one does not.
@Suite("Shared additions: taking in what another device anchored")
struct SharedAdditionsAnchorLandingTests {
    let noon = at(8, 12, 0)

    func addition(_ title: String, bundleIDs: [String] = [], hosts: [String] = [], half: Half = .anchor) -> SharedAddition {
        SharedAddition(
            id: UUID(), sequence: 1, title: title, isApp: !bundleIDs.isEmpty, bundleIDs: bundleIDs,
            hosts: hosts, rule: nil, half: half, origin: "phone", platform: .phone, addedAt: noon
        )
    }

    /// The case the whole feature turns on. Both devices already block YouTube; the phone
    /// anchors it; the Mac has no app to add, no host to add and no rule to take — and must
    /// still put it on its own anchor's list, which is the only thing the message was about.
    @Test("something already blocked here and not anchored here is not nothing")
    func alreadyBlockedNotYetHeld() {
        var row = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), systemName: "YouTube")
        row.also = [.host("youtube.com")]
        row.rule = Rule(windows: [window(18 * 60, 20 * 60)], dailyBudgetMinutes: 45)
        var config = makeConfig([row])
        let held = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], hosts: ["youtube.com"])
        let landing = SharedAdditions.landing(for: held, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon)
        #expect(landing.appBundleID == nil)
        #expect(landing.hosts.isEmpty)
        #expect(landing.rule == nil)
        #expect(landing.anchors)
        #expect(!landing.isNothing)
        #expect(SharedAdditions.land(landing, in: &config, now: noon) == [row.id])
        // Every door of it, because the anchor takes a row in as one thing.
        #expect(config.anchor.contains(.macApp(bundleID: "com.google.ios.youtube")))
        #expect(config.anchor.contains(.host("youtube.com")))
        // And now it really is nothing: said twice changes nothing the second time.
        let again = SharedAdditions.landing(for: held, in: config, installed: ["com.google.ios.youtube": "YouTube"], companion: .always, now: noon)
        #expect(!again.anchors)
        #expect(again.isNothing)
    }

    @Test("the same message on the rules half leaves the anchor's list alone")
    func rulesHalfDoesNot() {
        var row = Target(kind: .macApp(bundleID: "com.google.ios.youtube"), systemName: "YouTube")
        row.rule = Rule()
        let config = makeConfig([row])
        let ruled = addition("YouTube", bundleIDs: ["com.google.ios.youtube"], half: .rules)
        let landing = SharedAdditions.landing(for: ruled, in: config, installed: [:], companion: .never, now: noon)
        #expect(!landing.anchors)
        #expect(landing.isNothing)
    }

    @Test("nothing goes on the list under a lock, or where the list is what stays open")
    func refusals() {
        var locked = makeConfig([Target(kind: .host("youtube.com"))])
        locked.anchor.isAnchored = true
        locked.anchor.anchoredAt = at(8, 9, 0)
        let held = addition("YouTube", hosts: ["youtube.com"])
        #expect(!SharedAdditions.landing(for: held, in: locked, installed: [:], companion: .never, now: noon).anchors)
        var wide = makeConfig([Target(kind: .host("youtube.com"))])
        wide.anchor.scope = .everythingExcept
        #expect(!SharedAdditions.landing(for: held, in: wide, installed: [:], companion: .never, now: noon).anchors)
        // An anchor that lifted between the offer and the answer still refuses at the last step.
        var config = makeConfig([Target(kind: .host("youtube.com"))])
        let landing = SharedAdditions.landing(for: held, in: config, installed: [:], companion: .never, now: noon)
        #expect(landing.anchors)
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = at(8, 9, 0)
        SharedAdditions.land(landing, in: &config, now: noon)
        #expect(!config.anchor.contains(.host("youtube.com")))
    }

    @Test("the offer says it was anchored, and that it goes on the list here")
    func summary() {
        var config = makeConfig([Target(kind: .host("youtube.com"))])
        config.targets[0].rule = Rule()
        let held = addition("YouTube", hosts: ["youtube.com"])
        let nothingNew = SharedAdditions.landing(for: held, in: config, installed: [:], companion: .never, now: noon)
        let text = nothingNew.summary(from: "Your iPhone")
        #expect(text == "Your iPhone anchored YouTube. Hold it here too?")
        let fresh = SharedAdditions.landing(for: held, in: makeConfig([]), installed: [:], companion: .never, now: noon)
        #expect(fresh.summary(from: "Your iPhone").contains("It goes on the Anchor's list here too."))
        // The rules half says what it always said.
        let added = addition("YouTube", hosts: ["youtube.com"], half: .rules)
        let rules = SharedAdditions.landing(for: added, in: makeConfig([]), installed: [:], companion: .never, now: noon)
        #expect(rules.summary(from: "Your iPhone").hasPrefix("Your iPhone added YouTube."))
        #expect(!rules.summary(from: "Your iPhone").contains("Anchor"))
    }
}

/// The one arrival the phone cannot act on by name. This bundle is the Mac's, so the phone's
/// branch is pinned by the `appNeedsPicker` shape rather than reached through `landing`.
@Suite("Shared additions: an anchored app a phone cannot mint a token for")
struct SharedAdditionsOwedAppTests {
    let noon = at(8, 12, 0)

    func landing(half: Half, hosts: [String] = []) -> SharedAdditions.Landing {
        SharedAdditions.Landing(
            addition: SharedAddition(
                id: UUID(), sequence: 1, title: "Slack", isApp: true,
                bundleIDs: ["com.tinyspeck.slackmacgap"], hosts: hosts, rule: nil, half: half,
                origin: "mac", platform: .mac, addedAt: noon
            ),
            existing: nil, appBundleID: nil, appName: nil, hosts: hosts,
            appNeedsPicker: true, rule: nil, anchors: !hosts.isEmpty
        )
    }

    /// An app with no website, anchored on the Mac. Nothing here can be blocked under that
    /// name, and yet this is exactly the message the anchor half is for: it has to survive
    /// long enough for the tables, or the person, to find the app.
    @Test("an anchored app with no site to fall back on is not nothing")
    func owed() {
        let anchored = landing(half: .anchor)
        #expect(anchored.owesAnchoredApp)
        #expect(!anchored.isNothing)
        #expect(anchored.summary(from: "Your Mac").hasPrefix("Your Mac anchored Slack."))
        #expect(anchored.summary(from: "Your Mac").contains("Change apps here"))
        // The rules half is untouched: an app with no site and no rule still says nothing.
        let added = landing(half: .rules)
        #expect(!added.owesAnchoredApp)
        #expect(added.isNothing)
    }
}
