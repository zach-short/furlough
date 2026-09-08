import Foundation
import Testing

/// A week of use with the same hours every weekday and the same hours every weekend day.
/// `weekdays` and `weekend` map an hour to minutes.
private func histogram(weekdays: [Int: Double], weekend: [Int: Double], pickups: Int = 0) -> UsageHistogram {
    var histogram = UsageHistogram()
    for weekday in 1...7 {
        let hours = Weekdays.weekend.contains(weekday: weekday) ? weekend : weekdays
        for (hour, minutes) in hours {
            histogram.add(weekday: weekday, hour: hour, minutes: minutes, pickups: pickups)
        }
    }
    return histogram
}

private func hourly(_ minutes: [Int: Double]) -> [Double] {
    (0..<24).map { minutes[$0] ?? 0 }
}

@Suite("UsageHistogram")
struct UsageHistogramTests {
    @Test("a fortnight holds each weekday twice, and a part day still counts")
    func daysObserved() {
        let fortnight = DateInterval(start: at(1), end: at(15))
        #expect(UsageHistogram.daysObserved(in: fortnight, calendar: cal) == [2, 2, 2, 2, 2, 2, 2])

        let halfATuesday = DateInterval(start: at(8), end: at(8, 12))
        #expect(UsageHistogram.daysObserved(in: halfATuesday, calendar: cal) == [0, 0, 1, 0, 0, 0, 0])
    }

    @Test("averages divide by the days seen, not the days with use")
    func averages() {
        var histogram = UsageHistogram(daysObserved: [2, 2, 2, 2, 2, 2, 2])
        histogram.add(weekday: 2, hour: 22, minutes: 60, pickups: 3)
        histogram.add(weekday: 3, hour: 22, minutes: 80, pickups: 1)
        #expect(histogram.totalMinutes == 140)
        #expect(histogram.averageDailyMinutes == 10)
        #expect(histogram.pickupsPerDay == 4.0 / 14.0)
        #expect(histogram.hourlyAverage(on: .weekdays)[22] == 14)
        #expect(histogram.hourlyAverage(on: .weekend)[22] == 0)
    }

    @Test("off-the-clock samples and a second device")
    func addAndMerge() {
        var histogram = UsageHistogram()
        histogram.add(weekday: 0, hour: 5, minutes: 10)
        histogram.add(weekday: 3, hour: 24, minutes: 10)
        histogram.add(weekday: 3, hour: 5, minutes: -10)
        #expect(histogram.totalMinutes == 0)

        histogram.add(weekday: 3, hour: 5, minutes: 10)
        var other = UsageHistogram()
        other.add(weekday: 3, hour: 5, minutes: 5, pickups: 2)
        histogram.merge(other)
        #expect(histogram.totalMinutes == 15)
        #expect(histogram.pickups == 2)
    }

    @Test("late-night share")
    func lateShare() {
        let h = histogram(weekdays: [22: 30, 12: 10], weekend: [:])
        #expect(abs(h.share(of: UsageAnalysis.lateHours) - 0.75) < 1e-9)
        #expect(UsageHistogram().share(of: UsageAnalysis.lateHours) == 0)
    }
}

@Suite("UsageAnalysis")
struct UsageAnalysisTests {
    @Test("the peak is the shortest fullest run, and it may wrap past midnight")
    func peakWraps() {
        // 130 minutes; 60 % is 78. No two hours reach it; 10 PM to 1 AM holds 100, 11 PM to 2 AM 90.
        let peak = UsageAnalysis.peak(in: hourly([22: 30, 23: 40, 0: 30, 1: 20, 12: 5, 18: 5]))
        #expect(peak == TimeWindow(startMinute: 22 * 60, endMinute: 60))
        #expect(peak?.isNight == true)
        #expect(peak.map(UsageAnalysis.hours(of:)) == [22, 23, 0])
    }

    @Test("a peak that ends at midnight ends at 1440, and one hour can be enough")
    func peakEdges() {
        #expect(UsageAnalysis.peak(in: hourly([22: 30, 23: 30, 10: 10])) == TimeWindow(startMinute: 22 * 60, endMinute: Furlough.minutesPerDay))
        #expect(UsageAnalysis.peak(in: hourly([14: 60, 15: 30])) == TimeWindow(startMinute: 14 * 60, endMinute: 15 * 60))
        #expect(UsageAnalysis.hours(of: TimeWindow(startMinute: 0, endMinute: 180)) == [0, 1, 2])
        #expect(UsageAnalysis.hours(of: Rule.allDay).count == 24)
    }

