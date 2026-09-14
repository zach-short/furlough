import Foundation
import Testing

/// iOS caps activities at 20 (budget tracker + 19 spans); must check before Save since
/// registration only fails silently.
@Suite("Activity limit")
struct ActivityLimitTests {
    func windows(_ count: Int, days: Weekdays = .all) -> [TimeWindow] {
        (0..<count).map { window($0 * 60, $0 * 60 + 30, days) }
    }

    func rule(_ count: Int, days: Weekdays = .all, budget: Int = 30) -> Rule {
        Rule(windows: windows(count, days: days), dailyBudgetMinutes: budget)
    }

    // MARK: Counting

    @Test("no rules, no spans")
    func empty() {
        #expect(ActivityLimit.spans(in: makeState([])).isEmpty)
    }

    @Test("the same hours on different days are one span")
    func daysDoNotMultiply() {
        let weekday = makeTarget("A", rule: Rule(windows: [window(600, 660, .weekdays)], dailyBudgetMinutes: 30))
        let weekend = makeTarget("B", rule: Rule(windows: [window(600, 660, .weekend)], dailyBudgetMinutes: 30))
        #expect(ActivityLimit.spans(in: makeState([weekday, weekend])).count == 1)
    }

    @Test("two apps sharing hours cost one span between them")
    func sharedHours() {
        let a = makeTarget("A", rule: rule(3))
        let b = makeTarget("B", rule: rule(3))
        #expect(ActivityLimit.spans(in: makeState([a, b])).count == 3)
    }

    // Enforced by its zero budget, not the window.
    @Test("a rule that never allows anything costs nothing")
    func neverAllowed() {
        let blocked = makeTarget("A", rule: Rule(windows: windows(5), dailyBudgetMinutes: 0))
        #expect(ActivityLimit.spans(in: makeState([blocked])).isEmpty)
    }

    // `Monitoring.register` registers queued rules too.
    @Test("a queued rule's spans count as well")
    func pendingCounts() {
        let a = makeTarget("A", rule: rule(2))
        let queued = PendingChange(
            kind: .setRule(targetID: a.id, rule: Rule(windows: windows(3).map { window($0.startMinute + 500, $0.endMinute + 500) }, dailyBudgetMinutes: 30)),
            effectiveAt: .distantFuture
        )
        #expect(ActivityLimit.spans(in: makeState([a], pending: [queued])).count == 5)
    }

    @Test("a queued rule for a target that is gone is ignored")
    func pendingForMissingTarget() {
        let queued = PendingChange(kind: .setRule(targetID: UUID(), rule: rule(4)), effectiveAt: .distantFuture)
        #expect(ActivityLimit.spans(in: makeState([], pending: [queued])).isEmpty)
    }

    // MARK: Projecting a save

    // A loosening queues beside the old rule, so both sets of windows are registered during the delay.
    @Test("a loosening needs the old rule's spans and the new one's at once")
    func looseningCountsBoth() {
        let old = Rule(windows: windows(3), dailyBudgetMinutes: 30)
        let target = makeTarget("A", rule: old)
        let state = makeState([target])
        let looser = Rule(windows: windows(3).map { window($0.startMinute + 500, $0.endMinute + 500) }, dailyBudgetMinutes: 60)
        #expect(Policy.classify(newRule: looser, against: target) == .loosening)

        let projected = ActivityLimit.projecting(looser, appliedTo: [target.id], in: state)
        #expect(ActivityLimit.spans(in: projected).count == 6)
    }

    @Test("a tightening replaces the old rule's spans")
    func tighteningReplaces() {
        let target = makeTarget("A", rule: rule(5))
        let tighter = Rule(windows: windows(2), dailyBudgetMinutes: 15)
        #expect(Policy.classify(newRule: tighter, against: target) == .tightening)

        let projected = ActivityLimit.projecting(tighter, appliedTo: [target.id], in: makeState([target]))
        #expect(ActivityLimit.spans(in: projected).count == 2)
    }

    @Test("a queued rule is replaced, not added to")
    func replacesExistingPending() {
        let target = makeTarget("A", rule: rule(2))
        let stale = PendingChange(kind: .setRule(targetID: target.id, rule: rule(9)), effectiveAt: .distantFuture)
        let state = makeState([target], pending: [stale])
        #expect(ActivityLimit.spans(in: state).count == 9)

        let looser = Rule(windows: windows(3), dailyBudgetMinutes: 60)
        let projected = ActivityLimit.projecting(looser, appliedTo: [target.id], in: state)
        // The old 2 spans are a subset of the new 3.
        #expect(ActivityLimit.spans(in: projected).count == 3)
        #expect(projected.pending.count == 1)
    }

    @Test("an unchanged rule changes nothing")
    func unchanged() {
        let same = rule(4)
        let target = makeTarget("A", rule: same)
        let projected = ActivityLimit.projecting(same, appliedTo: [target.id], in: makeState([target]))
        #expect(projected.pending.isEmpty)
        #expect(ActivityLimit.spans(in: projected).count == 4)
    }

