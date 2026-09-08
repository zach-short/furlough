import Foundation
import Testing

@Suite("Policy.status")
struct PolicyStatusTests {
    /// Tuesday 8 September 2026 at 12:30, in the fixed calendar.
    let tuesdayNoon = at(8, 12, 30)

    func status(_ target: Target, config: Config? = nil, runtime: RuntimeState = RuntimeState(), now: Date? = nil) -> TargetStatus {
        Policy.status(
            of: target,
            config: config ?? makeConfig([target]),
            runtime: runtime,
            now: now ?? tuesdayNoon,
            calendar: cal
        )
    }

    @Test("the anchor comes before every rule")
    func anchored() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(0, 1440)], dailyBudgetMinutes: 240))
        var config = makeConfig([youTube])
        config.anchor.kinds = [youTube.kind]
        config.anchor.isAnchored = true
        #expect(status(youTube, config: config) == .anchored)
        config.anchor.isAnchored = false
        #expect(status(youTube, config: config) == .open(until: 1440))
    }

    @Test("a target with no rule is not enforced")
    func unconfigured() {
        #expect(status(makeTarget("Fresh", rule: nil)) == .unconfigured)
    }

    @Test("a rule that allows nothing blocks the whole day")
    func blockedAllDay() {
        #expect(status(makeTarget("Cat", rule: .alwaysBlocked)) == .blockedAllDay)
        #expect(status(makeTarget("Dayless", rule: Rule(windows: [window(1200, 1320, [])], dailyBudgetMinutes: 30))) == .blockedAllDay)
    }

    @Test("inside a window it is open until the window's end")
    func open() {
        let evening = makeTarget("YouTube", rule: Rule(windows: [window(720, 780)], dailyBudgetMinutes: 30))
        #expect(status(evening) == .open(until: 780))
        let allDay = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        #expect(status(allDay) == .open(until: 1440))
    }

    @Test("before today's window it opens later today")
    func closedLaterToday() {
        let evening = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        #expect(status(evening) == .closed(nextOpen: NextOpen(minuteOfDay: 1200, daysAhead: 0)))
    }

    @Test("after today's last window it opens tomorrow")
    func closedTomorrow() {
        let morning = makeTarget("YouTube", rule: Rule(windows: [window(480, 600)], dailyBudgetMinutes: 30))
        #expect(status(morning) == .closed(nextOpen: NextOpen(minuteOfDay: 480, daysAhead: 1)))
    }

    @Test("a day no window covers waits for the next day that has one")
    func closedOnAnotherDay() {
        // Saturdays only, asked on a Tuesday: four days out.
        let weekendOnly = makeTarget("Games", rule: Rule(windows: [window(600, 720, .saturday)], dailyBudgetMinutes: 60))
        #expect(status(weekendOnly) == .closed(nextOpen: NextOpen(minuteOfDay: 600, daysAhead: 4)))
    }

    @Test("a spent budget waits for the next window, even a week away")
    func exhausted() {
        let saturdayOnly = makeTarget("Games", rule: Rule(windows: [window(600, 720, .saturday)], dailyBudgetMinutes: 60))
        var runtime = RuntimeState()
        let saturday = at(12, 11, 0)
        runtime.exhausted[saturdayOnly.id.uuidString] = Policy.dayKey(saturday, calendar: cal)
        #expect(status(saturdayOnly, runtime: runtime, now: saturday)
                == .exhausted(nextOpen: NextOpen(minuteOfDay: 600, daysAhead: 7)))
    }

    @Test("an all-day rule that is used up comes back at midnight")
    func exhaustedAllDay() {
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        runtime.exhausted[mail.id.uuidString] = Policy.dayKey(tuesdayNoon, calendar: cal)
        let expected = NextOpen(minuteOfDay: 0, daysAhead: 1)
        #expect(status(mail, runtime: runtime) == .exhausted(nextOpen: expected))
        #expect(expected.isMidnight)
    }

    @Test("exhaustion is keyed by the day, so yesterday's does not count")
    func exhaustionResets() {
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        runtime.exhausted[mail.id.uuidString] = Policy.dayKey(at(7, 12, 0), calendar: cal)
        #expect(status(mail, runtime: runtime) == .open(until: 1440))
        #expect(Policy.dayKey(tuesdayNoon, calendar: cal) == "2026-09-08")
    }

    @Test("nextOpen wraps past Saturday into the new week")
    func nextOpenWraps() {
        let mondays = Rule(windows: [window(600, 720, .monday)], dailyBudgetMinutes: 60)
        #expect(Policy.nextOpen(in: mondays, afterWeekday: 7) == NextOpen(minuteOfDay: 600, daysAhead: 2))
        #expect(Policy.nextOpen(in: mondays, afterWeekday: 2) == NextOpen(minuteOfDay: 600, daysAhead: 7))
        #expect(Policy.nextOpen(in: .alwaysBlocked, afterWeekday: 3) == nil)
    }

    @Test("a status is allowed only when it lets the app through")
    func allowed() {
        #expect(TargetStatus.open(until: 600).isAllowed)
        #expect(TargetStatus.unconfigured.isAllowed)
        #expect(!TargetStatus.anchored.isAllowed)
        #expect(!TargetStatus.blockedAllDay.isAllowed)
        #expect(!TargetStatus.exhausted(nextOpen: nil).isAllowed)
        #expect(!TargetStatus.closed(nextOpen: NextOpen(minuteOfDay: 0, daysAhead: 1)).isAllowed)
    }
}

