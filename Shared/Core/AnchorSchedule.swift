import Foundation

/// A time of day, on some days of the week, at which the anchor drops by itself. Optionally
/// self-lifts at `liftMinuteOfDay`; otherwise only the tag lifts it.
struct AnchorSchedule: Codable, Hashable, Identifiable {
    var id = UUID()
    var minuteOfDay: Int
    var days: Weekdays = .all
    /// Nil means the tag is the only way back.
    var liftMinuteOfDay: Int?

    func applies(on weekday: Int) -> Bool { days.contains(weekday: weekday) }

    /// A lift earlier in the day than the drop wraps to the next morning.
    static func holdMinutes(drop: Int, lift: Int) -> Int {
        ((lift - drop) % Furlough.minutesPerDay + Furlough.minutesPerDay) % Furlough.minutesPerDay
    }

    /// Nil for a tag-only schedule; otherwise wraps to the next day when the lift minute
    /// falls at or before the drop.
    func liftDate(afterDropAt dropped: Date, calendar: Calendar = .current) -> Date? {
        guard let lift = liftMinuteOfDay else { return nil }
        let sameDay = Policy.date(atMinute: lift, of: dropped, calendar: calendar)
        if sameDay > dropped { return sameDay }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: dropped) ?? dropped
        return Policy.date(atMinute: lift, of: tomorrow, calendar: calendar)
    }

    /// Looks up to a week ahead; nil when the schedule applies on no days. A drop at exactly
    /// `now` counts as past (its callback is the one currently firing).
    func nextDrop(after now: Date, calendar: Calendar = .current) -> Date? {
        guard !days.isEmpty else { return nil }
        for ahead in 0...7 {
            let day = calendar.date(byAdding: .day, value: ahead, to: now) ?? now
            guard applies(on: Policy.weekday(day, calendar: calendar)) else { continue }
            let drop = Policy.date(atMinute: minuteOfDay, of: day, calendar: calendar)
            if drop > now { return drop }
        }
        return nil
    }
}

extension Array where Element == AnchorSchedule {
    func nextDrop(after now: Date, calendar: Calendar = .current) -> Date? {
        compactMap { $0.nextDrop(after: now, calendar: calendar) }.min()
    }
}

extension AnchorProfile {
    /// True past `isAnchored` alone checks `until` directly, since a timed anchor is
    /// considered released the instant `until` passes even before the flag is cleared.
    func isHolding(at now: Date) -> Bool {
        guard isAnchored else { return false }
        guard let until else { return true }
        return until > now
    }

    func blocks(_ kind: TargetKind, at now: Date) -> Bool { isHolding(at: now) && holds(kind) }
}

extension Config {
    /// The longest per-target delay among everything the anchor holds, since loosening the
    /// schedule loosens the hold on all of them at once.
    var anchorDelayHours: Int {
        let held = targets.filter { target in target.kinds.contains { anchor.holds($0) } }
        return held.map { delayHours(for: $0) }.max() ?? delayHours(for: nil)
    }
}

extension Policy {
    enum DropRefusal: Equatable {
        case alreadyAnchored
        case nothingToAnchor
        /// DeviceActivity won't wake the monitor for a shorter interval than this.
        case tooSoon
        case noList
        /// Mac-only: no linked iPhone, and only an iPhone's tag can lift an anchor.
        case noPhone
        /// Mac-only, checked before `noPhone`: signed out of iCloud entirely.
        case noCloud

        var message: String {
            switch self {
            case .alreadyAnchored: "Already anchored."
            case .nothingToAnchor: "Choose apps and pair a tag first."
            case .tooSoon: "Give it at least \(Furlough.minimumWindowMinutes) minutes."
            case .noList: "Choose what the anchor holds first."
            case .noPhone: "No iPhone is on the link with this Mac. Only an iPhone's tag can release an anchor dropped here, so Furlough will not lock this Mac until one is — link both under Settings > Devices, then Drop anchor."
            case .noCloud: AnchorSync.cutOffWarning
            }
        }
    }

