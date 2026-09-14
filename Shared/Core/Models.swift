import Foundation
#if os(iOS) && !NO_SCREEN_TIME
import ManagedSettings
#endif

/// Days of the week as a bit set. Bit 0 is Sunday, matching Calendar's weekday numbers (1…7).
struct Weekdays: OptionSet, Hashable {
    let rawValue: UInt8

    init(rawValue: UInt8) { self.rawValue = rawValue & 0x7F }

    /// `weekday` is Calendar's 1…7. Anything else is no day at all.
    init(weekday: Int) {
        self.init(rawValue: (1...7).contains(weekday) ? 1 << UInt8(weekday - 1) : 0)
    }

    static let sunday = Weekdays(weekday: 1)
    static let monday = Weekdays(weekday: 2)
    static let tuesday = Weekdays(weekday: 3)
    static let wednesday = Weekdays(weekday: 4)
    static let thursday = Weekdays(weekday: 5)
    static let friday = Weekdays(weekday: 6)
    static let saturday = Weekdays(weekday: 7)
    static let all = Weekdays(rawValue: 0x7F)
    static let weekdays: Weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: Weekdays = [.saturday, .sunday]

    var count: Int { rawValue.nonzeroBitCount }
    func contains(weekday: Int) -> Bool { contains(Weekdays(weekday: weekday)) }
    mutating func toggle(weekday: Int) { formSymmetricDifference(Weekdays(weekday: weekday)) }

    /// Rotates days forward by `days` in the week; used to move a night's evening to its morning.
    func shifted(by days: Int) -> Weekdays {
        let step = ((days % 7) + 7) % 7
        let bits = Int(rawValue)
        return Weekdays(rawValue: UInt8((bits << step | bits >> (7 - step)) & 0x7F))
    }

    /// Calendar weekday numbers in the order the user's calendar lays a week out.
    static func ordered(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// Where the earliest of these days falls in the calendar's week, 0…6; 7 when empty.
    func firstPosition(calendar: Calendar = .current) -> Int {
        Weekdays.ordered(calendar: calendar).firstIndex { contains(weekday: $0) } ?? 7
    }

    /// Sort key for display order: earliest day first, then broader group first, then a stable tiebreak.
    func groupOrder(calendar: Calendar = .current) -> (Int, Int, UInt8) {
        (firstPosition(calendar: calendar), -count, rawValue)
    }
}

/// Stored as the bare integer, not `{"rawValue": n}`.
extension Weekdays: Codable {
    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UInt8.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A span of minutes inside one calendar day, on the days of the week it applies. `endMinute`
/// is exclusive and may be 1440; a stored span never crosses midnight (see `split`/`folded`).
struct TimeWindow: Codable, Hashable, Identifiable, Comparable {
    var startMinute: Int
    var endMinute: Int
    var days: Weekdays = .all

    var id: String { "\(startMinute)-\(endMinute)-\(days.rawValue)" }
    var durationMinutes: Int { endMinute - startMinute }

    var isValid: Bool {
        startMinute >= 0
            && endMinute <= Furlough.minutesPerDay
            && durationMinutes >= Furlough.minimumWindowMinutes
    }

    /// True when end falls before start (an evening running past midnight). Never stored —
    /// only ever a draft the editors split on input.
    var isNight: Bool { endMinute < startMinute }

    /// How long the window is, a night's two halves counted together.
    var spanMinutes: Int {
        isNight ? Furlough.minutesPerDay - startMinute + endMinute : durationMinutes
    }

    /// True when every window this splits into is valid; a night is judged by its two halves.
    var isValidDraft: Bool {
        let parts = split
        return !parts.isEmpty && parts.allSatisfy(\.isValid)
    }

    /// Splits a night into its evening and next-day morning halves; a non-night returns itself.
    var split: [TimeWindow] {
        guard isNight else { return [self] }
        var parts = [TimeWindow(startMinute: startMinute, endMinute: Furlough.minutesPerDay, days: days)]
        if endMinute > 0 {
            parts.append(TimeWindow(startMinute: 0, endMinute: endMinute, days: days.shifted(by: 1)))
        }
        return parts
    }

    /// A night's stored halves: evening ends at midnight, morning starts at it.
    private var isEveningHalf: Bool { startMinute > 0 && endMinute == Furlough.minutesPerDay }
    private var isMorningHalf: Bool { startMinute == 0 && endMinute < Furlough.minutesPerDay }

