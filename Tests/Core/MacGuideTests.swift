import Foundation
import Testing

/// The Mac's two three-step guides. The steps are derived from the config, apart from the last
/// of each, which is a flag — so what these check is that the derivation matches what is actually
/// set up, and that the live step is the first thing still owed.
///
/// The phone's guides live in its app target with the views; the Mac's are here in Shared/Core,
/// where they are pure enough to be tested without a window. See `HalfGuide`.
@Suite("The Mac's guides")
struct MacGuideTests {
    // MARK: Rules

    @Test func rulesRunsFromTheFirstStepOnAFreshMac() {
        let guide = HalfGuide.macRules(config: Config(), finished: false)
        #expect(guide.isRunning)
        #expect(guide.live == 0)
        #expect(guide.steps[0].title == "Pick the apps that eat your day")
    }

    @Test func addingATargetMovesRulesToTheSecondStep() {
        let config = makeConfig([makeTarget("YouTube", rule: nil)])
        let guide = HalfGuide.macRules(config: config, finished: false)
        #expect(guide.steps[0].isDone)
        #expect(guide.live == 1)
    }

    @Test func savingTheFirstRuleMovesRulesToTheLastStep() {
        let config = makeConfig([makeTarget("YouTube", rule: Rule(windows: [window(540, 1320)], dailyBudgetMinutes: 45))])
        let guide = HalfGuide.macRules(config: config, finished: false)
        #expect(guide.steps[1].isDone)
        #expect(guide.live == 2)
    }

    /// The last step is the one thing the config cannot answer, so it reads the flag.
    @Test func rulesFoldsAwayOnlyOnceItsLastStepIsPressed() {
        let config = makeConfig([makeTarget("YouTube", rule: Rule(windows: [window(540, 1320)], dailyBudgetMinutes: 45))])
        #expect(HalfGuide.macRules(config: config, finished: false).isRunning)
        #expect(!HalfGuide.macRules(config: config, finished: true).isRunning)
    }

    /// Restarting the guides clears the flag and nothing else, so a Mac that is set up comes back
    /// showing its third step live rather than pretending the apps were never picked.
    @Test func restartingRulesComesBackOnTheThirdStep() {
        let config = makeConfig([makeTarget("YouTube", rule: Rule(windows: [window(540, 1320)], dailyBudgetMinutes: 45))])
        let guide = HalfGuide.macRules(config: config, finished: false)
        #expect(guide.live == 2)
        #expect(guide.steps[0].isDone)
        #expect(guide.steps[1].isDone)
    }

    // MARK: The Anchor

    /// The phone's first step is *Pair a tag*. This Mac has no reader, so what stands in its
    /// place is the latch that says a phone has written the shared record — the same fact from
    /// the other end, and the thing `AnchorSync.macDrop` refuses a drop without.
    @Test func theAnchorStartsByWaitingForThePhone() {
        let guide = HalfGuide.macAnchor(config: Config(), finished: false, hasKey: false)
        #expect(guide.live == 0)
        #expect(guide.steps[0].title == "Link this Mac and your iPhone")
    }

    @Test func hearingFromThePhoneMovesTheAnchorToTheList() {
        let guide = HalfGuide.macAnchor(config: Config(), finished: false, hasKey: true)
        #expect(guide.steps[0].isDone)
        #expect(guide.live == 1)
    }

    @Test func somethingToHoldMovesTheAnchorToTheDrop() {
        var config = Config()
        config.anchor.kinds = [.macApp(bundleID: "com.apple.Safari")]
        let guide = HalfGuide.macAnchor(config: config, finished: false, hasKey: true)
        #expect(guide.steps[1].isDone)
        #expect(guide.live == 2)
    }

    /// An empty allowlist is still something to lock — it is the whole Mac — where an empty
    /// chosen list is nothing.
    @Test func theEverythingExceptScopeIsSomethingToHoldWhileEmpty() {
        var config = Config()
        config.anchor.scope = .everythingExcept
        let guide = HalfGuide.macAnchor(config: config, finished: false, hasKey: true)
        #expect(guide.steps[1].isDone)
        #expect(guide.live == 2)
    }

    @Test func theAnchorFoldsAwayOnceItHasBeenDropped() {
        var config = Config()
        config.anchor.kinds = [.macApp(bundleID: "com.apple.Safari")]
        #expect(HalfGuide.macAnchor(config: config, finished: false, hasKey: true).isRunning)
        #expect(!HalfGuide.macAnchor(config: config, finished: true, hasKey: true).isRunning)
    }

    /// The last step counts what is held. Before anything is chosen that count is zero, which is
    /// a true sentence about a step that has not happened and a poor one to read two ahead of it.
    @Test func theDropStepDoesNotCountAnEmptyList() {
        let empty = HalfGuide.macAnchor(config: Config(), finished: false, hasKey: true)
        #expect(!empty.steps[2].detail.contains("0 items"))

        var config = Config()
        config.anchor.kinds = [.macApp(bundleID: "com.apple.Safari"), .host("youtube.com")]
        let held = HalfGuide.macAnchor(config: config, finished: false, hasKey: true)
        #expect(held.steps[2].detail.contains("2 items"))
    }

    // MARK: The card

    /// The footnote belongs to the live step, so the fact arrives with the step rather than
    /// three screens earlier.
    @Test func theCardShowsTheLiveStepsFootnote() {
        let guide = HalfGuide.macAnchor(config: Config(), finished: false, hasKey: false)
        #expect(guide.footnote == guide.steps[0].footnote)
        #expect(guide.title == "Setting up the Anchor")
    }

    @Test func aFinishedGuideHasNoFootnoteLeft() {
        let config = makeConfig([makeTarget("YouTube", rule: Rule(windows: [window(540, 1320)], dailyBudgetMinutes: 45))])
        let guide = HalfGuide.macRules(config: config, finished: true)
        #expect(guide.live == nil)
        #expect(guide.footnote == nil)
    }
}
