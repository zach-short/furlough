import Foundation

/// Furlough has no emergency unblock, deliberately — but the trap that catches beginners isn't
/// craving, it's arithmetic: a first rule lands instantly (baseline is "unrestricted"), while
/// undoing it is a loosening that waits `delayHours`. Two mechanisms soften that without being
/// a door out:
///
/// - **The first week.** For `Furlough.trialDays` after Screen Time access is first granted,
///   `Config.delayHours` is capped at `Furlough.trialDelayHours`; everything else (windows,
///   budgets, shields) is real. Granted once per install, fixed the moment it starts, never
///   extended.
/// - **The undo window.** For `Furlough.undoWindowMinutes` after an edit lands, it can be put
///   back exactly as it was — see `RuleUndo`, which can only restore the rule that was already
///   there, so it's no use to anyone who wants out.
///
/// The anchor gets neither: pairing a tag requires the tag physically in hand, so nothing here
/// touches `AnchorProfile`.
enum Forgiveness {
    /// Guarded on `trialStartedAt` rather than `isInTrial` so the record survives the trial
    /// ending — switching Screen Time access off and on is the documented way out of Furlough,
    /// and also the only way back to this call; without the record it would restart weekly.
    @discardableResult
    static func startTrial(_ config: inout Config, now: Date) -> Bool {
        guard config.trialStartedAt == nil else { return false }
        config.trialStartedAt = now
        config.trialEndsAt = now.addingTimeInterval(TimeInterval(Furlough.trialDays) * 86_400)
        config.isInTrial = true
        return true
    }

    /// Ends the week once its date has passed, and forgets undos nobody can reach any more.
    /// True when either happened, so the caller knows to save. `now` is Furlough's own time,
    /// never the device's clock.
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

    /// Rounded up so the last afternoon reads "1 day left", not "0".
    static func trialDaysLeft(_ config: Config, at now: Date) -> Int? {
        guard config.isInTrial, let ends = config.trialEndsAt, now < ends else { return nil }
        return max(1, Int((ends.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    /// A second edit inside the window replaces the note rather than stacking: undo is one
    /// step back, not a history to walk — walking one would eventually reach "unrestricted",
    /// which must never be reachable.
    static func record(previous: Rule?, on target: inout Target, at now: Date) {
        target.undo = RuleUndo(rule: previous, savedAt: now)
    }

    /// The undo still open on `target` at `now`, or nil.
    static func undo(for target: Target, at now: Date) -> RuleUndo? {
        guard let undo = target.undo, undo.isOpen(at: now) else { return nil }
        return undo
    }

    /// Instant and safe to be instant: the restored rule was already in force minutes ago, so
    /// nothing loosens beyond that.
    @discardableResult
    static func revert(targetID: UUID, in state: inout SharedState, now: Date) -> Bool {
        guard let index = state.config.targets.firstIndex(where: { $0.id == targetID }),
              let undo = undo(for: state.config.targets[index], at: now)
        else { return false }
        state.config.targets[index].rule = undo.rule
        state.config.targets[index].undo = nil
        // A queued loosening was queued against the rule now taken back, so it's void. Same
        // call `AppModel.assign` makes when a rule is replaced.
        state.pending.removeAll { change in
            if case .setRule(let id, _) = change.kind { return id == targetID }
            return false
        }
        return true
    }
}
