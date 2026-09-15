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
        "Locks everything the Anchor holds. Only the paired tag lifts it again, or the time you name here.",
        categoryName: "Anchor",
        searchKeywords: ["anchor", "lock", "block", "brick"]
    )
    static let openAppWhenRun = false

    /// The one thing the screen could say that an automation could not: when the anchor lifts.
    /// A time of day rather than a date, because "until 7 AM" in a nightly automation has to
    /// mean tomorrow's 7 AM, and a date is the sharp edge that gets that wrong at 11 PM. Left
    /// empty — as the control, the widget button and the bare phrase leave it — only the tag
    /// lifts it. It can never shorten a hold that exists: `Policy.drop` refuses outright while
    /// the anchor is already down.
    @Parameter(
        title: "Lifts at",
        description: "A time of day. The anchor lifts at the next one — a time already gone today means tomorrow. Leave it empty and only your tag lifts it.",
        kind: .time
    )
    var liftsAt: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer: String
        // Resolved the way the Anchor screen resolves its own "Lifts at", on Furlough's clock.
        let until = liftsAt.map { Policy.liftDate(atMinute: Policy.minuteOfDay($0), from: SharedStore.load().now) }
        let outcome = AnchorDrop.drop(until: until, reason: "intent")
        switch outcome {
        case .anchored(let anchor):
            let lift = anchor.until.map { "until \(TimeFormat.clock($0)), or sooner with your tag" } ?? "until you scan your tag"
            answer = anchor.anchorsEverything
                ? "Anchored. \(anchor.heldDescription) is locked \(lift)."
                : "Anchored. \(anchor.blockedDescription) \(lift)."
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
