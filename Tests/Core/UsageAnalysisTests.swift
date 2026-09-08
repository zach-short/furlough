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

    @Test("a peak too wide to close leaves only a budget")
    func peakTooWideToClose() throws {
        // Twenty minutes an hour from 7 AM to 6 PM: 60 % of it needs eight hours, and "closed
        // 7 AM to 3 PM" is not a suggestion anybody takes.
        var spread: [Int: Double] = [:]
        for hour in 7...18 { spread[hour] = 20 }
        #expect((UsageAnalysis.peak(in: hourly(spread))?.spanMinutes ?? 0) > UsageAnalysis.longestPeakMinutes)

        let advice = try #require(UsageAnalysis.recommendation(
            key: "com.example.scroll",
            name: "Scroll",
            histogram: histogram(weekdays: spread, weekend: spread)
        ))
        #expect(advice.peaks.isEmpty)
        #expect(advice.isBudgetOnly)
        #expect(advice.rule.isAllDay)
        #expect(advice.rule.dailyBudgetMinutes == 120)
    }

    @Test("a peak too wide to close becomes a bedtime when most of it is late")
    func bedtime() throws {
        // Eleven minutes in each late hour and nine in each of 4 PM to 10 PM: the run holding
        // 60 % is seven hours long, too wide to suggest, but 55 % of it lands after 10 PM.
        var owl: [Int: Double] = [:]
        for hour in UsageAnalysis.lateHours { owl[hour] = 11 }
        for hour in 16...21 { owl[hour] = 9 }
        #expect(UsageAnalysis.share(of: UsageAnalysis.lateHours, in: hourly(owl)) >= UsageAnalysis.bedtimeShare)
        #expect((UsageAnalysis.peak(in: hourly(owl))?.spanMinutes ?? 0) > UsageAnalysis.longestPeakMinutes)

        let advice = try #require(UsageAnalysis.recommendation(
            key: "com.example.owl",
            name: "Owl",
            histogram: histogram(weekdays: owl, weekend: owl)
        ))
        // Both groups came out the same, so the suggestion says it once.
        #expect(advice.peaks == [Recommendation.Peak(days: .all, window: UsageAnalysis.bedtime)])
        #expect(advice.rule.windows == [window(4 * 60, 22 * 60)])
        #expect(advice.rule.dailyBudgetMinutes == 60)
    }

    @Test("the late share of one day group, and the runs a strip draws")
    func sharesAndRuns() {
        #expect(UsageAnalysis.share(of: [22, 23], in: hourly([22: 30, 12: 10])) == 0.75)
        #expect(UsageAnalysis.share(of: [22], in: hourly([:])) == 0)
        #expect(UsageAnalysis.runs(of: [22, 23, 0, 1]) == [0..<2, 22..<24])
        #expect(UsageAnalysis.runs(of: []) == [])
        #expect(UsageAnalysis.runs(of: Set(0..<24)) == [0..<24])
    }
}

/// The two sentences a card says. Every one of them is checked whole, through `plainSpaces`,
/// because a card is only as good as the line a stranger reads off it.
@Suite("Suggestions in words")
struct UsageWordsTests {
    private func advice(_ peaks: [Recommendation.Peak], budget: Int = 35) -> Recommendation {
        Recommendation(
            key: "com.example.app",
            name: "App",
            averageDailyMinutes: 90,
            pickupsPerDay: 12,
            lateNightShare: 0.2,
            peaks: peaks,
            rule: Rule(windows: [], dailyBudgetMinutes: budget)
        )
    }

    @Test("one pile leads with the part of the day it falls in")
    func onePeak() {
        let evenings = advice([Recommendation.Peak(days: .weekend, window: window(19 * 60, 23 * 60))])
        #expect(plainSpaces(evenings.whereLine(calendar: cal)) == "Mostly evenings: 7 PM to 11 PM on weekends.")
        #expect(plainSpaces(evenings.consequence(calendar: cal)) == "Closed 7 PM to 11 PM on weekends, and 35 min a day the rest of the time.")

        let nights = advice([Recommendation.Peak(days: .all, window: UsageAnalysis.bedtime)])
        #expect(plainSpaces(nights.whereLine(calendar: cal)) == "Mostly late nights: 10 PM to 4 AM every day.")
        #expect(plainSpaces(nights.consequence(calendar: cal)) == "Closed 10 PM to 4 AM every day, and 35 min a day the rest of the time.")
    }

