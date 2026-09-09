#if os(iOS)
import AppIntents
import Foundation
import WidgetKit

/// Drops the anchor without opening Furlough.
///
/// Safe to run from anywhere precisely because it only tightens. Anchoring needs no tag —
/// weighing anchor does — so this is the one half that can happen in the background, and it
/// is the half worth having at the end of a Spotlight search, on a Shortcuts automation
/// ("at 10pm, drop anchor"), on the medium widget and in Control Center. Nothing here can let
/// anything through.
///
/// Compiled into the app and the widget extension both, which is what a Control Center
/// control needs: the control lives in the widget extension and runs its intent there, with
/// no app process to reach. So this goes through `AnchorDrop`, never `AppModel`; the app
/// finds out through the change notification the drop posts.
struct DropAnchorIntent: AppIntent {
    static let title: LocalizedStringResource = "Drop Anchor"
    static let description = IntentDescription(
        "Locks everything the Anchor holds. Only the paired tag lifts it again.",
        categoryName: "Anchor",
        searchKeywords: ["anchor", "lock", "block", "brick"]
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer: String
        switch AnchorDrop.drop(reason: "intent") {
        case .anchored(let anchor) where anchor.anchorsEverything:
            answer = "Anchored. \(anchor.heldDescription) is locked until you scan your tag."
        case .anchored(let anchor):
            answer = "Anchored. \(anchor.count) \(anchor.count == 1 ? "thing" : "things") locked until you scan your tag."
        case .refused(let why):
            answer = why.message
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(answer)")
    }
}
#endif
