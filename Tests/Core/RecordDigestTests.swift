import Foundation
import Testing

/// A day's record for the digest tests. Its own rather than the one in `RecordTests`, which is
/// private to that file.
private func digestDay(
    spent: Bool = false,
    shielded: Int = 0,
    anchored: Int = 0,
    cancelled: Int = 0,
    landed: Int = 0
) -> DayRecord {
    var record = DayRecord()
    if spent {
        var entry = TargetDay()
        entry.spent = true
        record.targets[UUID().uuidString] = entry
    }
    if shielded > 0 || anchored > 0 {
        var entry = TargetDay()
        entry.shieldedMinutes = shielded
        entry.anchoredMinutes = anchored
        record.targets[UUID().uuidString] = entry
    }
    record.cancelled = cancelled
    record.landed = landed
    return record
}

private func dayKey(_ d: Int) -> String { Policy.dayKey(at(d), calendar: cal) }

/// Monday 14 September 2026, nine in the morning: a digest's own moment. The 6th is a Sunday,
/// so the week it reports is Monday the 7th through Sunday the 13th.
private let digestMonday = at(14, 9, 0)

@Suite("Record.weeklyDigest")
struct RecordDigestTests {
    private func digest(_ days: [String: DayRecord], at now: Date = digestMonday) -> Record.Digest? {
        Record.weeklyDigest(days, upTo: now, calendar: cal)
    }

    @Test("a fresh install has nothing to say")
    func freshInstall() {
        #expect(digest([:]) == nil)
    }

    @Test("a week where nothing was held and nothing waited is not worth a notification")
    func emptyWeek() {
        let days = [dayKey(9): digestDay(), dayKey(10): digestDay()]
        #expect(digest(days) == nil)
    }

    @Test("a held streak reads as one, in the screen's own words")
    func heldStreak() {
        var days: [String: DayRecord] = [:]
        for day in 7...13 { days[dayKey(day)] = digestDay(shielded: 60, anchored: 30) }
        let digest = digest(days)
        #expect(digest?.title == "Last week")
        let lines = digest?.body.components(separatedBy: "\n") ?? []
        #expect(lines.first == "No budget spent: 7 days in a row.")
        #expect(lines.contains("Held shut: 7 hours · 3 h 30 min anchored"))
        // Nothing queued, so the loosenings line is left out rather than showing two zeroes.
        #expect(lines.count == 2)
    }

    @Test("a streak broken inside the week says so rather than counting from the break")
    func brokenStreak() {
        var days: [String: DayRecord] = [:]
        for day in 7...13 { days[dayKey(day)] = digestDay(shielded: 60) }
        // Wednesday the 9th: a budget went, so the run is Thursday through Sunday.
        days[dayKey(9)] = digestDay(spent: true, shielded: 60)
        #expect(digest(days)?.body.hasPrefix("No budget spent: 4 days in a row.") == true)
    }

    @Test("a budget spent on the last day of the week reads as the break it is")
    func brokeOnTheLastDay() {
        var days: [String: DayRecord] = [:]
        for day in 7...13 { days[dayKey(day)] = digestDay(shielded: 60) }
        days[dayKey(13)] = digestDay(spent: true, shielded: 60)
        #expect(digest(days)?.body.hasPrefix("No budget spent: Not today.") == true)
    }

    /// The day after a break: the streak line refuses the proud "1".
    @Test("the day after a break is not day one dressed up")
    func brokeTheDayBefore() {
        var days: [String: DayRecord] = [:]
        for day in 7...13 { days[dayKey(day)] = digestDay(shielded: 60) }
        days[dayKey(12)] = digestDay(spent: true, shielded: 60)
        #expect(digest(days)?.body.hasPrefix("No budget spent: Back to day one.") == true)
    }

    @Test("loosenings are counted over the week, cancelled first")
    func loosenings() {
        var days: [String: DayRecord] = [:]
        days[dayKey(8)] = digestDay(shielded: 30, cancelled: 2)
        days[dayKey(11)] = digestDay(shielded: 30, landed: 1)
        let lines = digest(days)?.body.components(separatedBy: "\n") ?? []
        #expect(lines.last == "Loosenings: 2 cancelled, 1 landed")
    }

