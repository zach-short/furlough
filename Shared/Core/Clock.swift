import Foundation

/// A reading of both clocks at the same instant: the wall clock, which anyone can change in
/// Settings, and the machine's own count of seconds since it booted, which nobody can.
struct ClockMark: Codable, Equatable {
    var wall: Date
    var uptime: TimeInterval
}

/// Furlough distrusts the wall clock, since its whole loosening rule is "wait" and the device's
/// clock is a user setting. Tracks drift via boot-relative uptime instead, so setting the date
/// forward manually changes nothing. Known gap: a reboot resets the uptime counter to zero, so
/// a reboot + clock change looks like a first reading — documented in README, and doubles as
/// the escape hatch for a genuinely wrong clock.
enum Clock {
    /// Small corrections (NTP step, manual nudge) aren't worth distrusting the clock over.
    static let tolerance: TimeInterval = 10 * 60

    /// Uses `CLOCK_MONOTONIC` rather than `ProcessInfo.systemUptime`, since the latter stops
    /// counting while a Mac sleeps (an overnight lid-close would read as an 8-hour jump).
    static var uptime: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    static var mark: ClockMark { ClockMark(wall: .now, uptime: uptime) }

    struct Reading: Equatable {
        var now: Date
        /// How far the device's clock is ahead (+) or behind (-). Zero in normal use.
        var drift: TimeInterval

        var isTrusted: Bool { drift == 0 }

        /// System-rendered UI (Live Activity timers, widget timelines) needs Furlough time
        /// converted back onto the device's own clock.
        func device(_ date: Date) -> Date { drift == 0 ? date : date.addingTimeInterval(drift) }

        func honest(_ date: Date) -> Date { drift == 0 ? date : date.addingTimeInterval(-drift) }
    }

    /// Trusts the device clock with no mark to check against, right after a reboot (uptime
    /// reset makes the two incomparable), or within tolerance of the projection. Otherwise runs
    /// on the projection either direction — a clock moved backward holds things up too.
    static func read(
        wall: Date = .now,
        uptime: TimeInterval = Clock.uptime,
        mark: ClockMark?,
        tolerance: TimeInterval = Clock.tolerance
    ) -> Reading {
        guard let mark, uptime >= mark.uptime else { return Reading(now: wall, drift: 0) }
        let projected = mark.wall.addingTimeInterval(uptime - mark.uptime)
        let drift = wall.timeIntervalSince(projected)
        return abs(drift) <= tolerance ? Reading(now: wall, drift: 0) : Reading(now: projected, drift: drift)
    }

    /// Keeps the old mark while the device's clock is off — it's the only thing left that
    /// knows the real time.
    static func stamp(
        _ mark: ClockMark?,
        wall: Date = .now,
        uptime: TimeInterval = Clock.uptime
    ) -> ClockMark {
        let fresh = ClockMark(wall: wall, uptime: uptime)
        guard mark != nil else { return fresh }
        return read(wall: wall, uptime: uptime, mark: mark).isTrusted ? fresh : mark ?? fresh
    }

    /// "40 min", "3 h 5 min", "1 day", "2 d 4 h". Unsigned; the caller says which way.
    static func describe(_ drift: TimeInterval) -> String {
        let total = Int(abs(drift).rounded())
        let (days, hours, minutes) = (total / 86_400, (total % 86_400) / 3600, (total % 3600) / 60)
        if days > 0 {
            if hours > 0 { return "\(days) d \(hours) h" }
            return days == 1 ? "1 day" : "\(days) days"
        }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }
}

extension SharedState {
    func clock(wall: Date = .now, uptime: TimeInterval = Clock.uptime) -> Clock.Reading {
        Clock.read(wall: wall, uptime: uptime, mark: runtime.clock)
    }

    /// The time Furlough runs on. Use this, never `Date.now`, for anything the rules touch.
    var now: Date { clock().now }
}
