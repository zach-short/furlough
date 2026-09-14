import Foundation

/// Usage folded onto one week: minutes per hour per weekday, summed across every occurrence of
/// that weekday. Hours are the grain because that's what Screen Time hands out. Pure Foundation
/// so the report extension, the phone app, and the tests all run the same arithmetic.
struct UsageHistogram: Hashable, Sendable {
    /// minutes[weekday - 1][hour]: Calendar weekdays 1…7, Sunday first; hours 0…23.
    private(set) var minutes: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    /// How many of each weekday the stretch held, for turning a sum into a per-day average.
    /// A quiet day still counts.
    var daysObserved: [Int]
    private(set) var pickups = 0

    static let oneWeek = [Int](repeating: 1, count: 7)

    init(daysObserved: [Int] = oneWeek) {
        self.daysObserved = daysObserved.count == 7 ? daysObserved : Self.oneWeek
    }

    /// Off-clock weekday/hour is ignored; negative minutes/pickups clamp to zero.
    mutating func add(weekday: Int, hour: Int, minutes: Double, pickups: Int = 0) {
        guard (1...7).contains(weekday), (0..<24).contains(hour) else { return }
        self.minutes[weekday - 1][hour] += max(0, minutes)
        self.pickups += max(0, pickups)
    }

    /// The same thing seen from a second device: add its minutes on top.
    mutating func merge(_ other: UsageHistogram) {
        for weekday in 0..<7 {
            for hour in 0..<24 { minutes[weekday][hour] += other.minutes[weekday][hour] }
        }
        pickups += other.pickups
    }

    /// How many of each weekday `interval` touches; a day only partly inside still counts.
    static func daysObserved(in interval: DateInterval, calendar: Calendar) -> [Int] {
        var counts = [Int](repeating: 0, count: 7)
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            counts[calendar.component(.weekday, from: day) - 1] += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return counts
    }

    var totalMinutes: Double { minutes.reduce(0) { $0 + $1.reduce(0, +) } }
    var totalDays: Int { daysObserved.reduce(0, +) }
    var averageDailyMinutes: Double { totalDays == 0 ? 0 : totalMinutes / Double(totalDays) }
    var pickupsPerDay: Double { totalDays == 0 ? 0 : Double(pickups) / Double(totalDays) }

    /// 24 entries. With no observed days in `days`, the raw sums come back undivided.
    func hourlyAverage(on days: Weekdays) -> [Double] {
        var sums = [Double](repeating: 0, count: 24)
        var count = 0
        for weekday in 1...7 where days.contains(weekday: weekday) {
            count += daysObserved[weekday - 1]
            for hour in 0..<24 { sums[hour] += minutes[weekday - 1][hour] }
        }
        guard count > 0 else { return sums }
        return sums.map { $0 / Double(count) }
    }

    func share(of hours: Set<Int>) -> Double {
        let total = totalMinutes
        guard total > 0 else { return 0 }
        let inside = minutes.reduce(0.0) { sum, day in sum + hours.reduce(0.0) { $0 + day[$1] } }
        return inside / total
    }
}

/// Where use piles up, and the rule that would close those hours and keep a fixed share of the
/// time — plain arithmetic on the histogram, so the same numbers always give the same advice.
struct Recommendation: Hashable, Sendable, Identifiable {
    /// A pile of use on a group of days. The window may run past midnight (`TimeWindow.isNight`);
    /// `UsageAnalysis.hours(of:)` says which hours that is.
    struct Peak: Hashable, Sendable {
        var days: Weekdays
        var window: TimeWindow
    }

    /// The bundle identifier, the web domain, or a stand-in for a token with no name.
    var key: String
    var name: String
    var averageDailyMinutes: Double
    var pickupsPerDay: Double
    /// The share of use between 10 PM and 4 AM: 0…1. Above a half, it is a bedtime problem.
    var lateNightShare: Double
    /// One per day group whose use piles up; none when it is spread thin all day.
    var peaks: [Peak]
    /// Allowed windows that leave the peaks out, and a budget: what "Apply" writes.
    var rule: Rule

