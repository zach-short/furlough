import Foundation
#if os(iOS) && !NO_SCREEN_TIME
import ManagedSettings
#endif

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

    /// The same days moved forward through the week. The morning after a Saturday night is a
    /// Sunday, so a night's two halves sit on days one apart. Sunday is bit 0, so a day later
    /// is a bit up, and Saturday comes round to Sunday again.
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
/// `endMinute` is exclusive and may be 1440 (midnight). A stored span never crosses midnight;
/// an evening that runs late is an evening window plus an early-morning window on the next day.
/// The editors let one be written the way it is said — "5 PM until 4 AM" — and `split` turns
/// that night into the pair Furlough keeps, with `folded` reading it back as one row.
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

    /// An evening that runs into the next morning: the end falls earlier in the day than the
    /// start. Only ever drafted, never stored — both the rules engine and DeviceActivity work
    /// a day at a time — but it is how a late night is said, so the editors take one and split
    /// it on the way in.
    var isNight: Bool { endMinute < startMinute }

    /// How long the window is, a night's two halves counted together.
    var spanMinutes: Int {
        isNight ? Furlough.minutesPerDay - startMinute + endMinute : durationMinutes
    }

    /// True when every window this becomes is one Furlough can keep. A night is judged by its
    /// halves, because the halves are what DeviceActivity is given and each has its own minimum.
    var isValidDraft: Bool {
        let parts = split
        return !parts.isEmpty && parts.allSatisfy(\.isValid)
    }

    /// The windows this really is: itself, or, for a night, the evening on the days it starts
    /// and the early morning on the days after. An evening that runs to exactly midnight has
    /// no morning half and comes back alone.
    var split: [TimeWindow] {
        guard isNight else { return [self] }
        var parts = [TimeWindow(startMinute: startMinute, endMinute: Furlough.minutesPerDay, days: days)]
        if endMinute > 0 {
            parts.append(TimeWindow(startMinute: 0, endMinute: endMinute, days: days.shifted(by: 1)))
        }
        return parts
    }

    /// Half of a night as stored: an evening that ends at midnight, and the morning that starts
    /// at it. The all-day window is neither.
    private var isEveningHalf: Bool { startMinute > 0 && endMinute == Furlough.minutesPerDay }
    private var isMorningHalf: Bool { startMinute == 0 && endMinute < Furlough.minutesPerDay }

    /// `split` in reverse: an evening ending at midnight and a morning starting at midnight on
    /// the days after are one night again. Exact rather than a guess — those two windows and
    /// that one night allow the very same minutes of the week — so a night reads back as the
    /// row it was written as, and a pair someone wrote by hand reads as the night it is.
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
    /// The daily limit, or nil when there is not really one. A whole day of budget is no
    /// budget at all — `Rule.unrestricted` has always carried one — and on iOS a typed host
    /// always does, because DeviceActivity counts only tokens and so nothing counts it. Read
    /// this rather than `dailyBudgetMinutes` wherever a limit is being shown to a person.
    var limitMinutes: Int? { dailyBudgetMinutes < Furlough.minutesPerDay ? dailyBudgetMinutes : nil }
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

    /// The window on the day after that this day's last one runs into: the morning half of a
    /// night, whose evening half ends at midnight. Nil when the day ends where it says it does.
    /// A rule without windows has none — midnight only resets its budget.
    func continuation(after weekday: Int) -> TimeWindow? {
        guard !isAllDay else { return nil }
        return windows(on: weekday % 7 + 1).first { $0.startMinute == 0 && $0.endMinute < Furlough.minutesPerDay }
    }

    /// The window on the day before that runs into this one, when this day opens at midnight
    /// because the evening before never closed. Nil when the day begins on its own.
    func continues(into weekday: Int) -> TimeWindow? {
        guard !isAllDay,
              windows(on: weekday).contains(where: { $0.startMinute == 0 && $0.endMinute < Furlough.minutesPerDay })
        else { return nil }
        return windows(on: weekday == 1 ? 7 : weekday - 1)
            .first { $0.startMinute > 0 && $0.endMinute == Furlough.minutesPerDay }
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

/// What a target is. On iOS these are the opaque Screen Time tokens; on the Mac, where there
/// is no Screen Time API, an app is its bundle identifier and a website is its host.
enum TargetKind: Codable, Hashable {
    #if os(iOS)
    case application(ApplicationToken)
    case webDomain(WebDomainToken)
    case category(ActivityCategoryToken)
    /// A website typed by name rather than minted by Apple's picker: "youtube.com", subdomains
    /// too. Blocked through `WebContentSettings.blockedByFilter`, which takes a plain string,
    /// so it needs no token and carries its own name from the moment it is added — unlike
    /// `.webDomain`, which says nothing until the shield learns a name.
    ///
    /// It buys that with two things a picked site has. Nothing counts it: a DeviceActivity
    /// budget event needs a token, so a typed host has windows and no daily budget. And iOS
    /// draws its own "Website Not Allowed" page over it rather than Furlough's shield.
    /// Verified on the phone 2026-09-08; see the note in `ShieldReconciler.apply`.
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
}

/// One app, website, or category that Furlough manages.
struct Target: Codable, Hashable, Identifiable {
    var id = UUID()
    /// The face of this thing: the app, wherever there is one. Blocking the YouTube app and
    /// leaving youtube.com open is the gap everyone finds a week later, so the two halves are
    /// one target — and the app is the half with real artwork and Apple's own name, so it is
    /// the half the row shows.
    var kind: TargetKind
    /// The other doors into the same thing, blocked on the same rule.
    ///
    /// Two doors into one habit should not cost two rules to close. Everything downstream reads
    /// `kinds` rather than `kind`, so one status, one schedule, one budget, one removal delay and
    /// one row cover every half: `Policy.decide` shields them together, and `Monitoring.include`
    /// puts their tokens in *one* DeviceActivity event, so 45 minutes is 45 across the app and
    /// the site together rather than 45 each. Where a half has no token — a site typed by name —
    /// it shares the windows and nothing counts it; the editor says so.
    ///
    /// Optional for the same reason `systemName` and `utilityLevel` are: a synthesised
    /// `init(from:)` demands every non-optional key, and the state already on the phone has none.
    /// Read it through `kinds`.
    var also: [TargetKind]?
    var nickname = ""
    /// nil means "not configured yet": nothing is enforced until the first rule is saved.
    var rule: Rule?
    var addedAt = Date.now
    /// The name iOS gave this one, learned from the shield the first time Furlough blocked it.
    /// A Screen Time token is opaque: only `Label(token)`, drawn inside the app, ever shows a
    /// name, so without this the widget, the notifications and the Live Activity have nothing
    /// to call an app but "This app". Optional so state written before it existed still
    /// decodes; `SharedStore` folds the learned names in on every load.
    ///
    /// Since 2026-09-08 one other thing may write it: when the companion nudge adds the app
    /// half beside a website, Furlough already knows from the `Companions` table what it just
    /// added, so it says so rather than waiting to be told. A name Screen Time teaches later
    /// still wins — `SharedStore.load` folds the learned names over the top.
    var systemName: String?
    /// The tier Zach put this in, or nil while he has not said. Stored optional for the same
    /// reason `systemName` is: a synthesised `init(from:)` demands every non-optional key, and
    /// state written before tiers existed has none. Read it through `utility`.
    var utilityLevel: Utility?

    /// Every door into this thing, the face first. Read this rather than `kind` anywhere the
    /// question is "what does this target cover": one target may be an app *and* the website it
    /// is also at, and both are blocked on the one rule.
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

    /// Whether `displayName` is a name rather than a stand-in. A nickname or a name Screen Time
    /// has taught is; so is a typed host, which names itself. An app that has never yet been
    /// blocked is not, and reads "This app" until it is. The widget lists the named ones first,
    /// so that when three open together the two a person knows are the two it shows.
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

/// One tag paired with the anchor: the hardware identifier read over NFC, and a name. The name
/// is what makes more than one usable — two identifiers are four hex digits apiece, and nobody
/// tells those apart. A tag lives in a place; the name is which place.
struct PairedTag: Codable, Equatable, Identifiable {
    /// Hardware identifier read over NFC. Unique per tag, so it is the identity.
    var id: Data
    var name: String

    /// The longest name a row can show without wrapping into the identifier under it.
    static let maxNameLength = 24
}

/// A set of apps, sites, or categories locked behind a physical NFC tag. Anchoring is instant
/// from the app; weighing anchor needs one of the paired tags. This is the only unblock path in
/// Furlough, and it exists only here: rule-based targets never get one. While anchored, the list
/// and the tags cannot be changed.
struct AnchorProfile: Codable, Equatable {
    var kinds: [TargetKind] = []
    var isAnchored = false
    var anchoredAt: Date?
    /// Every tag that releases this anchor. They are keys to one lock, not a sequence: any of
    /// them lifts it, so a tag at each place you live keeps the friction at "walk to the drawer"
    /// in both. Capped at `Furlough.maxAnchorTags`, since the failure here is not two keys but
    /// enough of them that one is always within reach.
    var tags: [PairedTag] = []

    var isPaired: Bool { !tags.isEmpty }
    /// Room for another key. Pairing is refused past the cap rather than evicting the oldest:
    /// silently dropping a key is how someone finds out at the drawer that it no longer opens.
    var canPairMore: Bool { tags.count < Furlough.maxAnchorTags }
    var count: Int { kinds.count }
    /// Ready to anchor: something to lock and a tag to unlock it with.
    var canAnchor: Bool { !kinds.isEmpty && isPaired && !isAnchored }
    func contains(_ kind: TargetKind) -> Bool { kinds.contains(kind) }
    /// True when `kind` is blocked by the anchor right now.
    func blocks(_ kind: TargetKind) -> Bool { isAnchored && contains(kind) }
    /// The paired tag a scan matches, if any.
    func tag(matching scanned: Data) -> PairedTag? { tags.first { $0.id == scanned } }
    /// A placeholder for a tag just paired, never a duplicate of one already here, because a
    /// name only earns its place by telling one drawer from another.
    var nextTagName: String {
        var n = tags.count + 1
        while tags.contains(where: { $0.name == "Tag \(n)" }) { n += 1 }
        return "Tag \(n)"
    }
}

extension AnchorProfile {
    /// The anchor was called the Brick until 2026-09-08, and held a single `tagID` until
    /// 2026-09-08. Read the old names when the new ones are missing; encoding always writes the
    /// new. A lone stored identifier becomes the first of the list, named rather than blank, so
    /// the phone comes back with the key it already had.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        kinds = try container.decodeIfPresent([TargetKind].self, forKey: .kinds) ?? []
        isAnchored = try container.decodeIfPresent(Bool.self, forKey: .isAnchored)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .isBricked) ?? false
        anchoredAt = try container.decodeIfPresent(Date.self, forKey: .anchoredAt)
            ?? legacy.decodeIfPresent(Date.self, forKey: .brickedAt)
        if let stored = try container.decodeIfPresent([PairedTag].self, forKey: .tags) {
            // Trimmed on the way in as well as on the way out: a file written when the cap was
            // higher, or by hand, does not get to hand the anchor more keys than it allows.
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
    var schemaVersion = 1

    init() {}

    /// The anchor arrived after the first stored states, so its absence must decode cleanly,
    /// and it was stored under `brick` until the rename, so that key still reads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        targets = try container.decode([Target].self, forKey: .targets)
        loosenDelayHours = try container.decode(Int.self, forKey: .loosenDelayHours)
        anchor = try container.decodeIfPresent(AnchorProfile.self, forKey: .anchor)
            ?? legacy.decodeIfPresent(AnchorProfile.self, forKey: .brick)
            ?? AnchorProfile()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

    private enum LegacyKeys: String, CodingKey { case brick }

    var loosenDelay: TimeInterval { TimeInterval(loosenDelayHours) * 3600 }

    /// Whether `target` is locked by the anchor right now. Any door being anchored anchors the
    /// target: the halves are one thing, and one of them held is the whole of it held.
    func isAnchored(_ target: Target) -> Bool { target.kinds.contains { anchor.blocks($0) } }

    func target(id: UUID) -> Target? { targets.first { $0.id == id } }
    /// The target `kind` is a door into, whether it is the face or a linked half. Reading only
    /// `kind` here would let the picker and an import add a second target for a half that is
    /// already covered.
    func target(kind: TargetKind) -> Target? { targets.first { $0.covers(kind) } }
}

enum PendingKind: Codable, Hashable {
    case setRule(targetID: UUID, rule: Rule)
    case removeTarget(targetID: UUID)
    case setDelay(hours: Int)
    /// Moving a target toward essential shortens its delay, so that is a loosening and queues.
    case setUtility(targetID: UUID, level: Utility)
    /// Taking one half off a linked target: the website an app is also at stops being blocked
    /// while the app stays. Something shielded a moment ago is not any more, so it is a
    /// loosening and queues, exactly as removing the whole row does. Linking is the tightening
    /// and lands at once.
    case unlink(targetID: UUID, kind: TargetKind)
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
        case .setDelay: nil
        }
    }
}

