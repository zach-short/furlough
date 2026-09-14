import Foundation
#if os(iOS) && !NO_SCREEN_TIME
import ManagedSettings
#endif

enum TargetStatus: Equatable {
    /// Locked by the Anchor profile. Only its paired tag lifts this.
    case anchored
    case unconfigured
    case blockedAllDay
    /// Inside a window with budget remaining. `until` is the end minute — midnight for an
    /// all-day rule, past 1440 for a night whose two stored windows are one logical window
    /// to the user.
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
    /// Typed hosts blocked via the web content filter rather than the shield (no token to
    /// shield). No allowed counterpart — an open host is just absent from the list.
    var filteredHosts: Set<String> = []
    /// Anchor is down over the whole phone: everything shielded except `allowedApps`/`allowedWeb`/
    /// `allowedHosts`, which already exclude anything a rule shields right now.
    var shieldsEverything = false
    /// Typed hosts let through while `shieldsEverything`; empty otherwise (a blocked list has
    /// no allowed hosts, only absent ones).
    var allowedHosts: Set<String> = []
    var statuses: [UUID: TargetStatus] = [:]

    /// Includes filter-blocked hosts: deleting Furlough clears the filter just like a shield,
    /// so `denyAppRemoval` needs to count them too.
    var isAnythingShielded: Bool {
        shieldsEverything || !shieldedApps.isEmpty || !shieldedWeb.isEmpty || !categories.isEmpty || !filteredHosts.isEmpty
    }

    /// What `shield.applicationCategories` should be: nil, blocked categories excepting open
    /// apps, or (anchor-everything) all categories excepting the allowlist.
    var appCategoryPolicy: ShieldSettings.ActivityCategoryPolicy<Application>? {
        if shieldsEverything { return .all(except: allowedApps) }
        return categories.isEmpty ? nil : .specific(categories, except: allowedApps)
    }

    /// The same for `shield.webDomainCategories`.
    var webCategoryPolicy: ShieldSettings.ActivityCategoryPolicy<WebDomain>? {
        if shieldsEverything { return .all(except: allowedWeb) }
        return categories.isEmpty ? nil : .specific(categories, except: allowedWeb)
    }

    /// What `blockedByFilter` should be: nil, the closed typed hosts (`.specific`), or — with
    /// the anchor over everything — `.all(except:)` the allowlist. The filter reaches every
    /// browser (the shield may only reach Safari) and is the only way to let a typed host through.
    var webFilter: WebContentSettings.FilterPolicy? {
        if shieldsEverything {
            var allowed = Set(allowedHosts.map { WebDomain(domain: $0) })
            allowed.formUnion(allowedWeb.map { WebDomain(token: $0) })
            return .all(except: allowed)
        }
        return filteredHosts.isEmpty ? nil : .specific(Set(filteredHosts.map { WebDomain(domain: $0) }))
    }
}
#else
/// What the Mac must enforce right now: apps by bundle identifier, websites by host.
struct Decision {
    var blockedApps: Set<String> = []
    var blockedHosts: Set<String> = []
    /// Anchor is down over the whole Mac: everything blocked except `allowedApps`/`allowedHosts`.
    /// `Enforcer` reads this via `blocks(app:)`/`blocks(host:)`, keeping apps the Mac can't do
    /// without (`AppCatalog.excluded`) and anything without a Dock presence out of it.
    var shieldsEverything = false
    /// The allowlist, by bundle identifier and host, while `shieldsEverything`.
    var allowedApps: Set<String> = []
    var allowedHosts: Set<String> = []
    var statuses: [UUID: TargetStatus] = [:]

    var isAnythingShielded: Bool { shieldsEverything || !blockedApps.isEmpty || !blockedHosts.isEmpty }

    /// Whether to block `bundleID`: on the blocked list, or (anchor-everything) off the
    /// allowlist. The blocked list is checked first, since a rule still blocks an allowlisted
    /// app outside its window.
    func blocks(app bundleID: String) -> Bool {
        if blockedApps.contains(bundleID) { return true }
        return shieldsEverything && !allowedApps.contains(bundleID)
    }

    /// The same for a site: a blocked host (or subdomain), or, under anchor-everything,
    /// anything not under an allowlisted host.
    func blocks(host: String) -> Bool {
        if blockedHosts.contains(where: { Hosts.matches(host, rule: $0) }) { return true }
        return shieldsEverything && !allowedHosts.contains { Hosts.matches(host, rule: $0) }
    }
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

