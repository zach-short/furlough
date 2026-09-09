import Foundation
import UserNotifications

/// One local notification Furlough wants outstanding, and when it should fire.
struct PlannedNotification: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var body: String
    /// On the device's clock. The system fires these, and the system only knows its own time,
    /// so a Furlough time has to be moved onto it first — see `Clock.Reading.device`.
    var fireAt: Date
}

/// The notifications that go with a queued loosening: one an hour before it lands, while there
/// is still time to cancel it, and one when it lands.
///
/// This is the half of the feature worth being careful about, so it is pure: `plan` says what
/// should be outstanding for a given state, and `sync` makes the system agree with it. Nothing
/// here enforces anything — a notification that fires late or not at all cannot lift a shield —
/// but it is the only warning before something loosens, which is exactly when Zach would want
/// the chance to change his mind.
enum PendingNotifications {
    /// Every identifier scheduled ahead of time starts with this, so `sync` can tell Furlough's
    /// own scheduled notifications from the ones other code posts on the spot.
    static let prefix = "furlough.pending."
    /// How long before a change lands the warning arrives.
    static let lead: TimeInterval = 3600

    /// Everything that should be outstanding for `state` at `now`. `drift` is the device clock's
    /// distance from Furlough's own time, from `Clock.Reading.drift`: the fire dates are moved
    /// onto the device's clock, because that is the clock the system will fire them against.
    static func plan(
        state: SharedState,
        now: Date,
        drift: TimeInterval = 0,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        state.pending
            .filter { $0.effectiveAt > now }
            .sorted { $0.effectiveAt < $1.effectiveAt }
            .flatMap { change -> [PlannedNotification] in
                let what = describe(change, in: state.config, calendar: calendar)
                var planned: [PlannedNotification] = []
                let warnAt = change.effectiveAt.addingTimeInterval(-lead)
                // A change queued with less than an hour to run gets no warning: it would fire
                // at the same moment as the change landing, and say the opposite thing.
                if warnAt > now {
                    planned.append(PlannedNotification(
                        id: id(change, .warning),
                        title: "Loosening lands in an hour",
                        body: "\(what) Cancel it in Furlough until then.",
                        fireAt: warnAt.addingTimeInterval(drift)
                    ))
                }
                planned.append(PlannedNotification(
                    id: id(change, .landed),
                    title: "Change landed",
                    body: what,
                    fireAt: change.effectiveAt.addingTimeInterval(drift)
                ))
                return planned
            }
    }

    enum Moment: String { case warning, landed }

    static func id(_ change: PendingChange, _ moment: Moment) -> String {
        "\(prefix)\(change.id.uuidString).\(moment.rawValue)"
    }

    /// What the change will do, in the same words the pending list uses.
    static func describe(_ change: PendingChange, in config: Config, calendar: Calendar = .current) -> String {
        switch change.kind {
        case .setRule(let targetID, let rule):
            let name = config.target(id: targetID)?.displayName ?? "An app"
            return "\(name): \(TimeFormat.rule(rule, calendar: calendar))."
        case .removeTarget(let targetID):
            let name = config.target(id: targetID)?.displayName ?? "An app"
            return "\(name) will no longer be limited."
        case .setDelay(let hours):
            return "The delay before a loosening lands becomes \(TimeFormat.delay(hours: hours))."
        case .setUtility(let targetID, let level):
            let name = config.target(id: targetID)?.displayName ?? "An app"
            var config = config
            if let index = config.targets.firstIndex(where: { $0.id == targetID }) {
                config.targets[index].utilityLevel = level
            }
            let hours = config.delayHours(forTargetID: targetID)
            return "\(name) becomes \(level.label.lowercased()), so its loosenings will wait \(TimeFormat.delay(hours: hours))."
        case .unlink(let targetID, let kind):
            let name = config.target(id: targetID)?.displayName ?? "An app"
            let half = kind.hostName ?? "its other half"
            return "\(half) stops being blocked with \(name)."
        }
    }

    /// Makes the system's scheduled notifications match `plan`: anything of Furlough's that is
    /// no longer planned is withdrawn (a cancelled change must not still announce itself), and
    /// anything planned that is not already scheduled is added. Already-correct requests are
    /// left alone, so this can run on every enforce without re-scheduling the world.
    static func sync(state: SharedState, now: Date, drift: TimeInterval = 0, calendar: Calendar = .current) {
        let planned = plan(state: state, now: now, drift: drift, calendar: calendar)
        // Only the identifiers are carried into the callback. `UNUserNotificationCenter` and
        // `UNNotificationRequest` are not Sendable, so neither may be captured by it.
        UNUserNotificationCenter.current().getPendingNotificationRequests { existing in
            let scheduled = Set(existing.map(\.identifier).filter { $0.hasPrefix(prefix) })
            apply(planned, alreadyScheduled: scheduled, calendar: calendar)
        }
    }

    private static func apply(_ planned: [PlannedNotification], alreadyScheduled: Set<String>, calendar: Calendar) {
        let center = UNUserNotificationCenter.current()
        let stale = alreadyScheduled.subtracting(planned.map(\.id))
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(stale)) }

        for note in planned where !alreadyScheduled.contains(note.id) {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            // A calendar trigger rather than a time interval, so it survives the app being
            // closed and fires at the moment the change actually lands.
            // Seconds included: without them the trigger fires at the top of the minute, which
            // would announce a change as landed up to a minute before it lands.
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: note.fireAt)
            let request = UNNotificationRequest(
                identifier: note.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            center.add(request) { error in
                if let error { SharedStore.log("notification failed: \(error.localizedDescription)") }
            }
        }
    }
}

/// Posts a local notification now. One copy, shared by the phone's monitor extension and the
/// Mac's enforcer, which each had their own before.
enum Notifier {
    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { SharedStore.log("notification failed: \(error.localizedDescription)") }
        }
    }
}