    /// `split` in reverse: rejoins an evening-at-midnight with the next day's morning-from-midnight.
    static func folded(_ windows: [TimeWindow]) -> [TimeWindow] {
        let sorted = windows.sorted()
        var mornings = sorted.filter(\.isMorningHalf)
        var result: [TimeWindow] = []
        for window in sorted where !window.isMorningHalf {
            guard window.isEveningHalf,
                  let index = mornings.firstIndex(where: { $0.days == window.days.shifted(by: 1) })
            else {
                result.append(window)
                continue
            }
            let morning = mornings.remove(at: index)
            result.append(TimeWindow(startMinute: window.startMinute, endMinute: morning.endMinute, days: window.days))
        }
        return result + mornings
    }

    /// The same span with `days` dropped, since DeviceActivity is told about each distinct span once.
    var span: TimeWindow { TimeWindow(startMinute: startMinute, endMinute: endMinute) }

    func applies(on weekday: Int) -> Bool { days.contains(weekday: weekday) }

    func contains(minuteOfDay minute: Int) -> Bool {
        minute >= startMinute && minute < endMinute
    }

    /// Spans overlap in the day, whatever their days are.
    func overlaps(_ other: TimeWindow) -> Bool {
        startMinute < other.endMinute && other.startMinute < endMinute
    }

    /// Spans overlap on at least one shared day.
    func collides(with other: TimeWindow) -> Bool {
        overlaps(other) && !days.isDisjoint(with: other.days)
    }

    static func < (lhs: TimeWindow, rhs: TimeWindow) -> Bool {
        (lhs.startMinute, lhs.endMinute, lhs.days.rawValue) < (rhs.startMinute, rhs.endMinute, rhs.days.rawValue)
    }

    /// The order a list of windows reads best in: by group of days, then by time of day.
    static func grouped(_ windows: [TimeWindow], calendar: Calendar = .current) -> [TimeWindow] {
        windows.sorted { a, b in
            let (ga, gb) = (a.days.groupOrder(calendar: calendar), b.days.groupOrder(calendar: calendar))
            return ga != gb ? ga < gb : (a.startMinute, a.endMinute) < (b.startMinute, b.endMinute)
        }
    }

    /// Next free slot on `days`: after the latest existing end if room remains, else the first
    /// free stretch. Up to an hour, at least the minimum; nil when full.
    static func nextFree(after windows: [TimeWindow], on days: Weekdays) -> TimeWindow? {
        let related = windows.filter { !$0.days.isDisjoint(with: days) }
        var taken = [Bool](repeating: false, count: Furlough.minutesPerDay)
        for window in related {
            let lower = max(0, window.startMinute)
            let upper = min(Furlough.minutesPerDay, window.endMinute)
            guard lower < upper else { continue }
            for minute in lower..<upper { taken[minute] = true }
        }
        let latestEnd = related.map(\.endMinute).max() ?? 12 * 60
        for origin in [min(latestEnd, Furlough.minutesPerDay), 0] {
            var minute = origin
            while minute < Furlough.minutesPerDay {
                guard !taken[minute] else { minute += 1; continue }
                let start = minute
                var end = start
                while end < Furlough.minutesPerDay, !taken[end], end - start < 60 { end += 1 }
                if end - start >= Furlough.minimumWindowMinutes {
                    return TimeWindow(startMinute: start, endMinute: end, days: days)
                }
                minute = end
            }
        }
        return nil
    }

    /// Windows on the same days that overlap or touch, merged in order; different days untouched.
    static func joined(_ windows: [TimeWindow]) -> [TimeWindow] {
        var result: [TimeWindow] = []
        for window in windows.sorted() {
            if let index = result.lastIndex(where: { $0.days == window.days }),
               window.startMinute <= result[index].endMinute {
                result[index].endMinute = max(result[index].endMinute, window.endMinute)
            } else {
                result.append(window)
            }
        }
        return result
    }
}

extension TimeWindow {
    /// `days` arrived after the first stored rules, so its absence means every day.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        endMinute = try container.decode(Int.self, forKey: .endMinute)
        days = try container.decodeIfPresent(Weekdays.self, forKey: .days) ?? .all
    }
}

/// When a target may be used and its daily budget. No windows means open all day (budget-limited
/// only); once windows exist, a day none of them covers is blocked.
struct Rule: Codable, Hashable {
    var windows: [TimeWindow] = []
    var dailyBudgetMinutes: Int = Furlough.defaultBudgetMinutes
    /// Seven minute counts, Sunday first, when the week isn't one number; nil otherwise.
    /// Read via `budget(on:)`, not directly. Anything but exactly seven entries decodes as nil.
    var budgetByWeekday: [Int]?

    /// Midnight to midnight: what a rule without windows allows on every day.
    static let allDay = TimeWindow(startMinute: 0, endMinute: Furlough.minutesPerDay)

    /// Permits everything. The baseline for a target that has no rule yet, and what "remove" means.
    static let unrestricted = Rule(windows: [], dailyBudgetMinutes: Furlough.minutesPerDay)
    /// No budget, so never allowed: what a category gets.
    static let alwaysBlocked = Rule(windows: [], dailyBudgetMinutes: 0)

