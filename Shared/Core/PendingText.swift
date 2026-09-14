import Foundation

/// The two halves of a pending card: what is enforced now, and what the queued change replaces
/// it with. The baseline is the target's *saved* rule — correct because `assign` on both
/// platforms replaces any rule already queued, so at most one change per target is ever in flight.
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
        case .unlink(_, let kind):
            // A picked website's token has no name of its own, so it's just "the other half".
            let half = kind.hostName ?? "the other half"
            return Delta(
                now: "\(TimeFormat.rule(target?.rule, calendar: calendar)), \(half) too",
                becomes: "\(half) no longer blocked"
            )
        case .setAnchorSchedules(let schedules):
            return Delta(
                now: TimeFormat.anchorSchedules(config.anchor.schedules, calendar: calendar),
                becomes: TimeFormat.anchorSchedules(schedules, calendar: calendar)
            )
        }
    }

    /// The card's header for a change about no single target (the delay, the anchor's
    /// schedule); nil for a change a target's name heads.
    static func subject(of kind: PendingKind) -> String? {
        switch kind {
        case .setDelay: "Loosening delay"
        case .setAnchorSchedules: "Anchor schedule"
        case .setRule, .removeTarget, .setUtility, .unlink: nil
        }
    }

    /// A tier and the wait it buys — the name alone doesn't say how long a loosening waits.
    private static func tier(_ utility: Utility, in config: Config) -> String {
        "\(utility.label) · waits \(TimeFormat.delay(hours: config.delayHours(for: utility)))"
    }
}
