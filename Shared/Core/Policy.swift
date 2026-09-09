import Foundation
#if os(iOS)
import ManagedSettings
#endif

enum TargetStatus: Equatable {
    /// Locked by the Anchor profile. Only its paired tag lifts this.
    case anchored
    case unconfigured
    case blockedAllDay
    /// Inside a window with budget remaining. `until` is the window's end minute, midnight
    /// for a rule without windows, and past 1440 for a night: an evening that runs into the
    /// next morning is stored as two windows, but it is one window to whoever is using it, so
    /// it says the morning it really ends. `Policy.date(atMinute:of:)` reads those minutes on
    /// into the next day; `TimeFormat.until` says them.
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

/// What `Policy.plan(utility:for:queued:)` says to do with a tier edit.
enum UtilityPlan: Equatable {
    /// Nothing to do, and nothing queued to drop.
    case unchanged
    /// Set it now: it lengthens the wait, or the target enforces nothing yet, or the only
    /// thing happening is that a queued change is being cancelled.
    case now
    /// Queue it behind the delay the target has today: it shortens the wait.
    case queue
}

#if os(iOS)
/// What the shields should look like right now.
struct Decision {
    var allowedApps: Set<ApplicationToken> = []
    var allowedWeb: Set<WebDomainToken> = []
    var shieldedApps: Set<ApplicationToken> = []
    var shieldedWeb: Set<WebDomainToken> = []
    var categories: Set<ActivityCategoryToken> = []
    /// Typed hosts to block through the web content filter rather than the shield. A `.host`
    /// target has no token, so it cannot be shielded; `ShieldReconciler` writes these into
    /// `store.webContent.blockedByFilter` instead. There is no allowed counterpart: the filter
    /// takes the whole blocked list or nothing, and a host that is open right now is simply
    /// absent from it.
    var filteredHosts: Set<String> = []
    var statuses: [UUID: TargetStatus] = [:]

    /// Counts a filter-blocked host. `denyAppRemoval` follows this, and Zach's call on
    /// 2026-09-08 was that a host counts: the flag's job is stopping Furlough itself from
    /// being deleted to escape, and deleting Furlough clears the filter exactly as it clears
    /// a shield.
    var isAnythingShielded: Bool {
        !shieldedApps.isEmpty || !shieldedWeb.isEmpty || !categories.isEmpty || !filteredHosts.isEmpty
    }

    /// What `blockedByFilter` should be set to, or nil when nothing is filtered. Kept here
    /// rather than in `ShieldReconciler` so it can be tested: that file imports ManagedSettings
    /// and is excluded from the test bundle, and nil-when-empty is the part worth pinning.
    var webFilterHosts: Set<String>? { filteredHosts.isEmpty ? nil : filteredHosts }
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
    /// `now` is Furlough's own time, never the device's: it defaults to `state.now` so that a
    /// caller who forgets cannot let a clock moved forward land a loosening early.
    @discardableResult
    static func applyDuePending(_ state: inout SharedState, now: Date? = nil) -> Bool {
        let now = now ?? state.now
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
        case .setUtility(let id, let level):
            if let index = config.targets.firstIndex(where: { $0.id == id }) {
                config.targets[index].utilityLevel = level
            }
        case .unlink(let id, let kind):
            // Only ever a linked half: the face is what the row *is*, so dropping it would leave
            // a target with no identity rather than a looser one. `AppModel.unlink` refuses to
            // queue that, and this refuses to perform it, because a change can sit in the queue
            // across an edit that changes which half is the face.
            if let index = config.targets.firstIndex(where: { $0.id == id }), config.targets[index].kind != kind {
                var remaining = config.targets[index].also ?? []
                remaining.removeAll { $0 == kind }
                config.targets[index].also = remaining.isEmpty ? nil : remaining
            }
        }
    }

    /// The config as it stands at `now`, with due pending changes folded in but nothing
    /// persisted. `now` is Furlough's own time; the widget passes future ones to draw a timeline.
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

    /// What setting `level` on `target` should do. `queued` says whether a tier change is
    /// already waiting for this target.
    ///
    /// A queued tier change is dropped whichever answer comes back, and that is the point: the
    /// rule editor seeds its picker from the queued tier rather than the saved one, so choosing
    /// the saved tier back is the obvious way to cancel a queued change. It used to be a silent
    /// no-op that left the loosening in place, which is the wrong way for a commitment device
    /// to fail.
    ///
    /// The comparison is against `target.utility`, not `target.utilityLevel`: a target nobody
    /// has tiered is already effectively `.unset`, so choosing that tier is not a change.
    static func plan(utility level: Utility, for target: Target, queued: Bool) -> UtilityPlan {
        guard target.utility != level || queued else { return .unchanged }
        // The tier is already what was asked for, so only the queued change is being dropped.
        if target.utility == level { return .now }
        // Nothing is enforced yet, so the first tier is free, exactly as the first rule is.
        if target.rule == nil { return .now }
        return classify(newUtility: level, against: target) == .tightening ? .now : .queue
    }

