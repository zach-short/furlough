import Foundation
import Testing

/// `Summary.nextOpenUntil`: when the window that opens next closes again. It exists so the app
/// can ask ActivityKit for that window's Live Activity before it starts, which needs both ends
/// of it while it is still in the future.
@Suite("Policy.summary next window")
struct NextWindowTests {
    /// Tuesday 8 September 2026 at 12:30.
    let now = at(8, 12, 30)

    func summary(_ state: SharedState) -> Policy.Summary {
        Policy.summary(state: state, now: now, calendar: cal)
    }

    @Test("the next window says both its ends")
    func bothEnds() {
        let evening = makeTarget("Evening", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let result = summary(makeState([evening]))
        #expect(result.nextOpenAt == at(8, 20, 0))
        #expect(result.nextOpenUntil == at(8, 22, 0))
    }

    @Test("a window tomorrow closes tomorrow")
    func tomorrow() {
        let morning = makeTarget("Morning", rule: Rule(windows: [window(480, 540)], dailyBudgetMinutes: 30))
        let result = summary(makeState([morning]))
        #expect(result.nextOpenAt == at(9, 8, 0))
        #expect(result.nextOpenUntil == at(9, 9, 0))
    }

    @Test("several opening together close at the soonest of them")
    func soonestClose() {
        let short = makeTarget("Short", rule: Rule(windows: [window(900, 960)], dailyBudgetMinutes: 30))
        let long = makeTarget("Long", rule: Rule(windows: [window(900, 1080)], dailyBudgetMinutes: 30))
        let result = summary(makeState([long, short]))
        #expect(result.nextOpenAt == at(8, 15, 0))
        #expect(result.nextOpenNames == ["Long", "Short"])
        #expect(result.nextOpenUntil == at(8, 16, 0))
    }

    @Test("a rule with no windows has nothing to close")
    func allDayHasNoClose() {
        // Spent for the day, so it opens again at midnight — with no window around it.
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        runtime.exhausted[mail.id.uuidString] = Policy.dayKey(now, calendar: cal)
        let result = summary(makeState([mail], runtime: runtime))
        #expect(result.nextOpenAt == at(9, 0, 0))
        #expect(result.nextOpenUntil == nil)
    }

    @Test("a night is one window, so it closes on the next morning")
    func night() {
        // Stored as the pair a night is stored as: Tuesday evening and Wednesday's small hours.
        let tuesday = Weekdays.tuesday
        let wednesday = Weekdays.wednesday
        let netflix = makeTarget("Netflix", rule: Rule(
            windows: [window(1320, 1440, tuesday), window(0, 120, wednesday)],
            dailyBudgetMinutes: 120
        ))
        let result = summary(makeState([netflix]))
        #expect(result.nextOpenAt == at(8, 22, 0))
        #expect(result.nextOpenUntil == at(9, 2, 0))
    }

    @Test("a target whose budget is spent still opens with its next window")
    func exhaustedReopens() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(720, 780), window(1200, 1260)], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        runtime.exhausted[youTube.id.uuidString] = Policy.dayKey(now, calendar: cal)
        let result = summary(makeState([youTube], runtime: runtime))
        // Spent today, so `nextOpen` looks past today to tomorrow's first window.
        #expect(result.nextOpenIsExhausted)
        #expect(result.nextOpenAt == at(9, 12, 0))
        #expect(result.nextOpenUntil == at(9, 13, 0))
    }

    @Test("both ends move onto the device's clock together")
    func shifted() {
        let evening = makeTarget("Evening", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let result = summary(makeState([evening])).shifted(by: 3600)
        #expect(result.nextOpenAt == at(8, 21, 0))
        #expect(result.nextOpenUntil == at(8, 23, 0))
    }
}
