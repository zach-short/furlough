import Foundation
import Testing

/// What the Anchor's Live Activity should be showing, and the words it shares with the widget.
/// Fixed calendar: the 8th is a Tuesday, the 12th a Saturday.
@Suite("Anchor activity: what the Lock Screen should say")
struct AnchorActivityTests {
    func paired(_ kinds: [TargetKind], scope: AnchorProfile.Scope = .chosen) -> AnchorProfile {
        var anchor = AnchorProfile(kinds: kinds)
        anchor.scope = scope
        anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        return anchor
    }

    @Test("a tag-only hold carries its start and no lift")
    func tagOnlyHold() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com"), .host("x.com")])
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = at(8, 23, 0)
        let plan = Policy.anchorActivity(config: config, now: at(8, 23, 30), calendar: cal)
        #expect(plan?.droppedAt == at(8, 23, 0))
        #expect(plan?.until == nil)
        #expect(plan?.startsAt == nil)
        #expect(plan?.isScheduled == false)
        #expect(plan?.headline == "2 anchored")
        #expect(plan?.held == "2 items")
        #expect(plan?.anchorsEverything == false)
    }

    @Test("a timed hold carries the lift it counts down to")
    func timedHold() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com")])
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = at(8, 22, 0)
        config.anchor.until = at(9, 7, 0)
        let plan = Policy.anchorActivity(config: config, now: at(8, 23, 0), calendar: cal)
        #expect(plan?.until == at(9, 7, 0))
        #expect(plan?.startsAt == nil)
        #expect(plan?.headline == "1 anchored")
    }

    @Test("an everything-except hold says everything, never the size of the allowlist")
    func everythingExcept() {
        var config = makeConfig([])
        config.anchor = paired([.host("messages.com")], scope: .everythingExcept)
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = at(8, 21, 0)
        let plan = Policy.anchorActivity(config: config, now: at(8, 21, 30), calendar: cal)
        #expect(plan?.headline == "Everything anchored")
        #expect(plan?.held == "Everything except 1")
        #expect(plan?.anchorsEverything == true)
    }

    @Test("a lift that has passed is not a hold, and nothing is promised without a schedule")
    func expiredIsNothing() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com")])
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = at(8, 22, 0)
        config.anchor.until = at(8, 23, 0)
        #expect(Policy.anchorActivity(config: config, now: at(8, 23, 0), calendar: cal) == nil)
    }

    // MARK: A hold promised ahead

    @Test("a schedule promises the next drop, with the lift that schedule carries")
    func promisesTheNextDrop() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com")])
        // 10 PM every day, lifting at 6 AM the next morning.
        config.anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60, liftMinuteOfDay: 6 * 60)]
        let plan = Policy.anchorActivity(config: config, now: at(8, 12, 0), calendar: cal)
        #expect(plan?.startsAt == at(8, 22, 0))
        #expect(plan?.droppedAt == at(8, 22, 0))
        #expect(plan?.until == at(9, 6, 0))
        #expect(plan?.isScheduled == true)
    }

    @Test("the soonest of several schedules wins, and brings its own lift")
    func soonestWins() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com")])
        config.anchor.schedules = [
            AnchorSchedule(minuteOfDay: 22 * 60, liftMinuteOfDay: 6 * 60),
            AnchorSchedule(minuteOfDay: 14 * 60, liftMinuteOfDay: 15 * 60),
        ]
        let plan = Policy.anchorActivity(config: config, now: at(8, 12, 0), calendar: cal)
        #expect(plan?.startsAt == at(8, 14, 0))
        #expect(plan?.until == at(8, 15, 0))
    }

    @Test("a hold that is on beats a schedule that has not come round yet")
    func holdBeatsPromise() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com")])
        config.anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60)]
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = at(8, 12, 0)
        let plan = Policy.anchorActivity(config: config, now: at(8, 13, 0), calendar: cal)
        #expect(plan?.startsAt == nil)
        #expect(plan?.droppedAt == at(8, 12, 0))
    }

    @Test("nothing is promised the schedule could not perform: no tag, or nothing to hold")
    func promisesOnlyWhatCanHappen() {
        var config = makeConfig([])
        var anchor = AnchorProfile(kinds: [.host("tiktok.com")])
        anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60)]
        config.anchor = anchor
        // The same two conditions `scheduledDrop` checks.
        #expect(Policy.anchorActivity(config: config, now: at(8, 12, 0), calendar: cal) == nil)
        config.anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        #expect(Policy.anchorActivity(config: config, now: at(8, 12, 0), calendar: cal) != nil)
        config.anchor.kinds = []
        #expect(Policy.anchorActivity(config: config, now: at(8, 12, 0), calendar: cal) == nil)
    }

    @Test("a schedule on days that never come promises nothing")
    func noDaysNoPromise() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com")])
        config.anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60, days: Weekdays())]
        #expect(Policy.anchorActivity(config: config, now: at(8, 12, 0), calendar: cal) == nil)
    }

    @Test("the plan moves onto the device's clock whole, or not at all")
    func shifting() {
        var config = makeConfig([])
        config.anchor = paired([.host("tiktok.com")])
        config.anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60, liftMinuteOfDay: 6 * 60)]
        let plan = Policy.anchorActivity(config: config, now: at(8, 12, 0), calendar: cal)
        let shifted = plan?.shifted(by: 3600)
        #expect(shifted?.startsAt == at(8, 23, 0))
        #expect(shifted?.droppedAt == at(8, 23, 0))
        #expect(shifted?.until == at(9, 7, 0))
        #expect(plan?.shifted(by: 0) == plan)
    }

    // MARK: The words, shared with the widget

    @Test("the anchor's line is one wording for the widget and the Lock Screen")
    func oneWording() {
        #expect(AnchorText.headline(everything: false, count: 1) == "1 anchored")
        #expect(AnchorText.headline(everything: true, count: 3) == "Everything anchored")
        #expect(AnchorText.line(everything: false, count: 3, until: nil, calendar: cal) == "3 anchored")
        #expect(
            plainSpaces(AnchorText.line(everything: true, count: 0, until: at(8, 18, 30), calendar: cal))
                == "Everything anchored · lifts 6:30 PM"
        )
    }
}
