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
}
