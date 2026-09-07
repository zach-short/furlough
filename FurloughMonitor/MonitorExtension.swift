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
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reconcile("intervalDidEnd \(activity.rawValue)")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        SharedStore.log("eventDidReachThreshold \(event.rawValue)")
        guard let parsed = ActivityNaming.parseBudgetEvent(event.rawValue) else { return }
        let now = Date.now
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
        let now = Date.now
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
        let now = Date.now
        let state = SharedStore.load()
        let config = Policy.effectiveConfig(state, now: now)
        let closing = config.targets.filter { target in
            if case .open(let until) = Policy.status(of: target, runtime: state.runtime, now: now) {
                return until == window.endMinute
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

enum Notifier {
    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                SharedStore.log("notification failed: \(error.localizedDescription)")
            }
        }
    }
}