    @Test("a week with only a cancelled loosening still says something")
    func nothingHeldButSomethingWaited() {
        let days = [dayKey(10): digestDay(cancelled: 1)]
        let lines = digest(days)?.body.components(separatedBy: "\n") ?? []
        // No "Held shut" row: an absence is left out rather than shown as a zero.
        #expect(lines.count == 2)
        #expect(lines.last == "Loosenings: 1 cancelled, 0 landed")
    }

    @Test("the week is the seven whole days before today, so today is not in it")
    func todayIsNotCounted() {
        // Monday morning itself, and the Monday a week before it: one is today, one is a day
        // too early. Neither belongs to the week this digest reports.
        let days = [dayKey(14): digestDay(shielded: 600), dayKey(6): digestDay(shielded: 600)]
        #expect(digest(days) == nil)
    }

    @Test("the anchored share is left out when the anchor held none of it")
    func noAnchoredShare() {
        let days = [dayKey(10): digestDay(shielded: 45)]
        #expect(digest(days)?.body.contains("anchored") == false)
    }
}

@Suite("The digest's Monday")
struct DigestScheduleTests {
    /// New York, so the clocks actually move. DST ends on Sunday 1 November 2026.
    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func next(after now: Date, calendar: Calendar) -> Date? {
        PendingNotifications.nextDigestDate(after: now, calendar: calendar)
    }

    @Test("the next one is the coming Monday morning")
    func comingMonday() {
        // Tuesday the 8th, midday.
        let next = next(after: at(8, 12, 0), calendar: cal)
        #expect(next == at(14, 9, 0))
    }

    @Test("a Monday before nine gets that same morning; after it, the next week")
    func mondayItself() {
        #expect(next(after: at(14, 8, 59), calendar: cal) == at(14, 9, 0))
        #expect(next(after: at(14, 9, 0), calendar: cal) == at(21, 9, 0))
    }

    @Test("the clocks going back move the digest by an hour, not by a week of seconds")
    func acrossTheFallBack() {
        let calendar = newYork
        // Monday 26 October 2026, one second past nine, New York time.
        var october = DateComponents()
        october.year = 2026
        october.month = 10
        october.day = 26
        october.hour = 9
        october.second = 1
        let from = calendar.date(from: october) ?? .distantPast
        let next = next(after: from, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: next ?? .distantPast)
        #expect(parts.month == 11)
        #expect(parts.day == 2)
        #expect(parts.hour == Furlough.digestHour)
        #expect(parts.minute == 0)
        #expect(parts.weekday == Furlough.digestWeekday)
        // Seven days and an hour, less the second: nine o'clock local either side of the
        // clocks going back, rather than 604,800 seconds later at eight.
        #expect(next?.timeIntervalSince(from) == TimeInterval(7 * 86_400 + 3_600 - 1))
    }

    @Test("the clocks going forward take an hour off the same way")
    func acrossTheSpringForward() {
        let calendar = newYork
        // Monday 2 March 2026; DST begins on Sunday 8 March.
        var march = DateComponents()
        march.year = 2026
        march.month = 3
        march.day = 2
        march.hour = 9
        march.second = 1
        let from = calendar.date(from: march) ?? .distantPast
        let next = next(after: from, calendar: calendar)
        let parts = calendar.dateComponents([.month, .day, .hour, .weekday], from: next ?? .distantPast)
        #expect(parts.month == 3)
        #expect(parts.day == 9)
        #expect(parts.hour == Furlough.digestHour)
        #expect(parts.weekday == Furlough.digestWeekday)
        #expect(next?.timeIntervalSince(from) == TimeInterval(7 * 86_400 - 3_600 - 1))
    }
}

@Suite("The digest in the plan")
struct DigestPlanTests {
    private func state(_ days: [String: DayRecord]) -> SharedState {
        var state = makeState([])
        state.runtime.days = days
        return state
    }

    private var week: [String: DayRecord] {
        var days: [String: DayRecord] = [:]
        for day in 7...13 { days[dayKey(day)] = digestDay(shielded: 60) }
        return days
    }

    private func plan(_ state: SharedState, digest: Bool, now: Date = at(8, 12, 0), drift: TimeInterval = 0) -> [PlannedNotification] {
        PendingNotifications.plan(state: state, now: now, drift: drift, digest: digest, calendar: cal)
    }

    @Test("nobody who has not asked for it is planned one")
    func offByRequest() {
        #expect(plan(state(week), digest: false).isEmpty)
    }

