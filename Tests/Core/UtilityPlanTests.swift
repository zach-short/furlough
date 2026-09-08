import Foundation
import Testing

/// `Policy.plan` decides what a tier edit does. The case that matters is the one that used to
/// be missed: the rule editor seeds its picker from a *queued* tier, so choosing the saved tier
/// back has to cancel the queued change rather than quietly leave it in place.
@Suite("Policy.plan(utility:)")
struct UtilityPlanTests {
    func target(_ level: Utility?, rule: Rule? = Rule(windows: [window(600, 660)], dailyBudgetMinutes: 30)) -> Target {
        var target = makeTarget("YouTube", rule: rule)
        target.utilityLevel = level
        return target
    }

    @Test("the same tier, with nothing queued, is nothing to do")
    func unchanged() {
        #expect(Policy.plan(utility: .hazard, for: target(.hazard), queued: false) == .unchanged)
    }

    /// A target nobody has tiered is already effectively `.useful`, so choosing that is not a
    /// change — and must not quietly record a choice that turns off the suggestion.
    @Test("choosing the default on an untiered target is nothing to do")
    func untieredDefault() {
        #expect(Policy.plan(utility: .unset, for: target(nil), queued: false) == .unchanged)
        #expect(Policy.plan(utility: .useful, for: target(nil), queued: false) == .unchanged)
    }

    @Test("moving toward hazard lengthens the wait, so it lands now")
    func towardHazard() {
        #expect(Policy.plan(utility: .hazard, for: target(.useful), queued: false) == .now)
        #expect(Policy.plan(utility: .idle, for: target(.essential), queued: false) == .now)
    }

    @Test("moving toward essential shortens the wait, so it queues")
    func towardEssential() {
        #expect(Policy.plan(utility: .essential, for: target(.hazard), queued: false) == .queue)
        #expect(Policy.plan(utility: .useful, for: target(.idle), queued: false) == .queue)
    }

    @Test("a target enforcing nothing yet gets its first tier free")
    func firstTierIsFree() {
        #expect(Policy.plan(utility: .essential, for: target(.hazard, rule: nil), queued: false) == .now)
    }

    // MARK: Cancelling a queued tier change

    /// The defect this function exists to close. The picker shows the queued tier; picking the
    /// saved one back used to compare equal and return "nothing to do", leaving the queued
    /// loosening to land anyway.
    @Test("choosing the saved tier back cancels a queued change")
    func cancelsQueued() {
        #expect(Policy.plan(utility: .hazard, for: target(.hazard), queued: true) == .now)
    }

    @Test("an untiered target can cancel a queued change the same way")
    func cancelsQueuedFromUntiered() {
        #expect(Policy.plan(utility: .useful, for: target(nil), queued: true) == .now)
    }

    @Test("a queued change does not turn a loosening into an instant one")
    func queuedDoesNotShortcut() {
        #expect(Policy.plan(utility: .essential, for: target(.hazard), queued: true) == .queue)
    }

    @Test("a queued change does not stop a tightening landing now")
    func queuedTighteningStillLands() {
        #expect(Policy.plan(utility: .hazard, for: target(.useful), queued: true) == .now)
    }
}

/// Anchoring is instant, unrecoverable without the tag, and reaches things that are not even
/// targets, so it says something one tier wider than an ordinary block does.
@Suite("Anchoring warns one tier wider")
struct AnchorWarningWidthTests {
    @Test("idle is worth a word before anchoring, but not before a rule")
    func idleWarnsOnlyForAnchoring() {
        #expect(Utility.idle.warnsBeforeAnchoring)
        #expect(!Utility.idle.warnsBeforeBlocking)
    }

    @Test("hazard is what Furlough exists to block, so it says nothing either way")
    func hazardStaysQuiet() {
        #expect(!Utility.hazard.warnsBeforeAnchoring)
        #expect(!Utility.hazard.warnsBeforeBlocking)
    }

    @Test("the tiers above idle still warn both ways")
    func theOthersAreUnchanged() {
        for utility in [Utility.essential, .useful] {
            #expect(utility.warnsBeforeAnchoring)
            #expect(utility.warnsBeforeBlocking)
        }
    }

    /// Idle gets words that fit it: it is not flattered as "worth having around", which is what
    /// the useful tier's line says.
    @Test("an idle anchor warning says what is true, that it goes")
    func idleCopy() {
        let text = UtilityText.anchoring(names: ["Instagram"], utility: .idle, detail: nil)
        #expect(text?.contains("goes the moment you anchor") == true)
        #expect(text?.contains("Only the paired tag lifts an anchor.") == true)
        #expect(text?.contains("worth having around") == false)
    }

    @Test("blocking an idle target still says nothing")
    func idleBlockingStaysQuiet() {
        #expect(UtilityText.blocking(name: "Instagram", utility: .idle, detail: nil) == nil)
    }

    /// An anchor holding only idle things now speaks, where before it was silent.
    @Test("an anchor holding only idle targets warns")
    func anchorOfIdleWarns() {
        var idle = makeTarget("Instagram", rule: nil)
        idle.utilityLevel = .idle
        var config = makeConfig([idle])
        config.anchor.kinds = [idle.kind]
        let warning = config.anchorWarning
        #expect(warning?.utility == .idle)
        #expect(warning?.names == ["Instagram"])
    }

    /// The most-essential tier still speaks over the rest.
    @Test("an essential in the anchor still outranks an idle one")
    func essentialOutranksIdle() {
        var idle = makeTarget("Instagram", rule: nil)
        idle.utilityLevel = .idle
        var essential = makeTarget("Messages", rule: nil)
        essential.utilityLevel = .essential
        var config = makeConfig([idle, essential])
        config.anchor.kinds = [idle.kind, essential.kind]
        #expect(config.anchorWarning?.utility == .essential)
        #expect(config.anchorWarning?.names == ["Messages"])
    }
}
