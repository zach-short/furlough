#if os(iOS)
import Foundation

/// Drops the anchor from whichever process asks: the app, the Drop Anchor intent running in
/// the widget extension behind a Control Center button or a widget button, a Shortcut. One
/// function, so every path ends in the same store write, the same reconcile and the same log
/// line — the way the monitor extension already works, and the reason the widget extension
/// carries the Family Controls entitlement since 2026-09-09. The decision itself is
/// `Policy.drop`, which is pure and tested; this is the I/O around it.
///
/// Release is not here and must not be: only a tag scan in the app lifts the anchor.
enum AnchorDrop {
    enum Outcome: Equatable {
        case anchored(AnchorProfile)
        case refused(Policy.DropRefusal)
    }

    /// Drops now, until `until` or the tag. `reason` is what the log says.
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
