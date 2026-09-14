import Foundation
import Testing

/// These pin the now/becomes pairing, not the wording — `TimeFormatTests` owns a rule's phrasing.
@Suite("Pending card copy")
struct PendingTextTests {
    private let evening = Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 30)
    private let later = Rule(windows: [window(20 * 60, 24 * 60)], dailyBudgetMinutes: 60)

    @Test("A queued rule is shown against the rule still in force")
    func setRuleShowsBoth() {
        let target = makeTarget("YouTube", rule: evening)
        let config = makeConfig([target])
        let change = PendingChange(kind: .setRule(targetID: target.id, rule: later), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(delta.now == TimeFormat.rule(evening, calendar: cal))
        #expect(delta.becomes == TimeFormat.rule(later, calendar: cal))
        #expect(delta.now != delta.becomes)
    }

    @Test("The old rule is the saved one, not another target's")
    func setRuleUsesItsOwnTarget() {
        let youtube = makeTarget("YouTube", rule: evening)
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        let config = makeConfig([youtube, tiktok])
        let change = PendingChange(kind: .setRule(targetID: tiktok.id, rule: later), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(delta.now == "Blocked all day")
    }

    @Test("A removal says what is being given up")
    func removeShowsCurrentRule() {
        let target = makeTarget("YouTube", rule: evening)
        let config = makeConfig([target])
        let change = PendingChange(kind: .removeTarget(targetID: target.id), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(delta.now == TimeFormat.rule(evening, calendar: cal))
        #expect(delta.becomes == "Not managed by Furlough")
    }

    @Test("A target with no rule yet says so rather than inventing one")
    func missingRuleReadsAsUnconfigured() {
        let target = makeTarget("YouTube", rule: nil)
        let config = makeConfig([target])
        let change = PendingChange(kind: .removeTarget(targetID: target.id), effectiveAt: at(9))
        #expect(PendingText.delta(for: change, in: config, calendar: cal).now == "Not configured yet")
    }

    // A target can be gone by the time the card draws (removed elsewhere, a stale change); it must not trap.
    @Test("An unknown target still produces both halves")
    func unknownTargetIsSafe() {
        let config = makeConfig([])
        let change = PendingChange(kind: .setRule(targetID: UUID(), rule: later), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(delta.now == "Not configured yet")
        #expect(delta.becomes == TimeFormat.rule(later, calendar: cal))
    }

    @Test("The base delay is shown against the one it replaces")
    func delayShowsBoth() {
        let config = makeConfig([], delayHours: 24)
        let change = PendingChange(kind: .setDelay(hours: 12), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(delta.now == "1 day")
        #expect(delta.becomes == "12 hours")
    }

    // The tier's name alone doesn't say what changing it buys, so both halves carry the wait.
    @Test("A tier change names the wait on each side")
    func utilityShowsTheWait() {
        var target = makeTarget("Messages", rule: evening)
        target.utilityLevel = .useful
        let config = makeConfig([target], delayHours: 24)
        let change = PendingChange(kind: .setUtility(targetID: target.id, level: .essential), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(delta.now == "Useful · waits 1 day")
        #expect(delta.becomes == "Essential · waits 6 hours")
    }

    // `utilityLevel` is nil until picked; `Target.utility` answers `.unset` (= useful) for that,
    // and the card must show the tier actually in force, not a blank.
    @Test("A target that was never tiered shows the tier it is treated as")
    func untieredTargetShowsUnset() {
        let target = makeTarget("Messages", rule: evening)
        #expect(target.utilityLevel == nil)
        let config = makeConfig([target], delayHours: 24)
        let change = PendingChange(kind: .setUtility(targetID: target.id, level: .essential), effectiveAt: at(9))
        #expect(PendingText.delta(for: change, in: config, calendar: cal).now == "\(Utility.unset.label) · waits 1 day")
    }

    // Must agree with the floor in `Config.delayHours(for:)`: never reads as no wait at all.
    @Test("The wait shown never drops below the floor")
    func waitRespectsTheFloor() {
        let target = makeTarget("Messages", rule: evening)
        let config = makeConfig([target], delayHours: 2)
        let change = PendingChange(kind: .setUtility(targetID: target.id, level: .essential), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(delta.becomes == "Essential · waits \(TimeFormat.delay(hours: Furlough.minimumLoosenDelayHours))")
    }
}
