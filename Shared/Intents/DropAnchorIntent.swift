#if os(iOS)
import AppIntents
import Foundation
import WidgetKit

/// Drops the anchor without opening Furlough. Safe to run from anywhere because it only
/// tightens — anchoring needs no tag, weighing it does — so it works from Spotlight, Shortcuts
/// automations, the medium widget, and Control Center.
///
/// Compiled into both the app and the widget extension: the Control Center control lives in the
/// widget extension with no app process to reach, so this goes through `AnchorDrop`, never
/// `AppModel` — the app learns about it via the change notification the drop posts.
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
        let outcome = AnchorDrop.drop(reason: "intent")
        switch outcome {
        case .anchored(let anchor) where anchor.anchorsEverything:
            answer = "Anchored. \(anchor.heldDescription) is locked until you scan your tag."
        case .anchored(let anchor):
            answer = "Anchored. \(anchor.blockedDescription) until you scan your tag."
        case .refused(let why):
            answer = why.message
        }
        // The Anchor's Live Activity, where this process is allowed to start one: run from
        // Spotlight or Shortcuts it is the app, run from the control or the widget button it is
        // the widget extension, which may only update and end. A refusal there is logged and
        // costs nothing — the next time Furlough is opened, `enforce` starts it.
        if case .anchored = outcome { LiveActivityManager.sync(state: SharedStore.load()) }
        WidgetCenter.shared.reloadAllTimelines()
        // Without this the control keeps showing "Drop Anchor" after it's already dropped.
        ControlCenter.shared.reloadControls(ofKind: Furlough.anchorControlKind)
        return .result(dialog: "\(answer)")
    }
}
#endif
