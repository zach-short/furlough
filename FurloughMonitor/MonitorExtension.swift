import DeviceActivity
import Foundation
import ManagedSettings
import UserNotifications
import WidgetKit

/// Woken by iOS at window edges, at midnight, and when a budget threshold is reached.
/// Every callback re-derives the shields from persisted state, so a missed or duplicated
/// callback can never leave the shields out of sync.
final class MonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reconcile("intervalDidStart \(activity.rawValue)")
        announceOpening(activity)
    }

    /// "Window opened" for whatever this span just unblocked. `reconcile` above has already
    /// lifted the shields; this only says so, which is the difference between a window opening
    /// and Zach noticing it opened. A window activity also fires on days none of its targets
    /// use it, and then nothing is `.open` against this end and nothing is posted.
    ///
    /// A night is stored as an evening and the morning after it, so midnight is a join and not
    /// an opening: the morning half is skipped for anything that was already open through it,
    /// and the evening half matches a target whose window runs on past midnight.
    private func announceOpening(_ activity: DeviceActivityName) {
        guard let window = ActivityNaming.parseWindow(activity.rawValue) else { return }
        let state = SharedStore.load()
        let now = state.now
        let config = Policy.effectiveConfig(state, now: now)
        let weekday = Policy.weekday(now)
        let opened: [(name: String, until: Int)] = config.targets.compactMap { target in
            guard let rule = target.rule, !rule.isAllDay else { return nil }
            guard !(window.startMinute == 0 && rule.continues(into: weekday) != nil) else { return nil }
            guard case .open(let until) = Policy.status(of: target, config: config, runtime: state.runtime, now: now)
            else { return nil }
            let isThisWindow = until == window.endMinute
                || (window.endMinute == Furlough.minutesPerDay && until > Furlough.minutesPerDay)
            return isThisWindow ? (target.displayName, until) : nil
        }
        guard !opened.isEmpty else { return }
        let names = opened.map(\.name).joined(separator: ", ")
        let ends = Set(opened.map(\.until))
        // One closing time when they share one, which is every case but a night opening beside
        // an evening that stops at midnight.
        let end = ends.count == 1 ? ends.first ?? window.endMinute : nil
        Notifier.post(
            id: "opened-\(activity.rawValue)",
            title: "Window opened",
            body: end.map { "\(names) — open until \(TimeFormat.until($0))." } ?? "\(names) — open now."
        )
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reconcile("intervalDidEnd \(activity.rawValue)")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        SharedStore.log("eventDidReachThreshold \(event.rawValue)")
        guard let parsed = ActivityNaming.parseBudgetEvent(event.rawValue) else { return }
        let now = SharedStore.load().now
        var exhaustedName: String?
        SharedStore.mutate { state in
            Policy.applyDuePending(&state, now: now)
            guard let target = state.config.target(id: parsed.targetID), let rule = target.rule else { return }
            // Today's budget, not the rule's: every distinct budget in the week is registered,
            // so on a 30-minute Monday the 2-hour weekend event is live too. A threshold below
            // today's is another day's and is ignored — which is the same guard that already
            // threw out a stale event left over from an edit, now extended to the six other
            // budgets this rule holds.
            let weekday = Policy.weekday(now)
            let budget = rule.effectiveBudget(on: weekday)
            guard rule.isEverAllowed(on: weekday), parsed.minutes >= budget else {
                SharedStore.log("ignored stale threshold \(parsed.minutes) < today's budget \(budget)")
                return
            }
            let day = Policy.dayKey(now)
            guard !state.runtime.isExhausted(target.id, dayKey: day) else { return }
            state.runtime.exhausted[target.id.uuidString] = day
            exhaustedName = target.displayName
        }
        ShieldReconciler.reconcile(now: now, reason: "threshold \(parsed.minutes)m")
        if let name = exhaustedName {
            Notifier.post(
                id: "exhausted-\(parsed.targetID.uuidString)",
                title: "Time's up",
                body: "\(name) is blocked until its next window."
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        SharedStore.log("eventWillReachThresholdWarning \(event.rawValue)")
        guard let parsed = ActivityNaming.parseBudgetEvent(event.rawValue) else { return }
        let now = SharedStore.load().now
        var warnedName: String?
        SharedStore.mutate { state in
            Policy.applyDuePending(&state, now: now)
            guard let target = state.config.target(id: parsed.targetID), let rule = target.rule else { return }
            // Exactly today's, so only the day's own budget warns: a Monday must not get its
            // "5 minutes left" 25 minutes early because the weekend's larger event is loaded.
            let weekday = Policy.weekday(now)
            guard rule.isEverAllowed(on: weekday), parsed.minutes == rule.effectiveBudget(on: weekday) else { return }
            let day = Policy.dayKey(now)
            guard !state.runtime.wasWarned(target.id, dayKey: day),
                  !state.runtime.isExhausted(target.id, dayKey: day) else { return }
            state.runtime.warned[target.id.uuidString] = day
            warnedName = target.displayName
        }
        if let name = warnedName {
            Notifier.post(
                id: "warning-\(parsed.targetID.uuidString)",
                title: "\(Furlough.warningMinutes) minutes left",
                body: "\(name) has about \(Furlough.warningMinutes) minutes left today."
            )
        }
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        guard let window = ActivityNaming.parseWindow(activity.rawValue) else { return }
        let state = SharedStore.load()
        let now = state.now
        let config = Policy.effectiveConfig(state, now: now)
        // A rule without windows never closes; midnight only resets its budget. Neither does
        // the evening half of a night, whose `until` is a time on the next morning and so
        // never matches the midnight this activity ends at.
        let closing = config.targets.filter { target in
            if case .open(let until) = Policy.status(of: target, config: config, runtime: state.runtime, now: now) {
                return until == window.endMinute && !(target.rule?.isAllDay ?? false)
            }
            return false
        }
        guard !closing.isEmpty else { return }
        let names = closing.map(\.displayName).joined(separator: ", ")
        Notifier.post(
            id: "closing-\(activity.rawValue)",
            title: "Window closing",
            body: "\(names) will close at \(TimeFormat.until(window.endMinute))."
        )
    }

    private func reconcile(_ reason: String) {
        SharedStore.log(reason)
        ShieldReconciler.reconcile(reason: reason)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
