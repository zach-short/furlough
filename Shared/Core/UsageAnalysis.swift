import Foundation

/// How something was used over a stretch of days, folded onto one week: the minutes in each
/// hour of each weekday, summed over every time that weekday came round. Screen Time hands
/// out hours, so hours are the grain. Pure Foundation, so the report extension (the only
/// place iOS shows history everywhere), the phone app where iOS 26.4 lets it see the numbers
/// itself, and the tests all run the very same arithmetic.
struct UsageHistogram: Hashable, Sendable {
    /// minutes[weekday - 1][hour]: Calendar weekdays 1…7, Sunday first; hours 0…23.
    private(set) var minutes: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    /// How many of each weekday the stretch held, so a sum becomes a per-day average. Days
    /// with no use count too: a quiet Sunday is still a Sunday. One of each unless told.
    var daysObserved: [Int]
    private(set) var pickups = 0

    /// One week: every weekday once.
    static let oneWeek = [Int](repeating: 1, count: 7)

    init(daysObserved: [Int] = oneWeek) {
        self.daysObserved = daysObserved.count == 7 ? daysObserved : Self.oneWeek
    }

    /// Nothing happens for a weekday or hour off the clock, or for no time at all.
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

    /// How many of each weekday `interval` touches in `calendar`: what a sum is divided by.
    /// A day that is only partly inside still counts, today included.
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

    /// The minutes in each hour of an average day among `days`: 24 entries. Only the days the
    /// stretch held are divided by; with none of them, the raw sums come back.
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

    /// The share of all use that fell in `hours`, 0…1; 0 when there was none.
    func share(of hours: Set<Int>) -> Double {
        let total = totalMinutes
        guard total > 0 else { return 0 }
        let inside = minutes.reduce(0.0) { sum, day in sum + hours.reduce(0.0) { $0 + day[$1] } }
        return inside / total
    }
}

/// What to do about one thing: where its use piles up, and the rule that would close those
/// hours and keep a fixed share of the time. Everything in it is readable arithmetic on the
/// histogram, so the same numbers always give the same advice.
struct Recommendation: Hashable, Sendable, Identifiable {
    /// A pile of use on a group of days: what the rule closes. The window may run past
    /// midnight (`TimeWindow.isNight`); `UsageAnalysis.hours(of:)` says which hours that is.
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

/// The day groups one card draws: one row when a suggestion treats the whole week alike, two
/// when it tells weekdays and weekends apart. Read off the closed hours rather than the peaks,
/// so a suggestion that happens to close the same hours on both never draws the same row twice.
struct UsageRow: Identifiable {
    var days: Weekdays
    var label: String
    /// The hours the rule closes on these days.
    var closed: Set<Int>

    var id: UInt8 { days.rawValue }

    /// The rows for one suggestion, or the one plain row for something with no suggestion.
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

    /// Every hour the suggestion closes on any of `group`'s days.
    private static func closedHours(of item: Recommendation?, on group: Weekdays) -> Set<Int> {
        guard let item else { return [] }
        return item.peaks
            .filter { !$0.days.intersection(group).isEmpty }
            .reduce(into: Set<Int>()) { $0.formUnion(UsageAnalysis.hours(of: $1.window)) }
    }
}

/// Where the time goes and what rule would take it back. Nothing here guesses: the peak is the
/// shortest run of hours that holds most of the use, the rule closes exactly those hours, and
/// the budget is a fixed fraction of what was spent. Change a number below and the advice
/// changes the same way for everyone.
enum UsageAnalysis {
    /// The slice of a day's use the peak must hold: the closed hours carry most of it.
    static let peakShare = 0.6
    /// A peak longer than this is use spread out, not piled up, so only the budget applies.
    /// Nobody takes "closed from 7 AM to 4 PM" as a suggestion; six hours is about the widest
    /// closure a person reads as a decision rather than a ban.
    static let longestPeakMinutes = 6 * 60
    /// When a peak comes out too long to suggest, this much use after 10 PM makes it a bedtime
    /// instead: close the late hours rather than give up on hours altogether. Below it, hours
    /// that spread this wide are not a shape anyone would close, and only the budget applies.
    static let bedtimeShare = 0.5
    /// How much of today's average the suggested budget keeps.
    static let budgetKeep = 0.5
    /// Under this many minutes a day there is nothing worth a rule.
    static let minimumDailyMinutes = 10.0
    /// How many of the heaviest are ranked: one report slot each on the usage screen.
    static let rankLimit = 5
    /// 10 PM to 4 AM.
    static let lateHours: Set<Int> = [22, 23, 0, 1, 2, 3]
    /// `lateHours` as the one span it is, for a card to draw and a sentence to say.
    static let bedtime = TimeWindow(startMinute: 22 * 60, endMinute: 4 * 60)
    /// The day groups a suggestion tells apart. School nights and weekends differ; anything
    /// finer needs more than a fortnight of data to mean something.
    static let dayGroups: [Weekdays] = [.weekdays, .weekend]

    /// The shortest run of whole hours holding at least `share` of `hourly`'s total, wrapping
    /// past midnight when that is shorter: 10 PM to 2 AM is four hours, not twenty-two. Among
    /// runs of that length the fullest wins, then the earliest start. Nil when there was no use;
    /// the whole day when nothing shorter holds the share.
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