    /// Applies every pending change whose time has come; true if anything changed. `now`
    /// defaults to `state.now` so a caller can't accidentally land a loosening early using a
    /// device clock. Trial expiry and undo-window closing are folded in here too, as changes
    /// due like any other.
    @discardableResult
    static func applyDuePending(
        _ state: inout SharedState, now: Date? = nil, calendar: Calendar = .current
    ) -> Bool {
        let now = now ?? state.now
        var changed = Forgiveness.expire(&state.config, now: now)
        let due = state.pending
            .filter { $0.effectiveAt <= now }
            .sorted { $0.effectiveAt < $1.effectiveAt }
        guard !due.isEmpty else { return changed }
        for change in due {
            apply(change, to: &state.config)
        }
        state.pending.removeAll { $0.effectiveAt <= now }
        // The one place a loosening lands, so the one place the record counts it (a throwaway
        // call via `effectiveConfig` counts into its discarded copy too).
        Record.noteLanded(due.count, in: &state, now: now, calendar: calendar)
        changed = true
        return changed
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
            // Refuses to drop the face (only a linked half), since a queued change can outlive
            // an edit that changes which half is the face.
            if let index = config.targets.firstIndex(where: { $0.id == id }), config.targets[index].kind != kind {
                var remaining = config.targets[index].also ?? []
                remaining.removeAll { $0 == kind }
                config.targets[index].also = remaining.isEmpty ? nil : remaining
            }
        case .setAnchorSchedules(let schedules):
            config.anchor.schedules = schedules
        }
    }

    /// The config as it stands at `now`, with due pending changes folded in but nothing
    /// persisted; the widget passes future times to draw a timeline.
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

    /// What setting `level` on `target` should do. Always drops a queued tier change — the
    /// editor seeds its picker from the queued tier, so re-choosing the saved one is how a
    /// person cancels it, and this must not silently leave the loosening in place. Compares
    /// against `target.utility` (not `utilityLevel`), since an untiered target is already
    /// effectively `.unset`.
    static func plan(utility level: Utility, for target: Target, queued: Bool) -> UtilityPlan {
        guard target.utility != level || queued else { return .unchanged }
        // The tier is already what was asked for, so only the queued change is being dropped.
        if target.utility == level { return .now }
        // Nothing is enforced yet, so the first tier is free, exactly as the first rule is.
        if target.rule == nil { return .now }
        return classify(newUtility: level, against: target) == .tightening ? .now : .queue
    }

    /// Classified by the delay the tier buys, not `Rule.isTighterOrEqual`, since a tier changes
    /// nothing about what's allowed. Moving toward hazard lands now; toward essential queues —
    /// otherwise "mark everything essential" would be a way around the delay.
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
        if config.isAnchored(target, at: now) { return .anchored }
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

    /// When a window really ends, from the start of `weekday`: past 1440 for a night's evening
    /// half, since nothing actually shuts at the midnight join.
    static func end(of window: TimeWindow, in rule: Rule, on weekday: Int) -> Int {
        guard window.endMinute == Furlough.minutesPerDay,
              let morning = rule.continuation(after: weekday) else { return window.endMinute }
        return Furlough.minutesPerDay + morning.endMinute
    }

    /// Whether a picker trip should schedule `target`'s removal, given `selected`. A target with
    /// no tokenised door (a typed-by-name site) is excluded — it never appears in any selection,
    /// so it must not be treated as removed. A linked target survives while any of its tokenised
    /// doors is still picked — unpicking one half is `unlink`'s job, not a removal.
    static func picker(removes target: Target, selected: Set<TargetKind>) -> Bool {
        let tokenised = target.kinds.filter { !$0.isHost }
        guard !tokenised.isEmpty else { return false }
        return !tokenised.contains { selected.contains($0) }
    }

    /// When the window that opens at `next` closes again. Nil for an all-day rule, where
    /// midnight only resets the budget and nothing actually closes.
    static func close(of next: NextOpen, in target: Target, from now: Date, calendar: Calendar = .current) -> Date? {
        // `windows(on:)` returns the whole day for an all-day rule, which is wrong here —
        // nothing actually closes at that midnight.
        guard let rule = target.rule, !rule.isAllDay else { return nil }
        let weekday = weekday(now, calendar: calendar)
        let day = (weekday - 1 + next.daysAhead) % 7 + 1
        guard let window = rule.windows(on: day).first(where: { $0.startMinute == next.minuteOfDay })
        else { return nil }
        let openDay = calendar.date(byAdding: .day, value: next.daysAhead, to: now) ?? now
        return date(atMinute: end(of: window, in: rule, on: day), of: openDay, calendar: calendar)
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
            // Every door, not just the face — status is per target, so linking costs nothing here.
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
        if config.anchor.isHolding(at: now) {
            switch config.anchor.scope {
            case .chosen:
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
            case .everythingExcept:
                // Everything goes behind the shield; the allowed sets are replaced outright by
                // the allowlist minus whatever a rule still shields (so an allowlisted app
                // outside its window stays shielded). A category can't be excepted from `.all`,
                // so one on the list here is simply ignored.
                decision.shieldsEverything = true
                var apps: Set<ApplicationToken> = []
                var web: Set<WebDomainToken> = []
                var hosts: Set<String> = []
                for kind in config.anchor.kinds {
                    switch kind {
                    case .application(let token): apps.insert(token)
                    case .webDomain(let token): web.insert(token)
                    case .host(let host): hosts.insert(host)
                    case .category: break
                    }
                }
                decision.allowedApps = apps.subtracting(decision.shieldedApps)
                decision.allowedWeb = web.subtracting(decision.shieldedWeb)
                decision.allowedHosts = hosts.subtracting(decision.filteredHosts)
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
        if config.anchor.isHolding(at: now) {
            switch config.anchor.scope {
            case .chosen:
                for kind in config.anchor.kinds {
                    switch kind {
                    case .macApp(let bundleID): decision.blockedApps.insert(bundleID)
                    case .host(let host): decision.blockedHosts.insert(host)
                    }
                }
            case .everythingExcept:
                // The list stays open; everything else is blocked via `blocks(app:)`/`blocks(host:)`,
                // minus what a rule already blocks (as on the phone).
                decision.shieldsEverything = true
                for kind in config.anchor.kinds {
                    switch kind {
                    case .macApp(let bundleID) where !decision.blockedApps.contains(bundleID):
                        decision.allowedApps.insert(bundleID)
                    case .host(let host) where !decision.blockedHosts.contains(host):
                        decision.allowedHosts.insert(host)
                    default:
                        break
                    }
                }
            }
        }
        return decision
    }
    #endif

    /// The next instant at which some status can change: a window edge later today, else
    /// midnight — or a timed anchor's lift, when that comes first.
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
        let edge: Date
        if let soonest = candidates.min() {
            edge = date(atMinute: soonest, of: now, calendar: calendar)
        } else {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            edge = calendar.startOfDay(for: tomorrow)
        }
        if config.anchor.isHolding(at: now), let until = config.anchor.until, until < edge { return until }
        return edge
    }

    // MARK: Summary for widgets and Live Activities

    struct Summary: Equatable {
        var openNames: [String] = []
        var openUntil: Date?
        /// Start of the open window that closes soonest, so the widget's sand can be at the right level.
        var openStart: Date?
        /// That target has had its 5-minute budget warning.
        var openWarned = false
        /// Today's budget for that target, in minutes, or nil where there is no real limit.
        var openBudgetMinutes: Int?
        /// When its warning fired, for a countdown to the budget running out — the only budget
        /// deadline iOS ever exposes.
        var openWarnedAt: Date?
        /// Open with no windows of their own: usable all day, up to the budget. Kept apart from
        /// `openNames` so they get no closing countdown and no Live Activity.
        var allDayNames: [String] = []
        /// One of those has had its 5-minute budget warning.
        var allDayWarned = false
        var nextOpenAt: Date?
        /// When that window closes again, to schedule a Live Activity ahead of it; nil for an
        /// all-day rule (nothing to close).
        var nextOpenUntil: Date?
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
        /// What the anchor holds (or, if `anchorsEverything`, how many it lets through).
        var anchoredCount = 0
        /// Anchor is down over the whole phone (everything but `anchoredCount`); shown instead of a count.
        var anchorsEverything = false
        /// When a timed anchor lifts by itself; nil for the tag alone, and while it is up.
        var anchorUntil: Date?
        /// The anchor is up and could be dropped: the widget's button shows only then.
        var canDropAnchor = false

        var isEmpty: Bool {
            openNames.isEmpty && allDayNames.isEmpty && nextOpenAt == nil && blockedCount == 0
                && unconfiguredCount == 0 && anchoredCount == 0 && !anchorsEverything
        }

        /// The same summary with dates moved onto the device's clock, since the system draws
        /// widget/Live Activity timers against its own clock.
        func shifted(by drift: TimeInterval) -> Summary {
            guard drift != 0 else { return self }
            var copy = self
            copy.openUntil = openUntil?.addingTimeInterval(drift)
            copy.openStart = openStart?.addingTimeInterval(drift)
            copy.openWarnedAt = openWarnedAt?.addingTimeInterval(drift)
            copy.nextOpenAt = nextOpenAt?.addingTimeInterval(drift)
            copy.anchorUntil = anchorUntil?.addingTimeInterval(drift)
            copy.nextOpenUntil = nextOpenUntil?.addingTimeInterval(drift)
            return copy
        }
    }

    static func summary(state: SharedState, now: Date, calendar: Calendar = .current) -> Summary {
        let config = effectiveConfig(state, now: now)
        var summary = Summary()
        summary.pendingCount = state.pending.filter { $0.effectiveAt > now }.count
        summary.isAnchored = config.anchor.isHolding(at: now)
        summary.anchoredCount = summary.isAnchored ? config.anchor.count : 0
        summary.anchorsEverything = summary.isAnchored && config.anchor.anchorsEverything
        summary.anchorUntil = summary.isAnchored ? config.anchor.until : nil
        summary.canDropAnchor = !summary.isAnchored && config.anchor.hasSomethingToHold && config.anchor.isPaired
        let minute = minuteOfDay(now, calendar: calendar)
        let weekday = weekday(now, calendar: calendar)
        var soonestOpen: (until: Int, start: Int, warned: Bool, budget: Int?, warnedAt: Date?)?
        var soonest: (date: Date, until: Date?, names: [String], budget: Int?, exhausted: Bool)?
        // Unnamed targets go to the end of every list, so a widget with limited space shows a
        // recognisable name.
        var unnamedAllDay: [String] = []
        var unnamedOpen: [String] = []
        var unnamedNext: [String] = []

        for target in config.targets {
            switch status(of: target, config: config, runtime: state.runtime, now: now, calendar: calendar) {
            case .anchored:
                summary.blockedCount += 1
            case .unconfigured:
                summary.unconfiguredCount += 1
            case .blockedAllDay:
                summary.blockedCount += 1
            case .open(let until):
                let day = dayKey(now, calendar: calendar)
                let warned = state.runtime.wasWarned(target.id, dayKey: day)
                if target.rule?.isAllDay ?? false {
                    if target.isNamed { summary.allDayNames.append(target.displayName) }
                    else { unnamedAllDay.append(target.displayName) }
                    summary.allDayWarned = summary.allDayWarned || warned
                } else {
                    if target.isNamed { summary.openNames.append(target.displayName) }
                    else { unnamedOpen.append(target.displayName) }
                    if soonestOpen == nil || until < soonestOpen!.until {
                        let start = target.rule?.window(containing: minute, on: weekday)?.startMinute ?? 0
                        soonestOpen = (
                            until,
                            start,
                            warned,
                            target.rule?.limit(on: weekday),
                            state.runtime.warnedMoment(target.id, dayKey: day)
                        )
                    }
                }
            case .exhausted(let next):
                summary.exhaustedCount += 1
                summary.blockedCount += 1
                if let next { consider(next, target, exhausted: true) }
            case .closed(let next):
                summary.blockedCount += 1
                consider(next, target, exhausted: false)
            }
        }
        func consider(_ next: NextOpen, _ target: Target, exhausted: Bool) {
            let date = date(at: next, from: now, calendar: calendar)
            let name = target.displayName
            // Read on the day it next opens (not today), so a Sunday-closed/Monday-open rule
            // offers Monday's budget, not today's nothing.
            let budget = target.rule?.limit(on: Policy.weekday(date, calendar: calendar))
            let until = close(of: next, in: target, from: now, calendar: calendar)
            if let current = soonest {
                if date < current.date {
                    soonest = (date, until, [], budget, exhausted)
                    unnamedNext = []
                } else if date != current.date {
                    return
                } else if let until, current.until.map({ until < $0 }) ?? true {
                    // Several open together and close apart: the soonest close, as `openUntil` is.
                    soonest?.until = until
                }
            } else {
                soonest = (date, until, [], budget, exhausted)
            }
            if target.isNamed { soonest?.names.append(name) } else { unnamedNext.append(name) }
        }
        if let soonestOpen {
            summary.openUntil = date(atMinute: soonestOpen.until, of: now, calendar: calendar)
            summary.openStart = date(atMinute: soonestOpen.start, of: now, calendar: calendar)
            summary.openWarned = soonestOpen.warned
            summary.openBudgetMinutes = soonestOpen.budget
            summary.openWarnedAt = soonestOpen.warnedAt
        }
        summary.allDayNames += unnamedAllDay
        summary.openNames += unnamedOpen
        summary.nextOpenAt = soonest?.date
        summary.nextOpenUntil = soonest?.until
        summary.nextOpenNames = (soonest?.names ?? []) + unnamedNext
        summary.nextOpenBudgetMinutes = soonest?.budget
        summary.nextOpenIsExhausted = soonest?.exhausted ?? false
        return summary
    }
}