    // MARK: The reason shown above Save

    @Test("19 spans fits, 20 does not")
    func theCeiling() {
        #expect(ActivityLimit.maxSpans == 19)
        let target = makeTarget("A", rule: nil)
        let state = makeState([target])
        #expect(ActivityLimit.reason(applying: rule(19), to: [target.id], in: state) == nil)

        let over = ActivityLimit.reason(applying: rule(20), to: [target.id], in: state)
        #expect(over != nil)
        #expect(over?.contains("20 different windows") == true)
        #expect(over?.contains("iOS allows 19") == true)
    }

    // A first rule is always a tightening against "unrestricted", so nothing is replaced.
    @Test("a first rule fits on its own spans alone")
    func firstRule() {
        let target = makeTarget("A", rule: nil)
        #expect(ActivityLimit.reason(applying: rule(19), to: [target.id], in: makeState([target])) == nil)
    }

    @Test("applying the same rule to many targets costs one set of spans")
    func applyToOthers() {
        let a = makeTarget("A", rule: nil)
        let b = makeTarget("B", rule: nil)
        let c = makeTarget("C", rule: nil)
        let state = makeState([a, b, c])
        #expect(ActivityLimit.reason(applying: rule(19), to: [a.id, b.id, c.id], in: state) == nil)
    }

    // Overflows because each target's existing rule is loosened away, not replaced.
    @Test("applying over other targets' loosened rules can overflow")
    func applyOverExisting() {
        let a = makeTarget("A", rule: Rule(windows: windows(10), dailyBudgetMinutes: 30))
        let b = makeTarget("B", rule: Rule(windows: windows(10).map { window($0.startMinute + 5, $0.endMinute + 5) }, dailyBudgetMinutes: 30))
        let state = makeState([a, b])
        let looser = Rule(windows: [window(1300, 1400)], dailyBudgetMinutes: 240)
        let reason = ActivityLimit.reason(applying: looser, to: [a.id, b.id], in: state)
        #expect(reason != nil)
    }

    @Test("a target that is not there is skipped rather than crashing")
    func missingTarget() {
        #expect(ActivityLimit.reason(applying: rule(30), to: [UUID()], in: makeState([])) == nil)
    }

    // MARK: A whole import against the ceiling

    // Mirrors what the Mac's own matcher produces, so these tests read like the real review.
    func plan(_ targets: [ExportedTarget], _ state: SharedState) -> ImportPlan {
        let file = ConfigExport(
            platform: .mac,
            exportedAt: at(8),
            appVersion: "1.0",
            loosenDelayHours: 24,
            targets: targets
        )
        return ConfigImport.plan(
            file,
            matches: ConfigImport.matches(for: file, config: state.config),
            state: state,
            now: at(8, 12, 0)
        )
    }

    func site(_ host: String, _ rule: Rule) -> ExportedTarget {
        ExportedTarget(kind: .website, identifier: host, name: nil, nickname: nil, utility: nil, rule: rule)
    }

    // Must check on the plan: `enforce` swallows what `Monitoring.register` throws, so an
    // oversized import would otherwise land whole with nothing watching it.
    @Test("an import that would not register is refused while it is still a proposal")
    func importOverTheCeiling() {
        let target = makeTarget("A", rule: nil)
        let state = makeState([target])
        let reason = ActivityLimit.reason(applying: plan([site("a.com", rule(20))], state), in: state)
        #expect(reason?.contains("20 different windows") == true)
        #expect(reason?.contains("iOS allows 19") == true)
    }

    @Test("an import that fits is not refused")
    func importUnderTheCeiling() {
        let target = makeTarget("A", rule: nil)
        let state = makeState([target])
        #expect(ActivityLimit.reason(applying: plan([site("a.com", rule(19))], state), in: state) == nil)
    }

    // `Monitoring.register` registers pending rules too, so the queued half counts against the
    // ceiling immediately, not only once it lands.
    @Test("the queued half of an import counts before it lands")
    func importQueuedCounts() {
        let target = makeTarget("A", rule: Rule(windows: windows(10), dailyBudgetMinutes: 30))
        let state = makeState([target])
        let looser = Rule(
            windows: windows(10).map { window($0.startMinute + 5, $0.endMinute + 5) },
            dailyBudgetMinutes: 240
        )
        let plan = plan([site("a.com", looser)], state)
        #expect(plan.queued.count == 1)
        #expect(ActivityLimit.spans(in: ActivityLimit.projecting(plan, in: state)).count == 20)
        #expect(ActivityLimit.reason(applying: plan, in: state) != nil)
    }

    @Test("an import that changes nothing needs nothing")
    func importOfWhatIsAlreadyHere() {
        let target = makeTarget("A", rule: rule(19))
        let state = makeState([target])
        let plan = plan([site("a.com", rule(19))], state)
        #expect(plan.isEmpty)
        #expect(ActivityLimit.reason(applying: plan, in: state) == nil)
    }
}
