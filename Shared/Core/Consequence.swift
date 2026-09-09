import Foundation

/// What a rule is about to do, said before it is saved.
///
/// The cheapest forgiveness is the kind nobody needs. Most of the trouble a beginner gets into
/// is not that they cannot undo a rule, it is that they could not see what the rule meant: a
/// 30-minute budget reads like a generous allowance until it runs out at ten past nine and the
/// app says "tomorrow". So the editor says both halves out loud while there is still nothing to
/// undo — what today looks like under this rule, and what changing your mind will cost.
///
/// Pure, and here rather than in the editor, because it is the sentence the whole feature turns
/// on and a sentence that is wrong is worse than no sentence.
enum Consequence {
    struct Preview: Equatable {
        /// What the rule does today, in one sentence.
        var today: String
        /// What changing your mind costs, in one sentence.
        var undoing: String
    }

    /// The two sentences for `rule` on `target`, or nil when there is nothing worth saying.
    ///
    /// Nil for a loosening: the editor already says a loosening waits, and naming a window that
    /// will not exist for another day would be a second, quieter answer to the same question.
    /// Nil too when nothing changes.
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
        // The sentence is about today, so it is today's budget that is quoted: since the
        // per-weekday budgets landed there is no one figure for the week to fall back on.
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

    /// Today's open stretches as they are read, a night counted as the one span it is.
    ///
    /// A night is stored as an evening ending at midnight plus a morning starting at it on the
    /// day after, so an evening is said through to the morning it really ends in — `Policy.end`,
    /// the same join the status line uses, so neither says a window shuts at midnight when it
    /// does not.
    ///
    /// The morning half is *not* dropped on the day it falls, which it is tempting to do on the
    /// grounds that yesterday's sentence already covered it. Yesterday's sentence was read
    /// yesterday. On Wednesday morning a rule that runs 8 PM to 4 AM is open, and a preview
    /// that answered "blocked all day today" would be plainly false to someone holding the
    /// phone at 2 AM.
    private static func openSpans(in rule: Rule, on weekday: Int, calendar: Calendar) -> [String] {
        rule.windows(on: weekday).map { window in
            let end = Policy.end(of: window, in: rule, on: weekday)
            return "\(TimeFormat.minute(window.startMinute, calendar: calendar))–\(TimeFormat.until(end, calendar: calendar))"
        }
    }

    /// What it costs to take this back, which is the number the editor exists to say early.
    static func undoing(
        for target: Target?,
        config: Config,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let full = TimeFormat.delay(hours: config.fullDelayHours(for: target))
        let window = "\(Furlough.undoWindowMinutes) minutes"
        // Nothing is enforced yet, so this rule is the target's first and its own baseline:
        // there is no earlier rule to put back, and removing it is all there is to undo.
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
