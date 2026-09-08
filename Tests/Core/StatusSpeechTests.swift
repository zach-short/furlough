import Foundation
import Testing

/// The sentence the App Intents answer with, from Spotlight or Siri. There is no hourglass
/// and no list out there, so the whole status has to survive being said out loud.
@Suite("StatusSpeech")
struct StatusSpeechTests {
    /// Tuesday 8 September 2026 at 12:30, the same moment the summary tests use.
    let now = at(8, 12, 30)

    /// Through `plainSpaces`: the times in these sentences come out of ICU with a narrow
    /// no-break space before AM/PM, which is right everywhere it is shown and cannot be
    /// written in a literal below.
    func said(_ state: SharedState) -> String {
        plainSpaces(
            StatusSpeech.sentence(
                Policy.summary(state: state, now: now, calendar: cal),
                hasTargets: !state.config.targets.isEmpty,
                now: now,
                calendar: cal
            )
        )
    }

    func openNow(_ name: String) -> Target {
        makeTarget(name, rule: Rule(windows: [window(720, 780)], dailyBudgetMinutes: 60))
    }

    // MARK: Nothing to say

    @Test("an install with nothing in it says so, rather than that nothing is open")
    func empty() {
        #expect(said(makeState([])) == "Nothing is in Furlough yet.")
    }

    @Test("targets with nothing open and nothing coming")
    func quiet() {
        let blocked = makeTarget("Blocked", rule: Rule(windows: [], dailyBudgetMinutes: 0))
        #expect(said(makeState([blocked])) == "Nothing is open.")
    }

    // MARK: What is open

    @Test("a window says when it closes")
    func openWindow() {
        #expect(said(makeState([openNow("YouTube")])) == "YouTube is open until 1:00 PM.")
    }

    @Test("a rule with no windows is open all day, and gets no closing time")
    func allDay() {
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        #expect(said(makeState([mail])) == "Mail is open all day.")
    }

    @Test("the two kinds of open are said in one sentence")
    func both() {
        let mail = makeTarget("Mail", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        #expect(
            said(makeState([openNow("YouTube"), mail]))
                == "YouTube is open until 1:00 PM, and Mail is open all day."
        )
    }

    @Test("two names are joined, three are listed")
    func names() {
        #expect(said(makeState([openNow("A"), openNow("B")])) == "A and B are open until 1:00 PM.")
        #expect(said(makeState([openNow("A"), openNow("B"), openNow("C")])) == "A, B and C are open until 1:00 PM.")
    }

    /// Four apps read aloud is a list, not an answer.
    @Test("past three, the names give way to a count")
    func tooManyToName() {
        let many = [openNow("A"), openNow("B"), openNow("C"), openNow("D")]
        #expect(said(makeState(many)) == "4 things are open until 1:00 PM.")
    }

    // MARK: What is next

    @Test("nothing open names what opens next, in the words the rows use")
    func nextToday() {
        let evening = makeTarget("Evening", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        #expect(said(makeState([evening])) == "Nothing is open. Evening opens at 8:00 PM.")
    }

    @Test("one that has already closed today opens tomorrow")
    func nextTomorrow() {
        let morning = makeTarget("Morning", rule: Rule(windows: [window(480, 540)], dailyBudgetMinutes: 30))
        #expect(said(makeState([morning])) == "Nothing is open. Morning opens tomorrow at 8:00 AM.")
    }

    // MARK: The anchor and the delay

    @Test("the anchor is said first, because it is the thing a tag has to lift")
    func anchored() {
        var state = makeState([])
        state.config.anchor.kinds = [.host("a.com"), .host("b.com")]
        state.config.anchor.isAnchored = true
        #expect(said(state) == "Anchored: 2 things locked until you scan your tag. Nothing is open.")
    }

    @Test("a queued loosening is counted, and agrees with itself")
    func pending() {
        let target = openNow("YouTube")
        let queued = PendingChange(
            kind: .setRule(targetID: target.id, rule: Rule(windows: [], dailyBudgetMinutes: 60)),
            effectiveAt: at(9, 12, 0)
        )
        #expect(
            said(makeState([target], pending: [queued]))
                == "YouTube is open until 1:00 PM. 1 change is still waiting out the delay."
        )
        #expect(said(makeState([target], pending: [queued, queued])).hasSuffix("2 changes are still waiting out the delay."))
    }
}
