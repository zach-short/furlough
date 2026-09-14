import Foundation

/// Checks the DeviceActivity activity ceiling (20) before Save, since `Monitoring.register`
/// only refuses *after* the rule is already saved and in force. iOS-only; the Mac enforces
/// from its own timer loop and never consults this.
///
/// Projections must match `AppModel.assign`'s tightening-lands/loosening-queues rule: a
/// loosening is registered alongside the old rule, so both count until it lands.
enum ActivityLimit {
    /// Per-weekday budgets don't add activities — they're `DeviceActivityEvent`s carried by
    /// the one day activity, so only window spans count toward the ceiling.
    static var maxSpans: Int { Furlough.maxActivities - 1 }

    /// Mirrors `Monitoring.register`: saved rules plus queued ones, spans stripped of days so
    /// equal hours on different days count once.
    static func spans(in state: SharedState) -> Set<TimeWindow> {
        var spans = Set<TimeWindow>()
        func include(_ rule: Rule) {
            guard rule.isEverAllowed else { return }
            spans.formUnion(rule.windows.map(\.span))
        }
        for target in state.config.targets {
            if let rule = target.rule { include(rule) }
        }
        for change in state.pending {
            if case .setRule(let id, let rule) = change.kind, state.config.target(id: id) != nil {
                include(rule)
            }
        }
        return spans
    }

    /// Saved schedules plus queued ones, like `spans` — a queued schedule can carry a minute
    /// of its own before it lands.
    static func anchorMinutes(in state: SharedState) -> (drops: Set<Int>, lifts: Set<Int>) {
        var schedules = state.config.anchor.schedules
        for change in state.pending {
            if case .setAnchorSchedules(let queued) = change.kind { schedules += queued }
        }
        return (Set(schedules.map(\.minuteOfDay)), Set(schedules.compactMap(\.liftMinuteOfDay)))
    }

    /// One per distinct drop minute, one per distinct lift minute, plus one for a timed
    /// anchor's own `until` while it holds.
    static func anchorActivities(in state: SharedState) -> Int {
        let minutes = anchorMinutes(in: state)
        let timed = state.config.anchor.isAnchored && state.config.anchor.until != nil ? 1 : 0
        return minutes.drops.count + minutes.lifts.count + timed
    }

    static func activities(in state: SharedState) -> Int {
        spans(in: state).count + anchorActivities(in: state)
    }

    /// Only worded in when the anchor actually adds to the count.
    private static func anchorClause(_ state: SharedState) -> String {
        anchorActivities(in: state) > 0 ? " and the Anchor's drop and lift times" : ""
    }

    /// Nil when the anchor's drop times fit. Counted with the current schedules still in
    /// place, like a queued rule counts beside the saved one.
    static func reason(schedules: [AnchorSchedule], in state: SharedState) -> String? {
        var copy = state
        copy.pending.append(PendingChange(kind: .setAnchorSchedules(schedules), effectiveAt: .distantFuture))
        let needed = activities(in: copy)
        guard needed > maxSpans else { return nil }
        return "That would need \(needed) windows and anchor times across everything Furlough manages, and iOS allows \(maxSpans). Drop a time, or give it a minute another drop or lift already uses."
    }

    /// Follows `AppModel.assign`'s tightening-lands/loosening-queues rule. Nothing persisted.
    static func projecting(_ rule: Rule, appliedTo targetIDs: [UUID], in state: SharedState) -> SharedState {
        var copy = state
        for id in targetIDs {
            guard let index = copy.config.targets.firstIndex(where: { $0.id == id }) else { continue }
            let target = copy.config.targets[index]
            guard !(target.rule?.isEquivalent(to: rule) ?? false) else { continue }
            copy.pending.removeAll { change in
                if case .setRule(let targetID, _) = change.kind { return targetID == id }
                return false
            }
            if Policy.classify(newRule: rule, against: target) == .tightening {
                copy.config.targets[index].rule = rule
            } else {
                copy.pending.append(
                    PendingChange(kind: .setRule(targetID: id, rule: rule), effectiveAt: .distantFuture)
                )
            }
        }
        return copy
    }

    /// Nil when the rule fits once saved; otherwise the banner text for above Save.
    static func reason(applying rule: Rule, to targetIDs: [UUID], in state: SharedState) -> String? {
        let projected = projecting(rule, appliedTo: targetIDs, in: state)
        let needed = activities(in: projected)
        guard needed > maxSpans else { return nil }
        return "That would need \(needed) different windows across everything Furlough manages\(anchorClause(projected)), and iOS allows \(maxSpans). Merge or drop a window, or give this app hours another app already uses."
    }

    /// Projects by running the real `ConfigImport.apply` on a copy, rather than reimplementing
    /// import logic, so the projection can't diverge from the real apply.
    static func projecting(_ plan: ImportPlan, in state: SharedState) -> SharedState {
        var copy = state
        ConfigImport.apply(plan, to: &copy, now: plan.plannedAt)
        return copy
    }

    /// Checked before Apply, since an oversized import would otherwise save whole and silently
    /// fail to register. Queued rules count too, matching how `spans` gathers pending rules.
    static func reason(applying plan: ImportPlan, in state: SharedState) -> String? {
        let projected = projecting(plan, in: state)
        let needed = activities(in: projected)
        guard needed > maxSpans else { return nil }
        return "This setup would need \(needed) different windows across everything Furlough manages\(anchorClause(projected)), and iOS allows \(maxSpans). Leave some of these rows out, or merge windows where two apps could share hours, and open the file again."
    }
}
