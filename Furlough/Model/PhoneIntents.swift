import AppIntents
import Foundation

// `DropAnchorIntent` moved to `Shared/Intents/DropAnchorIntent.swift` on 2026-09-09, so the
// widget extension can run it behind a Control Center control and a widget button. It drops
// through `AnchorDrop` in `Shared/Core` and never reaches `AppModel`; the app hears of the
// drop through `SharedStore.announceChange`.

/// Weighs anchor — which means opening Furlough and asking for the tag.
///
/// It cannot be done in the background and it is not meant to be. Core NFC only reads for an
/// app that is in front, and the tag is the whole mechanism: the Anchor's friction is a thing
/// you have to walk to, not a screen you have to find. So this saves the walk to the app and
/// nothing else — the scan still has to succeed, with the paired tag, or the anchor holds.
struct WeighAnchorIntent: AppIntent {
    static let title: LocalizedStringResource = "Weigh Anchor"
    static let description = IntentDescription(
        "Opens Furlough and asks for the paired tag. Without the tag, nothing is unlocked.",
        categoryName: "Anchor",
        searchKeywords: ["anchor", "unlock", "unanchor", "tag", "nfc"]
    )
    /// Has to be. The NFC sheet belongs to the foreground app; there is no reading a tag from
    /// a background intent, and no unlocking without reading one.
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppModel.shared.requestWeighAnchor() }
        return .result()
    }
}

/// What Spotlight puts under Furlough's name, in the order it draws them.
///
/// Three, because the row beside the app icon holds three, and these are the three worth a
/// slot: the two halves of the Anchor — kept apart because they behave differently, one
/// instant and silent, one opening the app for the tag — and the question that needs no app
/// at all. Everything else Furlough can do either loosens a rule, which is not allowed to
/// happen in one tap, or wants the editor in front of you.
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
            // SF Symbols has no anchor, and this slot takes an SF Symbol name and nothing else:
            // the system draws the row beside the app's name in Spotlight, out of our process,
            // where the app's own `anchor` symbol (Shared/UI/Ember.xcassets, drawn by
            // scripts/make-anchor-symbol.swift) cannot be reached. Naming it here drew an empty
            // circle — seen in Spotlight on the phone, 2026-09-09. A lock is what the drop
            // does, and it is the one honest symbol Apple ships for it. The custom anchor is
            // still right in `DropAnchorControl`, which renders inside our own extension.
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