    /// A tier changes nothing about what is allowed, only how long the next loosening waits —
    /// so it is classified on the delay it buys, not with `Rule.isTighterOrEqual`. Moving
    /// toward hazard lengthens the wait and lands now; moving toward essential shortens it and
    /// queues, which is what stops "mark everything essential" from being a way out of the delay.
    static func classify(newUtility: Utility, against target: Target?) -> ChangeClass {
        let old = target?.utility ?? .unset
        return newUtility.delayMultiplier >= old.delayMultiplier ? .tightening : .loosening
    }

    // MARK: Status

    static func status(
        of target: Target,
        config: Config,
        runtime: RuntimeState,
        now: Date,
        calendar: Calendar = .current
    ) -> TargetStatus {
        if config.isAnchored(target) { return .anchored }
        guard let rule = target.rule else { return .unconfigured }
        guard rule.isEverAllowed else { return .blockedAllDay }
        let minute = minuteOfDay(now, calendar: calendar)
        let weekday = weekday(now, calendar: calendar)
        if runtime.isExhausted(target.id, dayKey: dayKey(now, calendar: calendar)) {
            return .exhausted(nextOpen: nextOpen(in: rule, afterWeekday: weekday))
        }
        if let current = rule.window(containing: minute, on: weekday) {
            return .open(until: end(of: current, in: rule, on: weekday))
        }
        if let next = rule.windows(on: weekday).first(where: { $0.startMinute > minute }) {
            return .closed(nextOpen: NextOpen(minuteOfDay: next.startMinute, daysAhead: 0))
        }
        return .closed(nextOpen: nextOpen(in: rule, afterWeekday: weekday) ?? NextOpen(minuteOfDay: 0, daysAhead: 1))
    }

    /// When a window really ends, counted from the start of `weekday`. An evening that ends at
    /// midnight where the next day opens at midnight is half of a night: it runs on past 1440,
    /// to the end of the morning half. Nothing shuts at the join, so nothing says it does.
    static func end(of window: TimeWindow, in rule: Rule, on weekday: Int) -> Int {
        guard window.endMinute == Furlough.minutesPerDay,
              let morning = rule.continuation(after: weekday) else { return window.endMinute }
        return Furlough.minutesPerDay + morning.endMinute
    }

