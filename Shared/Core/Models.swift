import Foundation
import ManagedSettings

/// Days of the week as a bit set. Bit 0 is Sunday, so bits line up with Calendar's weekday
/// numbers (1 = Sunday … 7 = Saturday) whatever the user's first day of the week is.
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

    /// Calendar weekday numbers in the order the user's calendar lays a week out.
    static func ordered(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// Where the earliest of these days falls in the calendar's week, 0…6; 7 when empty.
    func firstPosition(calendar: Calendar = .current) -> Int {
        Weekdays.ordered(calendar: calendar).firstIndex { contains(weekday: $0) } ?? 7
    }

    /// The order groups of days are listed in: earliest day first, then the broader group
    /// ("Every day" before "Sat, Sun"), then a stable tiebreak.
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

/// A span of minutes inside one calendar day, on the days of the week it applies.
/// `endMinute` is exclusive and may be 1440 (midnight). A span never crosses midnight; an
/// evening that runs late is an evening window plus an early-morning window on the next day.
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

    /// The same span on every day. DeviceActivity is told about each distinct span once; the
    /// rules engine decides per day.
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

    /// Where a new window on `days` goes among `windows`: from the latest end on those days
    /// when there is room before midnight, else the first free stretch of the day. Up to an
    /// hour long, never shorter than the minimum. Nil when those days are already full.
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

    /// Windows on the same days that overlap or touch, joined into one, in order. Windows on
    /// different days are left alone.
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

/// When a target may be used, and for how many minutes per day in total. No windows means
/// open all day, every day: only the budget limits it. Windows narrow that to their hours,
/// and once there are any, a day none of them covers is blocked.
struct Rule: Codable, Hashable {
    var windows: [TimeWindow] = []
    var dailyBudgetMinutes: Int = Furlough.defaultBudgetMinutes

    /// Midnight to midnight: what a rule without windows allows on every day.
    static let allDay = TimeWindow(startMinute: 0, endMinute: Furlough.minutesPerDay)

    /// Permits everything. The baseline for a target that has no rule yet, and what "remove" means.
    static let unrestricted = Rule(windows: [], dailyBudgetMinutes: Furlough.minutesPerDay)
    /// No budget, so never allowed: what a category gets.
    static let alwaysBlocked = Rule(windows: [], dailyBudgetMinutes: 0)

    /// No windows of its own, so open all day up to the budget.
    var isAllDay: Bool { windows.isEmpty }
    /// Allowed at some minute of some day.
    var isEverAllowed: Bool { dailyBudgetMinutes > 0 && (isAllDay || windows.contains { !$0.days.isEmpty }) }
    var effectiveBudgetMinutes: Int { isEverAllowed ? dailyBudgetMinutes : 0 }
    var sortedWindows: [TimeWindow] { windows.sorted() }
    /// Every window applies every day, so one list describes the whole week.
    var isSameEveryDay: Bool { windows.allSatisfy { $0.days == .all } }

    /// The same rule whatever order the windows are listed in.
    func isEquivalent(to other: Rule) -> Bool {
        dailyBudgetMinutes == other.dailyBudgetMinutes && sortedWindows == other.sortedWindows
    }

    /// The windows that apply on `weekday` (Calendar's 1…7), in order: the whole day when
    /// the rule has none of its own.
    func windows(on weekday: Int) -> [TimeWindow] {
        isAllDay ? [Self.allDay] : sortedWindows.filter { $0.applies(on: weekday) }
    }

    /// One flag per minute of `weekday`; true where use is permitted.
    func allowedMask(on weekday: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: Furlough.minutesPerDay)
        guard isEverAllowed else { return mask }
        for window in windows(on: weekday) {
            let lower = max(0, window.startMinute)
            let upper = min(Furlough.minutesPerDay, window.endMinute)
            guard lower < upper else { continue }
            for minute in lower..<upper { mask[minute] = true }
        }
        return mask
    }

    func window(containing minute: Int, on weekday: Int) -> TimeWindow? {
        guard isEverAllowed else { return nil }
        return windows(on: weekday).first { $0.contains(minuteOfDay: minute) }
    }

    /// True when this rule allows no minute of any day that `other` forbids and has no larger budget.
    func isTighterOrEqual(to other: Rule) -> Bool {
        for weekday in 1...7 {
            let mine = allowedMask(on: weekday)
            let theirs = other.allowedMask(on: weekday)
            for minute in 0..<Furlough.minutesPerDay where mine[minute] && !theirs[minute] {
                return false
            }
        }
        return effectiveBudgetMinutes <= other.effectiveBudgetMinutes
    }

    /// Problems that make the rule unusable, or nil.
    var validationError: String? {
        for window in windows where !window.isValid {
            return "Each window must be at least \(Furlough.minimumWindowMinutes) minutes and end after it starts."
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

enum TargetKind: Codable, Hashable {
    case application(ApplicationToken)
    case webDomain(WebDomainToken)
    case category(ActivityCategoryToken)

    var isCategory: Bool {
        if case .category = self { return true }
        return false
    }
}

/// One app, website, or category that Furlough manages.
struct Target: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: TargetKind
    var nickname = ""
    /// nil means "not configured yet": nothing is enforced until the first rule is saved.
    var rule: Rule?
    var addedAt = Date.now

    var defaultName: String {
        switch kind {
        case .application: "This app"
        case .webDomain: "This website"
        case .category: "This category"
        }
    }

    var displayName: String { nickname.isEmpty ? defaultName : nickname }
}

/// A set of apps, sites, or categories locked behind a physical NFC tag. Bricking is instant
/// from the app; unbricking needs the paired tag. This is the only unblock path in Furlough,
/// and it exists only here: rule-based targets never get one. While bricked, the list and the
/// tag cannot be changed.
struct BrickProfile: Codable, Equatable {
    var kinds: [TargetKind] = []
    var isBricked = false
    var brickedAt: Date?
    /// Hardware identifier of the paired tag, read over NFC.
    var tagID: Data?

    var isPaired: Bool { tagID != nil }
    var count: Int { kinds.count }
    /// Ready to brick: something to lock and a tag to unlock it with.
    var canBrick: Bool { !kinds.isEmpty && isPaired && !isBricked }
    func contains(_ kind: TargetKind) -> Bool { kinds.contains(kind) }
    /// True when `kind` is blocked by the brick right now.
    func blocks(_ kind: TargetKind) -> Bool { isBricked && contains(kind) }
}

struct Config: Codable, Equatable {
    var targets: [Target] = []
    var loosenDelayHours: Int = Furlough.defaultLoosenDelayHours
    var brick = BrickProfile()
    var schemaVersion = 1

    init() {}

    /// `brick` arrived after the first stored states, so its absence must decode cleanly.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decode([Target].self, forKey: .targets)
        loosenDelayHours = try container.decode(Int.self, forKey: .loosenDelayHours)
        brick = try container.decodeIfPresent(BrickProfile.self, forKey: .brick) ?? BrickProfile()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

    var loosenDelay: TimeInterval { TimeInterval(loosenDelayHours) * 3600 }

    /// Whether `target` is locked by the brick right now.
    func isBricked(_ target: Target) -> Bool { brick.blocks(target.kind) }

    func target(id: UUID) -> Target? { targets.first { $0.id == id } }
    func target(kind: TargetKind) -> Target? { targets.first { $0.kind == kind } }
}

enum PendingKind: Codable, Hashable {
    case setRule(targetID: UUID, rule: Rule)
    case removeTarget(targetID: UUID)
    case setDelay(hours: Int)
}

/// A loosening edit waiting out the delay.
struct PendingChange: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: PendingKind
    var createdAt = Date.now
    var effectiveAt: Date

    var targetID: UUID? {
        switch kind {
        case .setRule(let id, _), .removeTarget(let id): id
        case .setDelay: nil
        }
    }
}

/// Facts the monitor extension learns at runtime, keyed by target id and day.
struct RuntimeState: Codable, Equatable {
    var exhausted: [String: String] = [:]
    var warned: [String: String] = [:]
    var lastReconcile: Date?
    var lastRegistration: Date?
    var registrationError: String?

    func isExhausted(_ id: UUID, dayKey: String) -> Bool { exhausted[id.uuidString] == dayKey }
    func wasWarned(_ id: UUID, dayKey: String) -> Bool { warned[id.uuidString] == dayKey }
}

struct SharedState: Codable, Equatable {
    var config = Config()
    var pending: [PendingChange] = []
    var runtime = RuntimeState()
}
