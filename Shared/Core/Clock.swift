import Foundation

/// A reading of both clocks at the same instant: the wall clock, which anyone can change in
/// Settings, and the machine's own count of seconds since it booted, which nobody can.
struct ClockMark: Codable, Equatable {
    var wall: Date
    var uptime: TimeInterval
}

/// The time zone Furlough honours, and when the device stopped agreeing with it. A zone change
/// moves neither of `ClockMark`'s numbers — the same instant is the same `Date` in every zone —
/// so it needs a mark of its own. Keyed on the identifier, never the offset: DST moves the offset
/// twice a year with nobody's hand on it, and has to read as nothing here.
struct ZoneMark: Codable, Equatable {
    var identifier: String
    /// When the device was first seen in another zone; nil while it agrees. The hold is measured
    /// from this sighting rather than from the last save, because a phone that saved nothing
    /// since last night's midnight callback would otherwise arrive at the hold with most of it
    /// already spent.
    var movedAt: Date?
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

    // MARK: The time zone

    /// Where the rules run. A zone change delays nothing — it re-reads the same rules against
    /// different local hours — so it is not held the way a moved wall clock is. Instead the zone
    /// the device left is honoured beside the new one for a while: every decision is made under
    /// both and the tighter wins (`Policy.tighter`), and the day budgets are keyed by is the held
    /// zone's, since a new day refills them whichever way the traveller flew.
    enum ZoneReading: Equatable {
        /// The device agrees with the zone Furlough honours, or the move has been held long enough.
        case settled
        /// The device is in another zone; `from` is still honoured until `until`.
        case moved(from: String, until: Date)

        var isSettled: Bool { self == .settled }

        /// A calendar like `current` but in the held zone, for the second decision; nil when
        /// settled, and nil when this OS cannot name the held zone, which leaves one decision
        /// rather than two identical ones.
        func heldCalendar(like current: Calendar = .current) -> Calendar? {
            guard case .moved(let from, _) = self, let zone = TimeZone(identifier: from),
                  zone.identifier != current.timeZone.identifier
            else { return nil }
            var held = current
            held.timeZone = zone
            return held
        }

        /// The calendar day keys are made with: the held zone's while a move is held, so a spent
        /// budget stays spent across a day that rolled only because the zone moved.
        func dayCalendar(like current: Calendar = .current) -> Calendar {
            heldCalendar(like: current) ?? current
        }
    }

    /// Pure: nothing here reads the device. A missing mark is trusted, exactly as a missing
    /// `ClockMark` is. A move not yet stamped (`movedAt` nil) is held from `now`, which is
    /// what the stamp that follows this read will write down.
    static func zone(mark: ZoneMark?, current identifier: String, now: Date, hold: TimeInterval) -> ZoneReading {
        guard let mark, mark.identifier != identifier else { return .settled }
        let until = (mark.movedAt ?? now).addingTimeInterval(hold)
        return now < until ? .moved(from: mark.identifier, until: until) : .settled
    }

    /// Keeps the old zone while a move is still being held — the same reason `stamp` keeps the
    /// old `ClockMark` — writing down when the move was first seen, and lets go of it once the
    /// hold has run out or the device has come back.
    static func stampZone(_ mark: ZoneMark?, current identifier: String, now: Date, hold: TimeInterval) -> ZoneMark {
        guard let mark, mark.identifier != identifier else { return ZoneMark(identifier: identifier) }
        guard let movedAt = mark.movedAt else { return ZoneMark(identifier: mark.identifier, movedAt: now) }
        return now < movedAt.addingTimeInterval(hold) ? mark : ZoneMark(identifier: identifier)
    }

    /// "Eastern Time", "Japan Standard Time" — or the identifier's own last word when the OS has
    /// no name for it.
    static func zoneName(_ identifier: String, locale: Locale = .current) -> String {
        if let name = TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: locale) { return name }
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// The banner's sentence, kept here so the phone, the Mac and the tests share one wording.
    static func describeMove(
        from held: String, to current: String, until: Date, now: Date,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let time = TimeFormat.clock(until, calendar: calendar)
        let when: String
        if calendar.isDate(until, inSameDayAs: now) {
            when = time
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(until, inSameDayAs: tomorrow) {
            when = "\(time) tomorrow"
        } else {
            when = "\(time) on \(TimeFormat.day(until, calendar: calendar))"
        }
        return "Your time zone is now \(zoneName(current, locale: locale)). "
            + "Furlough is keeping \(zoneName(held, locale: locale)) until \(when)."
    }
}

extension SharedState {
    func clock(wall: Date = .now, uptime: TimeInterval = Clock.uptime) -> Clock.Reading {
        Clock.read(wall: wall, uptime: uptime, mark: runtime.clock)
    }

    /// The time Furlough runs on. Use this, never `Date.now`, for anything the rules touch.
    var now: Date { clock().now }

    /// How long the zone a device left stays honoured: the base loosening delay, capped by the
    /// first week like every other delay. A zone change loosens every window at once, which is
    /// the argument `setDelay` already makes for waiting out the base delay when the delay is
    /// lowered. Built on the pass-off's recommendation, 2026-09-14; a flat day was the other
    /// candidate, and this line is the whole difference.
    var zoneHold: TimeInterval { TimeInterval(config.delayHours(for: nil)) * 3600 }

    /// The zone reading at `now`, on Furlough's own clock and this device's zone.
    func zone(now: Date? = nil, current: TimeZone = .current) -> Clock.ZoneReading {
        Clock.zone(mark: runtime.zone, current: current.identifier, now: now ?? self.now, hold: zoneHold)
    }
}
