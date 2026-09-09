import Foundation
import Testing

/// The sentence the editor says before a rule is saved. The cheapest forgiveness is the kind
/// nobody needs, so this is the one that has to be right: a preview that lies is worse than
/// none at all.
@Suite struct ConsequenceTests {

    // MARK: What today looks like

    @Test func aBudgetAloneSaysWhenItRunsOut() {
        let rule = Rule(windows: [], dailyBudgetMinutes: 30)
        #expect(Consequence.today(rule: rule, now: at(8), calendar: cal)
            == "Open all day, up to 30 min. Once that is gone, blocked until midnight.")
    }

    @Test func windowsAreSaidWithTodaysHours() {
        let rule = Rule(windows: [window(540, 1020)], dailyBudgetMinutes: 30)
        #expect(plainSpaces(Consequence.today(rule: rule, now: at(8), calendar: cal))
            == "Open 9:00 AM–5:00 PM today, up to 30 min. Blocked the rest of the day.")
    }

    @Test func aWholeDayOfBudgetIsNoBudgetToSay() {
        let rule = Rule(windows: [window(540, 1020)], dailyBudgetMinutes: Furlough.minutesPerDay)
        #expect(plainSpaces(Consequence.today(rule: rule, now: at(8), calendar: cal))
            == "Open 9:00 AM–5:00 PM today. Blocked the rest of the day.")
    }

    @Test func twoWindowsRead() {
        let rule = Rule(windows: [window(480, 540), window(1200, 1320)], dailyBudgetMinutes: 45)
        #expect(plainSpaces(Consequence.today(rule: rule, now: at(8), calendar: cal))
            == "Open 8:00 AM–9:00 AM and 8:00 PM–10:00 PM today, up to 45 min. Blocked the rest of the day.")
    }

    /// The 8th is a Tuesday; this rule only opens at the weekend.
    @Test func aDayNoWindowCoversSaysSoAndSaysWhenItOpens() {
        let rule = Rule(windows: [window(600, 720, .weekend)], dailyBudgetMinutes: 30)
        #expect(plainSpaces(Consequence.today(rule: rule, now: at(8), calendar: cal))
            == "Blocked all day today. Opens Saturday at 10:00 AM.")
    }

    @Test func aZeroBudgetIsBlockedEveryDay() {
        #expect(Consequence.today(rule: Rule(windows: [], dailyBudgetMinutes: 0), now: at(8), calendar: cal)
            == "Blocked all day, every day.")
    }

    /// A night is stored as an evening plus a morning on the day after, and it is read as the
    /// one span it was written as: nothing shuts at midnight, so nothing says it does.
    @Test func aNightIsSaidThroughToTheMorningItEndsIn() {
        let tuesday = Weekdays.tuesday
        let rule = Rule(
            windows: [window(1200, 1440, tuesday), window(0, 240, .wednesday)],
            dailyBudgetMinutes: 60
        )
        #expect(plainSpaces(Consequence.today(rule: rule, now: at(8), calendar: cal))
            == "Open 8:00 PM–4:00 AM today, up to 1 hour. Blocked the rest of the day.")
    }

    /// And the morning half is still today's, on the day it falls. Answering "blocked all day"
    /// to someone holding the phone at 2 AM would be plainly false.
    @Test func theMorningOfANightIsStillOpenOnItsOwnDay() {
        let rule = Rule(
            windows: [window(1200, 1440, .tuesday), window(0, 240, .wednesday)],
            dailyBudgetMinutes: 60
        )
        #expect(plainSpaces(Consequence.today(rule: rule, now: at(9, 2), calendar: cal))
            == "Open 12:00 AM–4:00 AM today, up to 1 hour. Blocked the rest of the day.")
    }

    // MARK: What changing your mind costs

    @Test func outsideTheWeekItNamesTheWindowAndTheDelay() {
        let target = makeTarget("YouTube", rule: Rule())
        let config = makeConfig([target])
        #expect(Consequence.undoing(for: target, config: config, now: at(8), calendar: cal)
            == "You can undo this for 15 minutes after saving. After that, loosening it takes 1 day.")
    }

    /// A first rule replaces nothing, so what there is to undo is the whole of it.
    @Test func aFirstRuleTalksAboutRemoving() {
        let target = makeTarget("Messenger", rule: nil)
        #expect(Consequence.undoing(for: target, config: makeConfig([target]), now: at(8), calendar: cal)
            == "You can undo this for 15 minutes after saving. After that, removing it takes 1 day.")
    }

    /// Both numbers, because the point of saying it early is that the end of the week is not
    /// a surprise the first time a delay is real.
    @Test func insideTheWeekItNamesTheCliffTheWeekEndsOn() {
        var target = makeTarget("TikTok", rule: Rule())
        target.utilityLevel = .hazard
        var config = makeConfig([target])
        Forgiveness.startTrial(&config, now: at(8))
        #expect(Consequence.undoing(for: target, config: config, now: at(8), calendar: cal)
            == "Your first week runs to Sep 15: until then loosening it takes 1 hour, and after it, 4 days.")
    }

    // MARK: When there is nothing worth saying

    @Test func nothingIsSaidAboutALoosening() {
        let target = makeTarget("YouTube", rule: Rule(windows: [window(540, 600)], dailyBudgetMinutes: 10))
        let looser = Rule(windows: [window(540, 1020)], dailyBudgetMinutes: 120)
        #expect(Consequence.preview(rule: looser, for: target, config: makeConfig([target]), now: at(8), calendar: cal) == nil)
    }

    @Test func nothingIsSaidWhenNothingChanges() {
        let rule = Rule(windows: [window(540, 600)], dailyBudgetMinutes: 10)
        let target = makeTarget("YouTube", rule: rule)
        #expect(Consequence.preview(rule: rule, for: target, config: makeConfig([target]), now: at(8), calendar: cal) == nil)
    }

    @Test func nothingIsSaidAboutARuleThatWillNotSave() {
        let broken = Rule(windows: [window(540, 545)], dailyBudgetMinutes: 10)
        #expect(broken.validationError != nil)
        #expect(Consequence.preview(rule: broken, for: nil, config: makeConfig([]), now: at(8), calendar: cal) == nil)
    }

    /// A brand-new target: the rule is a tightening against "unrestricted", so both halves get
    /// said, and they are the two sentences the whole feature turns on.
    @Test func aFirstRuleOnANewTargetSaysBothHalves() throws {
        let preview = try #require(
            Consequence.preview(
                rule: Rule(windows: [], dailyBudgetMinutes: 5),
                for: nil,
                config: makeConfig([]),
                now: at(8),
                calendar: cal
            )
        )
        #expect(preview.today == "Open all day, up to 5 min. Once that is gone, blocked until midnight.")
        #expect(preview.undoing == "You can undo this for 15 minutes after saving. After that, removing it takes 1 day.")
    }
}
