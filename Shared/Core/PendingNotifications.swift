import Foundation
import UserNotifications

/// One local notification Furlough wants outstanding, and when it should fire.
struct PlannedNotification: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var body: String
    /// On the device's clock — Furlough times must be moved onto it first; see `Clock.Reading.device`.
    var fireAt: Date
}

/// The notifications for a queued loosening: one an hour before it lands (time to cancel), one
/// when it lands. Pure: `plan` computes what should be outstanding, `sync` applies it.
enum PendingNotifications {
    /// Prefix on every scheduled identifier, so `sync` can tell these apart from ad hoc notifications.
    static let prefix = "furlough.pending."
    /// How long before a change lands the warning arrives.
    static let lead: TimeInterval = 3600
    /// The weekly digest's own prefix, under the one above so `sync` still owns it.
    static let digestPrefix = prefix + "digest."
    /// Stored in the App Group, not `Config`: this is device-local (must not travel in an export
    /// or wait out a loosening delay), and the monitor extension needs it outside `UserDefaults.standard`.
    #if os(iOS)
    static let digestPreferenceKey = "furlough.weeklyDigest"
    #else
    static let digestPreferenceKey = "furlough.mac.weeklyDigest"
    #endif

    /// Defaults to true when unanswered, since an unread record is what the digest exists to fix.
    static var wantsWeeklyDigest: Bool {
        SharedStore.defaults.object(forKey: digestPreferenceKey) as? Bool ?? true
    }

    static func setWantsWeeklyDigest(_ on: Bool) {
        SharedStore.defaults.set(on, forKey: digestPreferenceKey)
    }

    /// Back to what a fresh install has, for the testing reset.
    static func forgetWeeklyDigest() {
        SharedStore.defaults.removeObject(forKey: digestPreferenceKey)
    }

    /// Everything that should be outstanding for `state` at `now`. `drift` (from
    /// `Clock.Reading.drift`) moves fire dates onto the device's own clock, since that's what
    /// the system schedules against. `digest` defaults off since it's a device-local preference.
    static func plan(
        state: SharedState,
        now: Date,
        drift: TimeInterval = 0,
        digest: Bool = false,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        weeklyDigests(state: state, now: now, drift: drift, wanted: digest, calendar: calendar)
        + state.pending
            .filter { $0.effectiveAt > now }
            .sorted { $0.effectiveAt < $1.effectiveAt }
            .flatMap { change -> [PlannedNotification] in
                let what = describe(change, in: state.config, calendar: calendar)
                var planned: [PlannedNotification] = []
                let warnAt = change.effectiveAt.addingTimeInterval(-lead)
                // Skip the warning if under an hour remains — it would fire at the same moment as landing.
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

    /// The digest for the coming Monday, if wanted and the week has something to report. A
    /// one-shot notification, not repeating (its numbers would go stale); re-planned on every
    /// enforce/reconcile. A missed digest is never caught up — the next one is just next Monday.
    private static func weeklyDigests(
        state: SharedState, now: Date, drift: TimeInterval, wanted: Bool, calendar: Calendar
    ) -> [PlannedNotification] {
        guard wanted, let next = nextDigestDate(after: now, calendar: calendar) else { return [] }
        // Re-planning closes the gap between whole days counted now and Monday morning; the id
        // carries a fingerprint of the copy so a changed re-plan replaces rather than duplicates.
        guard let digest = Record.weeklyDigest(state.runtime.days, upTo: next, calendar: calendar) else { return [] }
        return [PlannedNotification(
            id: digestPrefix + fingerprint(digest.title + digest.body),
            title: digest.title,
            body: digest.body,
            fireAt: next.addingTimeInterval(drift)
        )]
    }

    /// The next Monday morning strictly after `now`, on Furlough's own clock (matches local
    /// time, not a fixed offset).
    static func nextDigestDate(after now: Date, calendar: Calendar = .current) -> Date? {
        var parts = DateComponents()
        parts.weekday = Furlough.digestWeekday
        parts.hour = Furlough.digestHour
        parts.minute = 0
        parts.second = 0
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
    }

    /// A fingerprint stable across launches (Swift's `hashValue` is seeded per process and
    /// would reschedule the same digest forever). FNV-1a, 64-bit, base 36.
    static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
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
        case .setAnchorSchedules(let schedules):
            return "The anchor's schedule becomes: \(TimeFormat.anchorSchedules(schedules, calendar: calendar))."
        }
    }

    /// Makes the system's scheduled notifications match `plan`, diffing against what's already
    /// scheduled so this can run on every enforce without re-scheduling everything.
    static func sync(
        state: SharedState,
        now: Date,
        drift: TimeInterval = 0,
        digest: Bool = false,
        calendar: Calendar = .current
    ) {
        let planned = plan(state: state, now: now, drift: drift, digest: digest, calendar: calendar)
        // Only identifiers cross into the callback — UNUserNotificationCenter/UNNotificationRequest aren't Sendable.
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
            // A calendar trigger (not a time interval) survives the app being closed. Seconds
            // are included so it doesn't fire early, at the top of the minute.
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

/// Posts a local notification now; shared by the monitor extension and the Mac enforcer, which
/// each used to have their own copy.
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