    /// No windows of its own, so open all day up to the budget.
    var isAllDay: Bool { windows.isEmpty }
    /// Allowed at some minute of some day.
    var isEverAllowed: Bool { (1...7).contains { isEverAllowed(on: $0) } }
    /// The daily limit, or nil when a full day of budget means no real limit (e.g. `.unrestricted`
    /// or an uncounted typed host). Prefer this over `dailyBudgetMinutes` for display.
    func limit(on weekday: Int) -> Int? {
        let minutes = budget(on: weekday)
        return minutes < Furlough.minutesPerDay ? minutes : nil
    }
    var sortedWindows: [TimeWindow] { windows.sorted() }
    /// Every window applies every day, so one list describes the whole week.
    var isSameEveryDay: Bool { windows.allSatisfy { $0.days == .all } }

    // MARK: The budget, day by day

    /// The minutes allowed on `weekday` (Calendar's 1…7); the one accessor every budget read goes through.
    func budget(on weekday: Int) -> Int {
        guard let byWeekday = budgetByWeekday, byWeekday.count == 7, (1...7).contains(weekday) else {
            return dailyBudgetMinutes
        }
        return byWeekday[weekday - 1]
    }

    /// One number describes the week. True for a rule that never grew a per-day budget, and for
    /// one whose seven entries happen to agree.
    var isSameBudgetEveryDay: Bool {
        guard let byWeekday = budgetByWeekday, byWeekday.count == 7 else { return true }
        return byWeekday.allSatisfy { $0 == byWeekday[0] }
    }

    /// The same rule with a redundant per-day budget collapsed to one number. Editors save through this.
    var normalized: Rule {
        guard !isSameBudgetEveryDay else {
            var copy = self
            copy.dailyBudgetMinutes = budget(on: 1)
            copy.budgetByWeekday = nil
            return copy
        }
        return self
    }

    /// The most common day's budget (ties go to the smaller), for collapsing sliders back to one.
    /// Use instead of `dailyBudgetMinutes`, which is a stale shadow once a per-day budget is set.
    var representativeBudget: Int {
        guard budgetByWeekday != nil else { return dailyBudgetMinutes }
        var counts: [Int: Int] = [:]
        for weekday in 1...7 { counts[budget(on: weekday), default: 0] += 1 }
        return counts.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? dailyBudgetMinutes
    }

    /// Actual spendable budget on `weekday`: zero if the day is never allowed, regardless of the stored number.
    func effectiveBudget(on weekday: Int) -> Int {
        isEverAllowed(on: weekday) ? budget(on: weekday) : 0
    }

    /// Allowed at some minute of `weekday`: budget to spend, and hours to spend it in.
    func isEverAllowed(on weekday: Int) -> Bool {
        guard budget(on: weekday) > 0 else { return false }
        return isAllDay || windows.contains { $0.applies(on: weekday) }
    }

    /// Equal regardless of window order or whether the budget is per-day or a single number.
    func isEquivalent(to other: Rule) -> Bool {
        (1...7).allSatisfy { budget(on: $0) == other.budget(on: $0) } && sortedWindows == other.sortedWindows
    }

    /// Windows applying on `weekday`: the whole day if the rule has none, none if the day has
    /// no budget. Callers that gate the shield also check `isEverAllowed(on:)` directly.
    func windows(on weekday: Int) -> [TimeWindow] {
        guard budget(on: weekday) > 0 else { return [] }
        return isAllDay ? [Self.allDay] : sortedWindows.filter { $0.applies(on: weekday) }
    }

    /// One flag per minute of `weekday`; true where use is permitted.
    func allowedMask(on weekday: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: Furlough.minutesPerDay)
        guard isEverAllowed(on: weekday) else { return mask }
        for window in windows(on: weekday) {
            let lower = max(0, window.startMinute)
            let upper = min(Furlough.minutesPerDay, window.endMinute)
            guard lower < upper else { continue }
            for minute in lower..<upper { mask[minute] = true }
        }
        return mask
    }

    /// The next day's morning window if this day's evening runs into it; nil otherwise.
    func continuation(after weekday: Int) -> TimeWindow? {
        guard !isAllDay else { return nil }
        return windows(on: weekday % 7 + 1).first { $0.startMinute == 0 && $0.endMinute < Furlough.minutesPerDay }
    }

    /// The previous day's evening window if it runs into this day's midnight-start; nil otherwise.
    func continues(into weekday: Int) -> TimeWindow? {
        guard !isAllDay,
              windows(on: weekday).contains(where: { $0.startMinute == 0 && $0.endMinute < Furlough.minutesPerDay })
        else { return nil }
        return windows(on: weekday == 1 ? 7 : weekday - 1)
            .first { $0.startMinute > 0 && $0.endMinute == Furlough.minutesPerDay }
    }

