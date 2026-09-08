import Foundation
import Testing

@Suite("Pending notifications")
struct PendingNotificationTests {
    let now = at(8, 12, 0)

    func change(_ kind: PendingKind, dueAt: Date) -> PendingChange {
        PendingChange(kind: kind, createdAt: at(7), effectiveAt: dueAt)
    }

    @Test("nothing queued, nothing scheduled")
    func empty() {
        #expect(PendingNotifications.plan(state: makeState([]), now: now, calendar: cal).isEmpty)
    }

    @Test("a queued change gets a warning an hour before and one when it lands")
    func warningAndLanding() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let due = at(8, 20, 0)
        let queued = change(.setRule(targetID: youTube.id, rule: Rule(windows: [], dailyBudgetMinutes: 30)), dueAt: due)
        let plan = PendingNotifications.plan(state: makeState([youTube], pending: [queued]), now: now, calendar: cal)

        #expect(plan.count == 2)
        #expect(plan[0].id == PendingNotifications.id(queued, .warning))
        #expect(plan[0].fireAt == due.addingTimeInterval(-PendingNotifications.lead))
        #expect(plan[0].title == "Loosening lands in an hour")
        #expect(plan[0].body.contains("YouTube"))
        #expect(plan[0].body.contains("Cancel it in Furlough"))

        #expect(plan[1].id == PendingNotifications.id(queued, .landed))
        #expect(plan[1].fireAt == due)
        #expect(plan[1].title == "Change landed")
    }

    /// A change queued with less than an hour to run would have both notifications land at
    /// once, the warning saying there is still time to cancel when there is not.
    @Test("a change due within the hour gets only the landing notification")
    func noLateWarning() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let queued = change(.setRule(targetID: youTube.id, rule: .unrestricted), dueAt: at(8, 12, 30))
        let plan = PendingNotifications.plan(state: makeState([youTube], pending: [queued]), now: now, calendar: cal)
        #expect(plan.count == 1)
        #expect(plan[0].id.hasSuffix(".landed"))
    }

    @Test("a change already past is not announced at all")
    func alreadyDue() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let queued = change(.setRule(targetID: youTube.id, rule: .unrestricted), dueAt: at(8, 11, 0))
        #expect(PendingNotifications.plan(state: makeState([youTube], pending: [queued]), now: now, calendar: cal).isEmpty)
    }

    @Test("they are in the order they will fire")
    func ordered() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let soon = change(.removeTarget(targetID: youTube.id), dueAt: at(8, 18, 0))
        let later = change(.setDelay(hours: 12), dueAt: at(9, 18, 0))
        let plan = PendingNotifications.plan(state: makeState([youTube], pending: [later, soon]), now: now, calendar: cal)
        #expect(plan.map(\.fireAt) == plan.map(\.fireAt).sorted())
        #expect(plan.count == 4)
    }

    @Test("every kind of change says what it will do")
    func copy() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let config = makeState([youTube]).config

        let rule = change(.setRule(targetID: youTube.id, rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30)), dueAt: at(9))
        #expect(PendingNotifications.describe(rule, in: config, calendar: cal).hasPrefix("YouTube: "))

        let removal = change(.removeTarget(targetID: youTube.id), dueAt: at(9))
        #expect(PendingNotifications.describe(removal, in: config, calendar: cal) == "YouTube will no longer be limited.")

        let delay = change(.setDelay(hours: 12), dueAt: at(9))
        #expect(PendingNotifications.describe(delay, in: config, calendar: cal).contains("12 hours"))
    }

    /// A change whose target was removed in the meantime still has to say something.
    @Test("a change for a target that is gone still reads")
    func missingTarget() {
        let queued = change(.setRule(targetID: UUID(), rule: .unrestricted), dueAt: at(9))
        #expect(PendingNotifications.describe(queued, in: makeState([]).config, calendar: cal).hasPrefix("An app"))
    }

    /// The system fires these against its own clock, so a device clock that is off has to be
    /// compensated for or the warning arrives at the wrong moment.
    @Test("fire dates are moved onto the device's clock")
    func driftIsApplied() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let due = at(8, 20, 0)
        let queued = change(.setRule(targetID: youTube.id, rule: .unrestricted), dueAt: due)
        let state = makeState([youTube], pending: [queued])
        let drift: TimeInterval = 24 * 3600

        let plan = PendingNotifications.plan(state: state, now: now, drift: drift, calendar: cal)
        #expect(plan.map(\.fireAt) == [
            due.addingTimeInterval(-PendingNotifications.lead + drift),
            due.addingTimeInterval(drift),
        ])
        // Which change is due is still judged on Furlough's own time, not the shifted one.
        #expect(plan.count == 2)
    }

    @Test("identifiers are stable per change, so re-syncing does not reschedule")
    func stableIdentifiers() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let queued = change(.setRule(targetID: youTube.id, rule: .unrestricted), dueAt: at(8, 20, 0))
        let state = makeState([youTube], pending: [queued])
        let first = PendingNotifications.plan(state: state, now: now, calendar: cal)
        let again = PendingNotifications.plan(state: state, now: now.addingTimeInterval(300), calendar: cal)
        #expect(first.map(\.id) == again.map(\.id))
        #expect(first.allSatisfy { $0.id.hasPrefix(PendingNotifications.prefix) })
    }
}
