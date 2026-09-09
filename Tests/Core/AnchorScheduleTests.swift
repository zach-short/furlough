import Foundation
import Testing

/// The anchor's clock, added 2026-09-09: a timed drop (`until`), scheduled drops
/// (`schedules`), and the pure decisions the monitor and the app make with them. The 8th is a
/// Tuesday in the fixed calendar, the 12th a Saturday.
@Suite("Anchor schedule: a timed drop")
struct AnchorUntilTests {
    let openAllDay = Rule(windows: [], dailyBudgetMinutes: 30)

    func timed(until: Date, kinds: [TargetKind]) -> AnchorProfile {
        var anchor = AnchorProfile(kinds: kinds)
        anchor.isAnchored = true
        anchor.anchoredAt = at(8, 12, 0)
        anchor.until = until
        anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        return anchor
    }

    @Test("a timed anchor holds until its time and not a second past it")
    func holdsUntil() {
        let anchor = timed(until: at(8, 18, 0), kinds: [.host("tiktok.com")])
        #expect(anchor.isHolding(at: at(8, 17, 59)))
        #expect(!anchor.isHolding(at: at(8, 18, 0)))
        #expect(anchor.blocks(.host("tiktok.com"), at: at(8, 17, 59)))
        #expect(!anchor.blocks(.host("tiktok.com"), at: at(8, 18, 0)))
        // No `until` is the tag alone, whenever it is asked.
        var forever = anchor
        forever.until = nil
        #expect(forever.isHolding(at: .distantFuture))
    }

    @Test("status and the decision read the anchor as released once its time has passed")
    func statusAndDecisionFollow() {
        let tiktok = makeTarget("TikTok", rule: openAllDay)
        var config = makeConfig([tiktok])
        config.anchor = timed(until: at(8, 18, 0), kinds: [tiktok.kind])
        let before = Policy.decide(config: config, runtime: RuntimeState(), now: at(8, 17, 0), calendar: cal)
        #expect(before.statuses[tiktok.id] == .anchored)
        #expect(before.blockedHosts == ["tiktok.com"])
        let after = Policy.decide(config: config, runtime: RuntimeState(), now: at(8, 18, 0), calendar: cal)
        #expect(after.statuses[tiktok.id] == .open(until: 1440))
        #expect(!after.isAnythingShielded)
        #expect(!Policy.summary(state: makeState([tiktok]), now: at(8, 18, 0), calendar: cal).isAnchored)
    }

    @Test("the summary carries the lift time, and the widget can offer a drop only while it is up")
    func summaryCarriesUntil() {
        var state = makeState([])
        state.config.anchor = timed(until: at(8, 18, 0), kinds: [.host("tiktok.com")])
        let down = Policy.summary(state: state, now: at(8, 17, 0), calendar: cal)
        #expect(down.isAnchored)
        #expect(down.anchorUntil == at(8, 18, 0))
        #expect(!down.canDropAnchor)
        #expect(down.shifted(by: 60).anchorUntil == at(8, 18, 1))
        let up = Policy.summary(state: state, now: at(8, 18, 0), calendar: cal)
        #expect(!up.isAnchored)
        #expect(up.anchorUntil == nil)
        #expect(up.canDropAnchor)
    }

    @Test("lifting an expired anchor clears it, and only an expired one")
    func liftExpired() {
        var config = makeConfig([])
        config.anchor = timed(until: at(8, 18, 0), kinds: [.host("tiktok.com")])
        #expect(!Policy.liftExpiredAnchor(&config, now: at(8, 17, 59)))
        #expect(config.anchor.isAnchored)
        #expect(Policy.liftExpiredAnchor(&config, now: at(8, 18, 0)))
        #expect(!config.anchor.isAnchored)
        #expect(config.anchor.anchoredAt == nil)
        #expect(config.anchor.until == nil)
        // A tag-only anchor never expires.
        config.anchor.isAnchored = true
        #expect(!Policy.liftExpiredAnchor(&config, now: .distantFuture))
        #expect(config.anchor.isAnchored)
    }

