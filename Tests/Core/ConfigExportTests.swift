import Foundation
import Testing

/// The file Furlough hands out. Two things are being held to: a Mac setup survives the round
/// trip whole, and nothing that should not leave the device leaves with it.
@Suite("Exporting a setup")
struct ConfigExportTests {
    /// A Mac config with one app, one website, and one target nobody has ruled on yet.
    func sample() -> SharedState {
        var state = SharedState()
        state.config.loosenDelayHours = 48
        state.config.targets = [
            Target(
                kind: .macApp(bundleID: "com.google.Chrome"),
                nickname: "The bad one",
                rule: Rule(windows: [TimeWindow(startMinute: 1020, endMinute: 1140, days: .weekdays)], dailyBudgetMinutes: 30),
                systemName: "Google Chrome",
                utilityLevel: .hazard
            ),
            Target(kind: .host("youtube.com"), rule: .alwaysBlocked, systemName: "youtube.com"),
            Target(kind: .macApp(bundleID: "com.apple.Safari"), systemName: "Safari"),
        ]
        return state
    }

    @Test("a Mac target travels as the identifier another Mac can look up")
    func macTargetsCarryTheirIdentifier() {
        let export = ConfigExport.current(sample())
        #expect(export.platform == .mac)
        #expect(export.loosenDelayHours == 48)
        #expect(export.targets.map(\.identifier) == ["com.google.Chrome", "youtube.com", "com.apple.Safari"])
        #expect(export.targets.map(\.kind) == [.app, .website, .app])
    }

    @Test("the two names stay apart")
    func nameAndNicknameAreSeparate() {
        let chrome = ConfigExport.current(sample()).targets[0]
        #expect(chrome.name == "Google Chrome")
        #expect(chrome.nickname == "The bad one")
        // Nothing typed in, so nothing written down: the field is absent rather than empty.
        #expect(ConfigExport.current(sample()).targets[1].nickname == nil)
    }

    @Test("a tier that was chosen is a word, and one that was not is absent")
    func tiersTravelAsWords() throws {
        let targets = ConfigExport.current(sample()).targets
        #expect(targets[0].utility == .hazard)
        #expect(targets[0].utility?.utility == .hazard)
        #expect(targets[2].utility == nil)
        let json = try String(decoding: ConfigExport.current(sample()).json(), as: UTF8.self)
        #expect(json.contains("\"utility\" : \"hazard\""))
    }

    @Test("a target with no rule exports no rule")
    func unconfiguredTargetCarriesNoRule() {
        let targets = ConfigExport.current(sample()).targets
        #expect(targets[0].rule?.dailyBudgetMinutes == 30)
        #expect(targets[1].rule == .alwaysBlocked)
        #expect(targets[2].rule == nil)
    }

    @Test("the file round-trips")
    func roundTrips() throws {
        let export = ConfigExport.current(sample())
        let decoded = try ConfigExport.decode(try export.json())
        #expect(decoded.version == ConfigExport.currentVersion)
        #expect(decoded.targets == export.targets)
        #expect(decoded.loosenDelayHours == export.loosenDelayHours)
        // ISO8601 keeps whole seconds only, so the dates match to the second, not the instant.
        #expect(abs(decoded.exportedAt.timeIntervalSince(export.exportedAt)) < 1)
    }

    @Test("nothing that belongs to the device goes in the file")
    func runtimeAndAnchorStayHome() throws {
        var state = sample()
        state.config.anchor = AnchorProfile(
            kinds: [.host("youtube.com")],
            isAnchored: true,
            anchoredAt: .now,
            tags: [PairedTag(id: Data([1, 2, 3]), name: "Home")]
        )
        state.pending = [PendingChange(kind: .setDelay(hours: 1), effectiveAt: .now)]
        state.runtime.exhausted = ["\(state.config.targets[0].id.uuidString)": Policy.dayKey(.now)]
        let json = try String(decoding: ConfigExport.current(state).json(), as: UTF8.self)
        for leak in ["anchor", "tags", "Home", "isAnchored", "pending", "exhausted", "clock"] {
            #expect(!json.contains(leak), "the file mentions \(leak)")
        }
    }
}
