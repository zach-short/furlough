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
}