    var id: String { key }
}

/// The day groups one card draws: one row if weekdays and weekends close the same hours, two
/// otherwise. Compared by closed hours rather than by peaks, so two suggestions that happen to
/// land on the same hours never draw as separate rows.
struct UsageRow: Identifiable {
    var days: Weekdays
    var label: String
    var closed: Set<Int>

    var id: UInt8 { days.rawValue }

    static func rows(for item: Recommendation?) -> [UsageRow] {
        let weekdays = closedHours(of: item, on: .weekdays)
        let weekend = closedHours(of: item, on: .weekend)
        guard weekdays != weekend else {
            return [UsageRow(days: .all, label: "Every day", closed: weekdays)]
        }
        return [
            UsageRow(days: .weekdays, label: "Weekdays", closed: weekdays),
            UsageRow(days: .weekend, label: "Weekends", closed: weekend),
        ]
    }

    private static func closedHours(of item: Recommendation?, on group: Weekdays) -> Set<Int> {
        guard let item else { return [] }
        return item.peaks
            .filter { !$0.days.intersection(group).isEmpty }
            .reduce(into: Set<Int>()) { $0.formUnion(UsageAnalysis.hours(of: $1.window)) }
    }
}

/// Where the time goes and what rule would take it back. The peak is the shortest run of hours
/// holding most of the use, the rule closes exactly those hours, and the budget is a fixed
/// fraction of what was spent — so the advice is deterministic from the numbers.
enum UsageAnalysis {
    static let peakShare = 0.6
    /// Past this, use is spread out rather than piled up, so only the budget applies. Six hours
    /// is about the widest closure a person reads as a decision rather than a ban.
    static let longestPeakMinutes = 6 * 60
    /// When a peak is too long to suggest, this much use after 10 PM calls it a bedtime instead
    /// (closing the late hours); below it, only the budget applies.
    static let bedtimeShare = 0.5
    static let budgetKeep = 0.5
    static let minimumDailyMinutes = 10.0
    static let rankLimit = 5
    static let lateHours: Set<Int> = [22, 23, 0, 1, 2, 3]
    /// `lateHours` as one span, for a card to draw and a sentence to say. Keep the two in sync.
    static let bedtime = TimeWindow(startMinute: 22 * 60, endMinute: 4 * 60)
    /// School nights vs. weekends; anything finer needs more than a fortnight of data to mean
    /// something.
    static let dayGroups: [Weekdays] = [.weekdays, .weekend]

    /// Shortest run of whole hours holding at least `share` of `hourly`'s total, wrapping past
    /// midnight when that's shorter (10 PM–2 AM is 4 hours, not 22). Ties go to the fuller run,
    /// then the earlier start. Nil for no use; the whole day if nothing shorter suffices.
    static func peak(in hourly: [Double], share: Double = peakShare) -> TimeWindow? {
        guard hourly.count == 24 else { return nil }
        let total = hourly.reduce(0, +)
        guard total > 0 else { return nil }
        let needed = total * share - 1e-9
        for length in 1..<24 {
            var best: (start: Int, sum: Double)?
            for start in 0..<24 {
                var sum = 0.0
                for offset in 0..<length { sum += hourly[(start + offset) % 24] }
                if sum >= needed, sum > (best?.sum ?? -1) { best = (start, sum) }
            }
            if let best {
                let end = best.start + length
                let endMinute = end == 24 ? Furlough.minutesPerDay : (end % 24) * 60
                return TimeWindow(startMinute: best.start * 60, endMinute: endMinute)
            }
        }
        return Rule.allDay
    }

    /// The whole hours a peak covers: {22, 23, 0, 1} for 10 PM to 2 AM.
    static func hours(of window: TimeWindow) -> Set<Int> {
        let start = window.startMinute / 60
        let end = window.endMinute == Furlough.minutesPerDay ? 24 : window.endMinute / 60
        guard window.isNight else { return Set(start..<end) }
        return Set(start..<24).union(0..<end)
    }

