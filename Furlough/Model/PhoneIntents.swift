import AppIntents
import Foundation

// `DropAnchorIntent` lives in `Shared/Intents/DropAnchorIntent.swift` so the widget extension
// can run it behind a Control Center control and a widget button. It goes through `AnchorDrop`
// in `Shared/Core` and never reaches `AppModel`; the app hears of the drop through
// `SharedStore.announceChange`.

/// Opens Furlough and asks for the tag. Cannot run in the background: Core NFC only reads for
/// a foreground app.
struct WeighAnchorIntent: AppIntent {
    static let title: LocalizedStringResource = "Weigh Anchor"
    static let description = IntentDescription(
        "Opens Furlough and asks for the paired tag. Without the tag, nothing is unlocked.",
        categoryName: "Anchor",
        searchKeywords: ["anchor", "unlock", "unanchor", "tag", "nfc"]
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppModel.shared.requestWeighAnchor() }
        return .result()
    }
}

/// The three shortcuts Spotlight shows under Furlough's name, in this order.
struct FurloughShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DropAnchorIntent(),
            phrases: [
                "Drop anchor in \(.applicationName)",
                "Anchor with \(.applicationName)",
                "Lock my apps with \(.applicationName)"
            ],
            shortTitle: "Drop Anchor",
            // This slot only accepts an SF Symbol name (rendered by the system out-of-process),
            // so the app's custom `anchor` glyph (Shared/UI/Ember.xcassets) can't be used here —
            // naming it drew an empty circle. `DropAnchorControl` still uses the custom glyph
            // since it renders inside our own extension.
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: WeighAnchorIntent(),
            phrases: [
                "Weigh anchor in \(.applicationName)",
                "Unanchor in \(.applicationName)"
            ],
            shortTitle: "Weigh Anchor",
            systemImageName: "tag.fill"
        )
        AppShortcut(
            intent: WhatsOpenIntent(),
            phrases: [
                "What's open in \(.applicationName)",
                "Ask \(.applicationName) what's open"
            ],
            shortTitle: "What's Open",
            systemImageName: "hourglass"
        )
    }
}