    @Test("the next transition is the lift when it comes before the next window edge")
    func nextTransitionIncludesUntil() {
        let evening = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        var config = makeConfig([evening])
        config.anchor = timed(until: at(8, 18, 0), kinds: [evening.kind])
        #expect(Policy.nextTransition(config: config, after: at(8, 12, 0), calendar: cal) == at(8, 18, 0))
        config.anchor.until = at(8, 21, 0)
        #expect(Policy.nextTransition(config: config, after: at(8, 12, 0), calendar: cal) == at(8, 20, 0))
        // Past its time it is no longer a transition, and neither is a tag-only anchor.
        config.anchor.until = at(8, 11, 0)
        #expect(Policy.nextTransition(config: config, after: at(8, 12, 0), calendar: cal) == at(8, 20, 0))
    }

    @Test("dropping the anchor: what it refuses, and what it writes")
    func drop() {
        var config = makeConfig([])
        // No tag, nothing to hold.
        #expect(Policy.drop(&config, now: at(8, 12, 0)) == .nothingToAnchor)
        config.anchor.kinds = [.host("tiktok.com")]
        config.anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        // Too short a hold for the monitor to be woken for.
        #expect(Policy.drop(&config, now: at(8, 12, 0), until: at(8, 12, 10)) == .tooSoon)
        #expect(!config.anchor.isAnchored)
        #expect(Policy.drop(&config, now: at(8, 12, 0), until: at(8, 12, 15)) == nil)
        #expect(config.anchor.isAnchored)
        #expect(config.anchor.anchoredAt == at(8, 12, 0))
        #expect(config.anchor.until == at(8, 12, 15))
        #expect(Policy.drop(&config, now: at(8, 12, 1)) == .alreadyAnchored)
        // Once the time has passed the expired anchor is folded and it can drop again, this
        // time until the tag.
        #expect(Policy.drop(&config, now: at(8, 12, 15)) == nil)
        #expect(config.anchor.until == nil)
        #expect(config.anchor.anchoredAt == at(8, 12, 15))
    }

    @Test("the refusals have words")
    func refusalMessages() {
        #expect(Policy.DropRefusal.alreadyAnchored.message == "Already anchored.")
        #expect(Policy.DropRefusal.nothingToAnchor.message == "Choose apps and pair a tag first.")
        #expect(Policy.DropRefusal.tooSoon.message.contains("15 minutes"))
    }
}

@Suite("Anchor schedule: drop times")
struct AnchorScheduleTimeTests {
    let schoolNights = AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays)

    @Test("the next drop is later today when today is a school night")
    func laterToday() {
        // Tuesday noon.
        #expect(schoolNights.nextDrop(after: at(8, 12, 0), calendar: cal) == at(8, 22, 0))
    }

    @Test("the next drop skips the weekend")
    func skipsTheWeekend() {
        // Friday 11 PM: past tonight's drop, and Saturday and Sunday are off, so Monday.
        #expect(schoolNights.nextDrop(after: at(11, 23, 0), calendar: cal) == at(14, 22, 0))
    }

    @Test("a drop at exactly now is the one that just fired, so the next is tomorrow's")
    func nowIsPast() {
        #expect(schoolNights.nextDrop(after: at(8, 22, 0), calendar: cal) == at(9, 22, 0))
    }

    @Test("a schedule on no days never drops, and does not stop the others")
    func noDays() {
        let never = AnchorSchedule(minuteOfDay: 20 * 60, days: [])
        #expect(never.nextDrop(after: at(8, 12, 0), calendar: cal) == nil)
        #expect([never].nextDrop(after: at(8, 12, 0), calendar: cal) == nil)
        #expect([never, schoolNights].nextDrop(after: at(8, 12, 0), calendar: cal) == at(8, 22, 0))
    }

    @Test("the soonest of several wins, a week out at most")
    func soonestOfSeveral() {
        let saturday = AnchorSchedule(minuteOfDay: 9 * 60, days: .saturday)
        #expect([saturday, schoolNights].nextDrop(after: at(12, 10, 0), calendar: cal) == at(14, 22, 0))
        #expect(saturday.nextDrop(after: at(12, 10, 0), calendar: cal) == at(19, 9, 0))
    }

    @Test("a lift earlier in the day than the drop is the next morning")
    func liftDate() {
        var schedule = schoolNights
        #expect(schedule.liftDate(afterDropAt: at(8, 22, 0), calendar: cal) == nil)
        schedule.liftMinuteOfDay = 7 * 60
        #expect(schedule.liftDate(afterDropAt: at(8, 22, 0), calendar: cal) == at(9, 7, 0))
        schedule.liftMinuteOfDay = 23 * 60
        #expect(schedule.liftDate(afterDropAt: at(8, 22, 0), calendar: cal) == at(8, 23, 0))
        #expect(AnchorSchedule.holdMinutes(drop: 22 * 60, lift: 7 * 60) == 9 * 60)
        #expect(AnchorSchedule.holdMinutes(drop: 22 * 60, lift: 23 * 60) == 60)
    }
}

