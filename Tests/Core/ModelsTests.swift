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

@Suite("Target")
struct TargetTests {
    /// A Screen Time token has no name until iOS says one on the shield, and that learned name
    /// is what the widget and the notifications read. A nickname still wins over it.
    @Test("a learned name stands in until a nickname is set")
    func names() {
        var target = Target(kind: .host("youtube.com"))
        #expect(target.displayName == "youtube.com")
        target.systemName = "YouTube"
        #expect(target.displayName == "YouTube")
        target.nickname = "Tube"
        #expect(target.displayName == "Tube")
    }
}

/// An evening that runs into the next morning. The editors take it as one row; Furlough keeps
/// the two windows it really is, because the rules engine and DeviceActivity work a day at a
/// time, and reads them back as the row it was written as.
@Suite("A night")
struct NightTests {
    @Test("days move forward through the week, Saturday coming round to Sunday")
    func shiftedDays() {
        #expect(Weekdays.saturday.shifted(by: 1) == .sunday)
        #expect(Weekdays.weekend.shifted(by: 1) == [.sunday, .monday])
        #expect(Weekdays.all.shifted(by: 1) == .all)
        #expect(Weekdays.monday.shifted(by: 0) == .monday)
        #expect(Weekdays.monday.shifted(by: 7) == .monday)
        #expect(Weekdays.weekdays.shifted(by: 2) == [.wednesday, .thursday, .friday, .saturday, .sunday])
    }

    @Test("it splits at midnight, the morning landing on the days after")
    func split() {
        let night = window(17 * 60, 4 * 60, .weekend)
        #expect(night.isNight)
        #expect(night.spanMinutes == 11 * 60)
        #expect(night.split == [
            window(17 * 60, Furlough.minutesPerDay, .weekend),
            window(0, 4 * 60, [.sunday, .monday]),
        ])
    }

    @Test("an evening that stops at midnight has no morning half")
    func endsAtMidnight() {
        #expect(window(17 * 60, 0).split == [window(17 * 60, Furlough.minutesPerDay)])
        #expect(!window(17 * 60, Furlough.minutesPerDay).isNight)
        #expect(window(17 * 60, Furlough.minutesPerDay).split == [window(17 * 60, Furlough.minutesPerDay)])
    }

    @Test("the halves fold back into the night they were written as")
    func fold() {
        let weekend = window(17 * 60, 4 * 60, .weekend)
        #expect(TimeWindow.folded(weekend.split) == [weekend])
        let nightly = window(20 * 60, 2 * 60)
        #expect(TimeWindow.folded(nightly.split) == [nightly])
    }

    @Test("a morning that is not the one after stays a window of its own")
    func foldsOnlyTheDayAfter() {
        let evening = window(17 * 60, Furlough.minutesPerDay, .saturday)
        let morning = window(0, 4 * 60, .saturday)
        #expect(TimeWindow.folded([evening, morning]) == [evening, morning])
        // Nothing else is touched: an ordinary evening is left where it is.
        let plain = window(20 * 60, 22 * 60)
        #expect(TimeWindow.folded([plain]) == [plain])
        #expect(TimeWindow.folded([Rule.allDay]) == [Rule.allDay])
    }

    @Test("it is judged by its halves, which each need the minimum")
    func validity() {
        #expect(window(17 * 60, 4 * 60).isValidDraft)
        // Fifteen minutes end to end, but ten before midnight and five after: neither can be kept.
        #expect(!window(1430, 5).isValidDraft)
        #expect(window(1425, 15).isValidDraft)
        #expect(!window(1200, 1210).isValidDraft)
    }

    /// Saturday 12 September 2026 into the Sunday: 5 PM until 4 AM, on the weekend.
    @Test("it stays open until the morning it really ends")
    func openPastMidnight() {
        let target = makeTarget("TikTok", rule: Rule(windows: window(17 * 60, 4 * 60, .weekend).split, dailyBudgetMinutes: 240))
        let config = makeConfig([target])
        func status(_ now: Date) -> TargetStatus {
            Policy.status(of: target, config: config, runtime: RuntimeState(), now: now, calendar: cal)
        }
        // Saturday at 11 PM: open past midnight, to 4 AM on the Sunday.
        let saturdayNight = at(12, 23, 0)
        #expect(status(saturdayNight) == .open(until: Furlough.minutesPerDay + 4 * 60))
        #expect(Policy.date(atMinute: Furlough.minutesPerDay + 4 * 60, of: saturdayNight, calendar: cal) == at(13, 4, 0))
        #expect(TimeFormat.until(Furlough.minutesPerDay + 4 * 60, calendar: cal) == TimeFormat.minute(4 * 60, calendar: cal))
        // Sunday at 2 AM: the same night, now ending later today.
        #expect(status(at(13, 2, 0)) == .open(until: 4 * 60))
        // Sunday at 5 AM: shut, until the Sunday evening.
        #expect(status(at(13, 5, 0)) == .closed(nextOpen: NextOpen(minuteOfDay: 17 * 60, daysAhead: 0)))
    }

    @Test("midnight is a join, and both sides of it know")
    func join() {
        let rule = Rule(windows: window(17 * 60, 4 * 60, .weekend).split, dailyBudgetMinutes: 240)
        // Saturday runs into Sunday, and Sunday into Monday.
        #expect(rule.continuation(after: 7) == window(0, 4 * 60, [.sunday, .monday]))
        #expect(rule.continues(into: 1) == window(17 * 60, Furlough.minutesPerDay, .weekend))
        // Tuesday has nothing either side of it.
        #expect(rule.continuation(after: 3) == nil)
        #expect(rule.continues(into: 3) == nil)
        // A rule without windows only resets its budget at midnight.
        #expect(Rule(windows: [], dailyBudgetMinutes: 30).continuation(after: 7) == nil)
        #expect(Rule(windows: [], dailyBudgetMinutes: 30).continues(into: 1) == nil)
        // An evening that stops at midnight beside a morning that is not the one after it.
        let apart = Rule(windows: [window(17 * 60, Furlough.minutesPerDay, .saturday), window(0, 4 * 60, .saturday)], dailyBudgetMinutes: 30)
        #expect(apart.continuation(after: 7) == nil)
        #expect(apart.continues(into: 7) == nil)
    }

    @Test("what it becomes is an ordinary rule, and reads as one span")
    func inARule() {
        let rule = Rule(windows: window(17 * 60, 4 * 60, .weekend).split, dailyBudgetMinutes: 30)
        #expect(rule.validationError == nil)
        // Sunday 1 AM is open, from Saturday night; Saturday 1 AM is not.
        #expect(rule.allowedMask(on: 1)[60])
        #expect(!rule.allowedMask(on: 7)[60])
        // Monday 1 AM is open too, because Sunday night is one of the nights asked for.
        #expect(rule.allowedMask(on: 2)[60])
        // One span rather than an evening and a morning apart. The times themselves come from
        // the formatter, which spaces AM and PM its own way.
        let evening = TimeFormat.minute(17 * 60, calendar: cal)
        let morning = TimeFormat.minute(4 * 60, calendar: cal)
        #expect(TimeFormat.schedule(rule, calendar: cal) == "Weekends \(evening)–\(morning)")
    }
}

