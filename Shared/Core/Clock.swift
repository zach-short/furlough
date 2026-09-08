import Foundation

/// A reading of both clocks at the same instant: the wall clock, which anyone can change in
/// Settings, and the machine's own count of seconds since it booted, which nobody can.
struct ClockMark: Codable, Equatable {
    var wall: Date
    var uptime: TimeInterval
}

/// Furlough's whole loosening rule is "wait", so the clock is part of the lock. Turning off
/// "Set Automatically" and moving the date forward a day would otherwise land every queued
/// loosening at once, on both platforms. Every save records the two clocks together; a later
/// reading whose wall time has run further ahead than the machine has been up says the wall
/// clock was moved, and the queue freezes until it is put back.
///
/// The hole that is left: a reboot resets the machine's count, so a reboot followed by a clock
/// change looks like an ordinary first reading. That is documented in README on purpose.
enum Clock {
    /// Small corrections — an NTP step, a manual nudge of a few minutes — are not worth
    /// freezing the queue for.
    static let tolerance: TimeInterval = 10 * 60

    /// Seconds since boot, counting the time the machine spent asleep. `ProcessInfo`'s
    /// `systemUptime` stops while a Mac sleeps, which would read a night with the lid shut as
    /// an eight-hour jump forward; Darwin's `CLOCK_MONOTONIC` keeps counting through sleep and
    /// still starts again from zero at boot, which is what makes a reboot detectable.
    static var uptime: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    static var mark: ClockMark { ClockMark(wall: .now, uptime: uptime) }

    enum Trust: Equatable {
        case trusted
        /// The wall clock has run this far ahead of the machine's own count.
        case movedForward(by: TimeInterval)

        var isTrusted: Bool { self == .trusted }
    }

    /// Trusted when there is no mark to compare against (the first reading), after a reboot
    /// (uptime went backwards, so the two are no longer comparable), and whenever the wall
    /// clock has advanced no further than uptime has, give or take the tolerance. A clock moved
    /// *backwards* is trusted too: it only delays pending changes, which is what holding them
    /// would do anyway.
    static func isTrusted(
        now: Date,
        uptime: TimeInterval,
        mark: ClockMark?,
        tolerance: TimeInterval = Clock.tolerance
    ) -> Trust {
        guard let mark, uptime >= mark.uptime else { return .trusted }
        let drift = now.timeIntervalSince(mark.wall) - (uptime - mark.uptime)
        return drift > tolerance ? .movedForward(by: drift) : .trusted
    }

    /// The mark to store with this reading. A trusted reading replaces the mark; while the wall
    /// clock is ahead, the old mark is kept, so only putting the clock back restores trust.
    static func stamp(
        _ mark: ClockMark?,
        now: Date = .now,
        uptime: TimeInterval = Clock.uptime
    ) -> ClockMark {
        let fresh = ClockMark(wall: now, uptime: uptime)
        guard let mark else { return fresh }
        return isTrusted(now: now, uptime: uptime, mark: mark).isTrusted ? fresh : mark
    }

    /// "2 h 5 min", for the log.
    static func describe(_ drift: TimeInterval) -> String {
        let minutes = Int((drift / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

extension SharedState {
    /// What this machine's clock looks like against the mark the last save left behind.
    func clockTrust(now: Date = .now, uptime: TimeInterval = Clock.uptime) -> Clock.Trust {
        Clock.isTrusted(now: now, uptime: uptime, mark: runtime.clock)
    }
}
