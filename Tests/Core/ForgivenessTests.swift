import Foundation
import Testing

/// The first week and the undo window: the two things that let a beginner make a mistake
/// without paying a day for it, and the reasons neither is a way out.
@Suite struct ForgivenessTests {

    // MARK: The first week

    @Test func trialStartsOnceAndFixesItsEnd() {
        var config = makeConfig([])
        #expect(Forgiveness.startTrial(&config, now: at(8)))
        #expect(config.isInTrial)
        #expect(config.trialStartedAt == at(8))
        #expect(config.trialEndsAt == at(15))
    }

    /// Screen Time access off and on again is the documented way out of Furlough. It must not
    /// also be the way to a fresh week, so the record outlives the week it records.
    @Test func trialIsNeverGrantedTwice() {
        var config = makeConfig([])
        Forgiveness.startTrial(&config, now: at(8))
        Forgiveness.expire(&config, now: at(15))
        #expect(!config.isInTrial)
        #expect(!Forgiveness.startTrial(&config, now: at(20)))
        #expect(config.trialEndsAt == at(15))
        #expect(!config.isInTrial)
    }

    @Test func trialEndsOnItsDateAndNotBefore() {
        var config = makeConfig([])
        Forgiveness.startTrial(&config, now: at(8))
        #expect(!Forgiveness.expire(&config, now: at(14, 23, 59)))
        #expect(config.isInTrial)
        #expect(Forgiveness.expire(&config, now: at(15)))
        #expect(!config.isInTrial)
    }

    @Test func delaysAreCappedWhileTheWeekRuns() {
        var config = makeConfig([
            makeTarget("Messages", rule: Rule()),
            makeTarget("TikTok", rule: Rule()),
        ])
        config.targets[0].utilityLevel = .essential
        config.targets[1].utilityLevel = .hazard
        #expect(config.delayHours(for: config.targets[0]) == 6)
        #expect(config.delayHours(for: config.targets[1]) == 96)

        Forgiveness.startTrial(&config, now: at(8))
        #expect(config.delayHours(for: config.targets[0]) == 1)
        #expect(config.delayHours(for: config.targets[1]) == 1)
        // What it will cost once the week is over is still answerable, because the editor says
        // it while the week runs: the cliff at the end must not be a surprise.
        #expect(config.fullDelayHours(for: config.targets[1]) == 96)

        Forgiveness.expire(&config, now: at(15))
        #expect(config.delayHours(for: config.targets[1]) == 96)
    }

    /// A cap, never a floor. Someone whose base delay is already an hour gets the same hour.
    @Test func theCapNeverLengthensADelay() {
        var config = makeConfig([makeTarget("Messages", rule: Rule())], delayHours: 1)
        config.targets[0].utilityLevel = .essential
        let before = config.delayHours(for: config.targets[0])
        Forgiveness.startTrial(&config, now: at(8))
        #expect(config.delayHours(for: config.targets[0]) == before)
    }

    @Test func daysLeftRoundsUpAndStopsAtTheEnd() {
        var config = makeConfig([])
        Forgiveness.startTrial(&config, now: at(8))
        #expect(Forgiveness.trialDaysLeft(config, at: at(8)) == 7)
        // Most of the last day gone is still "1 day left", never "0".
        #expect(Forgiveness.trialDaysLeft(config, at: at(14, 18)) == 1)
        #expect(Forgiveness.trialDaysLeft(config, at: at(15)) == nil)
        #expect(Forgiveness.trialDaysLeft(makeConfig([]), at: at(8)) == nil)
    }

    // MARK: The undo window

    @Test func anEditIsTakeableBackForFifteenMinutes() {
        var target = makeTarget("YouTube", rule: Rule())
        Forgiveness.record(previous: target.rule, on: &target, at: at(8, 9))
        #expect(Forgiveness.undo(for: target, at: at(8, 9, 14)) != nil)
        #expect(Forgiveness.undo(for: target, at: at(8, 9, 15)) == nil)
    }

    @Test func revertingRestoresExactlyWhatWasThere() {
        let was = Rule(windows: [window(540, 1020)], dailyBudgetMinutes: 60)
        let id = UUID()
        var target = makeTarget("YouTube", rule: was, id: id)
        Forgiveness.record(previous: target.rule, on: &target, at: at(8, 9))
        target.rule = Rule(windows: [window(540, 600)], dailyBudgetMinutes: 5)
        var state = makeState([target])

        #expect(Forgiveness.revert(targetID: id, in: &state, now: at(8, 9, 10)))
        #expect(state.config.targets[0].rule?.isEquivalent(to: was) == true)
        #expect(state.config.targets[0].undo == nil)
    }

    /// A target's first rule replaces nothing, so undoing it puts the target back to having
    /// none — which is where it stood before it was touched, and enforces nothing.
    @Test func revertingAFirstRuleLeavesTheTargetUnconfigured() {
        let id = UUID()
        var target = makeTarget("Messenger", rule: nil, id: id)
        Forgiveness.record(previous: nil, on: &target, at: at(8, 9))
        target.rule = Rule(windows: [], dailyBudgetMinutes: 5)
        var state = makeState([target])

        #expect(Forgiveness.revert(targetID: id, in: &state, now: at(8, 9, 5)))
        #expect(state.config.targets[0].rule == nil)
    }

