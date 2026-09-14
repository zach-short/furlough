import Foundation
import Testing

/// The Mac's two three-step guides: each step but the last is derived from config, so these
/// check the derivation matches what's actually set up and the live step is what's still owed.
/// The phone's guides live with its views; the Mac's are pure enough to test here. See `HalfGuide`.
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

    // Restarting clears only the flag, so an already-set-up Mac comes back on its third step.
    @Test func restartingRulesComesBackOnTheThirdStep() {
        let config = makeConfig([makeTarget("YouTube", rule: Rule(windows: [window(540, 1320)], dailyBudgetMinutes: 45))])
        let guide = HalfGuide.macRules(config: config, finished: false)
        #expect(guide.live == 2)
        #expect(guide.steps[0].isDone)
        #expect(guide.steps[1].isDone)
    }

    // MARK: The Anchor

    // No reader on the Mac, so this step stands in for "Pair a tag": has a phone written the
    // shared record — the same thing `AnchorSync.macDrop` requires.
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

    // An empty allowlist is still the whole Mac to lock; an empty chosen list is nothing.
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

    // Zero is technically true before anything is chosen, but a poor thing to read two steps early.
    @Test func theDropStepDoesNotCountAnEmptyList() {
        let empty = HalfGuide.macAnchor(config: Config(), finished: false, hasKey: true)
        #expect(!empty.steps[2].detail.contains("0 items"))

        var config = Config()
        config.anchor.kinds = [.macApp(bundleID: "com.apple.Safari"), .host("youtube.com")]
        let held = HalfGuide.macAnchor(config: config, finished: false, hasKey: true)
        #expect(held.steps[2].detail.contains("2 items"))
    }

    // MARK: The card

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
