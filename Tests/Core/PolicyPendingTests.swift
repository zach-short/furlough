import Foundation
import Testing

@Suite("Pending changes")
struct PendingTests {
    let now = at(8, 12, 0)

    func change(_ kind: PendingKind, dueAt: Date) -> PendingChange {
        PendingChange(kind: kind, createdAt: at(7), effectiveAt: dueAt)
    }

    @Test("due changes land in the order they became effective, and are then gone")
    func order() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let first = Rule(windows: [window(1140, 1320)], dailyBudgetMinutes: 45)
        let second = Rule(windows: [window(1080, 1320)], dailyBudgetMinutes: 60)
        let later = change(.setRule(targetID: youTube.id, rule: second), dueAt: at(8, 11, 0))
        let earlier = change(.setRule(targetID: youTube.id, rule: first), dueAt: at(8, 10, 0))
        let future = change(.setDelay(hours: 48), dueAt: at(9, 12, 0))
        // Listed out of order on purpose: the effective time decides, not the array.
        var state = makeState([youTube], pending: [later, earlier, future])

        #expect(Policy.applyDuePending(&state, now: now))
        #expect(state.config.targets.first?.rule == second)
        #expect(state.pending.map(\.id) == [future.id])
        #expect(state.config.loosenDelayHours == 24)
    }

    @Test("nothing due changes nothing")
    func nothingDue() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let future = change(.setRule(targetID: youTube.id, rule: .unrestricted), dueAt: at(9, 12, 0))
        var state = makeState([youTube], pending: [future])
        #expect(!Policy.applyDuePending(&state, now: now))
        #expect(state.config.targets.first?.rule?.dailyBudgetMinutes == 30)
        #expect(state.pending.count == 1)
    }

    @Test("a change due at this very instant lands")
    func exactlyDue() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        var state = makeState([youTube], pending: [change(.setDelay(hours: 72), dueAt: now)])
        #expect(Policy.applyDuePending(&state, now: now))
        #expect(state.config.loosenDelayHours == 72)
        #expect(state.pending.isEmpty)
    }

    @Test("removing a target and changing the delay both apply")
    func kinds() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var state = makeState([youTube, mail], pending: [
            change(.removeTarget(targetID: youTube.id), dueAt: at(8, 9, 0)),
            change(.setDelay(hours: 12), dueAt: at(8, 10, 0)),
        ])
        Policy.applyDuePending(&state, now: now)
        #expect(state.config.targets.map(\.id) == [mail.id])
        #expect(state.config.loosenDelayHours == 12)
        #expect(state.pending.isEmpty)
    }

    @Test("effectiveConfig folds due changes in without touching the state")
    func effectiveConfig() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let loosened = Rule(windows: [window(1080, 1320)], dailyBudgetMinutes: 60)
        let state = makeState([youTube], pending: [change(.setRule(targetID: youTube.id, rule: loosened), dueAt: at(8, 10, 0))])
        #expect(Policy.effectiveConfig(state, now: now).targets.first?.rule == loosened)
        #expect(state.config.targets.first?.rule?.dailyBudgetMinutes == 30)
        #expect(state.pending.count == 1)
    }

    @Test("a pending rule for a target that is gone is harmless")
    func missingTarget() {
        var state = makeState([], pending: [change(.setRule(targetID: UUID(), rule: .unrestricted), dueAt: at(8, 10, 0))])
        Policy.applyDuePending(&state, now: now)
        #expect(state.config.targets.isEmpty)
        #expect(state.pending.isEmpty)
    }
}

@Suite("Policy.classify")
struct ClassifyTests {
    let evening = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30)

    @Test("a target's first rule always applies now")
    func firstRule() {
        #expect(Policy.classify(newRule: evening, against: nil) == .tightening)
        #expect(Policy.classify(newRule: .unrestricted, against: nil) == .tightening)
        #expect(Policy.classify(newRule: nil, against: nil) == .tightening)
    }

    @Test("a smaller budget or a shorter window applies now")
    func tightening() {
        let configured = makeTarget("YouTube", rule: evening)
        #expect(Policy.classify(newRule: Rule(windows: evening.windows, dailyBudgetMinutes: 15), against: configured) == .tightening)
        #expect(Policy.classify(newRule: Rule(windows: [window(1230, 1320)], dailyBudgetMinutes: 30), against: configured) == .tightening)
        #expect(Policy.classify(newRule: evening, against: configured) == .tightening)
        #expect(Policy.classify(newRule: .alwaysBlocked, against: configured) == .tightening)
    }

    @Test("more time, more days, or removing the target waits out the delay")
    func loosening() {
        let configured = makeTarget("YouTube", rule: evening)
        #expect(Policy.classify(newRule: Rule(windows: evening.windows, dailyBudgetMinutes: 60), against: configured) == .loosening)
        #expect(Policy.classify(newRule: Rule(windows: [window(1080, 1320)], dailyBudgetMinutes: 30), against: configured) == .loosening)
        #expect(Policy.classify(newRule: nil, against: configured) == .loosening)
        // Dropping the last window opens the whole day.
        #expect(Policy.classify(newRule: Rule(windows: [], dailyBudgetMinutes: 30), against: configured) == .loosening)
    }

    @Test("the first window on an all-day rule is a tightening")
    func firstWindow() {
        let allDay = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        #expect(Policy.classify(newRule: evening, against: allDay) == .tightening)
    }
}
