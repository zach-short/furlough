#if os(iOS)
import Foundation

/// Single entry point for dropping the anchor from any process (app, widget-extension intent,
/// Shortcut) so every path shares the same store write, reconcile, and log line. Wraps the
/// pure, tested `Policy.drop` with the actual I/O.
///
/// Deliberately has no release/lift function: only a tag scan in the app may lift the anchor.
enum AnchorDrop {
    enum Outcome: Equatable {
        case anchored(AnchorProfile)
        case refused(Policy.DropRefusal)
    }

    @discardableResult
    static func drop(until: Date? = nil, reason: String) -> Outcome {
        var state = SharedStore.load()
        let now = state.now
        Policy.applyDuePending(&state, now: now)
        if let refusal = Policy.drop(&state.config, now: now, until: until) {
            return .refused(refusal)
        }
        SharedStore.save(state)
        let lift = until.map { " until \(TimeFormat.clock($0))" } ?? ""
        SharedStore.log("anchored (\(reason)): \(state.config.anchor.heldDescription)\(lift)")
        ShieldReconciler.reconcile(now: now, reason: reason)
        AnchorSync.publish(state.config.anchor, origin: .drop, now: now)
        SharedStore.announceChange()
        return .anchored(state.config.anchor)
    }
}
#endif
