import Foundation
import Testing

@Suite("Clock.read")
struct ClockReadTests {
    /// A machine that booted an hour before the mark was taken.
    let mark = ClockMark(wall: at(8, 12, 0), uptime: 3600)

    /// The reading `minutesLater` on the device's clock, when the machine has counted
    /// `seconds` since the mark. The two agree when they match.
    func read(_ minutesLater: Int, uptimePlus seconds: TimeInterval, tolerance: TimeInterval = Clock.tolerance) -> Clock.Reading {
        Clock.read(
            wall: at(8, 12, 0).addingTimeInterval(TimeInterval(minutesLater) * 60),
            uptime: 3600 + seconds,
            mark: mark,
            tolerance: tolerance
        )
    }

    @Test("with no mark to compare against, the device's clock is taken at its word")
    func noMark() {
        let reading = Clock.read(wall: at(8), uptime: 10, mark: nil)
        #expect(reading.isTrusted)
        #expect(reading.now == at(8))
        #expect(reading.drift == 0)
    }

    @Test("both clocks moving together is trusted, and Furlough runs on the device's clock")
    func together() {
        #expect(read(30, uptimePlus: 1800).isTrusted)
        #expect(read(30, uptimePlus: 1800).now == at(8, 12, 30))
        #expect(read(0, uptimePlus: 0).isTrusted)
        #expect(read(600, uptimePlus: 36_000).isTrusted)
    }

    @Test("a few minutes of drift is inside the tolerance")
    func tolerated() {
        #expect(read(30, uptimePlus: 1800 - 60).isTrusted)
        #expect(read(30, uptimePlus: 1800 - 599).isTrusted)
        // Exactly at the tolerance is still trusted; a second past it is not.
        #expect(read(30, uptimePlus: 1800 - 600).isTrusted)
        #expect(!read(30, uptimePlus: 1800 - 601).isTrusted)
        #expect(read(30, uptimePlus: 1800 - 601).drift == 601)
    }

    /// The whole point: the day added to the wall clock is not the time Furlough runs on.
    @Test("a day added to the wall clock is ignored, and Furlough keeps its own time")
    func movedForward() {
        let reading = read(24 * 60, uptimePlus: 60)
        #expect(!reading.isTrusted)
        #expect(reading.drift == 24 * 3600 - 60)
        // A minute of machine time passed since the mark, so a minute is what Furlough counts.
        #expect(reading.now == at(8, 12, 1))
        #expect(Clock.describe(reading.drift) == "23 h 59 min")
    }

    /// Moving the clock back would hold every pending change up for as long as it was back by,
    /// which is just as wrong in the other direction, so it is corrected the same way.
    @Test("a clock moved backwards is corrected too")
    func movedBackward() {
        let reading = read(-24 * 60, uptimePlus: 60)
        #expect(!reading.isTrusted)
        #expect(reading.drift == -(24 * 3600) - 60)
        #expect(reading.now == at(8, 12, 1))
    }

    @Test("a reboot resets the machine's count, so the pair is no longer comparable")
    func reboot() {
        let reading = Clock.read(wall: at(9, 12, 0), uptime: 30, mark: mark)
        #expect(reading.isTrusted)
        #expect(reading.now == at(9, 12, 0))
    }

    @Test("the tolerance can be tightened")
    func customTolerance() {
        let reading = read(30, uptimePlus: 1800 - 120, tolerance: 60)
        #expect(!reading.isTrusted)
        #expect(reading.drift == 120)
    }

    /// What the widget and the Live Activity need: their own timers are drawn against the
    /// device's clock, so a Furlough time has to be moved onto it and back.
    @Test("device and honest are inverses of each other")
    func deviceAndHonest() {
        let reading = read(24 * 60, uptimePlus: 60)
        let furloughTime = at(8, 20, 0)
        #expect(reading.device(furloughTime) == furloughTime.addingTimeInterval(reading.drift))
        #expect(reading.honest(reading.device(furloughTime)) == furloughTime)

        let trusted = read(30, uptimePlus: 1800)
        #expect(trusted.device(furloughTime) == furloughTime)
        #expect(trusted.honest(furloughTime) == furloughTime)
    }
}

@Suite("Clock.stamp")
struct ClockStampTests {
    let mark = ClockMark(wall: at(8, 12, 0), uptime: 3600)

    @Test("a trusted reading replaces the mark")
    func advances() {
        let fresh = Clock.stamp(mark, wall: at(8, 12, 30), uptime: 5400)
        #expect(fresh == ClockMark(wall: at(8, 12, 30), uptime: 5400))
    }

    @Test("the first reading is always the mark")
    func first() {
        #expect(Clock.stamp(nil, wall: at(8), uptime: 12) == ClockMark(wall: at(8), uptime: 12))
    }

    @Test("while the clock is off the old mark is kept, so only putting it back restores trust")
    func holdsWhileAhead() {
        let ahead = at(9, 12, 0)
        #expect(Clock.stamp(mark, wall: ahead, uptime: 3660) == mark)
        // Saving again a minute later still keeps it, so the jump cannot be laundered.
        #expect(Clock.stamp(mark, wall: ahead.addingTimeInterval(60), uptime: 3720) == mark)
        // Set back to where it should be and the next save marks again.
        let back = at(8, 12, 1)
        #expect(Clock.stamp(mark, wall: back, uptime: 3660) == ClockMark(wall: back, uptime: 3660))
    }