    @Test("two piles let the hours carry the sentence")
    func twoPeaks() {
        let item = advice([
            Recommendation.Peak(days: .weekdays, window: window(21 * 60, 23 * 60)),
            Recommendation.Peak(days: .weekend, window: window(14 * 60, 18 * 60)),
        ], budget: 60)
        #expect(plainSpaces(item.whereLine(calendar: cal)) == "Mostly 9 PM to 11 PM on weekdays, and 2 PM to 6 PM on weekends.")
        #expect(plainSpaces(item.consequence(calendar: cal))
            == "Closed 9 PM to 11 PM on weekdays and 2 PM to 6 PM on weekends, and 1 hour a day the rest of the time.")
    }

    @Test("nothing to close says so, and offers the budget alone")
    func budgetOnly() {
        let item = advice([], budget: 45)
        #expect(item.isBudgetOnly)
        #expect(item.whereLine(calendar: cal) == "Spread through the day; no one stretch stands out.")
        #expect(item.consequence(calendar: cal) == "45 min a day, whenever you like.")
    }

    @Test("midnight and noon are words, and a window is read by its middle")
    func clockWords() {
        #expect(TimeFormat.hour(0, calendar: cal) == "midnight")
        #expect(TimeFormat.hour(Furlough.minutesPerDay, calendar: cal) == "midnight")
        #expect(TimeFormat.hour(12 * 60, calendar: cal) == "noon")
        #expect(plainSpaces(TimeFormat.hour(19 * 60, calendar: cal)) == "7 PM")
        #expect(plainSpaces(TimeFormat.span(window(22 * 60, Furlough.minutesPerDay), calendar: cal)) == "10 PM to midnight")
        #expect(TimeFormat.onDays(.all, calendar: cal) == "every day")
        #expect(TimeFormat.onDays(.weekdays, calendar: cal) == "on weekdays")
        #expect(TimeFormat.onDays([.monday, .tuesday, .wednesday], calendar: cal) == "on Mon–Wed")

        #expect(UsageAnalysis.partOfDay(window(8 * 60, 11 * 60)) == "mornings")
        #expect(UsageAnalysis.partOfDay(window(13 * 60, 16 * 60)) == "afternoons")
        #expect(UsageAnalysis.partOfDay(window(19 * 60, 23 * 60)) == "evenings")
        #expect(UsageAnalysis.partOfDay(UsageAnalysis.bedtime) == "late nights")
    }
}

/// The rows a card draws: one when the week is treated alike, two when it is not.
@Suite("Usage card rows")
struct UsageRowTests {
    @Test("identical hours draw one row; different hours draw two")
    func rows() {
        let everyDay = Recommendation(
            key: "k", name: "K", averageDailyMinutes: 60, pickupsPerDay: 1, lateNightShare: 0.6,
            peaks: [Recommendation.Peak(days: .all, window: UsageAnalysis.bedtime)],
            rule: Rule(windows: [], dailyBudgetMinutes: 30)
        )
        #expect(UsageRow.rows(for: everyDay).map(\.label) == ["Every day"])
        #expect(UsageRow.rows(for: everyDay).first?.closed == UsageAnalysis.lateHours)

        let split = Recommendation(
            key: "k", name: "K", averageDailyMinutes: 60, pickupsPerDay: 1, lateNightShare: 0.1,
            peaks: [
                Recommendation.Peak(days: .weekdays, window: window(21 * 60, 23 * 60)),
                Recommendation.Peak(days: .weekend, window: window(14 * 60, 16 * 60)),
            ],
            rule: Rule(windows: [], dailyBudgetMinutes: 30)
        )
        #expect(UsageRow.rows(for: split).map(\.label) == ["Weekdays", "Weekends"])
        #expect(UsageRow.rows(for: split).map(\.closed) == [[21, 22], [14, 15]])

        #expect(UsageRow.rows(for: nil).map(\.closed) == [[]])
    }
}
