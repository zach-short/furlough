import Foundation

/// A time of day, on some days of the week, at which the anchor drops by itself. The tag
/// lifts it, as ever — or, when the schedule says so, it lifts by itself at
/// `liftMinuteOfDay`, later the same day or the next morning. Zach's case is the first: it
/// drops at 10 PM on school nights and only the tag lifts it in the morning.
struct AnchorSchedule: Codable, Hashable, Identifiable {
    var id = UUID()
    var minuteOfDay: Int
    var days: Weekdays = .all
    /// Nil means the tag is the only way back.
    var liftMinuteOfDay: Int?

    func applies(on weekday: Int) -> Bool { days.contains(weekday: weekday) }

    /// How long a drop at `drop` holds before a lift at `lift`, minutes round the clock: a
    /// lift earlier in the day than the drop is the next morning.
    static func holdMinutes(drop: Int, lift: Int) -> Int {
        ((lift - drop) % Furlough.minutesPerDay + Furlough.minutesPerDay) % Furlough.minutesPerDay
    }

    /// When a drop at `dropped` lifts by itself: the lift minute later that day, or the next
    /// day when it falls at or before the drop (10 PM to 7 AM). Nil for a tag-only schedule.
    func liftDate(afterDropAt dropped: Date, calendar: Calendar = .current) -> Date? {
        guard let lift = liftMinuteOfDay else { return nil }
        let sameDay = Policy.date(atMinute: lift, of: dropped, calendar: calendar)
        if sameDay > dropped { return sameDay }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: dropped) ?? dropped
        return Policy.date(atMinute: lift, of: tomorrow, calendar: calendar)
    }

    /// The next moment this schedule drops after `now`, up to a week ahead. Nil when it is on
    /// no days. A drop at exactly `now` is past: its callback is the one firing.
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
    /// The soonest drop among these after `now`, or nil when none ever drops.
    func nextDrop(after now: Date, calendar: Calendar = .current) -> Date? {
        compactMap { $0.nextDrop(after: now, calendar: calendar) }.min()
    }
}

extension AnchorProfile {
    /// Whether the anchor is down at `now`: dropped, and not yet past its `until`. A timed
    /// anchor is released the moment its `until` passes, whatever the flag still says — the
    /// monitor's callback and the next reconcile clear the flag, and nothing waits on them.
    func isHolding(at now: Date) -> Bool {
        guard isAnchored else { return false }
        guard let until else { return true }
        return until > now
    }

    /// True when `kind` is blocked by the anchor at `now`.
    func blocks(_ kind: TargetKind, at now: Date) -> Bool { isHolding(at: now) && holds(kind) }
}

extension Config {
    /// Hours a loosening of the anchor's schedule waits: the longest delay among the targets
    /// the anchor holds, since a dropped schedule loosens the hold over all of them at once —
    /// the way lowering the base delay waits out the slowest target — and the base when it
    /// holds nothing Furlough has a rule for.
    var anchorDelayHours: Int {
        let held = targets.filter { target in target.kinds.contains { anchor.holds($0) } }
        return held.map { delayHours(for: $0) }.max() ?? delayHours(for: nil)
    }
}

extension Policy {
    /// Why the anchor would not drop, in the words the alert and the intent use.
    enum DropRefusal: Equatable {
        case alreadyAnchored
        case nothingToAnchor
        /// A timed drop needs at least `Furlough.minimumWindowMinutes`: DeviceActivity will not
        /// wake the monitor for a shorter interval, so a shorter hold would have no lift.
        case tooSoon
        /// The Mac's: nothing on its list.
        case noList
        /// The Mac's: no iPhone is on the link with it, so nothing could ever lift the anchor
        /// — a Mac has no tag reader.
        case noPhone
        /// The Mac's: signed out of iCloud, so no phone can be heard from at all. Checked
        /// before `noPhone`, which is a latch that outlives the account that set it.
        case noCloud

