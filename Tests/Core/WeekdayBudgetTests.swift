import Foundation
import Testing

/// Per-weekday budgets: `Rule.budgetByWeekday`, seven figures Sunday first, and everything
/// that used to read one budget now reading today's.
///
/// September 2026 in `cal`: the 6th is a Sunday and the 12th a Saturday, so the 7th is a
/// Monday (Calendar weekday 2) and the 8th a Tuesday (weekday 3).
@Suite("Per-weekday budgets")
struct WeekdayBudgetTests {
    /// Five minutes on Monday, two hours on Saturday, thirty everywhere else. The week the
    /// hand-back asks for, and the one most of these tests are about.
    let mixed = Rule(
        windows: [window(20 * 60, 22 * 60)],
        dailyBudgetMinutes: 30,
        budgetByWeekday: [30, 5, 30, 30, 30, 30, 120]
    )

    @Test("a week of seven figures answers each day its own, and a rule without one answers the same every day")
    func budgetOnWeekday() {
        #expect(mixed.budget(on: 2) == 5)
        #expect(mixed.budget(on: 7) == 120)
        #expect(mixed.budget(on: 3) == 30)
        let flat = Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 45)
        #expect((1...7).allSatisfy { flat.budget(on: $0) == 45 })
    }

    @Test("out of range weekdays fall back to the one figure rather than trapping")
    func outOfRangeWeekday() {
        #expect(mixed.budget(on: 0) == 30)
        #expect(mixed.budget(on: 8) == 30)
    }

    @Test("a week that says one thing seven times is the same rule as one that says it once")
    func sameBudgetEveryDay() {
        let seven = Rule(windows: [], dailyBudgetMinutes: 30, budgetByWeekday: [Int](repeating: 30, count: 7))
        let one = Rule(windows: [], dailyBudgetMinutes: 30)
        #expect(seven.isSameBudgetEveryDay)
        #expect(one.isSameBudgetEveryDay)
        #expect(!mixed.isSameBudgetEveryDay)
        #expect(seven.isEquivalent(to: one))
        #expect(seven.normalized == one)
        #expect(seven.normalized.budgetByWeekday == nil)
    }

    @Test("normalizing a week that really varies leaves it alone")
    func normalizeKeepsAVaryingWeek() {
        #expect(mixed.normalized == mixed)
        #expect(mixed.normalized.budgetByWeekday != nil)
    }

    // MARK: What a day with no budget means

    @Test("a day worth no minutes has no open hours, and the rule still opens on the days that do")
    func zeroBudgetDayIsClosed() {
        let schoolNights = Rule(
            windows: [window(20 * 60, 22 * 60)],
            dailyBudgetMinutes: 60,
            budgetByWeekday: [60, 0, 0, 0, 0, 0, 60]
        )
        #expect(schoolNights.windows(on: 2).isEmpty)
        #expect(schoolNights.windows(on: 1) == [window(20 * 60, 22 * 60)])
        #expect(!schoolNights.isEverAllowed(on: 2))
        #expect(schoolNights.isEverAllowed(on: 1))
        // Never allowed *at all* is still the category's answer, and this is not that.
        #expect(schoolNights.isEverAllowed)
        #expect(schoolNights.allowedMask(on: 2).allSatisfy { !$0 })
    }

    @Test("a Monday worth nothing reads as closed until the next day that is worth something")
    func statusSkipsAZeroDay() {
        let rule = Rule(
            windows: [window(20 * 60, 22 * 60)],
            dailyBudgetMinutes: 60,
            budgetByWeekday: [60, 0, 60, 60, 60, 60, 60]
        )
        let target = makeTarget("YouTube", rule: rule)
        let config = makeConfig([target])
        // Monday the 7th, 8:30 PM: inside the hours, but the day is worth nothing.
        let status = Policy.status(of: target, config: config, runtime: RuntimeState(), now: at(7, 20, 30), calendar: cal)
        #expect(status == .closed(nextOpen: NextOpen(minuteOfDay: 20 * 60, daysAhead: 1)))
        // Tuesday the 8th, same hour: open.
        let tuesday = Policy.status(of: target, config: config, runtime: RuntimeState(), now: at(8, 20, 30), calendar: cal)
        #expect(tuesday == .open(until: 22 * 60))
    }

    @Test("a week worth nothing on every day is still blocked all day")
    func everyDayZeroIsBlockedAllDay() {
        let rule = Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 30, budgetByWeekday: [Int](repeating: 0, count: 7))
        let target = makeTarget("Games", rule: rule)
        #expect(!rule.isEverAllowed)
        let status = Policy.status(of: target, config: makeConfig([target]), runtime: RuntimeState(), now: at(8, 20, 30), calendar: cal)
        #expect(status == .blockedAllDay)
    }

    @Test("a Saturday night stops at midnight when the Sunday it runs into is worth nothing")
    func nightIntoAZeroDay() {
        // 5 PM Saturday until 4 AM Sunday, stored as the two halves Furlough keeps.
        let rule = Rule(
            windows: window(17 * 60, 4 * 60, .saturday).split,
            dailyBudgetMinutes: 60,
            budgetByWeekday: [0, 60, 60, 60, 60, 60, 60]
        )
        // Saturday the 12th at 11 PM: the morning half is on a Sunday worth nothing, so the
        // night is not joined and the window really does shut at midnight.
        #expect(rule.continuation(after: 7) == nil)
        let target = makeTarget("TikTok", rule: rule)
        let saturday = Policy.status(of: target, config: makeConfig([target]), runtime: RuntimeState(), now: at(12, 23), calendar: cal)
        #expect(saturday == .open(until: Furlough.minutesPerDay))
        // And 1 AM on that Sunday is shut, not the tail of the night before. The next open is
        // the following Saturday evening, six days out: Sunday's own morning half is worth
        // nothing, and no other day carries hours at all.
        let sunday = Policy.status(of: target, config: makeConfig([target]), runtime: RuntimeState(), now: at(13, 1), calendar: cal)
        #expect(sunday == .closed(nextOpen: NextOpen(minuteOfDay: 17 * 60, daysAhead: 6)))
        #expect(rule.continues(into: 1) == nil)
    }

    @Test("a night whose morning is worth something still reads as one window past midnight")
    func nightIntoADayWorthSomething() {
        let rule = Rule(
            windows: window(17 * 60, 4 * 60, .saturday).split,
            dailyBudgetMinutes: 60,
            budgetByWeekday: [Int](repeating: 60, count: 7)
        )
        let target = makeTarget("TikTok", rule: rule)
        let saturday = Policy.status(of: target, config: makeConfig([target]), runtime: RuntimeState(), now: at(12, 23), calendar: cal)
        #expect(saturday == .open(until: Furlough.minutesPerDay + 4 * 60))
    }

    @Test("when only one weekday is worth anything, the next open is a week out")
    func nextOpenAWeekAhead() {
        let saturdaysOnly = Rule(
            windows: [window(10 * 60, 12 * 60)],
            dailyBudgetMinutes: 60,
            budgetByWeekday: [0, 0, 0, 0, 0, 0, 60]
        )
        #expect(Policy.nextOpen(in: saturdaysOnly, afterWeekday: 7) == NextOpen(minuteOfDay: 10 * 60, daysAhead: 7))
        #expect(Policy.nextOpen(in: saturdaysOnly, afterWeekday: 1) == NextOpen(minuteOfDay: 10 * 60, daysAhead: 6))
    }

    @Test("the editor collapsing seven sliders back to one offers the week's ordinary day")
    func representativeBudget() {
        // Mon 5, Sat 120, 30 on the other five: 30 is the figure the week is really about,
        // not the shadow `dailyBudgetMinutes`, which an imported rule can set to anything.
        let imported = Rule(windows: [], dailyBudgetMinutes: 1440, budgetByWeekday: [30, 5, 30, 30, 30, 30, 120])
        #expect(imported.representativeBudget == 30)
        // A tie goes to the smaller, so collapsing never quietly buys minutes.
        let tied = Rule(windows: [], dailyBudgetMinutes: 999, budgetByWeekday: [15, 15, 15, 60, 60, 60, 90])
        #expect(tied.representativeBudget == 15)
        // Without a per-day budget the one figure is still the answer.
        #expect(Rule(windows: [], dailyBudgetMinutes: 45).representativeBudget == 45)
    }

    // MARK: Tightening and loosening

    @Test("a smaller budget on one day is a tightening, a larger one on any day is a loosening")
    func tighteningIsDayByDay() {
        let flat = Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 30)
        let mondayCut = Rule(
            windows: [window(20 * 60, 22 * 60)],
            dailyBudgetMinutes: 30,
            budgetByWeekday: [30, 5, 30, 30, 30, 30, 30]
        )
        #expect(mondayCut.isTighterOrEqual(to: flat))
        #expect(!flat.isTighterOrEqual(to: mondayCut))
        #expect(Policy.classify(newRule: mondayCut, against: makeTarget("YouTube", rule: flat)) == .tightening)
        #expect(Policy.classify(newRule: flat, against: makeTarget("YouTube", rule: mondayCut)) == .loosening)
    }

    @Test("a week the same size but rearranged is a loosening, because one day got longer")
    func movingMinutesBetweenDaysLoosens() {
        // 30 every day, and the same 210 minutes with Saturday's hour moved onto Monday.
        let flat = Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 30)
        let moved = Rule(
            windows: [window(20 * 60, 22 * 60)],
            dailyBudgetMinutes: 30,
            budgetByWeekday: [30, 60, 30, 30, 30, 30, 0]
        )
        #expect(moved.budgetByWeekday?.reduce(0, +) == 210)
        #expect(!moved.isTighterOrEqual(to: flat))
        #expect(Policy.classify(newRule: moved, against: makeTarget("YouTube", rule: flat)) == .loosening)
    }

    @Test("splitting a week without changing any day is neither, so nothing queues")
    func sevenEqualDaysIsNoChange() {
        let flat = Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 30)
        let split = Rule(
            windows: [window(20 * 60, 22 * 60)],
            dailyBudgetMinutes: 30,
            budgetByWeekday: [Int](repeating: 30, count: 7)
        )
        #expect(split.isEquivalent(to: flat))
        #expect(split.isTighterOrEqual(to: flat))
        #expect(flat.isTighterOrEqual(to: split))
    }

    // MARK: The monitor's side

    @Test("every distinct budget in the week is registered, and the equal days share one event")
    func distinctBudgetsRegistered() {
        // What `Monitoring.register` collects: one event name per distinct effective budget.
        let names = Set((1...7).map { mixed.effectiveBudget(on: $0) })
            .filter { $0 > 0 }
            .map { ActivityNaming.budgetEvent(targetID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!, minutes: $0) }
        #expect(names.count == 3)
        #expect(names.contains("budget:00000000-0000-0000-0000-0000000000AB:5"))
        #expect(names.contains("budget:00000000-0000-0000-0000-0000000000AB:30"))
        #expect(names.contains("budget:00000000-0000-0000-0000-0000000000AB:120"))
    }

    @Test("a day with no budget contributes no event, and a day with no hours contributes none either")
    func noEventForADayWorthNothing() {
        let weekendOnly = Rule(
            windows: [window(10 * 60, 12 * 60, .weekend)],
            dailyBudgetMinutes: 60,
            budgetByWeekday: [60, 0, 0, 0, 0, 0, 60]
        )
        // Monday has neither hours nor budget; Sunday and Saturday have both.
        #expect(weekendOnly.effectiveBudget(on: 2) == 0)
        #expect(weekendOnly.effectiveBudget(on: 1) == 60)
        #expect(Set((1...7).map { weekendOnly.effectiveBudget(on: $0) }).filter { $0 > 0 } == [60])
    }

    @Test("the monitor keeps another day's threshold out: 30 on a five-minute Monday, 5 on a two-hour Saturday")
    func thresholdsAreJudgedAgainstToday() {
        // `eventDidReachThreshold` exhausts when the fired minutes are at or above today's
        // budget, and logs the rest as stale. Monday is worth 5 and Saturday 120.
        func exhausts(_ fired: Int, on weekday: Int) -> Bool { fired >= mixed.effectiveBudget(on: weekday) }
        #expect(exhausts(5, on: 2))
        #expect(exhausts(30, on: 2))
        #expect(!exhausts(5, on: 7))
        #expect(exhausts(120, on: 7))
        // `eventWillReachThresholdWarning` is exact, so only the day's own budget warns: a
        // Monday must not get its five-minute warning off the weekend's larger event.
        func warns(_ fired: Int, on weekday: Int) -> Bool { fired == mixed.effectiveBudget(on: weekday) }
        #expect(warns(5, on: 2))
        #expect(!warns(30, on: 2))
        #expect(warns(120, on: 7))
        #expect(!warns(30, on: 7))
    }

    // MARK: What it reads as

    /// The weekend leads because `cal` starts its week on Sunday and groups are ordered by
    /// their earliest day — the same `groupOrder` that orders the hours half of the very same
    /// sentence. Both halves of a rule line read in one order, whichever day a calendar starts on.
    @Test("two groups read as one phrase, and three fall back to varies by day")
    func budgetGrammar() {
        let weekdaysAndWeekends = Rule(
            windows: [],
            dailyBudgetMinutes: 30,
            budgetByWeekday: [120, 30, 30, 30, 30, 30, 120]
        )
        #expect(TimeFormat.budgets(weekdaysAndWeekends, calendar: cal) == "2 hours weekends, 30 min weekdays")
        #expect(TimeFormat.budgets(mixed, calendar: cal) == "varies by day")
        let flat = Rule(windows: [], dailyBudgetMinutes: 30)
        #expect(TimeFormat.budgets(flat, calendar: cal) == "30 min/day")
        #expect(TimeFormat.budgets(.unrestricted, calendar: cal) == nil)
    }

    @Test("a day with no limit is said as one rather than as 24 hours of budget")
    func noLimitOnSomeDays() {
        let looseWeekends = Rule(
            windows: [],
            dailyBudgetMinutes: 30,
            budgetByWeekday: [1440, 30, 30, 30, 30, 30, 1440]
        )
        #expect(TimeFormat.budgets(looseWeekends, calendar: cal) == "no limit weekends, 30 min weekdays")
    }

    @Test("the rule line carries the week's budgets after its hours")
    func ruleLine() {
        let rule = Rule(
            windows: [window(20 * 60, 22 * 60)],
            dailyBudgetMinutes: 30,
            budgetByWeekday: [120, 30, 30, 30, 30, 30, 120]
        )
        #expect(plainSpaces(TimeFormat.rule(rule, calendar: cal))
            == "8:00 PM–10:00 PM · 2 hours weekends, 30 min weekdays")
    }

    @Test("the shield names today's budget, and the day it opens on when it is shut")
    func shieldSaysTheRightDay() {
        // Monday the 7th: worth 5 minutes, and Tuesday is worth 30.
        let exhausted = ShieldText.text(
            name: "YouTube",
            status: .exhausted(nextOpen: NextOpen(minuteOfDay: 20 * 60, daysAhead: 1)),
            rule: mixed,
            now: at(7, 22, 30),
            calendar: cal
        )
        #expect(exhausted.subtitle.contains("5 min"))
        let closed = ShieldText.text(
            name: "YouTube",
            status: .closed(nextOpen: NextOpen(minuteOfDay: 20 * 60, daysAhead: 1)),
            rule: mixed,
            now: at(7, 10),
            calendar: cal
        )
        #expect(closed.subtitle == "You get 30 min per day.")
    }

    // MARK: Stored state

    @Test("a stored rule from before per-weekday budgets reads as the same budget every day")
    func decodesOldRules() throws {
        let rule = try JSONDecoder().decode(Rule.self, from: Data(#"{"windows":[],"dailyBudgetMinutes":30}"#.utf8))
        #expect(rule.budgetByWeekday == nil)
        #expect(rule.isSameBudgetEveryDay)
        #expect((1...7).allSatisfy { rule.budget(on: $0) == 30 })
    }

    @Test("a per-weekday budget survives a round trip, and is left out of the file when there is none")
    func roundTrips() throws {
        let data = try JSONEncoder().encode(mixed)
        #expect(String(decoding: data, as: UTF8.self).contains("budgetByWeekday"))
        #expect(try JSONDecoder().decode(Rule.self, from: data) == mixed)
        let flat = Rule(windows: [], dailyBudgetMinutes: 30)
        let flatJSON = String(decoding: try JSONEncoder().encode(flat), as: UTF8.self)
        #expect(!flatJSON.contains("budgetByWeekday"))
    }

    @Test("a list that is not seven long is read as no per-weekday budget at all")
    func tolerantDecoding() throws {
        let short = try JSONDecoder().decode(
            Rule.self,
            from: Data(#"{"windows":[],"dailyBudgetMinutes":30,"budgetByWeekday":[10,20,30]}"#.utf8)
        )
        #expect(short.budgetByWeekday == nil)
        #expect(short.budget(on: 2) == 30)
        let wrongType = try JSONDecoder().decode(
            Rule.self,
            from: Data(#"{"windows":[],"dailyBudgetMinutes":30,"budgetByWeekday":"every day"}"#.utf8)
        )
        #expect(wrongType.budgetByWeekday == nil)
        #expect(wrongType.budget(on: 2) == 30)
    }

    @Test("an imported week outside the range is refused a day at a time")
    func importRefusesABadDay() {
        let bad = Rule(windows: [], dailyBudgetMinutes: 30, budgetByWeekday: [30, 30, 30, 5000, 30, 30, 30])
        #expect(ConfigImport.problem(with: bad) != nil)
        let negative = Rule(windows: [], dailyBudgetMinutes: 30, budgetByWeekday: [30, 30, 30, -1, 30, 30, 30])
        #expect(ConfigImport.problem(with: negative) != nil)
        #expect(ConfigImport.problem(with: mixed) == nil)
    }
}
