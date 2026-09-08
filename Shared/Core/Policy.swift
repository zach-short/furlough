import Foundation
#if os(iOS)
import ManagedSettings
#endif

enum TargetStatus: Equatable {
    /// Locked by the Brick profile. Only its paired tag lifts this.
    case bricked
    case unconfigured
    case blockedAllDay
    /// Inside a window with budget remaining. `until` is the window's end minute, midnight
    /// for a rule without windows.
    case open(until: Int)
    case exhausted(nextOpen: NextOpen?)
    case closed(nextOpen: NextOpen)

    var isAllowed: Bool {
        switch self {
        case .open, .unconfigured: true
        default: false
        }
    }
}

struct NextOpen: Equatable {
    var minuteOfDay: Int
    /// 0 is today, 1 tomorrow, up to 7 for the same weekday next week.
    var daysAhead: Int

    var isToday: Bool { daysAhead == 0 }
    var isTomorrow: Bool { daysAhead == 1 }
    /// 12:00 AM tomorrow: the day rolls over, which is when an all-day rule's budget resets.
    var isMidnight: Bool { daysAhead == 1 && minuteOfDay == 0 }
}

enum ChangeClass: Equatable {
    case tightening
    case loosening
}

#if os(iOS)
/// What the shields should look like right now.
struct Decision {
    var allowedApps: Set<ApplicationToken> = []
    var allowedWeb: Set<WebDomainToken> = []
    var shieldedApps: Set<ApplicationToken> = []
    var shieldedWeb: Set<WebDomainToken> = []
    var categories: Set<ActivityCategoryToken> = []
    var statuses: [UUID: TargetStatus] = [:]

    var isAnythingShielded: Bool {
        !shieldedApps.isEmpty || !shieldedWeb.isEmpty || !categories.isEmpty
    }
}
#else
/// What the Mac must enforce right now: apps by bundle identifier, websites by host.
struct Decision {
    var blockedApps: Set<String> = []
    var blockedHosts: Set<String> = []
    var statuses: [UUID: TargetStatus] = [:]

    var isAnythingShielded: Bool { !blockedApps.isEmpty || !blockedHosts.isEmpty }
}
#endif

/// Pure rules engine. No I/O; every function takes the state it needs.
enum Policy {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Calendar's weekday number, 1 = Sunday … 7 = Saturday.
    static func weekday(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// Whole days from the start of `from`'s day to the start of `to`'s day.
    static func daysAhead(of to: Date, from: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    static func date(atMinute minute: Int, of day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minute, to: start) ?? start
    }

    static func date(at next: NextOpen, from now: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: next.daysAhead, to: now) ?? now
        return date(atMinute: next.minuteOfDay, of: day, calendar: calendar)
    }