    /// Kept pure so `AnchorDrop.drop` and tests share it. Folds an already-passed `until`
    /// first, so a timed anchor that self-lifted but wasn't cleared yet can be dropped again.
    static func drop(_ config: inout Config, now: Date, until: Date? = nil) -> DropRefusal? {
        liftExpiredAnchor(&config, now: now)
        guard config.anchor.canAnchor else {
            return config.anchor.isAnchored ? .alreadyAnchored : .nothingToAnchor
        }
        if let until, until < now.addingTimeInterval(TimeInterval(Furlough.minimumWindowMinutes * 60)) {
            return .tooSoon
        }
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = now
        config.anchor.until = until
        config.anchor.sequence += 1
        return nil
    }

    /// Idempotent and only ever tightens: with the anchor already down it can lengthen the
    /// hold (never shorten it), and a lift already past by the time a late callback arrives
    /// drops nothing rather than re-dropping something already released.
    @discardableResult
    static func scheduledDrop(_ config: inout Config, minute: Int, now: Date, calendar: Calendar = .current) -> AnchorSchedule? {
        liftExpiredAnchor(&config, now: now)
        let weekday = weekday(now, calendar: calendar)
        guard let schedule = config.anchor.schedules.first(where: { $0.minuteOfDay == minute && $0.applies(on: weekday) }),
              config.anchor.hasSomethingToHold, config.anchor.isPaired
        else { return nil }
        // Uses the scheduled minute, not the callback time, so a late callback can't push
        // the lift later than promised.
        let dropped = date(atMinute: minute, of: now, calendar: calendar)
        let lift = schedule.liftDate(afterDropAt: dropped, calendar: calendar)
        if let lift, lift <= now { return nil }
        if config.anchor.isAnchored {
            let tighter = tighterUntil(config.anchor.until, lift)
            guard tighter != config.anchor.until else { return nil }
            config.anchor.until = tighter
            config.anchor.sequence += 1
            return schedule
        }
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = now
        config.anchor.until = lift
        config.anchor.sequence += 1
        return schedule
    }

    /// Nil (tag-only) beats any time; otherwise the later time wins.
    static func tighterUntil(_ a: Date?, _ b: Date?) -> Date? {
        guard let a, let b else { return nil }
        return max(a, b)
    }

    /// Called wherever pending changes are folded (reconciler, `enforce`) so a self-lifted
    /// anchor gets cleared by whichever process touches state first.
    @discardableResult
    static func liftExpiredAnchor(_ config: inout Config, now: Date) -> Bool {
        guard config.anchor.isAnchored, let until = config.anchor.until, until <= now else { return false }
        config.anchor.isAnchored = false
        config.anchor.anchoredAt = nil
        config.anchor.until = nil
        return true
    }

    /// Tightening iff every old drop still happens, held at least as long (tag-only lift
    /// counts as latest). Removing a drop/day, adding or earlying a lift is loosening and
    /// waits out the delay — including moving a drop's *time*, since the old minute is
    /// simply gone (the editor represents that as remove+add so only the removal waits).
    static func classify(newSchedules new: [AnchorSchedule], against old: [AnchorSchedule]) -> ChangeClass {
        for schedule in old {
            for weekday in 1...7 where schedule.applies(on: weekday) {
                let kept = new.contains { candidate in
                    candidate.minuteOfDay == schedule.minuteOfDay
                        && candidate.applies(on: weekday)
                        && liftIsNoEarlier(candidate.liftMinuteOfDay, than: schedule.liftMinuteOfDay, drop: schedule.minuteOfDay)
                }
                if !kept { return .loosening }
            }
        }
        return .tightening
    }

    private static func liftIsNoEarlier(_ candidate: Int?, than old: Int?, drop: Int) -> Bool {
        guard let old else { return candidate == nil }
        guard let candidate else { return true }
        return AnchorSchedule.holdMinutes(drop: drop, lift: candidate) >= AnchorSchedule.holdMinutes(drop: drop, lift: old)
    }
}
