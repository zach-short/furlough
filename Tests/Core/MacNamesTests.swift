import Foundation
import Testing

/// The one-time move of a Mac target's own name from `nickname` into `systemName`, run over
/// existing state: a typed name must survive, and an uninstalled app is never guessed at.
@MainActor
struct MacNamesTests {
    /// The names the Mac would look up, and the ones it cannot find.
    private let installed = ["com.apple.Safari": "Safari", "com.apple.Chess": "Chess"]

    private func lookup(_ bundleID: String) -> String? { installed[bundleID] }

    private func config(_ targets: [Target]) -> Config {
        var config = Config()
        config.targets = targets
        return config
    }

    @Test func theAppsOwnNameMovesAndTheNicknameGoesEmpty() {
        var config = config([Target(kind: .macApp(bundleID: "com.apple.Safari"), nickname: "Safari")])
        #expect(MacNames.adopt(&config, name: lookup))
        #expect(config.targets[0].systemName == "Safari")
        #expect(config.targets[0].nickname.isEmpty)
        #expect(config.targets[0].displayName == "Safari")
    }

    @Test func aNameZachTypedIsHisAndStays() {
        var config = config([Target(kind: .macApp(bundleID: "com.apple.Safari"), nickname: "The browser")])
        #expect(MacNames.adopt(&config, name: lookup))
        #expect(config.targets[0].systemName == "Safari")
        #expect(config.targets[0].nickname == "The browser")
        #expect(config.targets[0].displayName == "The browser")
    }

    @Test func anAppThatIsNoLongerInstalledIsLeftExactlyAsItIs() {
        var config = config([Target(kind: .macApp(bundleID: "com.example.Gone"), nickname: "Gone")])
        #expect(!MacNames.adopt(&config, name: lookup))
        #expect(config.targets[0].systemName == nil)
        #expect(config.targets[0].nickname == "Gone")
        #expect(config.targets[0].displayName == "Gone")
    }

    @Test func aHostLosesTheNicknameThatOnlyRepeatedIt() {
        var config = config([Target(kind: .host("youtube.com"), nickname: "youtube.com")])
        #expect(MacNames.adopt(&config, name: lookup))
        #expect(config.targets[0].nickname.isEmpty)
        #expect(config.targets[0].displayName == "youtube.com")
    }

    @Test func aHostKeepsANicknameThatSaysSomething() {
        var config = config([Target(kind: .host("youtube.com"), nickname: "YouTube")])
        #expect(!MacNames.adopt(&config, name: lookup))
        #expect(config.targets[0].nickname == "YouTube")
    }

    @Test func aSecondRunChangesNothing() {
        var config = config([
            Target(kind: .macApp(bundleID: "com.apple.Safari"), nickname: "Safari"),
            Target(kind: .host("youtube.com"), nickname: "youtube.com"),
        ])
        #expect(MacNames.adopt(&config, name: lookup))
        let after = config
        #expect(!MacNames.adopt(&config, name: lookup))
        #expect(config == after)
    }

    @Test func aTargetAddedSinceTheFixIsSkipped() {
        var config = config([
            Target(kind: .macApp(bundleID: "com.apple.Chess"), nickname: "Time sink", systemName: "Chess")
        ])
        #expect(!MacNames.adopt(&config, name: lookup))
        #expect(config.targets[0].systemName == "Chess")
        #expect(config.targets[0].nickname == "Time sink")
    }

    // Clearing the field is what this all exists for: falls back to the app's own name, not the bundle ID.
    @Test func clearingANicknameFallsBackToTheAppsOwnName() {
        var target = Target(kind: .macApp(bundleID: "com.apple.Safari"), nickname: "Safari")
        var config = config([target])
        MacNames.adopt(&config, name: lookup)
        target = config.targets[0]
        target.nickname = "Mine"
        #expect(target.displayName == "Mine")
        target.nickname = ""
        #expect(target.displayName == "Safari")
    }
}