    func window(containing minute: Int, on weekday: Int) -> TimeWindow? {
        guard isEverAllowed(on: weekday) else { return nil }
        return windows(on: weekday).first { $0.contains(minuteOfDay: minute) }
    }

    /// True when this allows nothing `other` forbids, and no day's budget exceeds `other`'s —
    /// compared per day, not summed, so shifting time between days still counts as loosening.
    func isTighterOrEqual(to other: Rule) -> Bool {
        for weekday in 1...7 {
            let mine = allowedMask(on: weekday)
            let theirs = other.allowedMask(on: weekday)
            for minute in 0..<Furlough.minutesPerDay where mine[minute] && !theirs[minute] {
                return false
            }
            if effectiveBudget(on: weekday) > other.effectiveBudget(on: weekday) { return false }
        }
        return true
    }

    /// Problems that make the rule unusable, or nil.
    var validationError: String? {
        for window in windows where !window.isValid {
            return "Each window must be at least \(Furlough.minimumWindowMinutes) minutes long, and a night that runs past midnight needs that much on each side of it."
        }
        if windows.contains(where: { $0.days.isEmpty }) {
            return "Each window needs at least one day."
        }
        let sorted = sortedWindows
        for (index, a) in sorted.enumerated() {
            for b in sorted[(index + 1)...] where a.collides(with: b) {
                return "Windows on the same day must not overlap."
            }
        }
        return nil
    }
}

extension Rule {
    /// Absent or non-seven-length `budgetByWeekday` falls back to `dailyBudgetMinutes` for the whole week.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windows = try container.decodeIfPresent([TimeWindow].self, forKey: .windows) ?? []
        dailyBudgetMinutes = try container.decode(Int.self, forKey: .dailyBudgetMinutes)
        let byWeekday = try? container.decodeIfPresent([Int].self, forKey: .budgetByWeekday)
        budgetByWeekday = (byWeekday?.count == 7) ? byWeekday : nil
    }
}

/// What a target is. On iOS these are the opaque Screen Time tokens; on the Mac, where there
/// is no Screen Time API, an app is its bundle identifier and a website is its host.
enum TargetKind: Codable, Hashable {
    #if os(iOS)
    case application(ApplicationToken)
    case webDomain(WebDomainToken)
    case category(ActivityCategoryToken)
    /// A website typed by name (not minted by Apple's picker), blocked via `blockedByFilter`.
    /// Unlike `.webDomain` it has no token: never counted toward a budget, and iOS shows its
    /// own "Website Not Allowed" page instead of Furlough's shield.
    case host(String)
    #else
    /// A Mac app, by bundle identifier: "com.google.Chrome".
    case macApp(bundleID: String)
    /// A website, by host: "youtube.com". Subdomains match too.
    case host(String)
    #endif

    var isCategory: Bool {
        #if os(iOS)
        if case .category = self { return true }
        #endif
        return false
    }

    /// An app on whichever platform is asking; used where a sentence names what it holds rather than counts it.
    var isApplication: Bool {
        #if os(iOS)
        if case .application = self { return true }
        #else
        if case .macApp = self { return true }
        #endif
        return false
    }
}

/// The rule an edit replaced, so a change is takeable-back for `Furlough.undoWindowMinutes`.
/// Always the exact prior rule, never a looser one — this is what stops undo from being usable
/// as a way to loosen something that was already open.
struct RuleUndo: Codable, Hashable {
    /// The rule before the edit; nil means unconfigured.
    var rule: Rule?
    /// Furlough's own time when the edit landed, never the device's — `SharedState.now`.
    var savedAt: Date

    /// The moment it stops being takeable back.
    var expiresAt: Date {
        savedAt.addingTimeInterval(TimeInterval(Furlough.undoWindowMinutes) * 60)
    }

    /// Still open at `now`; check this rather than trusting the field's presence, since expiry
    /// isn't always pruned yet.
    func isOpen(at now: Date) -> Bool { now < expiresAt }
}

/// One app, website, or category that Furlough manages.
struct Target: Codable, Hashable, Identifiable {
    var id = UUID()
    /// The face of this target: the app half, where there is one (shown in the row; see `also`).
    var kind: TargetKind
    /// Other doors into the same thing, sharing one rule/budget/status — read via `kinds`, not
    /// directly. A typed-host half shares the windows but is never counted toward the budget.
    /// Optional so old stored state (predating this field) still decodes.
    var also: [TargetKind]?
    var nickname = ""
    /// nil means "not configured yet": nothing is enforced until the first rule is saved.
    var rule: Rule?
    var addedAt = Date.now
    /// The name learned from the shield the first time this was blocked — a Screen Time token
    /// is opaque otherwise, and only `Label(token)` can render one. `SharedStore` folds learned
    /// names in on every load, which always wins over a name set any other way.
    var systemName: String?
    /// The still-takeable-back prior rule, or nil. Only set when a rule lands immediately —
    /// a delayed loosening landing later leaves this alone, since undoing it would be an
    /// (already-instant) tightening.
    var undo: RuleUndo?
    /// The chosen tier, or nil if unset (old stored state predates this field). Read via `utility`.
    var utilityLevel: Utility?

