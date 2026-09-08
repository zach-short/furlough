import AppIntents
import Foundation

/// Drops the anchor without opening Furlough.
///
/// Safe to run from anywhere precisely because it only tightens. Anchoring needs no tag —
/// weighing anchor does — so this is the one half that can happen in the background, and it
/// is the half worth having at the end of a Spotlight search or on a Shortcuts automation
/// ("at 10pm, drop anchor"). Nothing here can let anything through.
struct DropAnchorIntent: AppIntent {
    static let title: LocalizedStringResource = "Drop Anchor"
    static let description = IntentDescription(
        "Locks everything the Anchor holds. Only the paired tag lifts it again.",
        categoryName: "Anchor",
        searchKeywords: ["anchor", "lock", "block", "brick"]
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await MainActor.run { () -> String in
            let model = AppModel.shared
            model.reload()
            let anchor = model.state.config.anchor
            guard !anchor.isAnchored else { return "Already anchored." }
            switch model.anchor() {
            case .anchored:
                return "Anchored. \(anchor.count) \(anchor.count == 1 ? "thing" : "things")"
                    + " locked until you scan your tag."
            case .failed(let why):
                return why
            default:
                return "Nothing changed."
            }
        }
        return .result(dialog: "\(answer)")
    }
}

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
            // Not a system image: SF Symbols has no anchor, and a shortcut takes a name and
            // nothing else, so the app ships one custom symbol drawn from the same path as
            // the mark in the app. See scripts/make-anchor-symbol.swift.
            systemImageName: "anchor"
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
