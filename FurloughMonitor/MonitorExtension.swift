import DeviceActivity
import Foundation
import ManagedSettings
import UserNotifications
import WidgetKit

/// Woken by iOS at window edges, midnight, budget thresholds, and anchor drop/lift times.
/// Every callback re-derives shields from persisted state, so a missed or duplicated callback
/// can't desync them.
final class MonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if let event = anchorEvent(activity.rawValue, atStart: true) {
            handle(event, activity: activity.rawValue)
            return
        }
        reconcile("intervalDidStart \(activity.rawValue)")
        announceOpening(activity)
    }

    /// Announces what `reconcile` already opened — the difference between a window opening and
    /// Zach noticing. A window activity may fire on days none of its targets use it, posting
    /// nothing.
    ///
    /// A night is stored as evening + morning-after, so midnight is a join, not an opening: the
    /// morning half is skipped for anything already open through it.
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
        // One closing time when they share it — every case but a night opening beside an
        // evening ending at midnight.
        let end = ends.count == 1 ? ends.first ?? window.endMinute : nil
        Notifier.post(
            id: "opened-\(activity.rawValue)",
            title: "Window opened",
            body: end.map { "\(names) — open until \(TimeFormat.until($0))." } ?? "\(names) — open now."
        )
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if let event = anchorEvent(activity.rawValue, atStart: false) {
            handle(event, activity: activity.rawValue)
            return
        }
        reconcile("intervalDidEnd \(activity.rawValue)")
    }

    // MARK: The anchor's clock

    /// What an anchor callback means, or nil if it's just the wake half of the interval —
    /// DeviceActivity requires a 15-minute minimum, so a drop/lift minute is one end of a
    /// 15-min activity (`ActivityNaming` says which).
    private enum AnchorEvent {
        case drop(minute: Int)
        case lift
    }

    private func anchorEvent(_ raw: String, atStart: Bool) -> AnchorEvent? {
        if raw == ActivityNaming.anchorUntil { return atStart ? nil : .lift }
        if let minute = ActivityNaming.parseAnchorDrop(raw) {
            return ActivityNaming.anchorInterval(minute: minute).firesAtStart == atStart ? .drop(minute: minute) : nil
        }
        if let minute = ActivityNaming.parseAnchorLift(raw) {
            return ActivityNaming.anchorInterval(minute: minute).firesAtStart == atStart ? .lift : nil
        }
        return nil
    }

    private func handle(_ event: AnchorEvent, activity: String) {
        switch event {
        case .drop(let minute): scheduledDrop(minute: minute, activity: activity)
        case .lift: liftIfDue(activity: activity)
        }
    }

    /// Applies today's scheduled drop, if any. `Policy.scheduledDrop` is idempotent — a
    /// duplicate or off-day callback changes nothing. This and `liftIfDue` are the monitor's
    /// only writes to `Config.anchor` outside the app and the Drop Anchor intent.
    private func scheduledDrop(minute: Int, activity: String) {
        SharedStore.log(activity)
        let now = SharedStore.load().now
        var dropped: AnchorProfile?
        SharedStore.mutate { state in
            Policy.applyDuePending(&state, now: now)
            if Policy.scheduledDrop(&state.config, minute: minute, now: now) != nil {
                dropped = state.config.anchor
            }
        }
        ShieldReconciler.reconcile(now: now, reason: "scheduled drop")
        WidgetCenter.shared.reloadAllTimelines()
        guard let dropped else { return }
        let lift = dropped.until.map { " until \(TimeFormat.clock($0))" } ?? " until you scan your tag"
        SharedStore.log("dropped anchor on schedule: \(dropped.heldDescription)\(lift)")
        Notifier.post(id: "anchor-dropped", title: "Anchor dropped", body: "\(dropped.heldDescription) locked\(lift).")
        AnchorSync.publish(dropped, origin: .drop, now: now)
        SharedStore.announceChange()
    }

    /// A timed anchor's time has come; `Policy` already reads it as released, this just clears
    /// the flag and lifts the shields.
    private func liftIfDue(activity: String) {
        SharedStore.log(activity)
        let now = SharedStore.load().now
        var lifted: AnchorProfile?
        SharedStore.mutate { state in
            Policy.applyDuePending(&state, now: now)
            if Policy.liftExpiredAnchor(&state.config, now: now) { lifted = state.config.anchor }
        }
        ShieldReconciler.reconcile(now: now, reason: "anchor lift")
        WidgetCenter.shared.reloadAllTimelines()
        guard let lifted else { return }
        SharedStore.log("anchor lifted by itself")
        Notifier.post(id: "anchor-lifted", title: "Anchor lifted", body: "Everything it held is back on its own rules.")
        // Informational: the Mac computes the same expiry from the `until` it holds, and
        // `AnchorSync.merge` refuses this as a release.
        AnchorSync.publish(lifted, origin: .lift, now: now)
        SharedStore.announceChange()
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
            // Every distinct weekly budget is registered, so a Monday callback can be another
            // day's threshold — same guard that filtered stale edits, extended to cover all
            // weekday budgets.
            let weekday = Policy.weekday(now)
            let budget = rule.effectiveBudget(on: weekday)
            guard rule.isEverAllowed(on: weekday), parsed.minutes >= budget else {
                SharedStore.log("ignored stale threshold \(parsed.minutes) < today's budget \(budget)")
                return
            }
            let day = Policy.dayKey(now)
            guard !state.runtime.isExhausted(target.id, dayKey: day) else { return }
            state.runtime.exhausted[target.id.uuidString] = day
            Record.markSpent(target.id, in: &state, now: now)
            exhaustedName = target.displayName
        }
        ShieldReconciler.reconcile(now: now, reason: "threshold \(parsed.minutes)m")
        LiveActivityManager.sync(state: SharedStore.load(), canStart: false)
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
            // Must match today's budget exactly, so a Monday doesn't get its warning early
            // from a loaded weekend threshold.
            let weekday = Policy.weekday(now)
            guard rule.isEverAllowed(on: weekday), parsed.minutes == rule.effectiveBudget(on: weekday) else { return }
            let day = Policy.dayKey(now)
            guard !state.runtime.wasWarned(target.id, dayKey: day),
                  !state.runtime.isExhausted(target.id, dayKey: day) else { return }
            state.runtime.warned[target.id.uuidString] = day
            // Furlough's own `now`, so the Live Activity deadline can't be moved by touching the clock.
            state.runtime.warnedAt[target.id.uuidString] = now
            Record.markWarned(target.id, in: &state, now: now)
            warnedName = target.displayName
        }
        LiveActivityManager.sync(state: SharedStore.load(), canStart: false)
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
        // A windowless rule never closes (midnight only resets its budget); neither does a
        // night's evening half, whose `until` is next morning.
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

    /// Re-derives shields and syncs the Lock Screen. `canStart: false`: an extension can't
    /// start a Live Activity, only end/update one iOS already started while the app was in front.
    private func reconcile(_ reason: String) {
        SharedStore.log(reason)
        ShieldReconciler.reconcile(reason: reason)
        let state = SharedStore.load()
        LiveActivityManager.sync(state: state, canStart: false)
        // Re-planned here too since this runs when the app doesn't; keeps the weekly digest
        // from going stale if Furlough isn't opened all week. `sync` is idempotent.
        let clock = state.clock()
        PendingNotifications.sync(
            state: state, now: clock.now, drift: clock.drift,
            digest: PendingNotifications.wantsWeeklyDigest
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}
