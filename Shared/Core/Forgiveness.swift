import Foundation

/// The two things standing between someone new and a lock they did not mean to close.
///
/// Furlough has no emergency unblock and is not getting one: a break, a pause, temporary
/// access and an emergency release are all the same door under four names, and the app is
/// worth nothing if that door exists. But the trap that catches beginners is not craving, it
/// is *arithmetic*. A target's first rule lands instantly, because the baseline for something
/// Furlough has never restricted is "unrestricted"; undoing that same rule is a loosening, and
/// waits `delayHours` — a day for an untiered app, four for a hazard. So a curious tap costs
/// nothing and taking it back costs a day, and the first thing a new user learns is that the
/// app bites people who were only looking at it.
///
/// Two mechanisms answer that, and neither is a door:
///
/// - **The first week.** For `Furlough.trialDays` after Screen Time access is first granted,
///   `Config.delayHours` is capped at `Furlough.trialDelayHours`. Everything else behaves
///   exactly as it will forever: the windows are real, the budgets are real, the shields are
///   real. Only the price of a mistake is held down. It is granted once per install, stated at
///   onboarding, ends on a date fixed the moment it starts, and cannot be extended.
/// - **The undo window.** For `Furlough.undoWindowMinutes` after an edit lands, it can be put
///   back exactly as it was. See `RuleUndo`: it can only ever restore the rule that was
///   already there, so it is no use to anyone who wants out and every use to someone who
///   mistyped a budget.
///
/// The anchor gets neither, in the trial week or any other. Pairing a tag requires the tag in
/// hand at that moment, so a week-one anchor always begins with the key physically present,
/// and nothing here touches `AnchorProfile`.
enum Forgiveness {
    /// Starts the first week, if this install has not already had one. True when it did.
    ///
    /// Guarded on `trialStartedAt` rather than on `isInTrial`, and that is the point of keeping
    /// the dates after the week is over: switching Screen Time access off and on again is the
    /// documented way out of Furlough, and it is also the only way back to this call. Without
    /// the record, a weekly trip through Settings would be a weekly trial.
    @discardableResult
    static func startTrial(_ config: inout Config, now: Date) -> Bool {
        guard config.trialStartedAt == nil else { return false }
        config.trialStartedAt = now
        config.trialEndsAt = now.addingTimeInterval(TimeInterval(Furlough.trialDays) * 86_400)
        config.isInTrial = true
        return true
    }

    /// Ends the week once its date has passed, and forgets undos nobody can reach any more.
    /// True when either happened, so the caller knows to save.
    ///
    /// `now` is Furlough's own time. On the device's clock the week would be a text field in
    /// Settings, and so would every undo window.
    @discardableResult
    static func expire(_ config: inout Config, now: Date) -> Bool {
        var changed = false
        if config.isInTrial, let ends = config.trialEndsAt, now >= ends {
            config.isInTrial = false
            changed = true
        }
        for index in config.targets.indices {
            guard let undo = config.targets[index].undo, !undo.isOpen(at: now) else { continue }
            config.targets[index].undo = nil
            changed = true
        }
        return changed
    }

    /// Whole days left of the first week, rounded up, or nil when it is not running. What the
    /// countdown says: on the last afternoon it should read "1 day left", not "0".
    static func trialDaysLeft(_ config: Config, at now: Date) -> Int? {
        guard config.isInTrial, let ends = config.trialEndsAt, now < ends else { return nil }
        return max(1, Int((ends.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    /// Notes what an edit replaced, so it can be taken back. Called where a rule lands *now*.
    ///
    /// A second edit inside the window replaces the note rather than stacking on it: undo is
    /// one step back to the last rule that stood, not a history to walk. Walking a history
    /// would eventually reach "unrestricted", which is the thing that must never be reachable.
    static func record(previous: Rule?, on target: inout Target, at now: Date) {
        target.undo = RuleUndo(rule: previous, savedAt: now)
    }

    /// The undo still open on `target` at `now`, or nil.
    static func undo(for target: Target, at now: Date) -> RuleUndo? {
        guard let undo = target.undo, undo.isOpen(at: now) else { return nil }
        return undo
    }

    /// Puts `targetID` back to the rule it had before the edit, and drops anything queued for
    /// it. True when it happened; false when there is nothing open to take back.
    ///
    /// Instant, and safe to be instant: the restored rule is the one that was already in force,
    /// so this can loosen nothing that was not loose a quarter of an hour ago. It says nothing
    /// about the anchor, which shields on top of the rules and is not the rules' business.
    @discardableResult
    static func revert(targetID: UUID, in state: inout SharedState, now: Date) -> Bool {
        guard let index = state.config.targets.firstIndex(where: { $0.id == targetID }),
              let undo = undo(for: state.config.targets[index], at: now)
        else { return false }
        state.config.targets[index].rule = undo.rule
        state.config.targets[index].undo = nil
        // A loosening queued for this target was queued against the rule being taken back, so
        // it is now waiting to loosen something that no longer exists. Dropping it is the same
        // call `AppModel.assign` makes when a rule is replaced.
        state.pending.removeAll { change in
            if case .setRule(let id, _) = change.kind { return id == targetID }
            return false
        }
        return true
    }
}
