import Foundation

/// How many DeviceActivity activities the rules would need, and whether iOS will take them.
///
/// iOS monitors at most 20 activities at once. Furlough spends one on the daily budget tracker
/// and one on each distinct window span — whatever days that span applies on — so 19 spans is
/// the ceiling. `Monitoring.register` already refuses past it, but it runs *after* the rule is
/// saved: the editor accepted the rule, registration threw, and the reason turned up in Settings
/// with the rule already in force and nothing monitored. This is the same count run before Save,
/// so the editor can say no while the rule is still a draft.
///
/// This is an iOS constraint only. The Mac has no DeviceActivity — `Monitoring.swift` is in the
/// iOS app target and the Mac enforces from its own timer loop — so nothing there is limited by
/// it and the Mac's editor does not consult this. It lives in `Shared/Core` beside the rest of
/// the engine and is harmlessly unused on the Mac, the way `Hosts` is on the phone.
///
/// The projection has to match `AppModel.assign` rather than just swapping the rule in. A
/// tightening replaces the target's rule; a loosening is queued *alongside* it, and
/// `Monitoring.register` registers pending rules too, so a loosening can need the spans of the
/// old rule and the new one at the same time. Counting only the new rule would let exactly the
/// edit that overflows through.
enum ActivityLimit {
    /// One of the 20 is always the daily budget tracker.
    ///
    /// Per-weekday budgets do not press on this ceiling. A budget is a `DeviceActivityEvent`
    /// carried *by* the day activity, not an activity of its own, so a rule that asks for seven
    /// different budgets still costs the one activity every rule costs — only the event count
    /// inside it grows. The 20 is spent on the day tracker plus one per distinct window span,
    /// and that is why this counts spans and nothing else.
    static var maxSpans: Int { Furlough.maxActivities - 1 }

    /// Every distinct span the state would ask iOS to monitor. Mirrors what
    /// `Monitoring.register` collects: saved rules plus queued ones, spans stripped of their
    /// days so the same hours on different days count once, and nothing at all from a rule that
    /// never allows anything.
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

    /// The state as saving `rule` for each of `targetIDs` would leave it, following the same
    /// tightening-lands / loosening-queues rule the model uses. Nothing is persisted.
    static func projecting(_ rule: Rule, appliedTo targetIDs: [UUID], in state: SharedState) -> SharedState {
        var copy = state
        for id in targetIDs {
            guard let index = copy.config.targets.firstIndex(where: { $0.id == id }) else { continue }
            let target = copy.config.targets[index]
            // An unchanged rule is left alone, exactly as `assign` leaves it.
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

    /// Nil when the rule fits once saved. Otherwise why it does not, for the banner above Save.
    static func reason(applying rule: Rule, to targetIDs: [UUID], in state: SharedState) -> String? {
        let needed = spans(in: projecting(rule, appliedTo: targetIDs, in: state)).count
        guard needed > maxSpans else { return nil }
        return "That would need \(needed) different windows across everything Furlough manages, and iOS allows \(maxSpans). Merge or drop a window, or give this app hours another app already uses."
    }

    /// The state as applying a whole import would leave it.
    ///
    /// Projected by running the real `ConfigImport.apply` against a copy rather than by a second
    /// reading of what an import does: an import arrives as twenty edits at once, each of which
    /// may land or queue, and a projection that guessed differently from the thing it is
    /// predicting would be worth less than no projection at all. `plannedAt` stands in for the
    /// clock — nothing is persisted and a span count does not depend on when anything lands, so
    /// this stays a pure function of the plan and the state.
    static func projecting(_ plan: ImportPlan, in state: SharedState) -> SharedState {
        var copy = state
        ConfigImport.apply(plan, to: &copy, now: plan.plannedAt)
        return copy
    }

    /// Nil when the import fits once applied. Otherwise why it does not, for the review.
    ///
    /// Counted before the button rather than at registration, and for a worse reason than the
    /// editor's. `Monitoring.register` runs *after* `applyImport` has saved, and `enforce`
    /// catches what it throws and saves anyway — so an oversized import lands whole, registration
    /// fails, nothing at all is monitored, and the only sign of it is a row in Settings. The
    /// queued half counts too: `spans` gathers pending rules exactly as registration does, so
    /// the loosenings in a file press against the ceiling from the moment Apply is pressed,
    /// a day before any of them are in force.
    static func reason(applying plan: ImportPlan, in state: SharedState) -> String? {
        let needed = spans(in: projecting(plan, in: state)).count
        guard needed > maxSpans else { return nil }
        return "This setup would need \(needed) different windows across everything Furlough manages, and iOS allows \(maxSpans). Leave some of these rows out, or merge windows where two apps could share hours, and open the file again."
    }
}
