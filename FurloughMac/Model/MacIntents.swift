import AppIntents
import Foundation

/// Puts Furlough's window on screen.
///
/// Worth an action of its own here in a way it would not be on the phone. The Mac app has no
/// Dock icon once it is onboarded, and its menu bar item is not guaranteed to be visible —
/// on a full menu bar macOS places the overflow under the notch, where the item exists and
/// cannot be seen. This is the way in that does not depend on either.
struct ShowFurloughIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Furlough"
    static let description = IntentDescription(
        "Brings Furlough's window up from the menu bar.",
        categoryName: "Furlough",
        searchKeywords: ["window", "open", "show", "menu bar"]
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { MacAppDelegate.showWindow() }
        return .result()
    }
}

/// What Spotlight puts under Furlough's name on the Mac.
///
/// Two, not the phone's three: there is no Anchor here. It needs a tag to lift and a Mac has
/// no NFC reader, so anchoring on this machine would be a lock with no key — see `MacHero`.
struct FurloughMacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsOpenIntent(),
            phrases: [
                "What's open in \(.applicationName)",
                "Ask \(.applicationName) what's open"
            ],
            shortTitle: "What's Open",
            systemImageName: "hourglass"
        )
        AppShortcut(
            intent: ShowFurloughIntent(),
            phrases: [
                "Show \(.applicationName)",
                "Open the \(.applicationName) window"
            ],
            shortTitle: "Show Furlough",
            systemImageName: "macwindow"
        )
    }
}
