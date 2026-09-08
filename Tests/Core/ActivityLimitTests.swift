import Foundation
import Testing

/// iOS takes 20 monitored activities: the daily budget tracker plus 19 window spans. The
/// editor has to know before Save, because registration only finds out afterwards.
@Suite("Activity limit")
struct ActivityLimitTests {
    /// `count` windows an hour apart, all valid and all distinct.
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

    /// A rule that never allows anything registers no window: it is enforced by its zero budget.
    @Test("a rule that never allows anything costs nothing")
    func neverAllowed() {
        let blocked = makeTarget("A", rule: Rule(windows: windows(5), dailyBudgetMinutes: 0))
        #expect(ActivityLimit.spans(in: makeState([blocked])).isEmpty)
    }

    /// `Monitoring.register` registers queued rules too, so they have to be counted.
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

    /// The edit that would otherwise slip through: a loosening queues *beside* the old rule, so
    /// for the length of the delay both sets of windows are registered.
    @Test("a loosening needs the old rule's spans and the new one's at once")
    func looseningCountsBoth() {
        let old = Rule(windows: windows(3), dailyBudgetMinutes: 30)
        let target = makeTarget("A", rule: old)
        let state = makeState([target])
        // Later hours and a bigger budget: a loosening, so it queues rather than replacing.
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

    /// Saving replaces whatever was already queued for that target rather than stacking on it.
    @Test("a queued rule is replaced, not added to")
    func replacesExistingPending() {
        let target = makeTarget("A", rule: rule(2))
        let stale = PendingChange(kind: .setRule(targetID: target.id, rule: rule(9)), effectiveAt: .distantFuture)
        let state = makeState([target], pending: [stale])
        #expect(ActivityLimit.spans(in: state).count == 9)

        let looser = Rule(windows: windows(3), dailyBudgetMinutes: 60)
        let projected = ActivityLimit.projecting(looser, appliedTo: [target.id], in: state)
        // The stale queued rule is gone: the two saved spans plus the three queued ones.
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

    /// A first rule is always a tightening against "unrestricted", so it replaces nothing and
    /// only its own spans count.
    @Test("a first rule fits on its own spans alone")
    func firstRule() {
        let target = makeTarget("A", rule: nil)
        #expect(ActivityLimit.reason(applying: rule(19), to: [target.id], in: makeState([target])) == nil)
    }

    /// Apply-to-others saves the same rule to several targets at once, and the spans are shared,
    /// so it costs no more than saving to one.
    @Test("applying the same rule to many targets costs one set of spans")
    func applyToOthers() {
        let a = makeTarget("A", rule: nil)
        let b = makeTarget("B", rule: nil)
        let c = makeTarget("C", rule: nil)
        let state = makeState([a, b, c])
        #expect(ActivityLimit.reason(applying: rule(19), to: [a.id, b.id, c.id], in: state) == nil)
    }

    /// But applying to targets that already have different windows can overflow, because each
    /// one's existing rule is loosened away rather than replaced.
    @Test("applying over other targets' loosened rules can overflow")
    func applyOverExisting() {
        let a = makeTarget("A", rule: Rule(windows: windows(10), dailyBudgetMinutes: 30))
        let b = makeTarget("B", rule: Rule(windows: windows(10).map { window($0.startMinute + 5, $0.endMinute + 5) }, dailyBudgetMinutes: 30))
        let state = makeState([a, b])
        // A rule that is a loosening for both, so both old sets stay queued alongside it.
        let looser = Rule(windows: [window(1300, 1400)], dailyBudgetMinutes: 240)
        let reason = ActivityLimit.reason(applying: looser, to: [a.id, b.id], in: state)
        #expect(reason != nil)
    }

    @Test("a target that is not there is skipped rather than crashing")
    func missingTarget() {
        #expect(ActivityLimit.reason(applying: rule(30), to: [UUID()], in: makeState([])) == nil)
    }
}