@Suite("Policy.decide")
struct PolicyDecideTests {
    @Test("blocked targets are enforced and open ones are not")
    func decide() {
        let open = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        let closed = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let decision = Policy.decide(
            config: makeConfig([open, closed]),
            runtime: RuntimeState(),
            now: at(8, 12, 30),
            calendar: cal
        )
        #expect(decision.blockedHosts == ["youtube.com"])
        #expect(decision.isAnythingShielded)
        #expect(decision.statuses[open.id] == .open(until: 1440))
    }

    @Test("the anchor blocks things that are not targets at all")
    func anchorAddsKinds() {
        let open = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var config = makeConfig([open])
        config.anchor.kinds = [open.kind, .macApp(bundleID: "com.apple.Safari")]
        config.anchor.isAnchored = true
        let decision = Policy.decide(config: config, runtime: RuntimeState(), now: at(8, 12, 30), calendar: cal)
        #expect(decision.blockedHosts == ["mail.com"])
        #expect(decision.blockedApps == ["com.apple.Safari"])
    }

    @Test("nothing shielded when everything is open")
    func nothingShielded() {
        let open = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        let decision = Policy.decide(config: makeConfig([open]), runtime: RuntimeState(), now: at(8, 12, 30), calendar: cal)
        #expect(!decision.isAnythingShielded)
    }
}

@Suite("Policy.nextTransition")
struct NextTransitionTests {
    @Test("the next window edge today")
    func edge() {
        let evening = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let morning = at(8, 11, 0)
        #expect(Policy.nextTransition(config: makeConfig([evening]), after: morning, calendar: cal) == at(8, 20, 0))
    }

    @Test("inside a window, the end of it")
    func insideWindow() {
        let evening = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        #expect(Policy.nextTransition(config: makeConfig([evening]), after: at(8, 20, 30), calendar: cal) == at(8, 22, 0))
    }

    @Test("standing exactly on a window's start, the end is next")
    func onTheEdge() {
        let evening = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        #expect(Policy.nextTransition(config: makeConfig([evening]), after: at(8, 20, 0), calendar: cal) == at(8, 22, 0))
    }

    @Test("nothing left today means midnight")
    func midnight() {
        let evening = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        #expect(Policy.nextTransition(config: makeConfig([evening]), after: at(8, 23, 0), calendar: cal) == at(9, 0, 0))
        // A rule with no windows has no edges at all: its day ends at midnight.
        let allDay = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        #expect(Policy.nextTransition(config: makeConfig([allDay]), after: at(8, 12, 0), calendar: cal) == at(9, 0, 0))
        #expect(Policy.nextTransition(config: makeConfig([]), after: at(8, 12, 0), calendar: cal) == at(9, 0, 0))
    }

    @Test("windows on other days do not count as today's edges")
    func otherDays() {
        let saturday = makeTarget("Games", rule: Rule(windows: [window(600, 720, .saturday)], dailyBudgetMinutes: 60))
        #expect(Policy.nextTransition(config: makeConfig([saturday]), after: at(8, 9, 0), calendar: cal) == at(9, 0, 0))
    }
}
