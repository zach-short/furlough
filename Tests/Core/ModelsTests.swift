import Foundation
import Testing

@Suite("Weekdays")
struct WeekdaysTests {
    @Test("ordered follows the calendar's first day")
    func ordered() {
        #expect(Weekdays.ordered(calendar: fixedCalendar(firstWeekday: 1)) == [1, 2, 3, 4, 5, 6, 7])
        #expect(Weekdays.ordered(calendar: fixedCalendar(firstWeekday: 2)) == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test("the earliest day depends on where the week starts")
    func firstPosition() {
        let sundayFirst = fixedCalendar(firstWeekday: 1)
        let mondayFirst = fixedCalendar(firstWeekday: 2)
        #expect(Weekdays.weekend.firstPosition(calendar: sundayFirst) == 0)
        #expect(Weekdays.weekend.firstPosition(calendar: mondayFirst) == 5)
        #expect(Weekdays.weekdays.firstPosition(calendar: sundayFirst) == 1)
        #expect(Weekdays.weekdays.firstPosition(calendar: mondayFirst) == 0)
        #expect(Weekdays(rawValue: 0).firstPosition(calendar: sundayFirst) == 7)
    }

    @Test("groups sort by earliest day, then by how broad they are")
    func groupOrder() {
        let sundayFirst = fixedCalendar(firstWeekday: 1)
        let mondayFirst = fixedCalendar(firstWeekday: 2)
        let groups: [Weekdays] = [.weekend, .all, .weekdays]

        #expect(groups.sorted { $0.groupOrder(calendar: sundayFirst) < $1.groupOrder(calendar: sundayFirst) }
                == [.all, .weekend, .weekdays])
        #expect(groups.sorted { $0.groupOrder(calendar: mondayFirst) < $1.groupOrder(calendar: mondayFirst) }
                == [.all, .weekdays, .weekend])
        // "Every day" is broader than the weekend, and both start on Sunday there.
        #expect(Weekdays.all.groupOrder(calendar: sundayFirst).1 == -7)
        #expect(Weekdays.weekend.groupOrder(calendar: sundayFirst).1 == -2)
    }

    @Test("weekday numbers are Calendar's, whatever the first day")
    func bits() {
        #expect(Weekdays.sunday.rawValue == 1)
        #expect(Weekdays.saturday.rawValue == 64)
        #expect(Weekdays(weekday: 0).isEmpty)
        #expect(Weekdays(weekday: 8).isEmpty)
        #expect(Weekdays.all.count == 7)
        var days = Weekdays.weekdays
        days.toggle(weekday: 2)
        #expect(!days.contains(weekday: 2))
        #expect(days.count == 4)
    }
}

@Suite("TimeWindow")
struct TimeWindowTests {
    @Test("windows on the same days that overlap or touch become one")
    func joined() {
        #expect(TimeWindow.joined([window(540, 600), window(600, 660)]) == [window(540, 660)])
        #expect(TimeWindow.joined([window(0, 120), window(60, 180)]) == [window(0, 180)])
        #expect(TimeWindow.joined([window(0, 600), window(100, 200)]) == [window(0, 600)])
        #expect(TimeWindow.joined([window(600, 660), window(540, 600)]) == [window(540, 660)])
    }

    @Test("windows on different days are left alone")
    func joinedAcrossDays() {
        let evening = window(1200, 1320, .weekdays)
        let late = window(1320, 1380, .weekend)
        #expect(TimeWindow.joined([late, evening]) == [evening, late])
    }

    @Test("a gap keeps two windows apart")
    func joinedWithGap() {
        #expect(TimeWindow.joined([window(540, 600), window(601, 660)]) == [window(540, 600), window(601, 660)])
    }

    @Test("a new window lands after the last one, or in the first free stretch")
    func nextFree() {
        #expect(TimeWindow.nextFree(after: [], on: .all) == window(720, 780))
        #expect(TimeWindow.nextFree(after: [window(1200, 1320)], on: .all) == window(1320, 1380))
        // A window that runs to midnight leaves only the morning.
        #expect(TimeWindow.nextFree(after: [window(120, 1440)], on: .all) == window(0, 60))
        // Windows on other days do not count.
        #expect(TimeWindow.nextFree(after: [window(0, 1440, .weekend)], on: .weekdays) == window(720, 780, .weekdays))
    }

    @Test("a full day has nowhere for a new window")
    func nextFreeWhenFull() {
        #expect(TimeWindow.nextFree(after: [window(0, 1440)], on: .all) == nil)
        // Only ten free minutes, which is under the minimum.
        #expect(TimeWindow.nextFree(after: [window(0, 700), window(710, 1440)], on: .all) == nil)
    }

    @Test("windows collide only when they share a day")
    func collides() {
        #expect(window(1200, 1320).collides(with: window(1260, 1380)))
        #expect(!window(1200, 1320, .weekdays).collides(with: window(1260, 1380, .weekend)))
        #expect(window(1200, 1320, .all).collides(with: window(1260, 1380, .weekend)))
        // Touching is not overlapping: one ends where the next begins.
        #expect(!window(1200, 1320).collides(with: window(1320, 1380)))
    }