    /// Every door into this thing, face first. Use instead of `kind` to ask what this target covers.
    var kinds: [TargetKind] { [kind] + (also ?? []) }

    /// True when this target covers more than one door.
    var isLinked: Bool { !(also ?? []).isEmpty }

    /// Whether `kind` is one of this target's doors.
    func covers(_ kind: TargetKind) -> Bool { kinds.contains(kind) }

    /// How much this one is worth, which sets both how long a loosening waits and how loudly
    /// blocking it is questioned. Unset means the middle: the base delay, a mild warning.
    var utility: Utility { utilityLevel ?? .unset }
    /// Whether the tier is Zach's answer or Furlough's default, so the editor knows when to
    /// offer a suggestion.
    var hasChosenUtility: Bool { utilityLevel != nil }

    var defaultName: String {
        if let systemName, !systemName.isEmpty { return systemName }
        return switch kind {
        #if os(iOS)
        case .application: "This app"
        case .webDomain: "This website"
        case .category: "This category"
        // A typed host is the one iOS kind that names itself: it was written down, not minted.
        case .host(let host): host
        #else
        case .macApp(let bundleID): bundleID
        case .host(let host): host
        #endif
        }
    }

    var displayName: String { nickname.isEmpty ? defaultName : nickname }

    /// Whether `displayName` is a real name rather than a stand-in like "This app". The widget
    /// lists named targets first so recognisable ones show when space is limited.
    var isNamed: Bool {
        if !nickname.isEmpty { return true }
        if let systemName, !systemName.isEmpty { return true }
        #if os(iOS)
        if case .host = kind { return true }
        return false
        #else
        return true
        #endif
    }
}

/// One tag paired with the anchor: its NFC identifier and a name (identifiers alone are
/// indistinguishable hex, so the name is what tells tags apart).
struct PairedTag: Codable, Equatable, Identifiable {
    /// Hardware identifier read over NFC. Unique per tag, so it is the identity.
    var id: Data
    var name: String

    /// The longest name a row can show without wrapping into the identifier under it.
    static let maxNameLength = 24
}

/// Apps/sites/categories locked behind a physical NFC tag — dropping is instant, lifting needs
/// a paired tag. While anchored, the list and tags cannot be changed. `scope` decides whether
/// `kinds` is what's held or what's exempted; read through `holds` rather than checking `kinds`.
struct AnchorProfile: Codable, Equatable {
    /// How far the anchor reaches when it drops.
    enum Scope: String, Codable, CaseIterable, Sendable {
        /// The listed kinds and nothing else: what the anchor has always done.
        case chosen
        /// Everything except the listed kinds (the allowlist), seeded from Essential-tiered
        /// targets (`Config.essentialKinds`) so Messages/authenticator stay reachable by default.
        case everythingExcept
    }

    var scope: Scope = .chosen
    /// Under `.chosen`, what the anchor holds. Under `.everythingExcept`, what it lets through.
    var kinds: [TargetKind] = []
    var isAnchored = false
    var anchoredAt: Date?
    /// When a timed anchor lifts by itself, or nil for the tag alone. Read via `isHolding(at:)`:
    /// a past `until` is released regardless of `isAnchored` until the next reconcile clears it.
    var until: Date?
    /// Times the anchor drops by itself; the monitor extension performs them, the app registers the wakes.
    var schedules: [AnchorSchedule] = []
    /// Increments on every drop/release on either device; the clock `AnchorSync.merge` orders by.
    var sequence: Int = 0
    /// Tags that release this anchor — any one of them works (not a sequence). Capped at
    /// `Furlough.maxAnchorTags`.
    var tags: [PairedTag] = []