    /// Half-open hour ranges: closing {22, 23, 0, 1} opens 2..<22.
    static func openRuns(closing closed: Set<Int>) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for hour in 0...24 {
            let open = hour < 24 && !closed.contains(hour)
            if open, start == nil { start = hour }
            if !open, let from = start {
                runs.append(from..<hour)
                start = nil
            }
        }
        return runs
    }

    /// Like `UsageHistogram.share(of:)`, but for one day group's average day rather than the week.
    static func share(of hours: Set<Int>, in hourly: [Double]) -> Double {
        let total = hourly.reduce(0, +)
        guard total > 0 else { return 0 }
        return hours.reduce(0.0) { $0 + (hourly.indices.contains($1) ? hourly[$1] : 0) } / total
    }

    /// In clock order: {22, 23, 0, 1} draws as 0..<2 and 22..<24 — two bands, not one wrapped
    /// one, since a strip has two ends.
    static func runs(of hours: Set<Int>) -> [Range<Int>] {
        openRuns(closing: Set(0..<24).subtracting(hours))
    }

    /// Windows covering every hour except `closed` (index 0 is Sunday), days with the same hours
    /// sharing a row. Empty when nothing is closed. Hour edges never cross midnight, matching how
    /// Furlough stores a window.
    static func windows(closing closed: [Set<Int>]) -> [TimeWindow] {
        guard closed.count == 7, closed.contains(where: { !$0.isEmpty }) else { return [] }
        var groups: [[Range<Int>]: Weekdays] = [:]
        for weekday in 1...7 {
            groups[openRuns(closing: closed[weekday - 1]), default: []].insert(Weekdays(weekday: weekday))
        }
        return groups.flatMap { runs, days in
            runs.map { TimeWindow(startMinute: $0.lowerBound * 60, endMinute: $0.upperBound * 60, days: days) }
        }
        .sorted()
    }

    /// A fixed share of what was spent, rounded down to five minutes, never under five.
    static func budget(forDailyMinutes average: Double, keep: Double = budgetKeep) -> Int {
        let kept = Int(average * keep) / 5 * 5
        return min(Furlough.minutesPerDay, max(5, kept))
    }

    /// The advice for one thing, or nil when it is used too little to bother with.
    static func recommendation(key: String, name: String, histogram: UsageHistogram) -> Recommendation? {
        let average = histogram.averageDailyMinutes
        guard average >= minimumDailyMinutes else { return nil }
        let lateNightShare = histogram.share(of: lateHours)
        var peaks: [Recommendation.Peak] = []
        var closed = [Set<Int>](repeating: [], count: 7)
        for group in dayGroups {
            let hourly = histogram.hourlyAverage(on: group)
            guard let found = peak(in: hourly) else { continue }
            let window: TimeWindow
            if found.spanMinutes <= longestPeakMinutes {
                window = found
            } else if share(of: lateHours, in: hourly) >= bedtimeShare {
                // Too spread out to pin an hour on, but mostly after 10 PM — call it a bedtime.
                window = bedtime
            } else {
                continue
            }
            peaks.append(Recommendation.Peak(days: group, window: window))
            let hours = hours(of: window)
            for weekday in 1...7 where group.contains(weekday: weekday) { closed[weekday - 1] = hours }
        }
        // Same hours in every group: say it once rather than draw matching rows twice.
        if peaks.count == dayGroups.count, let first = peaks.first, peaks.allSatisfy({ $0.window == first.window }) {
            peaks = [Recommendation.Peak(days: dayGroups.reduce(into: Weekdays()) { $0.formUnion($1) }, window: first.window)]
        }
        return Recommendation(
            key: key,
            name: name,
            averageDailyMinutes: average,
            pickupsPerDay: histogram.pickupsPerDay,
            lateNightShare: lateNightShare,
            peaks: peaks,
            rule: Rule(windows: windows(closing: closed), dailyBudgetMinutes: budget(forDailyMinutes: average))
        )
    }

    /// Distinguishes "youtube.com" the website from an app called YouTube.
    static let webKeyPrefix = "web:"

    static func webKey(_ domain: String) -> String { webKeyPrefix + domain }

    static func domain(inKey key: String) -> String? {
        key.hasPrefix(webKeyPrefix) ? String(key.dropFirst(webKeyPrefix.count)) : nil
    }

    /// Maps each key in a linked app+website group to the key that carries the group's summed
    /// minutes (the face included, mapping to itself) — so a linked pair ranks and budgets as one
    /// row instead of two. A key absent from the map stands alone.
    ///
    /// The face wins as carrier when present (it's what a rule is written on, and has Apple's
    /// icon/name); otherwise the heaviest half, then the lowest key, so the answer is
    /// order-independent.
    static func folding(
        _ entries: [(key: String, kind: TargetKind?, minutes: Double)],
        in config: Config
    ) -> [String: String] {
        var groups: [UUID: [(key: String, isFace: Bool, minutes: Double)]] = [:]
        for entry in entries {
            guard let target = target(of: entry, in: config) else { continue }
            groups[target.id, default: []].append((entry.key, entry.kind == target.kind, entry.minutes))
        }
        var folding: [String: String] = [:]
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { a, b in
                if a.isFace != b.isFace { return a.isFace }
                if a.minutes != b.minutes { return a.minutes > b.minutes }
                return a.key < b.key
            }
            guard let face = ordered.first else { continue }
            for half in group { folding[half.key] = face.key }
        }
        return folding
    }

    /// By token when Screen Time provided one, else by the domain in the key — a typed-in host
    /// has no token to match on. Nil when the entry isn't a managed target at all.
    private static func target(
        of entry: (key: String, kind: TargetKind?, minutes: Double),
        in config: Config
    ) -> Target? {
        if let kind = entry.kind, let found = config.target(kind: kind) { return found }
        return domain(inKey: entry.key).flatMap { config.target(host: $0) }
    }

    /// Heaviest first, at most `limit`, only those worth a rule. Ties break on key.
    static func rank(_ entries: [(key: String, name: String, histogram: UsageHistogram)], limit: Int = rankLimit) -> [Recommendation] {
        let ranked = entries
            .compactMap { recommendation(key: $0.key, name: $0.name, histogram: $0.histogram) }
            .sorted { a, b in
                a.averageDailyMinutes != b.averageDailyMinutes ? a.averageDailyMinutes > b.averageDailyMinutes : a.key < b.key
            }
        return Array(ranked.prefix(limit))
    }
}