    @Test("asked for, it lands on the coming Monday morning")
    func plannedForMonday() {
        let planned = plan(state(week), digest: true)
        #expect(planned.count == 1)
        #expect(planned.first?.fireAt == at(14, 9, 0))
        #expect(planned.first?.title == "Last week")
        #expect(planned.first?.id.hasPrefix(PendingNotifications.digestPrefix) == true)
    }

    @Test("the week it reports is the one ending the night before it fires")
    func reportsTheWeekBeforeItFires() {
        // Planned on Tuesday the 8th for Monday the 14th: the week Monday the 7th to Sunday
        // the 13th, which is what the record already holds.
        #expect(plan(state(week), digest: true).first?.body.contains("Held shut: 7 hours") == true)
    }

    @Test("a device with nothing on record is planned nothing")
    func nothingToReport() {
        #expect(plan(state([:]), digest: true).isEmpty)
    }

    @Test("the fire date rides on the device's clock, like every other planned notification")
    func carriesTheDrift() {
        #expect(plan(state(week), digest: true, drift: 3600).first?.fireAt == at(14, 10, 0))
    }

    @Test("the identifier changes when the words do, and not otherwise")
    func fingerprintedIdentifier() {
        let first = plan(state(week), digest: true).first
        #expect(plan(state(week), digest: true).first?.id == first?.id)
        var busier = week
        busier[dayKey(9)] = digestDay(shielded: 240)
        #expect(plan(state(busier), digest: true).first?.id != first?.id)
    }

    @Test("a fingerprint is the same in every process")
    func stableFingerprint() {
        // The literal is the whole of the test: a hash seeded per launch would fail here on
        // the second run, which is exactly the bug it exists to prevent.
        #expect(PendingNotifications.fingerprint("Last week") == "1kusyro3vpq8b")
    }

    @Test("the digest comes first, so a plan of many still shows it")
    func digestLeadsThePlan() {
        var state = state(week)
        state.pending = [PendingChange(kind: .setDelay(hours: 1), effectiveAt: at(9, 12, 0))]
        let planned = plan(state, digest: true)
        #expect(planned.first?.id.hasPrefix(PendingNotifications.digestPrefix) == true)
        #expect(planned.count == 3)
    }
}

@Suite("Record.week, as bars")
struct RecordWeekBarsTests {
    private func week(_ days: [String: DayRecord], at now: Date = at(13, 12, 0)) -> [Record.DayBar] {
        Record.week(days, upTo: now, calendar: cal)
    }

    @Test("seven days, oldest first, ending today")
    func sevenDaysEndingToday() {
        let bars = week([:])
        #expect(bars.count == 7)
        #expect(bars.first?.key == dayKey(7))
        #expect(bars.last?.key == dayKey(13))
        #expect(bars.last?.isToday == true)
        #expect(bars.filter(\.isToday).count == 1)
    }

    @Test("a week that held nothing is seven empty bars, not seven divisions by zero")
    func emptyWeek() {
        #expect(week([:]).allSatisfy { $0.fraction == 0 && $0.shieldedMinutes == 0 })
    }

    @Test("heights are against the tallest day of the seven")
    func relativeHeights() {
        var days: [String: DayRecord] = [:]
        days[dayKey(11)] = digestDay(shielded: 120)
        days[dayKey(12)] = digestDay(shielded: 60)
        let bars = week(days)
        #expect(bars.first(where: { $0.key == dayKey(11) })?.fraction == 1)
        #expect(bars.first(where: { $0.key == dayKey(12) })?.fraction == 0.5)
        #expect(bars.first(where: { $0.key == dayKey(10) })?.fraction == 0)
    }

    @Test("every target's minutes on a day are added together")
    func minutesAcrossTargets() {
        var record = DayRecord()
        for minutes in [30, 45] {
            var entry = TargetDay()
            entry.shieldedMinutes = minutes
            record.targets[UUID().uuidString] = entry
        }
        #expect(week([dayKey(9): record]).first(where: { $0.key == dayKey(9) })?.shieldedMinutes == 75)
    }

    @Test("a day older than the seven is not in it")
    func olderDaysAreLeftOut() {
        let bars = week([dayKey(6): digestDay(shielded: 600)])
        #expect(bars.allSatisfy { $0.shieldedMinutes == 0 })
    }

    @Test("the weekday is the one the letter under the bar is drawn from")
    func weekdays() {
        // The 13th is a Sunday, weekday 1 in a Gregorian calendar.
        #expect(week([:]).last?.weekday == 1)
        #expect(week([:]).first?.weekday == 2)
    }
}