@Suite("Anchor schedule: the monitor's drop")
struct AnchorScheduledDropTests {
    func ready(_ schedules: [AnchorSchedule]) -> Config {
        var config = makeConfig([])
        config.anchor.kinds = [.host("tiktok.com")]
        config.anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        config.anchor.schedules = schedules
        return config
    }

    @Test("the activity for a school-night drop anchors on a Tuesday and not on a Saturday")
    func dropsOnItsDays() {
        var config = ready([AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays)])
        #expect(Policy.scheduledDrop(&config, minute: 22 * 60, now: at(12, 22, 0), calendar: cal) == nil)
        #expect(!config.anchor.isAnchored)
        let dropped = Policy.scheduledDrop(&config, minute: 22 * 60, now: at(8, 22, 1), calendar: cal)
        #expect(dropped?.minuteOfDay == 22 * 60)
        #expect(config.anchor.isAnchored)
        #expect(config.anchor.anchoredAt == at(8, 22, 1))
        #expect(config.anchor.until == nil)
        // The activity at another minute is not this schedule's.
        var other = ready([AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays)])
        #expect(Policy.scheduledDrop(&other, minute: 21 * 60, now: at(8, 21, 0), calendar: cal) == nil)
    }

    @Test("a schedule with a lift sets the lift from the minute it names, not the late callback")
    func liftFromTheScheduledMinute() {
        var config = ready([AnchorSchedule(minuteOfDay: 22 * 60, days: .all, liftMinuteOfDay: 7 * 60)])
        Policy.scheduledDrop(&config, minute: 22 * 60, now: at(8, 22, 4), calendar: cal)
        #expect(config.anchor.isAnchored)
        #expect(config.anchor.until == at(9, 7, 0))
    }

    @Test("nothing drops without a tag or with nothing to hold")
    func needsATagAndAList() {
        var untagged = ready([AnchorSchedule(minuteOfDay: 22 * 60)])
        untagged.anchor.tags = []
        #expect(Policy.scheduledDrop(&untagged, minute: 22 * 60, now: at(8, 22, 0), calendar: cal) == nil)
        var empty = ready([AnchorSchedule(minuteOfDay: 22 * 60)])
        empty.anchor.kinds = []
        #expect(Policy.scheduledDrop(&empty, minute: 22 * 60, now: at(8, 22, 0), calendar: cal) == nil)
        // An empty allowlist is the whole phone, which is something to hold.
        empty.anchor.scope = .everythingExcept
        #expect(Policy.scheduledDrop(&empty, minute: 22 * 60, now: at(8, 22, 0), calendar: cal) != nil)
    }

    @Test("with the anchor already down, a schedule only ever lengthens the hold")
    func onlyTightens() {
        var config = ready([
            AnchorSchedule(minuteOfDay: 22 * 60),
            AnchorSchedule(minuteOfDay: 21 * 60, liftMinuteOfDay: 23 * 60),
            AnchorSchedule(minuteOfDay: 20 * 60, liftMinuteOfDay: 6 * 60),
        ])
        // Dropped by hand until 10:30 PM.
        #expect(Policy.drop(&config, now: at(8, 19, 0), until: at(8, 22, 30)) == nil)
        // 8 PM's lift is 6 AM tomorrow: later, so it replaces 10:30 PM.
        #expect(Policy.scheduledDrop(&config, minute: 20 * 60, now: at(8, 20, 0), calendar: cal) != nil)
        #expect(config.anchor.until == at(9, 6, 0))
        // 9 PM's lift is 11 PM tonight: earlier, so nothing changes.
        #expect(Policy.scheduledDrop(&config, minute: 21 * 60, now: at(8, 21, 0), calendar: cal) == nil)
        #expect(config.anchor.until == at(9, 6, 0))
        // 10 PM is tag-only: the tightest of all.
        #expect(Policy.scheduledDrop(&config, minute: 22 * 60, now: at(8, 22, 0), calendar: cal) != nil)
        #expect(config.anchor.until == nil)
        // And nothing loosens a tag-only anchor.
        #expect(Policy.scheduledDrop(&config, minute: 21 * 60, now: at(9, 21, 0), calendar: cal) == nil)
        #expect(config.anchor.until == nil)
        #expect(config.anchor.anchoredAt == at(8, 19, 0))
    }

    @Test("a lift already past by the time the callback arrives drops nothing")
    func lateCallbackPastTheLift() {
        var config = ready([AnchorSchedule(minuteOfDay: 22 * 60, liftMinuteOfDay: 22 * 60 + 5)])
        #expect(Policy.scheduledDrop(&config, minute: 22 * 60, now: at(8, 22, 6), calendar: cal) == nil)
        #expect(!config.anchor.isAnchored)
    }

    @Test("the tighter of two ends")
    func tighterUntil() {
        #expect(Policy.tighterUntil(nil, at(8, 1)) == nil)
        #expect(Policy.tighterUntil(at(8, 1), nil) == nil)
        #expect(Policy.tighterUntil(at(8, 1), at(8, 2)) == at(8, 2))
        #expect(Policy.tighterUntil(at(8, 2), at(8, 1)) == at(8, 2))
    }
}

