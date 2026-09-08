import Foundation

/// A reading of both clocks at the same instant: the wall clock, which anyone can change in
/// Settings, and the machine's own count of seconds since it booted, which nobody can.
struct ClockMark: Codable, Equatable {
    var wall: Date
    var uptime: TimeInterval
}

/// Furlough keeps its own time, because its whole loosening rule is "wait" and the device's
/// clock is a setting. Every save records the two clocks together. Later, the mark plus the
/// seconds the machine has counted since says what the time really is; while the device agrees
/// with that, Furlough uses the device's clock, and when it does not, Furlough uses its own.
/// So turning off "Set Automatically" and moving the date forward a day changes nothing at all:
/// no window opens early, no budget resets, no queued loosening lands.
///
/// The hole that is left: a reboot starts the machine's count again from zero, so a reboot
/// followed by a clock change looks like an ordinary first reading. It is documented in README,
/// and it doubles as the way out for a device whose clock was genuinely wrong.
enum Clock {
    /// Small corrections — an NTP step, a manual nudge of a few minutes — are not worth
    /// leaving the device's clock over.
    static let tolerance: TimeInterval = 10 * 60

    /// Seconds since boot, counting the time the machine spent asleep. `ProcessInfo`'s
    /// `systemUptime` stops while a Mac sleeps, which would read a night with the lid shut as
    /// an eight-hour jump forward; Darwin's `CLOCK_MONOTONIC` keeps counting through sleep and
    /// still starts again from zero at boot, which is what makes a reboot detectable.
    static var uptime: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    static var mark: ClockMark { ClockMark(wall: .now, uptime: uptime) }

    /// What Furlough believes the time is, and how far the device's clock is from it.
    struct Reading: Equatable {
        /// The time to judge everything against: windows, days, budgets, pending changes.
        var now: Date
        /// How far the device's clock is ahead (positive) or behind (negative). Zero while the
        /// two agree, which is every day of normal use.
        var drift: TimeInterval

        var isTrusted: Bool { drift == 0 }

        /// A Furlough time on the device's clock. Anything the system renders for itself — a
        /// Live Activity's timer, a widget timeline entry — has to be given one of these.
        func device(_ date: Date) -> Date { drift == 0 ? date : date.addingTimeInterval(drift) }

        /// The Furlough time behind a device time.
        func honest(_ date: Date) -> Date { drift == 0 ? date : date.addingTimeInterval(-drift) }
    }

    /// The device's clock is taken at its word when there is no mark to check it against (the
    /// first reading), after a reboot (the machine's count started again, so the two are no
    /// longer comparable), and while it agrees with the mark's projection to within the
    /// tolerance. Otherwise Furlough runs on the projection, in either direction: a clock moved
    /// back would hold everything up just as surely as one moved forward lets it go.
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

    /// The mark to store with this reading. A reading Furlough trusts replaces the mark; while
    /// the device's clock is off, the old mark is kept, because it is the only thing left that
    /// knows what the time really is.
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
    /// What Furlough makes of this machine's clock, against the mark the last save left behind.
    func clock(wall: Date = .now, uptime: TimeInterval = Clock.uptime) -> Clock.Reading {
        Clock.read(wall: wall, uptime: uptime, mark: runtime.clock)
    }

    /// The time Furlough runs on. Use this, never `Date.now`, for anything the rules touch.
    var now: Date { clock().now }
}