    /// The whole hours a peak covers, on the clock: {22, 23, 0, 1} for 10 PM to 2 AM.
    static func hours(of window: TimeWindow) -> Set<Int> {
        let start = window.startMinute / 60
        let end = window.endMinute == Furlough.minutesPerDay ? 24 : window.endMinute / 60
        guard window.isNight else { return Set(start..<end) }
        return Set(start..<24).union(0..<end)
    }

    /// Runs of open hours in a day as half-open hour ranges: closing {22, 23, 0, 1} opens 2..<22.
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

    /// The share of an average day's minutes that fell in `hours`, 0…1; 0 when there was none.
    /// `UsageHistogram.share(of:)` answers the same question for a whole week; this one answers
    /// it for the one day group being judged.
    static func share(of hours: Set<Int>, in hourly: [Double]) -> Double {
        let total = hourly.reduce(0, +)
        guard total > 0 else { return 0 }
        return hours.reduce(0.0) { $0 + (hourly.indices.contains($1) ? hourly[$1] : 0) } / total
    }

    /// The whole-hour runs a set of hours makes, in clock order: {22, 23, 0, 1} draws as 0..<2
    /// and 22..<24, two bands rather than one wrapped one, because a strip has two ends.
    static func runs(of hours: Set<Int>) -> [Range<Int>] {
        openRuns(closing: Set(0..<24).subtracting(hours))
    }

    /// The allowed windows that are every hour except `closed` (index 0 is Sunday), days with
    /// the same hours sharing a row. Empty when nothing is closed: open all day, and only the
    /// budget bites. Hour edges never cross midnight, so every window is one Furlough stores.
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
                // Too spread out to pin an hour on, but most of it lands after 10 PM. That is a
                // bedtime, and closing the late hours is both truer and far shorter than
                // whatever nine-hour run happens to hold 60 % of a night owl's day.
                window = bedtime
            } else {
                continue
            }
            peaks.append(Recommendation.Peak(days: group, window: window))
            let hours = hours(of: window)
            for weekday in 1...7 where group.contains(weekday: weekday) { closed[weekday - 1] = hours }
        }
        // Every group came out with the same hours, so say it once. `windows(closing:)` already
        // folds the rows this way, and a card that drew "weekdays" and "weekends" side by side
        // with the same band would be asking a person to spot that they match.
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

    /// The heaviest first, at most `limit` of them, and only those worth a rule. Equal minutes
    /// fall back to the key, so the order never depends on how the input was gathered.
    static func rank(_ entries: [(key: String, name: String, histogram: UsageHistogram)], limit: Int = rankLimit) -> [Recommendation] {
        let ranked = entries
            .compactMap { recommendation(key: $0.key, name: $0.name, histogram: $0.histogram) }
            .sorted { a, b in
                a.averageDailyMinutes != b.averageDailyMinutes ? a.averageDailyMinutes > b.averageDailyMinutes : a.key < b.key
            }
        return Array(ranked.prefix(limit))
    }
}

/// The two sentences a card says out loud: where the time goes, and what the rule does about
/// it. Both are read straight off the numbers above, so a card never claims more than the
/// arithmetic found, and a stranger can check either one against the picture beside it.
extension Recommendation {
    /// Nothing is closed: the use was spread too thin for a peak, so only the budget bites.
    var isBudgetOnly: Bool { peaks.isEmpty }

    /// "Mostly evenings: 7 PM to 4 AM on weekends." With one pile the part of the day leads,
    /// because that is the word a person would use; with two the hours carry it, because two
    /// parts of the day in one sentence stop being readable.
    func whereLine(calendar: Calendar = .current) -> String {
        guard let first = peaks.first else { return "Spread through the day; no one stretch stands out." }
        if peaks.count == 1 {
            return "Mostly \(UsageAnalysis.partOfDay(first.window)): \(clause(first, calendar: calendar))."
        }
        return "Mostly " + peaks.map { clause($0, calendar: calendar) }.joined(separator: ", and ") + "."
    }

    /// "Closed 7 PM to 4 AM on weekends, and 35 min a day the rest of the time." One line, and
    /// it says what changes rather than listing the hours that survive.
    func consequence(calendar: Calendar = .current) -> String {
        let allowance = "\(TimeFormat.budget(rule.dailyBudgetMinutes)) a day"
        guard !peaks.isEmpty else { return "\(allowance), whenever you like." }
        let closures = peaks.map { clause($0, calendar: calendar) }.joined(separator: " and ")
        return "Closed \(closures), and \(allowance) the rest of the time."
    }

    /// "7 PM to 4 AM on weekends": one pile, hours then days.
    private func clause(_ peak: Peak, calendar: Calendar) -> String {
        "\(TimeFormat.span(peak.window, calendar: calendar)) \(TimeFormat.onDays(peak.days, calendar: calendar))"
    }
}

extension UsageAnalysis {
    /// What a person calls the stretch a window covers, from the hour at its middle: a window
    /// centred at 1 AM is late nights however early it starts.
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