        var message: String {
            switch self {
            case .alreadyAnchored: "Already anchored."
            case .nothingToAnchor: "Choose apps and pair a tag first."
            case .tooSoon: "Give it at least \(Furlough.minimumWindowMinutes) minutes."
            case .noList: "Choose what the anchor holds first."
            // Names the drop, not the pairing. Pairing a tag writes nothing to iCloud, so
            // someone who did only that came back to this Mac and found the same refusal —
            // the phone is heard from when it first drops the anchor, which needs the tag
            // anyway, so asking for the drop asks for both in the order they happen.
            case .noPhone: "No iPhone is on the link with this Mac. Only an iPhone's tag can release an anchor dropped here, so Furlough will not lock this Mac until one is — link both under Settings > Devices, then Drop anchor."
            case .noCloud: AnchorSync.cutOffWarning
            }
        }
    }

    /// Drops the anchor at `now`, until `until` or the tag. The one way the anchor goes down
    /// on purpose from any process — the app, the Drop Anchor intent in the widget extension,
    /// the monitor's schedule through `scheduledDrop` — kept pure so `AnchorDrop.drop` and the
    /// tests share it. An `until` already past is folded first, so a timed anchor that has
    /// lifted itself but not yet been cleared can be dropped again.
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

    /// The drop the monitor performs when the activity for `minute` fires: the schedule at
    /// that minute on today's weekday, if there is one and the anchor has a tag and something
    /// to hold. Returns the schedule that dropped, or nil when nothing changed.
    ///
    /// Idempotent, and a schedule only ever tightens. With the anchor already down it can
    /// lengthen the hold — a tag-only schedule turns a timed anchor into one only the tag
    /// lifts, a later lift replaces an earlier one — and never shortens it. A lift that has
    /// already passed when the callback arrives, which a late callback could produce for a
    /// very short hold, drops nothing rather than dropping something already released.
    @discardableResult
    static func scheduledDrop(_ config: inout Config, minute: Int, now: Date, calendar: Calendar = .current) -> AnchorSchedule? {
        liftExpiredAnchor(&config, now: now)
        let weekday = weekday(now, calendar: calendar)
        guard let schedule = config.anchor.schedules.first(where: { $0.minuteOfDay == minute && $0.applies(on: weekday) }),
              config.anchor.hasSomethingToHold, config.anchor.isPaired
        else { return nil }
        // Counted from the minute the schedule names, not from the callback, so a late
        // callback does not push a lift later than the schedule promised.
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

    /// The tighter of two ends: nil (only the tag) beats any time, and a later time beats an
    /// earlier one.
    static func tighterUntil(_ a: Date?, _ b: Date?) -> Date? {
        guard let a, let b else { return nil }
        return max(a, b)
    }

    /// Lifts an anchor whose `until` has passed. Returns true when it did. Folded wherever due
    /// pending changes are folded — the reconciler, `enforce` — so an anchor that has lifted
    /// itself is cleared by whichever process touches the state first, and the monitor's
    /// callback at `until` is the wake that makes sure one does.
    @discardableResult
    static func liftExpiredAnchor(_ config: inout Config, now: Date) -> Bool {
        guard config.anchor.isAnchored, let until = config.anchor.until, until <= now else { return false }
        config.anchor.isAnchored = false
        config.anchor.anchoredAt = nil
        config.anchor.until = nil
        return true
    }

    /// Tightening or loosening, for an edit to the anchor's schedules.
    ///
    /// Tightening means every drop the old schedules made still happens, held at least as
    /// long: for each old schedule and each day it is on, some new schedule drops at the same
    /// minute on that day, and its lift is no earlier (only the tag being the latest lift of
    /// all). Adding a drop, adding a day, removing a lift or moving one later is tightening
    /// and lands at once. Removing a drop, taking a day off it, adding a lift to a tag-only
    /// schedule or moving one earlier is loosening and waits out the delay. Moving a drop
    /// from 10 PM to 9 PM is a loosening too — the 10 PM drop is gone, and a tag scanned at
    /// half past nine would leave 10 PM uncovered; add the 9 PM drop and let the 10 PM
    /// removal wait, which is what the editor's two rows say.
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
