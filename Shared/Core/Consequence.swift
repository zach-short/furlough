import Foundation

/// What a rule is about to do, said before it is saved: what today looks like under it, and
/// what changing your mind will cost. Said up front because most beginner trouble isn't being
/// unable to undo a rule, it's not seeing what the rule meant until the budget runs out.
enum Consequence {
    struct Preview: Equatable {
        /// What the rule does today, in one sentence.
        var today: String
        /// What changing your mind costs, in one sentence.
        var undoing: String
    }

    /// The two sentences for `rule` on `target`, or nil when nothing changes or the change is a
    /// loosening (the editor already says a loosening waits; naming a window that won't exist
    /// yet would be a second, quieter answer to the same question).
    static func preview(
        rule: Rule,
        for target: Target?,
        config: Config,
        now: Date,
        calendar: Calendar = .current
    ) -> Preview? {
        guard rule.validationError == nil else { return nil }
        if let target, target.rule?.isEquivalent(to: rule) == true { return nil }
        guard Policy.classify(newRule: rule, against: target) == .tightening else { return nil }
        return Preview(
            today: today(rule: rule, now: now, calendar: calendar),
            undoing: undoing(for: target, config: config, now: now, calendar: calendar)
        )
    }

    /// "Open 9:00 AM–5:00 PM today, up to 30 min. Blocked the rest of the day."
    static func today(rule: Rule, now: Date, calendar: Calendar = .current) -> String {
        guard rule.isEverAllowed else { return "Blocked all day, every day." }
        // Today's budget specifically — per-weekday budgets mean there's no single weekly figure.
        let weekday = Policy.weekday(now, calendar: calendar)
        let budget = rule.limit(on: weekday).map { TimeFormat.budget($0) }
        if rule.isAllDay {
            guard let budget else { return "Open all day." }
            return "Open all day, up to \(budget). Once that is gone, blocked until midnight."
        }
        let spans = openSpans(in: rule, on: weekday, calendar: calendar)
        guard !spans.isEmpty else {
            guard let next = Policy.nextOpen(in: rule, afterWeekday: weekday) else {
                return "Blocked all day, every day."
            }
            return "Blocked all day today. Opens \(TimeFormat.nextOpen(next, from: now, calendar: calendar))."
        }
        let allowance = budget.map { ", up to \($0)" } ?? ""
        return "Open \(list(spans)) today\(allowance). Blocked the rest of the day."
    }

    /// A night (stored as an evening ending at midnight plus the next day's morning) is joined
    /// into one span via `Policy.end`, the same join the status line uses. The morning half is
    /// NOT dropped on the day it falls even though yesterday's sentence already mentioned it —
    /// yesterday's sentence was read yesterday, and someone at 2 AM needs today's to say "open".
    private static func openSpans(in rule: Rule, on weekday: Int, calendar: Calendar) -> [String] {
        rule.windows(on: weekday).map { window in
            let end = Policy.end(of: window, in: rule, on: weekday)
            return "\(TimeFormat.minute(window.startMinute, calendar: calendar))–\(TimeFormat.until(end, calendar: calendar))"
        }
    }

    /// What it costs to take this back.
    static func undoing(
        for target: Target?,
        config: Config,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let full = TimeFormat.delay(hours: config.fullDelayHours(for: target))
        let window = "\(Furlough.undoWindowMinutes) minutes"
        // No existing rule means nothing to put back — removing it is all there is to undo.
        let subject = target?.rule == nil ? "Removing it" : "Loosening it"
        guard config.isInTrial, let ends = config.trialEndsAt else {
            return "You can undo this for \(window) after saving. After that, \(subject.lowercased()) takes \(full)."
        }
        let capped = TimeFormat.delay(hours: config.delayHours(for: target))
        let day = TimeFormat.day(ends, calendar: calendar)
        return "Your first week runs to \(day): until then \(subject.lowercased()) takes \(capped), and after it, \(full)."
    }

    /// "9–5", "9–5 and 7–9", "9–5, 7–9 and 10–11".
    private static func list(_ spans: [String]) -> String {
        switch spans.count {
        case 0: ""
        case 1: spans[0]
        case 2: "\(spans[0]) and \(spans[1])"
        default: "\(spans.dropLast().joined(separator: ", ")) and \(spans[spans.count - 1])"
        }
    }
}