    @Test func revertingIsRefusedOnceTheWindowHasClosed() {
        let id = UUID()
        var target = makeTarget("YouTube", rule: Rule(), id: id)
        Forgiveness.record(previous: Rule(), on: &target, at: at(8, 9))
        target.rule = Rule(windows: [], dailyBudgetMinutes: 5)
        var state = makeState([target])

        #expect(!Forgiveness.revert(targetID: id, in: &state, now: at(8, 9, 30)))
        #expect(state.config.targets[0].rule?.dailyBudgetMinutes == 5)
    }

    /// Anything queued for this target was queued against the rule being taken back, so it is
    /// now waiting to loosen something that no longer exists. Other targets are not its business.
    @Test func revertingDropsThisTargetsQueuedRuleOnly() {
        let mine = UUID(), other = UUID()
        var target = makeTarget("YouTube", rule: Rule(), id: mine)
        Forgiveness.record(previous: Rule(), on: &target, at: at(8, 9))
        target.rule = Rule(windows: [], dailyBudgetMinutes: 5)
        var state = makeState(
            [target, makeTarget("TikTok", rule: Rule(), id: other)],
            pending: [
                PendingChange(kind: .setRule(targetID: mine, rule: .unrestricted), effectiveAt: at(9, 9)),
                PendingChange(kind: .setRule(targetID: other, rule: .unrestricted), effectiveAt: at(9, 9)),
                PendingChange(kind: .removeTarget(targetID: mine), effectiveAt: at(9, 9)),
            ]
        )

        #expect(Forgiveness.revert(targetID: mine, in: &state, now: at(8, 9, 5)))
        #expect(state.pending.count == 2)
        #expect(state.pending.contains { $0.kind == .setRule(targetID: other, rule: .unrestricted) })
        #expect(state.pending.contains { $0.kind == .removeTarget(targetID: mine) })
    }

    /// The property the whole design rests on: undo restores the rule that was in force, so a
    /// chain of edits walks back exactly one step and never reaches "unrestricted".
    @Test func undoIsOneStepBackAndNeverReachesUnrestricted() {
        let id = UUID()
        let first = Rule(windows: [window(540, 1020)], dailyBudgetMinutes: 60)
        var target = makeTarget("YouTube", rule: nil, id: id)

        Forgiveness.record(previous: nil, on: &target, at: at(8, 9))
        target.rule = first
        // Twenty minutes later, tighter again: the note is replaced, not stacked on.
        Forgiveness.record(previous: target.rule, on: &target, at: at(8, 9, 20))
        target.rule = Rule(windows: [window(540, 600)], dailyBudgetMinutes: 10)
        var state = makeState([target])

        #expect(Forgiveness.revert(targetID: id, in: &state, now: at(8, 9, 25)))
        #expect(state.config.targets[0].rule?.isEquivalent(to: first) == true)
        // And there is nothing left to walk back to.
        #expect(!Forgiveness.revert(targetID: id, in: &state, now: at(8, 9, 26)))
    }

    @Test func expiringForgetsUndosNobodyCanReach() {
        var open = makeTarget("YouTube", rule: Rule())
        var closed = makeTarget("TikTok", rule: Rule())
        Forgiveness.record(previous: Rule(), on: &open, at: at(8, 9, 50))
        Forgiveness.record(previous: Rule(), on: &closed, at: at(8, 9))
        var config = makeConfig([open, closed])

        #expect(Forgiveness.expire(&config, now: at(8, 10)))
        #expect(config.targets[0].undo != nil)
        #expect(config.targets[1].undo == nil)
    }

    // MARK: Through the pass everything goes through

    @Test func applyDuePendingEndsTheWeek() {
        var state = makeState([])
        Forgiveness.startTrial(&state.config, now: at(8))
        #expect(!Policy.applyDuePending(&state, now: at(14)))
        #expect(state.config.isInTrial)
        #expect(Policy.applyDuePending(&state, now: at(15)))
        #expect(!state.config.isInTrial)
    }

    /// The widget draws future timelines through `effectiveConfig`, so the week has to be over
    /// in the parts of them that fall after it ends.
    @Test func effectiveConfigSeesTheWeekEnd() {
        var state = makeState([makeTarget("TikTok", rule: Rule())])
        state.config.targets[0].utilityLevel = .hazard
        Forgiveness.startTrial(&state.config, now: at(8))
        #expect(Policy.effectiveConfig(state, now: at(10)).delayHours(for: state.config.targets[0]) == 1)
        #expect(Policy.effectiveConfig(state, now: at(20)).delayHours(for: state.config.targets[0]) == 96)
        // On a copy: the stored state is not quietly aged by drawing a timeline.
        #expect(state.config.isInTrial)
    }

    // MARK: What is already on the phone

    /// State written before any of this existed decodes with no week and no undo, and a week is
    /// granted at the moment access is given, which an upgrade is not.
    @Test func stateWrittenBeforeTheTrialGetsNone() throws {
        let json = """
        {"targets":[],"loosenDelayHours":24,"schemaVersion":1}
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(!config.isInTrial)
        #expect(config.trialStartedAt == nil)
        #expect(config.trialEndsAt == nil)
        #expect(config.delayHours(for: nil) == 24)
    }

    /// A target with nothing to undo writes no key for it, so state from before the window
    /// existed and state from after it are the same bytes.
    @Test func aTargetWithNothingToUndoWritesNoKeyForIt() throws {
        let target = makeTarget("YouTube", rule: Rule())
        let json = String(data: try JSONEncoder().encode(target), encoding: .utf8) ?? ""
        #expect(!json.contains("undo"))
        #expect(try JSONDecoder().decode(Target.self, from: Data(json.utf8)).undo == nil)
    }
}