    @Test("a reboot re-marks")
    func reboot() {
        #expect(Clock.stamp(mark, wall: at(9), uptime: 5) == ClockMark(wall: at(9), uptime: 5))
    }
}

/// Furlough does not hold pending changes back when the clock is wrong — it never sees the
/// wrong time in the first place. `state.now` is the projection, so a change that is due only
/// on the device's clock is simply not due.
@Suite("Pending changes on a clock that was moved")
struct ClockHoldTests {
    /// The mark a save left behind an hour after this machine booted.
    let mark = ClockMark(wall: at(8, 12, 0), uptime: 3600)
    /// A minute of machine time later, with the device's clock a day ahead.
    let deviceWall = at(9, 12, 1)
    let uptime: TimeInterval = 3660
    /// What Furlough makes of that: one minute past the mark.
    let honestNow = at(8, 12, 1)

    func state(_ targets: [Target], pending: [PendingChange]) -> SharedState {
        var state = makeState(targets, pending: pending)
        state.runtime.clock = mark
        return state
    }

    func change(_ kind: PendingKind, dueAt: Date) -> PendingChange {
        PendingChange(kind: kind, createdAt: at(7), effectiveAt: dueAt)
    }

    @Test("the time Furlough runs on is the projection, not the device's clock")
    func ownTime() {
        let state = state([], pending: [])
        #expect(state.clock(wall: deviceWall, uptime: uptime).now == honestNow)
        #expect(!state.clock(wall: deviceWall, uptime: uptime).isTrusted)
    }

    @Test("a loosening due tomorrow does not land because the clock says tomorrow")
    func heldLoosening() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let looser = Rule(windows: [window(1080, 1320)], dailyBudgetMinutes: 60)
        // Due in a day: reachable on the device's clock, not on Furlough's.
        var held = state([youTube], pending: [change(.setRule(targetID: youTube.id, rule: looser), dueAt: at(9, 11, 0))])

        #expect(!Policy.applyDuePending(&held, now: held.clock(wall: deviceWall, uptime: uptime).now))
        #expect(held.config.targets.first?.rule?.dailyBudgetMinutes == 30)
        #expect(held.pending.count == 1)

        // The same change lands once the day has actually passed on Furlough's own count.
        let aDayOfMachineTime = held.clock(wall: at(9, 12, 1), uptime: 3660 + 86_400).now
        #expect(Policy.applyDuePending(&held, now: aDayOfMachineTime))
        #expect(held.config.targets.first?.rule == looser)
        #expect(held.pending.isEmpty)
    }

    @Test("removing a target waits the same way")
    func heldRemoval() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        var held = state([youTube], pending: [change(.removeTarget(targetID: youTube.id), dueAt: at(9, 11, 0))])
        #expect(!Policy.applyDuePending(&held, now: held.clock(wall: deviceWall, uptime: uptime).now))
        #expect(held.config.targets.count == 1)
    }

    /// `applyDuePending`'s `now` defaults to `state.now` rather than to the device's clock, so a
    /// call site that forgets to pass one cannot let a shield lift early.
    @Test("the default time is Furlough's own, not the device's")
    func defaultsToOwnTime() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let open = Rule(windows: [], dailyBudgetMinutes: 240)
        // Due a year out, so no real clock this test could run under makes it due.
        var state = state([youTube], pending: [change(.setRule(targetID: youTube.id, rule: open), dueAt: at(8).addingTimeInterval(365 * 86_400))])
        #expect(!Policy.applyDuePending(&state))
        #expect(state.config.targets.first?.rule == .alwaysBlocked)
    }

    @Test("shields are decided from the config as it stands on Furlough's clock")
    func shieldsDoNotLoosen() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let open = Rule(windows: [], dailyBudgetMinutes: 240)
        let state = state([youTube], pending: [change(.setRule(targetID: youTube.id, rule: open), dueAt: at(9, 11, 0))])

        let held = Policy.effectiveConfig(state, now: honestNow)
        #expect(Policy.decide(config: held, runtime: state.runtime, now: honestNow, calendar: cal).blockedHosts == ["youtube.com"])

        let landed = Policy.effectiveConfig(state, now: at(9, 11, 30))
        #expect(Policy.decide(config: landed, runtime: state.runtime, now: at(9, 11, 30), calendar: cal).blockedHosts.isEmpty)
    }

    @Test("the summary follows the same config")
    func summaryHolds() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let open = Rule(windows: [], dailyBudgetMinutes: 240)
        let state = state([youTube], pending: [change(.setRule(targetID: youTube.id, rule: open), dueAt: at(9, 11, 0))])
        #expect(Policy.summary(state: state, now: honestNow, calendar: cal).blockedCount == 1)
        #expect(Policy.summary(state: state, now: at(9, 11, 30), calendar: cal).allDayNames == ["YouTube"])
    }
}
