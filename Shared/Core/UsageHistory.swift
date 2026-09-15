import Foundation

/// What the Mac actually measured, day by day.
///
/// The Mac is the only half of Furlough that genuinely *counts* time: `Enforcer.tick` adds a
/// second whenever an app or a site is in front and nobody is idle. Until now it threw the
/// measurement away at every day boundary, so the phone — which cannot see how much of a budget
/// was used — had a fortnight view, and the Mac, which knows precisely, had nothing.
///
/// Two things this is deliberately **not**:
///
/// - It is not part of `RuntimeState`. `UsageLedger` sits outside the shared model because on
///   iOS the counting is Apple's; this is Mac-local history, kept beside the state, not in it.
/// - It is not the record. `Record` keeps sixty days of minutes held *shut*; this keeps fourteen
///   of minutes *used*. Different numbers, and a screen that blurred them would be lying about
///   both.
struct UsageHistory: Codable, Equatable {
    /// Days kept, matching the fortnight the phone's usage page shows. Zach's call, 2026-09-14:
    /// fourteen and sixty stay two numbers, because the phone cannot reach past a fortnight and
    /// a Mac claiming sixty days of *used* minutes would be claiming a span its other half has
    /// no answer for.
    static let retainedDays = 14

    /// Where the Mac keeps it, named here so `SharedStore.reset()` can forget it without
    /// knowing anything else about the Mac. The load and save around this key live beside
    /// `UsageLedger`'s, in `Enforcer.swift`.
    static let storeKey = "furlough.mac.usageHistory.v1"

    /// Seconds per target, by `Policy.dayKey` — seconds, like the ledger this is written from,
    /// so nothing is rounded twice.
    var days: [String: [UUID: Double]] = [:]

    init(days: [String: [UUID: Double]] = [:]) {
        self.days = days
    }

    // MARK: - Writing

    /// Files a finished day. Replaces rather than merges: the ledger is the whole of that day's
    /// count, and a second call with a smaller figure means the day was reset, not continued.
    mutating func record(_ seconds: [UUID: Double], on dayKey: String) {
        guard !seconds.isEmpty else { return }
        days[dayKey] = seconds
    }

    /// Drops everything older than `retainedDays`, counting today as one of them. Day keys
    /// (`yyyy-MM-dd`) sort as text exactly as they sort as dates — the same trick `Record.prune`
    /// uses.
    mutating func prune(on now: Date, calendar: Calendar = .current) {
        guard let oldest = calendar.date(byAdding: .day, value: -(Self.retainedDays - 1), to: now) else { return }
        let cutoff = Policy.dayKey(oldest, calendar: calendar)
        days = days.filter { $0.key >= cutoff }
    }

    // MARK: - Reading

    /// One target's fortnight, in whole minutes.
    struct Total: Equatable, Identifiable {
        var id: UUID { targetID }
        var targetID: UUID
        var minutes: Int
        /// 0…1 against the busiest target, so a row can draw a bar without a fixed ceiling.
        var fraction: Double = 0
    }

    /// One day of the fortnight, for a strip of bars.
    struct DayBar: Equatable, Identifiable {
        var id: String { key }
        var key: String
        /// Calendar weekday, 1…7, for the letter under the bar.
        var weekday: Int
        var minutes = 0
        /// 0…1 against the busiest day of the fourteen.
        var fraction: Double = 0
        var isToday = false
    }

    /// Whole minutes for one target on one day. Seconds are rounded down: a target watched for
    /// fifty seconds was not watched for a minute.
    func minutes(for id: UUID, on dayKey: String) -> Int {
        Int((days[dayKey]?[id] ?? 0) / 60)
    }

    /// One target across every day kept. Summed in seconds and rounded once at the end, so a
    /// fortnight of forty-second visits is not fourteen zeroes.
    func minutes(for id: UUID) -> Int {
        Int(days.values.reduce(0) { $0 + ($1[id] ?? 0) } / 60)
    }

    /// Everything measured across every day kept.
    var totalMinutes: Int {
        Int(days.values.reduce(0) { $0 + $1.values.reduce(0, +) } / 60)
    }

    /// How many days actually carry a measurement, so a screen can say how far back it goes
    /// rather than promising a fortnight on its second day.
    var recordedDays: Int { days.values.filter { !$0.isEmpty }.count }

    /// Nothing has been counted yet.
    var isEmpty: Bool { totalMinutes == 0 }

    /// Per target, busiest first, leaving out anything that came to less than a minute. `order`
    /// is the ids worth showing — the config's own targets, so a rule deleted a week ago does
    /// not reappear as a row with no name.
    func totals(for order: [UUID]) -> [Total] {
        var totals = order
            .map { Total(targetID: $0, minutes: minutes(for: $0)) }
            .filter { $0.minutes > 0 }
            .sorted { ($0.minutes, $0.targetID.uuidString) > ($1.minutes, $1.targetID.uuidString) }
        let tallest = totals.first?.minutes ?? 0
        guard tallest > 0 else { return totals }
        for index in totals.indices {
            totals[index].fraction = Double(totals[index].minutes) / Double(tallest)
        }
        return totals
    }

    /// Everything measured over the last `days` days, ending today. Exists so a used figure can
    /// sit beside a held-shut one counted over the same span — the menu bar's trend is seven
    /// days, and "7 hours shut · 9 hours used" over two different spans would be nonsense.
    func minutes(overLast days: Int, upTo now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        var seconds: Double = 0
        for ago in 0..<max(0, days) {
            guard let date = calendar.date(byAdding: .day, value: -ago, to: today) else { continue }
            seconds += self.days[Policy.dayKey(date, calendar: calendar)]?.values.reduce(0, +) ?? 0
        }
        return Int(seconds / 60)
    }

    /// The fortnight as bars, oldest first, ending today. Relative heights for the same reason
    /// the record's week uses them: there is no natural ceiling to scale against.
    func bars(upTo now: Date, calendar: Calendar = .current) -> [DayBar] {
        var bars: [DayBar] = []
        let today = calendar.startOfDay(for: now)
        for ago in stride(from: Self.retainedDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -ago, to: today) else { continue }
            let key = Policy.dayKey(date, calendar: calendar)
            let seconds = days[key]?.values.reduce(0, +) ?? 0
            bars.append(DayBar(
                key: key,
                weekday: Policy.weekday(date, calendar: calendar),
                minutes: Int(seconds / 60),
                isToday: ago == 0
            ))
        }
        let tallest = bars.map(\.minutes).max() ?? 0
        guard tallest > 0 else { return bars }
        for index in bars.indices {
            bars[index].fraction = Double(bars[index].minutes) / Double(tallest)
        }
        return bars
    }

    /// The line under the card: how far back these numbers actually go. Today alone is not a
    /// fortnight and must not say it is.
    var rangeLine: String {
        switch recordedDays {
        case 0: "Nothing measured yet."
        case 1: "Today, on this Mac."
        default: "The last \(recordedDays) days, on this Mac."
        }
    }
}
