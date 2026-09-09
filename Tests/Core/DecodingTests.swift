import Foundation
import Testing

/// The store on Zach's phone was written by older builds. Every field added since has to
/// decode from a JSON that never had it.
@Suite("Decoding older stored state")
struct DecodingTests {
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

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    @Test("a window written before days existed applies every day")
    func windowWithoutDays() throws {
        let window = try decode(TimeWindow.self, #"{"startMinute":1200,"endMinute":1320}"#)
        #expect(window.days == .all)
        #expect(window.startMinute == 1200)
        #expect(window.endMinute == 1320)
    }

    @Test("days are stored as the bare bit set")
    func daysAreABareInteger() throws {
        let window = try decode(TimeWindow.self, #"{"startMinute":0,"endMinute":60,"days":5}"#)
        #expect(window.days.contains(weekday: 1))
        #expect(!window.days.contains(weekday: 2))
        #expect(window.days.contains(weekday: 3))
        #expect(String(data: try encoder.encode(window.days), encoding: .utf8) == "5")
    }

    @Test("a config written before the anchor and the schema version decodes")
    func configWithoutAnchor() throws {
        let config = try decode(Config.self, #"{"targets":[],"loosenDelayHours":24}"#)
        #expect(config.anchor == AnchorProfile())
        #expect(!config.anchor.isAnchored)
        #expect(config.anchor.tags.isEmpty)
        #expect(config.schemaVersion == 1)
        #expect(config.loosenDelayHours == 24)
    }

    @Test("a stored anchor comes back whole")
    func configWithAnchor() throws {
        let json = #"{"targets":[],"loosenDelayHours":48,"schemaVersion":1,"anchor":{"kinds":[],"isAnchored":true}}"#
        let config = try decode(Config.self, json)
        #expect(config.anchor.isAnchored)
        #expect(config.loosenDelayHours == 48)
    }

    @Test("state written before the rename still reads: brick becomes anchor")
    func legacyBrickKey() throws {
        let json = #"""
        {"targets":[],"loosenDelayHours":24,"schemaVersion":1,
         "brick":{"kinds":[],"isBricked":true,"brickedAt":"2026-09-08T18:12:00Z","tagID":"AQIDBA=="}}
        """#
        let config = try decode(Config.self, json)
        #expect(config.anchor.isAnchored)
        #expect(config.anchor.anchoredAt == at(8, 18, 12))
        #expect(config.anchor.tags == [PairedTag(id: Data([1, 2, 3, 4]), name: "Tag 1")])
        #expect(config.anchor.isPaired)
    }

    @Test("a lone paired tag becomes the first of the list")
    func legacySingleTag() throws {
        let json = #"""
        {"targets":[],"loosenDelayHours":24,"schemaVersion":1,
         "anchor":{"kinds":[],"isAnchored":false,"tagID":"AQIDBA=="}}
        """#
        let config = try decode(Config.self, json)
        #expect(config.anchor.tags == [PairedTag(id: Data([1, 2, 3, 4]), name: "Tag 1")])
        #expect(config.anchor.isPaired)
        #expect(config.anchor.canPairMore)
    }

    @Test("a stored list of tags wins over a lone identifier, and is capped on the way in")
    func storedTagsWinAndAreCapped() throws {
        let json = #"""
        {"targets":[],"loosenDelayHours":24,"schemaVersion":1,
         "anchor":{"kinds":[],"isAnchored":false,"tagID":"AQIDBA==","tags":[
           {"id":"AQ==","name":"Home"},{"id":"Ag==","name":"Apartment"},
           {"id":"Aw==","name":"Desk"},{"id":"BA==","name":"Backpack"}]}}
        """#
        let tags = try decode(Config.self, json).anchor.tags
        #expect(tags.count == Furlough.maxAnchorTags)
        #expect(tags.map(\.name) == ["Home", "Apartment", "Desk"])
    }

    @Test("tags are written back under the new key and read again")
    func tagsRoundTrip() throws {
        var config = Config()
        config.anchor.tags = [PairedTag(id: Data([0xAB, 0xCD]), name: "Apartment")]
        let json = String(data: try encoder.encode(config), encoding: .utf8) ?? ""
        #expect(json.contains("\"tags\""))
        #expect(!json.contains("tagID"))
        #expect(try decode(Config.self, json).anchor.tags == config.anchor.tags)
    }

    @Test("the new keys win when both are somehow present")
    func newKeyWins() throws {
        let json = #"""
        {"targets":[],"loosenDelayHours":24,
         "anchor":{"kinds":[],"isAnchored":false},"brick":{"kinds":[],"isBricked":true}}
        """#
        #expect(try decode(Config.self, json).anchor.isAnchored == false)
    }

    @Test("an anchor is written back under the new names")
    func encodesNewKeys() throws {
        var config = Config()
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = at(8, 18, 12)
        let json = String(data: try encoder.encode(config), encoding: .utf8) ?? ""
        #expect(json.contains("\"anchor\""))
        #expect(json.contains("\"isAnchored\""))
        #expect(!json.contains("brick"))
        // And it reads back.
        #expect(try decode(Config.self, json).anchor.anchoredAt == at(8, 18, 12))
    }

    @Test("a whole state survives a round trip")
    func roundTrip() throws {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320, .weekdays)], dailyBudgetMinutes: 30))
        var original = makeState([youTube], pending: [
            PendingChange(kind: .setRule(targetID: youTube.id, rule: .unrestricted), createdAt: at(7), effectiveAt: at(9)),
        ])
        original.config.anchor.kinds = [.macApp(bundleID: "com.apple.Safari")]
        original.config.anchor.isAnchored = true
        original.config.anchor.anchoredAt = at(8)
        original.config.anchor.tags = [PairedTag(id: Data([1, 2, 3, 4]), name: "Home")]
        original.runtime.exhausted["x"] = "2026-09-08"

        let restored = try decoder.decode(SharedState.self, from: encoder.encode(original))
        #expect(restored == original)
    }

    @Test("a target written before Furlough learned names decodes")
    func targetWithoutSystemName() throws {
        var youTube = makeTarget("YouTube", rule: nil)
        youTube.systemName = "YouTube"
        let json = String(data: try encoder.encode(youTube), encoding: .utf8) ?? ""
        #expect(json.contains("systemName"))
        let older = json
            .replacingOccurrences(of: #""systemName":"YouTube","#, with: "")
            .replacingOccurrences(of: #","systemName":"YouTube""#, with: "")
        #expect(!older.contains("systemName"))
        let restored = try decode(Target.self, older)
        #expect(restored.systemName == nil)
        #expect(restored.displayName == "YouTube")
    }

    @Test("a rule with no windows decodes as open all day")
    func ruleWithoutWindows() throws {
        let rule = try decode(Rule.self, #"{"windows":[],"dailyBudgetMinutes":30}"#)
        #expect(rule.isAllDay)
        #expect(rule.isEverAllowed)
    }
}

/// What a `TargetKind` looks like on disk.
///
/// This matters more than it looks. `TargetKind` gained a case on 2026-09-08 — websites by
/// name on the phone — and the state on Zach's phone was written by builds that had never
/// heard of it. Swift synthesises an enum's `Codable` as a single-key object named after the
/// case, so a new case adds a name nothing older ever wrote and changes nothing about the
/// names already there. These pin that shape, so a later hand-written `init(from:)` or a
/// renamed case cannot quietly make an existing phone's targets undecodable.
///
/// Read on macOS, so the cases here are the Mac's. The mechanism is the same one the phone's
/// three token cases go through; there is no iOS test bundle to read those in.
@Suite("How a target kind is stored")
struct TargetKindDecodingTests {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    @Test("a kind written before the sibling case existed still decodes")
    func olderKindStillDecodes() throws {
        let kind = try decoder.decode(TargetKind.self, from: Data(#"{"macApp":{"bundleID":"com.apple.Safari"}}"#.utf8))
        #expect(kind == .macApp(bundleID: "com.apple.Safari"))
    }

    @Test("each case is stored under its own name")
    func casesAreKeyedByName() throws {
        let app = String(data: try encoder.encode(TargetKind.macApp(bundleID: "com.apple.Safari")), encoding: .utf8)
        #expect(app?.contains("\"macApp\"") == true)
        let host = String(data: try encoder.encode(TargetKind.host("youtube.com")), encoding: .utf8)
        #expect(host?.contains("\"host\"") == true)
        #expect(host?.contains("macApp") == false)
    }

    @Test("a whole config of older targets decodes with the new case in the enum")
    func olderConfigDecodes() throws {
        let json = """
        {"targets":[\
        {"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","kind":{"macApp":{"bundleID":"com.apple.Safari"}},\
        "nickname":"Safari","addedAt":0}],\
        "loosenDelayHours":24,"schemaVersion":1}
        """
        let config = try decoder.decode(Config.self, from: Data(json.utf8))
        #expect(config.targets.count == 1)
        #expect(config.targets[0].kind == .macApp(bundleID: "com.apple.Safari"))
        #expect(config.targets[0].nickname == "Safari")
        #expect(config.targets[0].rule == nil)
        #expect(config.loosenDelayHours == 24)
    }

    @Test("a kind round-trips")
    func roundTrip() throws {
        for kind in [TargetKind.macApp(bundleID: "com.apple.Safari"), .host("youtube.com")] {
            let back = try decoder.decode(TargetKind.self, from: try encoder.encode(kind))
            #expect(back == kind)
        }
    }
}