    /// How much of the window from `start` to `end` (minutes of `now`'s day) is still ahead, 0…1.
    static func windowFraction(start: Int, end: Int, now: Date, calendar: Calendar = .current) -> Double {
        let startDate = date(atMinute: start, of: now, calendar: calendar)
        let endDate = date(atMinute: end, of: now, calendar: calendar)
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 0 }
        return min(1, max(0, endDate.timeIntervalSince(now) / total))
    }

    // MARK: Pending changes

    /// Applies every pending change whose time has come. Returns true when anything changed.
    @discardableResult
    static func applyDuePending(_ state: inout SharedState, now: Date) -> Bool {
        let due = state.pending
            .filter { $0.effectiveAt <= now }
            .sorted { $0.effectiveAt < $1.effectiveAt }
        guard !due.isEmpty else { return false }
        for change in due {
            apply(change, to: &state.config)
        }
        state.pending.removeAll { $0.effectiveAt <= now }
        return true
    }

    static func apply(_ change: PendingChange, to config: inout Config) {
        switch change.kind {
        case .setRule(let id, let rule):
            if let index = config.targets.firstIndex(where: { $0.id == id }) {
                config.targets[index].rule = rule
            }
        case .removeTarget(let id):
            config.targets.removeAll { $0.id == id }
        case .setDelay(let hours):
            config.loosenDelayHours = hours
        }
    }

    /// The config as it stands at `now`, with due pending changes folded in but nothing persisted.
    static func effectiveConfig(_ state: SharedState, now: Date) -> Config {
        var copy = state
        applyDuePending(&copy, now: now)
        return copy.config
    }

    /// Tightening applies immediately; loosening waits out the delay. Removing means "unrestricted".
    static func classify(newRule: Rule?, against target: Target?) -> ChangeClass {
        let old = target?.rule ?? .unrestricted
        let new = newRule ?? .unrestricted
        return new.isTighterOrEqual(to: old) ? .tightening : .loosening
    }

    // MARK: Status

    static func status(of target: Target, config: Config, runtime: RuntimeState, now: Date) -> TargetStatus {
        if config.isBricked(target) { return .bricked }
        guard let rule = target.rule else { return .unconfigured }
        guard rule.isEverAllowed else { return .blockedAllDay }
        let minute = minuteOfDay(now)
        let weekday = weekday(now)
        if runtime.isExhausted(target.id, dayKey: dayKey(now)) {
            return .exhausted(nextOpen: nextOpen(in: rule, afterWeekday: weekday))
        }
        if let current = rule.window(containing: minute, on: weekday) {
            return .open(until: current.endMinute)
        }
        if let next = rule.windows(on: weekday).first(where: { $0.startMinute > minute }) {
            return .closed(nextOpen: NextOpen(minuteOfDay: next.startMinute, daysAhead: 0))
        }
        return .closed(nextOpen: nextOpen(in: rule, afterWeekday: weekday) ?? NextOpen(minuteOfDay: 0, daysAhead: 1))
    }

    /// The first window on the nearest day after `weekday` that has one, up to a week out.
    /// Nil only when the rule never allows anything.
    static func nextOpen(in rule: Rule, afterWeekday weekday: Int) -> NextOpen? {
        guard rule.isEverAllowed else { return nil }
        for ahead in 1...7 {
            let day = (weekday - 1 + ahead) % 7 + 1
            if let first = rule.windows(on: day).first {
                return NextOpen(minuteOfDay: first.startMinute, daysAhead: ahead)
            }
        }
        return nil
    }

    #if os(iOS)
    static func decide(config: Config, runtime: RuntimeState, now: Date) -> Decision {
        var decision = Decision()
        for target in config.targets {
            let status = status(of: target, config: config, runtime: runtime, now: now)
            decision.statuses[target.id] = status
            switch target.kind {
            case .application(let token):
                if status.isAllowed { decision.allowedApps.insert(token) } else { decision.shieldedApps.insert(token) }
            case .webDomain(let token):
                if status.isAllowed { decision.allowedWeb.insert(token) } else { decision.shieldedWeb.insert(token) }
            case .category(let token):
                decision.categories.insert(token)
            }
        }
        // The brick can hold things that are not targets at all; while bricked they are all shielded.
        if config.brick.isBricked {
            for kind in config.brick.kinds {
                switch kind {
                case .application(let token):
                    decision.allowedApps.remove(token)
                    decision.shieldedApps.insert(token)
                case .webDomain(let token):
                    decision.allowedWeb.remove(token)
                    decision.shieldedWeb.insert(token)
                case .category(let token):
                    decision.categories.insert(token)
                }
            }
        }
        return decision
    }
    #else
    static func decide(config: Config, runtime: RuntimeState, now: Date) -> Decision {
        var decision = Decision()
        for target in config.targets {
            let status = status(of: target, config: config, runtime: runtime, now: now)
            decision.statuses[target.id] = status
            guard !status.isAllowed else { continue }
            switch target.kind {
            case .macApp(let bundleID): decision.blockedApps.insert(bundleID)
            case .host(let host): decision.blockedHosts.insert(host)
            }
        }
        if config.brick.isBricked {
            for kind in config.brick.kinds {
                switch kind {
                case .macApp(let bundleID): decision.blockedApps.insert(bundleID)
                case .host(let host): decision.blockedHosts.insert(host)
                }
            }
        }
        return decision
    }
    #endif

    /// The next instant at which some status can change: a window edge later today, else midnight.
    static func nextTransition(config: Config, after now: Date, calendar: Calendar = .current) -> Date {
        let minute = minuteOfDay(now, calendar: calendar)
        let weekday = weekday(now, calendar: calendar)
        var candidates: [Int] = []
        for target in config.targets {
            guard let rule = target.rule, rule.isEverAllowed else { continue }
            for window in rule.windows(on: weekday) {
                if window.startMinute > minute { candidates.append(window.startMinute) }
                if window.endMinute > minute && window.endMinute < Furlough.minutesPerDay { candidates.append(window.endMinute) }
            }
        }
        if let soonest = candidates.min() {
            return date(atMinute: soonest, of: now, calendar: calendar)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.startOfDay(for: tomorrow)
    }

    // MARK: Summary for widgets and Live Activities

    struct Summary: Equatable {
        var openNames: [String] = []
        var openUntil: Date?
        /// Start of the open window that closes soonest, so the widget's sand can be at the right level.
        var openStart: Date?
        /// That target has had its 5-minute budget warning.
        var openWarned = false
        /// Open with no windows of their own: usable all day, up to the budget. Kept apart from
        /// `openNames` so they get no closing countdown and no Live Activity.
        var allDayNames: [String] = []
        /// One of those has had its 5-minute budget warning.
        var allDayWarned = false
        var nextOpenAt: Date?
        var nextOpenNames: [String] = []
        /// Budget of the target opening next, for the widget's detail line.
        var nextOpenBudgetMinutes: Int?
        /// The target opening next is waiting because its budget is spent, not its window.
        var nextOpenIsExhausted = false
        var blockedCount = 0
        var exhaustedCount = 0
        var unconfiguredCount = 0
        var pendingCount = 0
        var isBricked = false
        /// Everything the brick holds, targets or not, while bricked.
        var brickedCount = 0

        var isEmpty: Bool {
            openNames.isEmpty && allDayNames.isEmpty && nextOpenAt == nil && blockedCount == 0
                && unconfiguredCount == 0 && brickedCount == 0
        }
    }

    static func summary(state: SharedState, now: Date) -> Summary {
        let config = effectiveConfig(state, now: now)
        var summary = Summary()
        summary.pendingCount = state.pending.filter { $0.effectiveAt > now }.count
        summary.isBricked = config.brick.isBricked
        summary.brickedCount = config.brick.isBricked ? config.brick.count : 0
        let minute = minuteOfDay(now)
        let weekday = weekday(now)
        var soonestOpen: (until: Int, start: Int, warned: Bool)?
        var soonest: (date: Date, names: [String], budget: Int?, exhausted: Bool)?

        for target in config.targets {
            switch status(of: target, config: config, runtime: state.runtime, now: now) {
            case .bricked:
                summary.blockedCount += 1
            case .unconfigured:
                summary.unconfiguredCount += 1
            case .blockedAllDay:
                summary.blockedCount += 1
            case .open(let until):
                let warned = state.runtime.wasWarned(target.id, dayKey: dayKey(now))
                if target.rule?.isAllDay ?? false {
                    summary.allDayNames.append(target.displayName)
                    summary.allDayWarned = summary.allDayWarned || warned
                } else {
                    summary.openNames.append(target.displayName)
                    if soonestOpen == nil || until < soonestOpen!.until {
                        let start = target.rule?.window(containing: minute, on: weekday)?.startMinute ?? 0
                        soonestOpen = (until, start, warned)
                    }
                }
            case .exhausted(let next):
                summary.exhaustedCount += 1
                summary.blockedCount += 1
                if let next { consider(date(at: next, from: now), target, exhausted: true) }
            case .closed(let next):
                summary.blockedCount += 1
                consider(date(at: next, from: now), target, exhausted: false)
            }
        }
        func consider(_ date: Date, _ target: Target, exhausted: Bool) {
            let name = target.displayName
            let budget = target.rule?.dailyBudgetMinutes
            if let current = soonest {
                if date < current.date { soonest = (date, [name], budget, exhausted) }
                else if date == current.date { soonest?.names.append(name) }
            } else {
                soonest = (date, [name], budget, exhausted)
            }
        }
        if let soonestOpen {
            summary.openUntil = date(atMinute: soonestOpen.until, of: now)
            summary.openStart = date(atMinute: soonestOpen.start, of: now)
            summary.openWarned = soonestOpen.warned
        }
        summary.nextOpenAt = soonest?.date
        summary.nextOpenNames = soonest?.names ?? []
        summary.nextOpenBudgetMinutes = soonest?.budget
        summary.nextOpenIsExhausted = soonest?.exhausted ?? false
        return summary
    }
}
