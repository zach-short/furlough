import Foundation
import Testing

/// The Mac's measured time, kept rather than thrown away at midnight. Fixed calendar: the 8th
/// is a Tuesday, the 12th a Saturday.
@Suite("Usage history: what the Mac counted")
struct UsageHistoryTests {
    let tiktok = UUID()
    let mail = UUID()

    private func key(_ day: Int) -> String { Policy.dayKey(at(day), calendar: cal) }

    /// Minutes as seconds, which is how the ledger counts.
    private func mins(_ minutes: Double) -> Double { minutes * 60 }

    private func history(_ days: [Int: [UUID: Double]]) -> UsageHistory {
        var history = UsageHistory()
        for (day, seconds) in days { history.record(seconds, on: key(day)) }
        return history
    }

    @Test("a day is filed whole, and filing it again replaces rather than adds")
    func filesADay() {
        var history = UsageHistory()
        history.record([tiktok: mins(30)], on: key(8))
        #expect(history.minutes(for: tiktok, on: key(8)) == 30)
        // A smaller figure for the same day means the day was reset, not continued.
        history.record([tiktok: mins(5)], on: key(8))
        #expect(history.minutes(for: tiktok, on: key(8)) == 5)
        // An empty ledger is not a day worth filing — it would only make `recordedDays` lie.
        history.record([:], on: key(9))
        #expect(history.recordedDays == 1)
    }

    @Test("seconds are rounded once, at the end, not once a day")
    func roundsOnce() {
        // Fifty seconds a day for a fortnight is eleven minutes, not zero.
        var history = UsageHistory()
        for day in 1...14 { history.record([tiktok: 50], on: key(day)) }
        #expect(history.minutes(for: tiktok, on: key(1)) == 0)
        #expect(history.minutes(for: tiktok) == 11)
    }

    @Test("the fortnight totals per target, busiest first, and in all")
    func totals() {
        let history = history([
            8: [tiktok: mins(40), mail: mins(10)],
            9: [tiktok: mins(20)],
            10: [mail: mins(45)],
        ])
        let totals = history.totals(for: [mail, tiktok])
        #expect(totals.map(\.targetID) == [tiktok, mail])
        #expect(totals.map(\.minutes) == [60, 55])
        #expect(totals.first?.fraction == 1)
        #expect(history.totalMinutes == 115)
        #expect(history.recordedDays == 3)
    }

    @Test("a target that is no longer in the config is not a row with no name")
    func onlyWhatTheConfigStillHas() {
        let history = history([8: [tiktok: mins(40), mail: mins(10)]])
        #expect(history.totals(for: [tiktok]).map(\.targetID) == [tiktok])
        // And nothing that came to less than a minute.
        var short = UsageHistory()
        short.record([tiktok: 30], on: key(8))
        #expect(short.totals(for: [tiktok]).isEmpty)
    }

    @Test("fourteen days are kept and the fifteenth is dropped")
    func prunesToAFortnight() {
        var history = UsageHistory()
        for day in 1...20 { history.record([tiktok: mins(10)], on: key(day)) }
        history.prune(on: at(20), calendar: cal)
        #expect(history.recordedDays == UsageHistory.retainedDays)
        // Today counts as one of the fourteen, so the 7th is the oldest kept.
        #expect(history.days[key(7)] != nil)
        #expect(history.days[key(6)] == nil)
    }

    @Test("the fortnight draws as fourteen bars, oldest first, today last")
    func bars() {
        let history = history([12: [tiktok: mins(60)], 14: [tiktok: mins(30)]])
        let bars = history.bars(upTo: at(14, 12, 0), calendar: cal)
        #expect(bars.count == 14)
        #expect(bars.last?.isToday == true)
        #expect(bars.last?.minutes == 30)
        #expect(bars.last?.fraction == 0.5)
        #expect(bars.first?.key == key(1))
        // Heights are against the fortnight's own tallest day, there being no natural ceiling.
        #expect(bars.first(where: { $0.key == key(12) })?.fraction == 1)
    }

    @Test("nothing measured draws fourteen empty bars rather than nothing at all")
    func emptyBars() {
        let bars = UsageHistory().bars(upTo: at(14), calendar: cal)
        #expect(bars.count == 14)
        #expect(bars.allSatisfy { $0.minutes == 0 && $0.fraction == 0 })
        #expect(UsageHistory().isEmpty)
    }

    @Test("a span shorter than the fortnight counts only its own days")
    func aShorterSpan() {
        let history = history([
            14: [tiktok: mins(10)],
            10: [tiktok: mins(20)],
            1: [tiktok: mins(300)],
        ])
        // The menu bar's seven days: the 8th through the 14th, so the 1st is left out.
        #expect(history.minutes(overLast: 7, upTo: at(14, 12, 0), calendar: cal) == 30)
        #expect(history.minutes(overLast: 14, upTo: at(14, 12, 0), calendar: cal) == 330)
        #expect(history.minutes(overLast: 0, upTo: at(14), calendar: cal) == 0)
    }

    @Test("the range line says how far back it really goes, not how far back it could")
    func rangeLine() {
        #expect(UsageHistory().rangeLine == "Nothing measured yet.")
        #expect(history([8: [tiktok: mins(5)]]).rangeLine == "Today, on this Mac.")
        #expect(history([8: [tiktok: mins(5)], 9: [tiktok: mins(5)]]).rangeLine == "The last 2 days, on this Mac.")
    }

    @Test("it survives a round trip, since it is stored as its own JSON")
    func codable() throws {
        let history = history([8: [tiktok: mins(40)], 9: [mail: mins(12)]])
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(UsageHistory.self, from: data) == history)
    }
}