extension Recommendation {
    var isBudgetOnly: Bool { peaks.isEmpty }

    /// With one peak the part of the day leads ("Mostly evenings: ..."); with two, listing both
    /// parts of the day in one sentence stops being readable, so the hours carry it instead.
    func whereLine(calendar: Calendar = .current) -> String {
        guard let first = peaks.first else { return "Spread through the day; no one stretch stands out." }
        if peaks.count == 1 {
            return "Mostly \(UsageAnalysis.partOfDay(first.window)): \(clause(first, calendar: calendar))."
        }
        return "Mostly " + peaks.map { clause($0, calendar: calendar) }.joined(separator: ", and ") + "."
    }

    func consequence(calendar: Calendar = .current) -> String {
        let allowance = "\(TimeFormat.budget(rule.dailyBudgetMinutes)) a day"
        guard !peaks.isEmpty else { return "\(allowance), whenever you like." }
        let closures = peaks.map { clause($0, calendar: calendar) }.joined(separator: " and ")
        return "Closed \(closures), and \(allowance) the rest of the time."
    }

    private func clause(_ peak: Peak, calendar: Calendar) -> String {
        "\(TimeFormat.span(peak.window, calendar: calendar)) \(TimeFormat.onDays(peak.days, calendar: calendar))"
    }
}

extension UsageAnalysis {
    /// Judged by the hour at the window's middle, not its start — centred at 1 AM is late
    /// nights however early it begins.
    static func partOfDay(_ window: TimeWindow) -> String {
        let middle = (window.startMinute + window.spanMinutes / 2) % Furlough.minutesPerDay
        return switch middle / 60 {
        case 5..<12: "mornings"
        case 12..<17: "afternoons"
        case 17..<22: "evenings"
        default: "late nights"
        }
    }
}