    @Test("the span drops the days, so DeviceActivity hears about it once")
    func span() {
        #expect(window(1200, 1320, .weekend).span == window(1200, 1320, .all))
        #expect(window(60, 90).isValid)
        #expect(!window(60, 70).isValid)
        #expect(!TimeWindow(startMinute: 1400, endMinute: 1500).isValid)
    }
}

@Suite("Rule")
struct RuleTests {
    @Test("windows are tighter than a rule with none")
    func tighterThanAllDay() {
        let allDay = Rule(windows: [], dailyBudgetMinutes: 30)
        let windowed = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30)
        #expect(windowed.isTighterOrEqual(to: allDay))
        #expect(!allDay.isTighterOrEqual(to: windowed))
        #expect(allDay.isTighterOrEqual(to: allDay))
    }

    @Test("dropping a day tightens")
    func tighterByOneDay() {
        let every = Rule(windows: [window(1200, 1320, .all)], dailyBudgetMinutes: 30)
        let notSunday = Rule(windows: [window(1200, 1320, Weekdays.all.subtracting(.sunday))], dailyBudgetMinutes: 30)
        #expect(notSunday.isTighterOrEqual(to: every))
        #expect(!every.isTighterOrEqual(to: notSunday))
    }

    @Test("the budget alone decides when the windows match")
    func tighterByBudget() {
        let windows = [window(1200, 1320)]
        #expect(Rule(windows: windows, dailyBudgetMinutes: 20).isTighterOrEqual(to: Rule(windows: windows, dailyBudgetMinutes: 30)))
        #expect(!Rule(windows: windows, dailyBudgetMinutes: 40).isTighterOrEqual(to: Rule(windows: windows, dailyBudgetMinutes: 30)))
        #expect(Rule(windows: windows, dailyBudgetMinutes: 30).isTighterOrEqual(to: Rule(windows: windows, dailyBudgetMinutes: 30)))
    }

    @Test("a zero budget is the tightest rule there is")
    func zeroBudget() {
        let anything = Rule(windows: [window(0, 1440)], dailyBudgetMinutes: 240)
        #expect(Rule.alwaysBlocked.isTighterOrEqual(to: anything))
        #expect(Rule.alwaysBlocked.isTighterOrEqual(to: .unrestricted))
        #expect(!Rule.unrestricted.isTighterOrEqual(to: .alwaysBlocked))
        #expect(!Rule.alwaysBlocked.isEverAllowed)
        #expect(Rule.alwaysBlocked.effectiveBudgetMinutes == 0)
    }

    @Test("windows with no days at all are never allowed")
    func noDays() {
        let rule = Rule(windows: [window(1200, 1320, [])], dailyBudgetMinutes: 30)
        #expect(!rule.isEverAllowed)
        #expect(rule.effectiveBudgetMinutes == 0)
        #expect(rule.isTighterOrEqual(to: .alwaysBlocked))
    }

    @Test("a rule with no windows is open every minute of every day")
    func allDayMask() {
        let rule = Rule(windows: [], dailyBudgetMinutes: 30)
        for weekday in 1...7 {
            #expect(rule.windows(on: weekday) == [Rule.allDay])
            #expect(rule.allowedMask(on: weekday).allSatisfy { $0 })
        }
        #expect(rule.isAllDay)
        #expect(rule.isSameEveryDay)
    }

    @Test("validation catches short windows, dayless windows and overlaps")
    func validation() {
        #expect(Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30).validationError == nil)
        #expect(Rule(windows: [], dailyBudgetMinutes: 30).validationError == nil)
        #expect(Rule(windows: [window(1200, 1210)], dailyBudgetMinutes: 30).validationError?.contains("15 minutes") == true)
        #expect(Rule(windows: [window(1200, 1320, [])], dailyBudgetMinutes: 30).validationError == "Each window needs at least one day.")
        #expect(Rule(windows: [window(1200, 1320), window(1260, 1380)], dailyBudgetMinutes: 30).validationError
                == "Windows on the same day must not overlap.")
        // The same hours on days that do not meet are fine.
        #expect(Rule(windows: [window(1200, 1320, .weekdays), window(1260, 1380, .weekend)], dailyBudgetMinutes: 30)
            .validationError == nil)
    }

    @Test("the same windows in another order are the same rule")
    func equivalence() {
        let a = Rule(windows: [window(1200, 1320), window(540, 600)], dailyBudgetMinutes: 30)
        let b = Rule(windows: [window(540, 600), window(1200, 1320)], dailyBudgetMinutes: 30)
        #expect(a.isEquivalent(to: b))
        #expect(!a.isEquivalent(to: Rule(windows: b.windows, dailyBudgetMinutes: 31)))
    }
}