/// Facts the monitor extension learns at runtime, keyed by target id and day.
struct RuntimeState: Codable, Equatable {
    var exhausted: [String: String] = [:]
    var warned: [String: String] = [:]
    /// Both clocks as they stood at the last save, so a wall clock moved forward is visible.
    var clock: ClockMark?
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

// MARK: - Host lookups

/// Finding a target by its host. Both platforms have `.host` since 2026-09-08 — the Mac has
/// only ever had it, and the phone gained typed sites alongside the picker's — so this is not
/// Mac-only the way the bundle-identifier lookups below are.
extension Config {
    /// The target whose host is `host` or a parent domain of it: "m.youtube.com" matches
    /// "youtube.com". Searches every door, so a site linked to an app is found through the app's
    /// target — which is the point of linking: one row answers for both halves.
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
    /// The face's host, or "" when the face is not a typed site. `hosts` is what to read when
    /// the question is which sites this target covers.
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

    /// Whether anything this target covers is counted against its budget.
    ///
    /// DeviceActivity counts tokens and nothing else, so a site typed by name is never counted —
    /// on its own that leaves a target with hours and no budget at all. Linked to an app it is
    /// different: the pair shares one budget event and the app's minutes draw it down, so the
    /// budget is real and only the browser half is invisible. The editor says which it is.
    var isCounted: Bool { kinds.contains { !$0.isHost } }

    /// Typed sites that share this target's budget without being counted towards it: the honest
    /// gap in a linked pair, and empty when there is none.
    var uncountedHosts: [String] { isCounted ? hosts : [] }

    /// Whether this target covers the website half, however it got there: Apple's picker mints a
    /// token, and a name typed into Furlough is a `.host`. Both are the site.
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

/// Finding a Mac app by its bundle identifier. Here rather than beside the Mac's model because
/// the import reads it too, and `Shared/Core` is the only place both can see.
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