@Suite("Anchor tags")
struct AnchorTagTests {
    private func tag(_ byte: UInt8, _ name: String) -> PairedTag {
        PairedTag(id: Data([byte]), name: name)
    }

    @Test("any paired tag matches, and nothing else does")
    func matching() {
        let anchor = AnchorProfile(tags: [tag(1, "Home"), tag(2, "Apartment")])
        #expect(anchor.tag(matching: Data([1]))?.name == "Home")
        #expect(anchor.tag(matching: Data([2]))?.name == "Apartment")
        #expect(anchor.tag(matching: Data([3])) == nil)
        // A prefix of a paired identifier is a different tag, not a partial match.
        #expect(anchor.tag(matching: Data()) == nil)
    }

    @Test("one key is enough to anchor, and none is not")
    func pairing() {
        var anchor = AnchorProfile(kinds: [.host("youtube.com")])
        #expect(!anchor.isPaired)
        #expect(!anchor.canAnchor)
        anchor.tags = [tag(1, "Home")]
        #expect(anchor.isPaired)
        #expect(anchor.canAnchor)
    }

    @Test("the cap is reached, not exceeded")
    func cap() {
        var anchor = AnchorProfile()
        #expect(anchor.canPairMore)
        anchor.tags = (1...UInt8(Furlough.maxAnchorTags)).map { tag($0, "Tag \($0)") }
        #expect(!anchor.canPairMore)
        anchor.tags.removeLast()
        #expect(anchor.canPairMore)
    }

    @Test("a suggested name never collides with one already there")
    func nextName() {
        var anchor = AnchorProfile()
        #expect(anchor.nextTagName == "Tag 1")
        anchor.tags = [tag(1, "Home")]
        #expect(anchor.nextTagName == "Tag 2")
        // The count is only a starting guess: renaming leaves gaps, and a name in the way is
        // stepped over rather than duplicated.
        anchor.tags = [tag(1, "Tag 2")]
        #expect(anchor.nextTagName == "Tag 3")
        anchor.tags = [tag(1, "Tag 2"), tag(2, "Tag 3")]
        #expect(anchor.nextTagName == "Tag 4")
    }
}
