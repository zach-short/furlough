import AppIntents
import Foundation

/// Needed because the onboarded Mac app has no Dock icon, and a full menu bar can hide its
/// menu bar item under the notch overflow.
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

/// No Anchor shortcut here: anchoring needs an NFC tag to lift, and Macs have no NFC reader.
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