@Suite("Anchor schedule: tightening and loosening")
struct AnchorScheduleClassifyTests {
    let tenWeekdays = AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays)

    func classify(_ new: [AnchorSchedule], against old: [AnchorSchedule]) -> ChangeClass {
        Policy.classify(newSchedules: new, against: old)
    }

    @Test("adding a drop, a day, or a whole schedule lands at once")
    func adding() {
        #expect(classify([tenWeekdays], against: []) == .tightening)
        var everyDay = tenWeekdays
        everyDay.days = .all
        #expect(classify([everyDay], against: [tenWeekdays]) == .tightening)
        let nine = AnchorSchedule(minuteOfDay: 21 * 60, days: .weekdays)
        #expect(classify([tenWeekdays, nine], against: [tenWeekdays]) == .tightening)
        #expect(classify([tenWeekdays], against: [tenWeekdays]) == .tightening)
    }

    @Test("removing a drop, taking a day off it, or moving it waits out the delay")
    func removing() {
        #expect(classify([], against: [tenWeekdays]) == .loosening)
        var fewerDays = tenWeekdays
        fewerDays.days = [.monday, .tuesday, .wednesday, .thursday]
        #expect(classify([fewerDays], against: [tenWeekdays]) == .loosening)
        var moved = tenWeekdays
        moved.minuteOfDay = 21 * 60
        #expect(classify([moved], against: [tenWeekdays]) == .loosening)
        // Same drop on the same days under a new identity is the same schedule.
        let same = AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays)
        #expect(classify([same], against: [tenWeekdays]) == .tightening)
    }

    @Test("a lift is a loosening of the hold: adding one or moving it earlier waits, removing one or moving it later lands")
    func lifts() {
        var lifts7 = tenWeekdays
        lifts7.liftMinuteOfDay = 7 * 60
        var lifts6 = tenWeekdays
        lifts6.liftMinuteOfDay = 6 * 60
        var lifts8 = tenWeekdays
        lifts8.liftMinuteOfDay = 8 * 60
        #expect(classify([lifts7], against: [tenWeekdays]) == .loosening)
        #expect(classify([tenWeekdays], against: [lifts7]) == .tightening)
        #expect(classify([lifts6], against: [lifts7]) == .loosening)
        #expect(classify([lifts8], against: [lifts7]) == .tightening)
        #expect(classify([lifts7], against: [lifts7]) == .tightening)
    }

    @Test("a schedule change lands now or queues, and the queue's copy replaces the config's when it lands")
    func applyPending() {
        let state = makeState([])
        var config = state.config
        let change = PendingChange(kind: .setAnchorSchedules([tenWeekdays]), effectiveAt: at(9))
        #expect(change.targetID == nil)
        Policy.apply(change, to: &config)
        #expect(config.anchor.schedules == [tenWeekdays])
        var due = state
        due.config = config
        due.pending = [PendingChange(kind: .setAnchorSchedules([]), effectiveAt: at(9))]
        #expect(Policy.applyDuePending(&due, now: at(9)))
        #expect(due.config.anchor.schedules.isEmpty)
    }

    @Test("a schedule loosening waits out the slowest thing the anchor holds")
    func anchorDelay() {
        var messages = makeTarget("Messages", rule: .unrestricted)
        messages.utilityLevel = .essential
        var tiktok = makeTarget("TikTok", rule: .unrestricted)
        tiktok.utilityLevel = .hazard
        var config = makeConfig([messages, tiktok], delayHours: 24)
        #expect(config.anchorDelayHours == 24)
        config.anchor.kinds = [messages.kind]
        #expect(config.anchorDelayHours == 6)
        config.anchor.kinds = [messages.kind, tiktok.kind]
        #expect(config.anchorDelayHours == 96)
        // Everything except Messages holds TikTok.
        config.anchor.scope = .everythingExcept
        config.anchor.kinds = [messages.kind]
        #expect(config.anchorDelayHours == 96)
    }

    @Test("the pending card and its notification say what the schedule becomes")
    func pendingCopy() {
        var config = makeConfig([])
        config.anchor.schedules = [tenWeekdays]
        let change = PendingChange(kind: .setAnchorSchedules([]), effectiveAt: at(9))
        let delta = PendingText.delta(for: change, in: config, calendar: cal)
        #expect(plainSpaces(delta.now).contains("10:00 PM"))
        #expect(plainSpaces(delta.now).contains("weekdays"))
        #expect(delta.becomes == "No scheduled drops")
        #expect(PendingText.subject(of: change.kind) == "Anchor schedule")
        #expect(PendingText.subject(of: .setDelay(hours: 1)) == "Loosening delay")
        #expect(PendingText.subject(of: .removeTarget(targetID: UUID())) == nil)
        let described = PendingNotifications.describe(change, in: config, calendar: cal)
        #expect(described.contains("No scheduled drops"))
    }

    @Test("a schedule reads as a sentence")
    func wording() {
        var lifts = tenWeekdays
        lifts.liftMinuteOfDay = 7 * 60
        let weekend = AnchorSchedule(minuteOfDay: 23 * 60, days: .weekend)
        let text = plainSpaces(TimeFormat.anchorSchedules([weekend, lifts], calendar: cal))
        #expect(text == "10:00 PM weekdays, lifts 7:00 AM · 11:00 PM weekends, until the tag")
        #expect(TimeFormat.anchorSchedules([], calendar: cal) == "No scheduled drops")
    }
}

