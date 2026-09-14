import Foundation

/// String conventions for DeviceActivity activity and event names.
enum ActivityNaming {
    static let day = "day"

    static func window(_ window: TimeWindow) -> String {
        "window:\(window.startMinute)-\(window.endMinute)"
    }

    static func parseWindow(_ raw: String) -> TimeWindow? {
        guard raw.hasPrefix("window:") else { return nil }
        let parts = raw.dropFirst("window:".count).split(separator: "-")
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) else { return nil }
        return TimeWindow(startMinute: start, endMinute: end)
    }

    static func budgetEvent(targetID: UUID, minutes: Int) -> String {
        "budget:\(targetID.uuidString):\(minutes)"
    }

    static func parseBudgetEvent(_ raw: String) -> (targetID: UUID, minutes: Int)? {
        let parts = raw.split(separator: ":")
        guard parts.count == 3, parts[0] == "budget",
              let id = UUID(uuidString: String(parts[1])),
              let minutes = Int(parts[2]) else { return nil }
        return (id, minutes)
    }

    // MARK: The anchor's clock

    static let anchorUntil = "anchor-until"

    /// One repeating activity per distinct minute of day; the monitor checks the weekday
    /// itself when it fires.
    static func anchorDrop(minute: Int) -> String { "anchor:\(minute)" }

    static func anchorLift(minute: Int) -> String { "anchor-lift:\(minute)" }

    static func parseAnchorDrop(_ raw: String) -> Int? { minute(after: "anchor:", in: raw) }
    static func parseAnchorLift(_ raw: String) -> Int? { minute(after: "anchor-lift:", in: raw) }

    private static func minute(after prefix: String, in raw: String) -> Int? {
        guard raw.hasPrefix(prefix) else { return nil }
        return Int(raw.dropFirst(prefix.count))
    }

    /// DeviceActivity needs at least a 15-minute interval, so the activity normally ends at
    /// the target minute (end callback); in the first 15 minutes after midnight there's no
    /// room before it, so it starts there instead (start callback).
    static func anchorInterval(minute: Int) -> (start: Int, end: Int, firesAtStart: Bool) {
        if minute < Furlough.minimumWindowMinutes {
            return (minute, minute + Furlough.minimumWindowMinutes, true)
        }
        return (minute - Furlough.minimumWindowMinutes, minute, false)
    }
}