    /// Whether a trip through Apple's picker should schedule `target`'s removal, given the kinds
    /// that came back in `selected`.
    ///
    /// The picker's answer is the whole truth about **tokens** and nothing else, and two kinds of
    /// door have to be held back from it.
    ///
    /// A target with no tokenised door at all — a website typed by name — is never in any
    /// selection, because it has no token and Apple's picker has never heard of it. Without this,
    /// one trip through the picker would queue the removal of every site added by name.
    ///
    /// And a linked target survives while *any* of its tokenised doors is still picked. Unpicking
    /// one half of a pair is not how a pair is broken: breaking one is a loosening that waits out
    /// the delay, and a removal scheduled from here would be a second, quieter way to do the same
    /// thing — one that takes the whole row rather than the half that was unpicked.
    ///
    /// Pure and here rather than inside `AppModel.applyPicker` so that it can be tested: the
    /// picker itself is iOS-only and unreachable from a test bundle, and this is the rule that
    /// decides whether a removal is queued.
    static func picker(removes target: Target, selected: Set<TargetKind>) -> Bool {
        let tokenised = target.kinds.filter { !$0.isHost }
        guard !tokenised.isEmpty else { return false }
        return !tokenised.contains { selected.contains($0) }
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
    static func decide(config: Config, runtime: RuntimeState, now: Date, calendar: Calendar = .current) -> Decision {
        var decision = Decision()
        for target in config.targets {
            let status = status(of: target, config: config, runtime: runtime, now: now, calendar: calendar)
            decision.statuses[target.id] = status
            // Every door, not just the face. One status covers the app and the website it is
            // also at, so linking costs nothing here: the status was only ever per target.
            for kind in target.kinds {
                switch kind {
                case .application(let token):
                    if status.isAllowed { decision.allowedApps.insert(token) } else { decision.shieldedApps.insert(token) }
                case .webDomain(let token):
                    if status.isAllowed { decision.allowedWeb.insert(token) } else { decision.shieldedWeb.insert(token) }
                case .category(let token):
                    decision.categories.insert(token)
                case .host(let host):
                    // No allowed set to put an open one in: the filter is the blocked list itself.
                    if !status.isAllowed { decision.filteredHosts.insert(host) }
                }
            }
        }
        // The anchor can hold things that are not targets at all; while anchored they are all shielded.
        if config.anchor.isAnchored {
            for kind in config.anchor.kinds {
                switch kind {
                case .application(let token):
                    decision.allowedApps.remove(token)
                    decision.shieldedApps.insert(token)
                case .webDomain(let token):
                    decision.allowedWeb.remove(token)
                    decision.shieldedWeb.insert(token)
                case .category(let token):
                    decision.categories.insert(token)
                case .host(let host):
                    decision.filteredHosts.insert(host)
                }
            }
        }
        return decision
    }
    #else
    static func decide(config: Config, runtime: RuntimeState, now: Date, calendar: Calendar = .current) -> Decision {
        var decision = Decision()
        for target in config.targets {
            let status = status(of: target, config: config, runtime: runtime, now: now, calendar: calendar)
            decision.statuses[target.id] = status
            guard !status.isAllowed else { continue }
            // Every door, as on the phone: an imported setup can link a host onto a Mac app.
            for kind in target.kinds {
                switch kind {
                case .macApp(let bundleID): decision.blockedApps.insert(bundleID)
                case .host(let host): decision.blockedHosts.insert(host)
                }
            }
        }
        if config.anchor.isAnchored {
            for kind in config.anchor.kinds {
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
        var isAnchored = false
        /// Everything the anchor holds, targets or not, while anchored.
        var anchoredCount = 0

        var isEmpty: Bool {
            openNames.isEmpty && allDayNames.isEmpty && nextOpenAt == nil && blockedCount == 0
                && unconfiguredCount == 0 && anchoredCount == 0
        }

        /// The same summary with its dates moved onto the device's clock. A widget entry and a
        /// Live Activity's timer are drawn by the system against its own clock, so they have to
        /// be handed device time even while Furlough is running on its own.
        func shifted(by drift: TimeInterval) -> Summary {
            guard drift != 0 else { return self }
            var copy = self
            copy.openUntil = openUntil?.addingTimeInterval(drift)
            copy.openStart = openStart?.addingTimeInterval(drift)
            copy.nextOpenAt = nextOpenAt?.addingTimeInterval(drift)
            return copy
        }
    }

    static func summary(state: SharedState, now: Date, calendar: Calendar = .current) -> Summary {
        let config = effectiveConfig(state, now: now)
        var summary = Summary()
        summary.pendingCount = state.pending.filter { $0.effectiveAt > now }.count
        summary.isAnchored = config.anchor.isAnchored
        summary.anchoredCount = config.anchor.isAnchored ? config.anchor.count : 0
        let minute = minuteOfDay(now, calendar: calendar)
        let weekday = weekday(now, calendar: calendar)
        var soonestOpen: (until: Int, start: Int, warned: Bool)?
        var soonest: (date: Date, names: [String], budget: Int?, exhausted: Bool)?

        for target in config.targets {
            switch status(of: target, config: config, runtime: state.runtime, now: now, calendar: calendar) {
            case .anchored:
                summary.blockedCount += 1
            case .unconfigured:
                summary.unconfiguredCount += 1
            case .blockedAllDay:
                summary.blockedCount += 1
            case .open(let until):
                let warned = state.runtime.wasWarned(target.id, dayKey: dayKey(now, calendar: calendar))
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
                if let next { consider(date(at: next, from: now, calendar: calendar), target, exhausted: true) }
            case .closed(let next):
                summary.blockedCount += 1
                consider(date(at: next, from: now, calendar: calendar), target, exhausted: false)
            }
        }
        func consider(_ date: Date, _ target: Target, exhausted: Bool) {
            let name = target.displayName
            // nil where there is no real limit, so the widget says what is blocked instead of
            // offering "24 hours budget" as if it were one.
            let budget = target.rule?.limitMinutes
            if let current = soonest {
                if date < current.date { soonest = (date, [name], budget, exhausted) }
                else if date == current.date { soonest?.names.append(name) }
            } else {
                soonest = (date, [name], budget, exhausted)
            }
        }
        if let soonestOpen {
            summary.openUntil = date(atMinute: soonestOpen.until, of: now, calendar: calendar)
            summary.openStart = date(atMinute: soonestOpen.start, of: now, calendar: calendar)
            summary.openWarned = soonestOpen.warned
        }
        summary.nextOpenAt = soonest?.date
        summary.nextOpenNames = soonest?.names ?? []
        summary.nextOpenBudgetMinutes = soonest?.budget
        summary.nextOpenIsExhausted = soonest?.exhausted ?? false
        return summary
    }
}
