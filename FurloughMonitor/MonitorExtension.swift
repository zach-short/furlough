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
    private func announceOpening(_ activity: DeviceActivityName) {
        guard let window = ActivityNaming.parseWindow(activity.rawValue) else { return }
        let state = SharedStore.load()
        let now = state.now
        let config = Policy.effectiveConfig(state, now: now)
        let opened = config.targets.filter { target in
            guard !(target.rule?.isAllDay ?? false) else { return false }
            if case .open(let until) = Policy.status(of: target, config: config, runtime: state.runtime, now: now) {
                return until == window.endMinute
            }
            return false
        }
        guard !opened.isEmpty else { return }
        let names = opened.map(\.displayName).joined(separator: ", ")
        Notifier.post(
            id: "opened-\(activity.rawValue)",
            title: "Window opened",
            body: "\(names) — open until \(TimeFormat.minute(window.endMinute))."
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
            guard rule.isEverAllowed, parsed.minutes >= rule.effectiveBudgetMinutes else {
                SharedStore.log("ignored stale threshold \(parsed.minutes) < budget \(rule.effectiveBudgetMinutes)")
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
            guard rule.isEverAllowed, parsed.minutes == rule.effectiveBudgetMinutes else { return }
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
        // A rule without windows never closes; midnight only resets its budget.
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
            body: "\(names) will close at \(TimeFormat.minute(window.endMinute))."
        )
    }

    private func reconcile(_ reason: String) {
        SharedStore.log(reason)
        ShieldReconciler.reconcile(reason: reason)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