    @Test("no use has no peak; use spread evenly needs most of the day")
    func peakSpread() {
        #expect(UsageAnalysis.peak(in: hourly([:])) == nil)
        #expect(UsageAnalysis.peak(in: [Double](repeating: 1, count: 23)) == nil)
        let flat = UsageAnalysis.peak(in: [Double](repeating: 10, count: 24))
        #expect(flat?.spanMinutes == 15 * 60)
        #expect(flat?.spanMinutes ?? 0 > UsageAnalysis.longestPeakMinutes)
    }

    @Test("closing hours opens the rest of the day, in rows shared by days alike")
    func windows() {
        var closed = [Set<Int>](repeating: [22, 23], count: 7)
        #expect(UsageAnalysis.windows(closing: closed) == [window(0, 22 * 60)])

        closed = [Set<Int>](repeating: [22, 23, 0, 1], count: 7)
        for weekday in [1, 7] { closed[weekday - 1] = [14] }
        #expect(UsageAnalysis.windows(closing: closed) == [
            window(0, 14 * 60, .weekend),
            window(2 * 60, 22 * 60, .weekdays),
            window(15 * 60, Furlough.minutesPerDay, .weekend),
        ])

        #expect(UsageAnalysis.windows(closing: [Set<Int>](repeating: [], count: 7)) == [])
        #expect(UsageAnalysis.openRuns(closing: [22, 23, 0, 1]) == [2..<22])
        #expect(UsageAnalysis.openRuns(closing: Set(0..<24)) == [])
    }

    @Test("the budget keeps half, rounds down to five, and stays on the clock")
    func budget() {
        #expect(UsageAnalysis.budget(forDailyMinutes: 82.86) == 40)
        #expect(UsageAnalysis.budget(forDailyMinutes: 7) == 5)
        #expect(UsageAnalysis.budget(forDailyMinutes: 3000) == Furlough.minutesPerDay)
    }

    @Test("late school nights and weekend afternoons become one rule")
    func recommendation() throws {
        let h = histogram(weekdays: [22: 30, 23: 30, 0: 20], weekend: [14: 60, 15: 30], pickups: 2)
        let advice = try #require(UsageAnalysis.recommendation(key: "com.example.reels", name: "Reels", histogram: h))

        #expect(abs(advice.averageDailyMinutes - 580.0 / 7.0) < 1e-9)
        // Two pickups per sampled hour: three hours on each of five weekdays, two on each weekend day.
        #expect(abs(advice.pickupsPerDay - 38.0 / 7.0) < 1e-9)
        #expect(abs(advice.lateNightShare - 400.0 / 580.0) < 1e-9)
        #expect(advice.peaks == [
            Recommendation.Peak(days: .weekdays, window: window(22 * 60, Furlough.minutesPerDay)),
            Recommendation.Peak(days: .weekend, window: window(14 * 60, 15 * 60)),
        ])
        #expect(advice.rule.dailyBudgetMinutes == 40)
        #expect(advice.rule.windows == [
            window(0, 14 * 60, .weekend),
            window(0, 22 * 60, .weekdays),
            window(15 * 60, Furlough.minutesPerDay, .weekend),
        ])
        #expect(advice.rule.validationError == nil)
    }

    @Test("use spread all day gets a budget and no windows; too little use gets nothing")
    func recommendationEdges() throws {
        var flat = UsageHistogram()
        for weekday in 1...7 {
            for hour in 0..<24 { flat.add(weekday: weekday, hour: hour, minutes: 5) }
        }
        let advice = try #require(UsageAnalysis.recommendation(key: "com.example.flat", name: "Flat", histogram: flat))
        #expect(advice.peaks.isEmpty)
        #expect(advice.rule.isAllDay)
        #expect(advice.rule.dailyBudgetMinutes == 60)

        let little = histogram(weekdays: [12: 5], weekend: [12: 5])
        #expect(UsageAnalysis.recommendation(key: "com.example.little", name: "Little", histogram: little) == nil)
    }

    @Test("ranking puts the heaviest first, breaks ties by key, and stops at the limit")
    func rank() {
        let heavy = histogram(weekdays: [20: 60], weekend: [20: 60])
        let light = histogram(weekdays: [20: 20], weekend: [20: 20])
        let none = histogram(weekdays: [20: 1], weekend: [20: 1])
        let ranked = UsageAnalysis.rank([
            (key: "b", name: "B", histogram: light),
            (key: "c", name: "C", histogram: none),
            (key: "a", name: "A", histogram: light),
            (key: "z", name: "Z", histogram: heavy),
        ])
        #expect(ranked.map(\.key) == ["z", "a", "b"])
        #expect(UsageAnalysis.rank([(key: "z", name: "Z", histogram: heavy), (key: "a", name: "A", histogram: light)], limit: 1).map(\.key) == ["z"])
    }
}