    var isPaired: Bool { !tags.isEmpty }
    /// Room for another key; past the cap, pairing is refused rather than silently evicting the oldest.
    var canPairMore: Bool { tags.count < Furlough.maxAnchorTags }
    /// How long the list is: what is held under the chosen scope, what stays open under the
    /// other. Read `heldDescription` for a line a person sees.
    var count: Int { kinds.count }
    /// The anchor is down over the whole phone when it drops, not over a list.
    var anchorsEverything: Bool { scope == .everythingExcept }
    /// Whether there's something to lock: everything-except always is (even with an empty
    /// allowlist); chosen needs a non-empty list.
    var hasSomethingToHold: Bool { anchorsEverything || !kinds.isEmpty }
    /// Ready to anchor: something to lock and a tag to unlock it with.
    var canAnchor: Bool { hasSomethingToHold && isPaired && !isAnchored }
    /// Whether `kind` is on the list. Says nothing about whether it is held: read `holds`.
    func contains(_ kind: TargetKind) -> Bool { kinds.contains(kind) }
    /// Whether the anchor takes `kind` away: on the list under `.chosen`, off it under `.everythingExcept`.
    func holds(_ kind: TargetKind) -> Bool {
        switch scope {
        case .chosen: contains(kind)
        case .everythingExcept: !contains(kind)
        }
    }
    /// What the anchor holds, for the state line, the home card and the spoken answer:
    /// "3 items", or "Everything except 3" — "Everything" when the allowlist is empty.
    var heldDescription: String {
        switch scope {
        case .chosen: "\(kinds.count) \(kinds.count == 1 ? "item" : "items")"
        case .everythingExcept: kinds.isEmpty ? "Everything" : "Everything except \(kinds.count)"
        }
    }
    /// The confirmation line for a Control Center/Spotlight drop, which has no app UI to show:
    /// "1 application blocked", or "N items" when the list isn't all apps.
    var blockedDescription: String {
        let noun = kinds.allSatisfy(\.isApplication) ? "application" : "item"
        return "\(kinds.count) \(noun)\(kinds.count == 1 ? "" : "s") blocked"
    }
    /// The paired tag a scan matches, if any.
    func tag(matching scanned: Data) -> PairedTag? { tags.first { $0.id == scanned } }
    /// A default name for a newly paired tag, never colliding with an existing one.
    var nextTagName: String {
        var n = tags.count + 1
        while tags.contains(where: { $0.name == "Tag \(n)" }) { n += 1 }
        return "Tag \(n)"
    }
}

extension AnchorProfile {
    /// Reads legacy keys (`brick`/`isBricked`/`brickedAt`/`tagID`) when the current ones are
    /// missing, for backward compatibility with pre-rename stored state.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .chosen
        kinds = try container.decodeIfPresent([TargetKind].self, forKey: .kinds) ?? []
        isAnchored = try container.decodeIfPresent(Bool.self, forKey: .isAnchored)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .isBricked) ?? false
        anchoredAt = try container.decodeIfPresent(Date.self, forKey: .anchoredAt)
            ?? legacy.decodeIfPresent(Date.self, forKey: .brickedAt)
        // Absent means an anchor only the tag lifts, with nothing scheduled.
        until = try container.decodeIfPresent(Date.self, forKey: .until)
        schedules = try container.decodeIfPresent([AnchorSchedule].self, forKey: .schedules) ?? []
        sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
        if let stored = try container.decodeIfPresent([PairedTag].self, forKey: .tags) {
            // Trimmed on read too, in case the cap was once higher or the file was hand-edited.
            tags = Array(stored.prefix(Furlough.maxAnchorTags))
        } else if let single = try legacy.decodeIfPresent(Data.self, forKey: .tagID) {
            tags = [PairedTag(id: single, name: "Tag 1")]
        }
    }

    private enum LegacyKeys: String, CodingKey { case isBricked, brickedAt, tagID }
}

struct Config: Codable, Equatable {
    var targets: [Target] = []
    var loosenDelayHours: Int = Furlough.defaultLoosenDelayHours
    var anchor = AnchorProfile()
    /// Set once, the first time Screen Time access is granted, and never moved after — this is
    /// also the record that the install already had its trial, so toggling access off/on can't
    /// grant a fresh one.
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    /// Whether the trial is still running — a stored fact, not computed on read, so callers
    /// don't each need to know the time; `Policy.applyDuePending` is what advances it.
    var isInTrial = false
    /// What crosses to/from other devices, and whether an app's site is blocked alongside it.
    var link = LinkPreferences()
    var schemaVersion = 1

    init() {}

