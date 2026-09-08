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

    @Test("a config written before the brick and the schema version decodes")
    func configWithoutBrick() throws {
        let config = try decode(Config.self, #"{"targets":[],"loosenDelayHours":24}"#)
        #expect(config.brick == BrickProfile())
        #expect(!config.brick.isBricked)
        #expect(config.brick.tagID == nil)
        #expect(config.schemaVersion == 1)
        #expect(config.loosenDelayHours == 24)
    }

    @Test("a stored brick comes back whole")
    func configWithBrick() throws {
        let json = #"{"targets":[],"loosenDelayHours":48,"schemaVersion":1,"brick":{"kinds":[],"isBricked":true}}"#
        let config = try decode(Config.self, json)
        #expect(config.brick.isBricked)
        #expect(config.loosenDelayHours == 48)
    }

    @Test("a whole state survives a round trip")
    func roundTrip() throws {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320, .weekdays)], dailyBudgetMinutes: 30))
        var original = makeState([youTube], pending: [
            PendingChange(kind: .setRule(targetID: youTube.id, rule: .unrestricted), createdAt: at(7), effectiveAt: at(9)),
        ])
        original.config.brick.kinds = [.macApp(bundleID: "com.apple.Safari")]
        original.config.brick.isBricked = true
        original.config.brick.brickedAt = at(8)
        original.config.brick.tagID = Data([1, 2, 3, 4])
        original.runtime.exhausted["x"] = "2026-09-08"

        let restored = try decoder.decode(SharedState.self, from: encoder.encode(original))
        #expect(restored == original)
    }

    @Test("a rule with no windows decodes as open all day")
    func ruleWithoutWindows() throws {
        let rule = try decode(Rule.self, #"{"windows":[],"dailyBudgetMinutes":30}"#)
        #expect(rule.isAllDay)
        #expect(rule.isEverAllowed)
    }
}
