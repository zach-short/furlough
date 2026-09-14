import DeviceActivity
import Foundation
import ManagedSettings

/// Registers DeviceActivity schedules and budget events from persisted state. Pending
/// (not-yet-effective) rules are registered too, so a loosening that lands while the app is
/// closed is still enforced by the monitor extension. Each distinct span repeats daily
/// regardless of which days it applies to, keeping the activity count at one per span rather
/// than one per span per weekday — an off-day callback just reconciles to the same shields.
enum Monitoring {
    struct RegistrationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func register(state: SharedState) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring()

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        // Spans come from `ActivityLimit` rather than a second count here, so this and the rule
        // editor/import review always agree on the same ceiling.
        let windows = ActivityLimit.spans(in: state)

        /// One event per target. `DeviceActivityEvent` takes applications and web domains
        /// together under one threshold, so a linked pair genuinely shares a budget (45 min
        /// total, not 45 each) with no arithmetic of ours.
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
                // A typed host has no token, so a threshold event can't count it — linked to an
                // app, only the app's minutes count. Its window spans are still collected by
                // ActivityLimit.spans, so the reconcile at each window edge still happens.
                case .host:
                    break
                }
            }
            guard !apps.isEmpty || !web.isEmpty else { return }
            // One event per distinct budget the week needs, not one per day — a threshold event
            // isn't a schedule, so days sharing a budget share an event. `Set` dedups identical
            // minutes; the monitor picks which registered event applies today.
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

        // Each drop/lift minute is one end of a quarter-hour activity (ActivityNaming
        // .anchorInterval), repeating daily; the monitor checks the weekday when it fires.
        // Registered individually, after the windows, so one refusal (e.g. `until` too close to
        // now) doesn't cost anything already registered.
        var anchorCount = 0
        for minute in anchorMinutes.drops {
            anchorCount += start(ActivityNaming.anchorDrop(minute: minute), during: anchorSchedule(minute), with: center)
        }
        for minute in anchorMinutes.lifts {
            anchorCount += start(ActivityNaming.anchorLift(minute: minute), during: anchorSchedule(minute), with: center)
        }
        if state.config.anchor.isAnchored, let until = state.config.anchor.until {
            // DeviceActivity keeps the device's clock, not Furlough's own.
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

    /// Starts one anchor activity, logging a refusal rather than throwing: the windows are
    /// already registered by now and a refused wake must not cost them. `Policy` treats a timed
    /// anchor as released once its time passes regardless of whether the wake arrives.
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