@Suite("Anchor schedule: activities and stored state")
struct AnchorScheduleActivityTests {
    func windows(_ count: Int) -> [TimeWindow] {
        (0..<count).map { window($0 * 60, $0 * 60 + 30) }
    }

    @Test("one activity per distinct drop minute and per distinct lift minute, plus a timed anchor's own")
    func counting() {
        var state = makeState([])
        #expect(ActivityLimit.anchorActivities(in: state) == 0)
        state.config.anchor.schedules = [
            AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays),
            AnchorSchedule(minuteOfDay: 22 * 60, days: .weekend, liftMinuteOfDay: 9 * 60),
            AnchorSchedule(minuteOfDay: 21 * 60, days: .sunday, liftMinuteOfDay: 9 * 60),
        ]
        #expect(ActivityLimit.anchorActivities(in: state) == 3)
        state.config.anchor.isAnchored = true
        state.config.anchor.until = at(8, 18)
        #expect(ActivityLimit.anchorActivities(in: state) == 4)
        #expect(ActivityLimit.activities(in: state) == 4)
        state.config.targets = [makeTarget("A", rule: Rule(windows: windows(2), dailyBudgetMinutes: 30))]
        #expect(ActivityLimit.activities(in: state) == 6)
    }

    @Test("a queued schedule change counts alongside the saved one, as queued rules do")
    func queuedCounts() {
        var state = makeState([])
        state.config.anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60)]
        state.pending = [PendingChange(kind: .setAnchorSchedules([AnchorSchedule(minuteOfDay: 21 * 60)]), effectiveAt: at(9))]
        #expect(ActivityLimit.anchorActivities(in: state) == 2)
    }

    @Test("the anchor's times press against the same ceiling as the windows")
    func ceiling() {
        let state = makeState([makeTarget("A", rule: Rule(windows: windows(18), dailyBudgetMinutes: 30))])
        #expect(ActivityLimit.reason(schedules: [AnchorSchedule(minuteOfDay: 22 * 60)], in: state) == nil)
        let two = [AnchorSchedule(minuteOfDay: 22 * 60), AnchorSchedule(minuteOfDay: 21 * 60)]
        #expect(ActivityLimit.reason(schedules: two, in: state) != nil)
        // And a rule edit sees the anchor's times.
        var withAnchor = state
        withAnchor.config.anchor.schedules = two
        let more = Rule(windows: windows(18), dailyBudgetMinutes: 30)
        #expect(ActivityLimit.reason(applying: more, to: [state.config.targets[0].id], in: withAnchor) != nil)
    }

    @Test("the anchor's activities are named, parsed, and placed so the minute is a callback")
    func naming() {
        #expect(ActivityNaming.anchorDrop(minute: 1320) == "anchor:1320")
        #expect(ActivityNaming.parseAnchorDrop("anchor:1320") == 1320)
        #expect(ActivityNaming.parseAnchorDrop("anchor-lift:1320") == nil)
        #expect(ActivityNaming.anchorLift(minute: 420) == "anchor-lift:420")
        #expect(ActivityNaming.parseAnchorLift("anchor-lift:420") == 420)
        #expect(ActivityNaming.parseAnchorLift("anchor:420") == nil)
        #expect(ActivityNaming.parseWindow("anchor:1320") == nil)
        // A drop at 10 PM is the end of a 9:45–10:00 activity; one at 12:05 AM has no
        // quarter hour before it, so it is the start of a 12:05–12:20 activity.
        let ten = ActivityNaming.anchorInterval(minute: 1320)
        #expect(ten.start == 1305 && ten.end == 1320 && !ten.firesAtStart)
        let five = ActivityNaming.anchorInterval(minute: 5)
        #expect(five.start == 5 && five.end == 20 && five.firesAtStart)
    }

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @Test("an anchor stored before it had a clock decodes with no time and no schedule")
    func decodesWithoutTheClock() throws {
        let json = #"{"targets":[],"loosenDelayHours":24,"anchor":{"kinds":[],"isAnchored":true,"scope":"chosen"}}"#
        let config = try decoder.decode(Config.self, from: Data(json.utf8))
        #expect(config.anchor.isAnchored)
        #expect(config.anchor.until == nil)
        #expect(config.anchor.schedules.isEmpty)
        #expect(config.anchor.isHolding(at: .distantFuture))
    }

    @Test("a timed anchor, its schedules and a queued schedule change all round-trip")
    func roundTrip() throws {
        var state = SharedState()
        state.config.anchor.isAnchored = true
        state.config.anchor.until = at(8, 18)
        state.config.anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays, liftMinuteOfDay: 7 * 60)]
        // A whole-second creation date: ISO 8601 keeps no fraction, and this compares the whole change.
        state.pending = [PendingChange(kind: .setAnchorSchedules([]), createdAt: at(8), effectiveAt: at(9))]
        let data = try encoder.encode(state)
        let back = try decoder.decode(SharedState.self, from: data)
        #expect(back.config.anchor.until == at(8, 18))
        #expect(back.config.anchor.schedules == state.config.anchor.schedules)
        #expect(back.pending == state.pending)
    }
}