    /// Decodes the legacy `brick` key when `anchor` is absent, for older stored state.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        targets = try container.decode([Target].self, forKey: .targets)
        loosenDelayHours = try container.decode(Int.self, forKey: .loosenDelayHours)
        anchor = try container.decodeIfPresent(AnchorProfile.self, forKey: .anchor)
            ?? legacy.decodeIfPresent(AnchorProfile.self, forKey: .brick)
            ?? AnchorProfile()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        // Absent means no trial: an already-running install keeps its existing delays rather
        // than getting a fresh grace period.
        trialStartedAt = try container.decodeIfPresent(Date.self, forKey: .trialStartedAt)
        trialEndsAt = try container.decodeIfPresent(Date.self, forKey: .trialEndsAt)
        isInTrial = try container.decodeIfPresent(Bool.self, forKey: .isInTrial) ?? false
        link = try container.decodeIfPresent(LinkPreferences.self, forKey: .link) ?? LinkPreferences()
    }

    private enum LegacyKeys: String, CodingKey { case brick }

    var loosenDelay: TimeInterval { TimeInterval(loosenDelayHours) * 3600 }

    /// Whether `target` is locked by the anchor at `now`: any one of its doors held anchors the whole target.
    func isAnchored(_ target: Target, at now: Date) -> Bool { target.kinds.contains { anchor.blocks($0, at: now) } }

    func target(id: UUID) -> Target? { targets.first { $0.id == id } }
    /// The target `kind` is a door into (face or linked half) — checks `covers`, not just `kind`,
    /// to avoid the picker/import adding a duplicate target for an already-covered half.
    func target(kind: TargetKind) -> Target? { targets.first { $0.covers(kind) } }
}

enum PendingKind: Codable, Hashable {
    case setRule(targetID: UUID, rule: Rule)
    case removeTarget(targetID: UUID)
    case setDelay(hours: Int)
    /// Moving a target toward essential shortens its delay, so that is a loosening and queues.
    case setUtility(targetID: UUID, level: Utility)
    /// Removes one half of a linked target (e.g. the site, leaving the app). A loosening, so it
    /// queues like removal does; linking itself is a tightening and lands at once.
    case unlink(targetID: UUID, kind: TargetKind)
    /// Replaces the anchor's drop schedules. Removing/shortening one queues as a loosening
    /// (else it isn't a real commitment); adding one lands at once.
    case setAnchorSchedules([AnchorSchedule])
}

/// A loosening edit waiting out the delay.
struct PendingChange: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: PendingKind
    var createdAt = Date.now
    var effectiveAt: Date

    var targetID: UUID? {
        switch kind {
        case .setRule(let id, _), .removeTarget(let id), .setUtility(let id, _), .unlink(let id, _): id
        case .setDelay, .setAnchorSchedules: nil
        }
    }
}

/// Facts the monitor extension learns at runtime, keyed by target id and day.
struct RuntimeState: Codable, Equatable {
    var exhausted: [String: String] = [:]
    var warned: [String: String] = [:]
    /// When each warning fired. Screen Time only ever reports "~5 minutes left" or "spent", so
    /// this warning moment is the only real deadline the Live Activity can count down to.
    var warnedAt: [String: Date] = [:]
    /// Both clocks as they stood at the last save, so a wall clock moved forward is visible.
    var clock: ClockMark?
    var lastReconcile: Date?
    var lastRegistration: Date?
    var registrationError: String?
    /// The record, keyed by `Policy.dayKey`; written only through `Record`, never read by `Policy.decide`.
    var days: [String: DayRecord] = [:]
    /// How far the record has counted. Whole minutes only, so the part-minute between two
    /// reconciles is carried rather than lost or double counted.
    var recordedThrough: Date?

    init() {}

    func isExhausted(_ id: UUID, dayKey: String) -> Bool { exhausted[id.uuidString] == dayKey }
    func wasWarned(_ id: UUID, dayKey: String) -> Bool { warned[id.uuidString] == dayKey }
    /// When today's warning fired; nil if it hasn't, or if it fired before this field existed.
    func warnedMoment(_ id: UUID, dayKey: String) -> Date? {
        guard wasWarned(id, dayKey: dayKey) else { return nil }
        return warnedAt[id.uuidString]
    }

    /// Tolerant decoding: every missing key falls back to its empty value rather than throwing.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exhausted = try container.decodeIfPresent([String: String].self, forKey: .exhausted) ?? [:]
        warned = try container.decodeIfPresent([String: String].self, forKey: .warned) ?? [:]
        warnedAt = try container.decodeIfPresent([String: Date].self, forKey: .warnedAt) ?? [:]
        clock = try container.decodeIfPresent(ClockMark.self, forKey: .clock)
        lastReconcile = try container.decodeIfPresent(Date.self, forKey: .lastReconcile)
        lastRegistration = try container.decodeIfPresent(Date.self, forKey: .lastRegistration)
        registrationError = try container.decodeIfPresent(String.self, forKey: .registrationError)
        days = try container.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
        recordedThrough = try container.decodeIfPresent(Date.self, forKey: .recordedThrough)
    }
}

