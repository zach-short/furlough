import Foundation

/// The two halves of a pending card: what is enforced now, and what the queued change
/// replaces it with.
///
/// A card used to name only where the change lands ("New rule: 8:00 PM–midnight ·
/// 60 min/day"), which is the half you already know, because you just wrote it. What is
/// worth reading while there is still time to cancel is what it costs, and that only shows
/// against what you have today.
///
/// The baseline is the target's *saved* rule, and that is exactly right: `assign` on both
/// platforms replaces any rule already queued for a target, so at most one change per target
/// is ever in flight and the saved rule is what stays in force until it lands.
enum PendingText {
    struct Delta: Equatable, Sendable {
        /// What is enforced until the change lands.
        var now: String
        /// What replaces it.
        var becomes: String
    }

    static func delta(
        for change: PendingChange,
        in config: Config,
        calendar: Calendar = .current
    ) -> Delta {
        let target = change.targetID.flatMap { config.target(id: $0) }
        switch change.kind {
        case .setRule(_, let rule):
            return Delta(
                now: TimeFormat.rule(target?.rule, calendar: calendar),
                becomes: TimeFormat.rule(rule, calendar: calendar)
            )
        case .removeTarget:
            return Delta(
                now: TimeFormat.rule(target?.rule, calendar: calendar),
                becomes: "Not managed by Furlough"
            )
        case .setDelay(let hours):
            return Delta(
                now: TimeFormat.delay(hours: config.loosenDelayHours),
                becomes: TimeFormat.delay(hours: hours)
            )
        case .setUtility(_, let level):
            return Delta(
                now: tier(target?.utility ?? .unset, in: config),
                becomes: tier(level, in: config)
            )
        }
    }

    /// A tier and what it buys. The name alone does not say how long the next loosening
    /// waits, which is the only reason the tier is worth changing.
    private static func tier(_ utility: Utility, in config: Config) -> String {
        "\(utility.label) · waits \(TimeFormat.delay(hours: config.delayHours(for: utility)))"
    }
}
