import DeviceActivity
import Foundation
import ManagedSettings

/// Registers DeviceActivity schedules and budget events from persisted state.
/// Pending (not yet effective) rules are registered too, so a loosening that becomes
/// effective while the app is closed is still enforced by the monitor extension.
/// Every distinct span repeats daily whatever days it applies on: a callback on a day the
/// window is off just reconciles to the same shields, and it keeps the activity count at one
/// per span rather than one per span per weekday.
enum Monitoring {
    struct RegistrationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func register(state: SharedState) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring()

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        // The spans come from `ActivityLimit` rather than from a second count here, so that what
        // the rule editor and the import review refuse ahead of time is exactly what this would
        // have refused after the fact. Two readings of the same ceiling is how one of them ends
        // up letting through the edit the other would have caught.
        let windows = ActivityLimit.spans(in: state)

        func include(_ target: Target, _ rule: Rule) {
            guard rule.isEverAllowed else { return }
            let minutes = rule.dailyBudgetMinutes
            let name = DeviceActivityEvent.Name(ActivityNaming.budgetEvent(targetID: target.id, minutes: minutes))
            let threshold = DateComponents(hour: minutes / 60, minute: minutes % 60)
            switch target.kind {
            case .application(let token):
                events[name] = DeviceActivityEvent(applications: [token], threshold: threshold, includesPastActivity: true)
            case .webDomain(let token):
                events[name] = DeviceActivityEvent(webDomains: [token], threshold: threshold, includesPastActivity: true)
            case .category:
                break
            // A typed host has no token, and a threshold event needs one, so nothing counts it
            // and it gets no budget event. Its window spans are still collected by
            // `ActivityLimit.spans`, so the reconcile at each window edge still happens.
            case .host:
                break
            }
        }

        for target in state.config.targets {
            if let rule = target.rule { include(target, rule) }
        }
        for change in state.pending {
            if case .setRule(let id, let rule) = change.kind, let target = state.config.target(id: id) {
                include(target, rule)
            }
        }

        guard windows.count <= ActivityLimit.maxSpans else {
            throw RegistrationError(message: "Too many distinct windows (\(windows.count)). iOS allows \(ActivityLimit.maxSpans).")
        }

        let day = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true,
            warningTime: DateComponents(minute: Furlough.warningMinutes)
        )
        try center.startMonitoring(DeviceActivityName(ActivityNaming.day), during: day, events: events)

        for window in windows {
            let schedule = DeviceActivitySchedule(
                intervalStart: components(window.startMinute),
                intervalEnd: components(window.endMinute),
                repeats: true,
                warningTime: DateComponents(minute: Furlough.warningMinutes)
            )
            try center.startMonitoring(DeviceActivityName(ActivityNaming.window(window)), during: schedule)
        }
        SharedStore.log("registered day + \(windows.count) window(s), \(events.count) budget event(s)")
    }

    static func components(_ minute: Int) -> DateComponents {
        if minute >= Furlough.minutesPerDay {
            return DateComponents(hour: 23, minute: 59, second: 59)
        }
        return DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
    }
}
