import Foundation
import Testing

@Suite("Policy.summary")
struct SummaryTests {
    /// Tuesday 8 September 2026 at 12:30.
    let now = at(8, 12, 30)

    func summary(_ state: SharedState) -> Policy.Summary {
        Policy.summary(state: state, now: now, calendar: cal)
    }

    @Test("a window that is open is kept apart from a rule with no windows")
    func openVersusAllDay() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(720, 780)], dailyBudgetMinutes: 30))
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        let result = summary(makeState([youTube, mail]))
        #expect(result.openNames == ["YouTube"])
        #expect(result.allDayNames == ["Mail"])
        #expect(result.openUntil == at(8, 13, 0))
        #expect(result.openStart == at(8, 12, 0))
        #expect(result.nextOpenAt == nil)
        #expect(result.blockedCount == 0)
        #expect(!result.isEmpty)
    }

    @Test("the window closing soonest sets the countdown")
    func soonestClose() {
        let short = makeTarget("Short", rule: Rule(windows: [window(720, 780)], dailyBudgetMinutes: 30))
        let long = makeTarget("Long", rule: Rule(windows: [window(600, 900)], dailyBudgetMinutes: 60))
        let result = summary(makeState([long, short]))
        #expect(result.openNames == ["Long", "Short"])
        #expect(result.openUntil == at(8, 13, 0))
        #expect(result.openStart == at(8, 12, 0))
    }

    @Test("the target opening soonest is the one the widget names")
    func soonestOpening() {
        let evening = makeTarget("Evening", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let afternoon = makeTarget("Afternoon", rule: Rule(windows: [window(900, 960)], dailyBudgetMinutes: 45))
        let result = summary(makeState([evening, afternoon]))
        #expect(result.nextOpenAt == at(8, 15, 0))
        #expect(result.nextOpenNames == ["Afternoon"])
        #expect(result.nextOpenBudgetMinutes == 45)
        #expect(!result.nextOpenIsExhausted)
        #expect(result.blockedCount == 2)
    }

    @Test("two targets opening at the same moment are named together")
    func tie() {
        let a = makeTarget("Alpha", rule: Rule(windows: [window(900, 960)], dailyBudgetMinutes: 30))
        let b = makeTarget("Beta", rule: Rule(windows: [window(900, 960)], dailyBudgetMinutes: 30))
        let result = summary(makeState([a, b]))
        #expect(result.nextOpenAt == at(8, 15, 0))
        #expect(result.nextOpenNames == ["Alpha", "Beta"])
    }

    @Test("a spent budget is flagged, and comes back at midnight")
    func exhausted() {
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        runtime.exhausted[mail.id.uuidString] = Policy.dayKey(now, calendar: cal)
        let result = summary(makeState([mail], runtime: runtime))
        #expect(result.exhaustedCount == 1)
        #expect(result.blockedCount == 1)
        #expect(result.nextOpenIsExhausted)
        #expect(result.nextOpenAt == at(9, 0, 0))
        #expect(result.allDayNames.isEmpty)
    }

    @Test("the 5-minute warning follows the target it belongs to")
    func warned() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(720, 780)], dailyBudgetMinutes: 30))
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        runtime.warned[youTube.id.uuidString] = Policy.dayKey(now, calendar: cal)
        let result = summary(makeState([youTube, mail], runtime: runtime))
        #expect(result.openWarned)
        #expect(!result.allDayWarned)
    }

    @Test("pending changes are counted only while they are still waiting")
    func pending() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let due = PendingChange(kind: .setDelay(hours: 12), createdAt: at(7), effectiveAt: at(8, 10, 0))
        let waiting = PendingChange(kind: .setDelay(hours: 48), createdAt: at(8), effectiveAt: at(9, 12, 0))
        let result = summary(makeState([youTube], pending: [due, waiting]))
        #expect(result.pendingCount == 1)
    }

    @Test("the brick is counted whole, targets or not")
    func bricked() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var state = makeState([youTube])
        state.config.brick.kinds = [youTube.kind, .macApp(bundleID: "com.apple.Safari")]
        state.config.brick.isBricked = true
        let result = summary(state)
        #expect(result.isBricked)
        #expect(result.brickedCount == 2)
        #expect(result.blockedCount == 1)
        #expect(result.openNames.isEmpty)
    }

    @Test("nothing configured is an empty summary")
    func empty() {
        #expect(summary(makeState([])).isEmpty)
        let fresh = makeTarget("Fresh", rule: nil)
        let result = summary(makeState([fresh]))
        #expect(result.unconfiguredCount == 1)
        #expect(!result.isEmpty)
    }
}