/// One day of the record, written from the events that already move the shields. See `Record`.
struct DayRecord: Codable, Equatable {
    /// By target id, as a string: the same shape `exhausted` and `warned` are stored in.
    var targets: [String: TargetDay] = [:]
    /// Loosenings queued on this day.
    var queued = 0
    /// Loosenings cancelled before landing — the count of times the delay did its job.
    var cancelled = 0
    /// Loosenings that waited out the delay and landed.
    var landed = 0
    /// Longest Anchor stretch ending this day; recorded on release, so one spanning midnight counts once.
    var longestAnchorMinutes = 0

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decodeIfPresent([String: TargetDay].self, forKey: .targets) ?? [:]
        queued = try container.decodeIfPresent(Int.self, forKey: .queued) ?? 0
        cancelled = try container.decodeIfPresent(Int.self, forKey: .cancelled) ?? 0
        landed = try container.decodeIfPresent(Int.self, forKey: .landed) ?? 0
        longestAnchorMinutes = try container.decodeIfPresent(Int.self, forKey: .longestAnchorMinutes) ?? 0
    }
}

/// What one target did on one day. Minutes are minutes of the *day* (shielded/open), not usage —
/// the phone can't see actual use without the Screen Time data-access entitlement.
struct TargetDay: Codable, Equatable {
    /// The daily budget ran out.
    var spent = false
    /// The 5-minute warning fired.
    var warned = false
    /// Minutes the rule left it open.
    var openMinutes = 0
    /// Minutes it was shut, whether by a rule, a spent budget or the Anchor.
    var shieldedMinutes = 0
    /// Of those, the minutes the Anchor was what held it.
    var anchoredMinutes = 0

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spent = try container.decodeIfPresent(Bool.self, forKey: .spent) ?? false
        warned = try container.decodeIfPresent(Bool.self, forKey: .warned) ?? false
        openMinutes = try container.decodeIfPresent(Int.self, forKey: .openMinutes) ?? 0
        shieldedMinutes = try container.decodeIfPresent(Int.self, forKey: .shieldedMinutes) ?? 0
        anchoredMinutes = try container.decodeIfPresent(Int.self, forKey: .anchoredMinutes) ?? 0
    }
}

struct SharedState: Codable, Equatable {
    var config = Config()
    var pending: [PendingChange] = []
    var runtime = RuntimeState()
}

// MARK: - Host lookups

/// Finding a target by its host. Unlike the bundle-identifier lookups below, this applies on
/// both platforms.
extension Config {
    /// The target whose host is `host` or a parent domain of it ("m.youtube.com" matches
    /// "youtube.com"); searches every door, including a linked app's.
    func target(host: String) -> Target? {
        let host = host.lowercased()
        return targets
            .compactMap { target -> (Target, Int)? in
                guard let matched = target.hosts.filter({ Hosts.matches(host, rule: $0) }).max(by: { $0.count < $1.count })
                else { return nil }
                return (target, matched.count)
            }
            .max { a, b in a.1 < b.1 }?
            .0
    }
}

extension TargetKind {
    var isHost: Bool {
        if case .host = self { return true }
        return false
    }

    /// The host this door is, or nil when it is not a typed site.
    var hostName: String? {
        if case .host(let h) = self { return h }
        return nil
    }
}

extension Target {
    /// The face's host, or "" if it isn't a typed site; use `hosts` to ask what sites this target covers.
    var host: String { kind.hostName ?? "" }

    /// Every typed site this target covers, the face first.
    var hosts: [String] { kinds.compactMap(\.hostName) }

    /// True when any door is a typed site, so the web content filter has work to do for it.
    var hasHost: Bool { kinds.contains(where: \.isHost) }

    /// Whether this target covers the app half of a thing.
    var coversApp: Bool {
        kinds.contains { kind in
            #if os(iOS)
            if case .application = kind { return true }
            #else
            if case .macApp = kind { return true }
            #endif
            return false
        }
    }

    /// Whether anything this target covers is counted against its budget. DeviceActivity counts
    /// only tokens, so a typed-host-only target has hours but no real budget.
    var isCounted: Bool { kinds.contains { !$0.isHost } }

    /// Typed sites that share this target's budget without being counted towards it: the honest
    /// gap in a linked pair, and empty when there is none.
    var uncountedHosts: [String] { isCounted ? hosts : [] }

    /// Whether this target covers the website half, whether picked (token) or typed (`.host`).
    var coversSite: Bool {
        kinds.contains { kind in
            #if os(iOS)
            if case .webDomain = kind { return true }
            #endif
            return kind.isHost
        }
    }
}

#if !os(iOS)
// MARK: - Mac lookups

/// Finding a Mac app by its bundle identifier. Lives here (not with the Mac model) since the
/// import also needs it.
extension Config {
    func target(bundleID: String) -> Target? {
        targets.first { $0.kind == .macApp(bundleID: bundleID) }
    }
}

extension Target {
    var bundleID: String? {
        if case .macApp(let id) = kind { return id }
        return nil
    }
}
#endif
