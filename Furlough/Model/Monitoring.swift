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

        /// One event per target, whatever it covers. `DeviceActivityEvent` takes applications and
        /// web domains together under one threshold, so a linked pair genuinely *shares* a
        /// budget: 45 minutes is 45 across the app and the site together, counted by iOS, with
        /// no arithmetic of ours. Two events would have meant 45 each, which is 90.
        func include(_ target: Target, _ rule: Rule) {
            guard rule.isEverAllowed else { return }
            var apps: Set<ApplicationToken> = []
            var web: Set<WebDomainToken> = []
            for kind in target.kinds {
                switch kind {
                case .application(let token): apps.insert(token)
                case .webDomain(let token): web.insert(token)
                case .category:
                    break
                // A typed host has no token, and a threshold event needs one, so nothing counts
                // it. On its own that means no budget event at all; linked to an app it means the
                // site shares the windows and only the app's minutes are counted. Either way its
                // window spans are still collected by `ActivityLimit.spans`, so the reconcile at
                // each window edge still happens.
                case .host:
                    break
                }
            }
            guard !apps.isEmpty || !web.isEmpty else { return }
            // One event per distinct budget the week asks for, not one per day. A threshold
            // event is not a schedule — it watches the day activity, which repeats — so the
            // seven days share whichever events they need, and a week of 30/30/30/30/30/120/120
            // costs two. The monitor decides which of them is today's; registering all of them
            // is what lets it, and `Set` is what stops five weekdays from registering five
            // copies of the same name.
            for minutes in Set((1...7).map { rule.effectiveBudget(on: $0) }).sorted() where minutes > 0 {
                let name = DeviceActivityEvent.Name(ActivityNaming.budgetEvent(targetID: target.id, minutes: minutes))
                let threshold = DateComponents(hour: minutes / 60, minute: minutes % 60)
                events[name] = DeviceActivityEvent(
                    applications: apps, webDomains: web, threshold: threshold, includesPastActivity: true
                )
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

        let anchorMinutes = ActivityLimit.anchorMinutes(in: state)
        let needed = ActivityLimit.activities(in: state)
        guard needed <= ActivityLimit.maxSpans else {
            throw RegistrationError(message: "Too many windows and anchor times (\(needed)). iOS allows \(ActivityLimit.maxSpans).")
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

        // The anchor's clock. A drop or a lift minute is one end of a quarter-hour activity
        // (`ActivityNaming.anchorInterval`), repeating daily like a window; the monitor checks
        // the weekday when it fires. Each is registered on its own, after the windows, so that
        // one iOS refuses — a timed anchor's `until` too close to now for a quarter hour —
        // costs nothing that was already registered.
        var anchorCount = 0
        for minute in anchorMinutes.drops {
            anchorCount += start(ActivityNaming.anchorDrop(minute: minute), during: anchorSchedule(minute), with: center)
        }
        for minute in anchorMinutes.lifts {
            anchorCount += start(ActivityNaming.anchorLift(minute: minute), during: anchorSchedule(minute), with: center)
        }
        if state.config.anchor.isAnchored, let until = state.config.anchor.until {
            // On the device's clock, which is the one DeviceActivity keeps: a quarter hour
            // ending at the lift, one time only.
            let deviceUntil = state.clock().device(until)
            if deviceUntil > .now {
                let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
                let begins = deviceUntil.addingTimeInterval(-TimeInterval(Furlough.minimumWindowMinutes * 60))
                let once = DeviceActivitySchedule(
                    intervalStart: Calendar.current.dateComponents(parts, from: begins),
                    intervalEnd: Calendar.current.dateComponents(parts, from: deviceUntil),
                    repeats: false
                )
                anchorCount += start(ActivityNaming.anchorUntil, during: once, with: center)
            }
        }
        SharedStore.log("registered day + \(windows.count) window(s), \(events.count) budget event(s), \(anchorCount) anchor time(s)")
    }

    /// Starts one anchor activity, logging a refusal rather than throwing it: the windows are
    /// registered by now, and one refused wake must not cost them. `Policy` reads a timed
    /// anchor as released once its time passes whether or not the wake arrives.
    private static func start(_ name: String, during schedule: DeviceActivitySchedule, with center: DeviceActivityCenter) -> Int {
        do {
            try center.startMonitoring(DeviceActivityName(name), during: schedule)
            return 1
        } catch {
            SharedStore.log("could not schedule \(name): \(error.localizedDescription)")
            return 0
        }
    }

    private static func anchorSchedule(_ minute: Int) -> DeviceActivitySchedule {
        let interval = ActivityNaming.anchorInterval(minute: minute)
        return DeviceActivitySchedule(
            intervalStart: components(interval.start),
            intervalEnd: components(interval.end),
            repeats: true
        )
    }

    static func components(_ minute: Int) -> DateComponents {
        if minute >= Furlough.minutesPerDay {
            return DateComponents(hour: 23, minute: 59, second: 59)
        }
        return DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
    }
}
