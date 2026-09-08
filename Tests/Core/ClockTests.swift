import Foundation
import Testing

@Suite("Clock.isTrusted")
struct ClockTrustTests {
    /// A machine that booted an hour before the mark was taken.
    let mark = ClockMark(wall: at(8, 12, 0), uptime: 3600)

    func trust(_ minutesLater: Int, uptimePlus seconds: TimeInterval, tolerance: TimeInterval = Clock.tolerance) -> Clock.Trust {
        Clock.isTrusted(
            now: at(8, 12, 0).addingTimeInterval(TimeInterval(minutesLater) * 60),
            uptime: 3600 + seconds,
            mark: mark,
            tolerance: tolerance
        )
    }

    @Test("with no mark to compare against, the clock is taken at its word")
    func noMark() {
        #expect(Clock.isTrusted(now: at(8), uptime: 10, mark: nil) == .trusted)
    }

    @Test("both clocks moving together is trusted")
    func together() {
        #expect(trust(30, uptimePlus: 1800) == .trusted)
        #expect(trust(0, uptimePlus: 0) == .trusted)
        #expect(trust(600, uptimePlus: 36_000) == .trusted)
    }

    @Test("a few minutes of drift is inside the tolerance")
    func tolerated() {
        #expect(trust(30, uptimePlus: 1800 - 60) == .trusted)
        #expect(trust(30, uptimePlus: 1800 - 599) == .trusted)
        // Exactly at the tolerance is still trusted; a second past it is not.
        #expect(trust(30, uptimePlus: 1800 - 600) == .trusted)
        #expect(trust(30, uptimePlus: 1800 - 601) == .movedForward(by: 601))
    }

    @Test("a day added to the wall clock is caught")
    func movedForward() {
        #expect(trust(24 * 60, uptimePlus: 60) == .movedForward(by: 24 * 3600 - 60))
        if case .movedForward(let drift) = trust(24 * 60, uptimePlus: 0) {
            #expect(Clock.describe(drift) == "24 h 0 min")
        } else {
            Issue.record("a day forward should not be trusted")
        }
    }

    @Test("a clock moved backwards is trusted: it only delays things")
    func movedBackward() {
        #expect(trust(-24 * 60, uptimePlus: 60) == .trusted)
    }

    @Test("a reboot resets the machine's count, so the pair is no longer comparable")
    func reboot() {
        #expect(Clock.isTrusted(now: at(9, 12, 0), uptime: 30, mark: mark) == .trusted)
    }

    @Test("the tolerance can be tightened")
    func customTolerance() {
        #expect(trust(30, uptimePlus: 1800 - 120, tolerance: 60) == .movedForward(by: 120))
    }
}

@Suite("Clock.stamp")
struct ClockStampTests {
    let mark = ClockMark(wall: at(8, 12, 0), uptime: 3600)

    @Test("a trusted reading replaces the mark")
    func advances() {
        let fresh = Clock.stamp(mark, now: at(8, 12, 30), uptime: 5400)
        #expect(fresh == ClockMark(wall: at(8, 12, 30), uptime: 5400))
    }

    @Test("the first reading is always the mark")
    func first() {
        #expect(Clock.stamp(nil, now: at(8), uptime: 12) == ClockMark(wall: at(8), uptime: 12))
    }

    @Test("while the clock is ahead the old mark is kept, so only putting it back restores trust")
    func holdsWhileAhead() {
        let ahead = at(9, 12, 0)
        #expect(Clock.stamp(mark, now: ahead, uptime: 3660) == mark)
        // Saving again a minute later still keeps it, so the jump cannot be laundered.
        #expect(Clock.stamp(mark, now: ahead.addingTimeInterval(60), uptime: 3720) == mark)
        // Set back to where it should be and the next save marks again.
        let back = at(8, 12, 1)
        #expect(Clock.stamp(mark, now: back, uptime: 3660) == ClockMark(wall: back, uptime: 3660))
    }

    @Test("a reboot re-marks")
    func reboot() {
        #expect(Clock.stamp(mark, now: at(9), uptime: 5) == ClockMark(wall: at(9), uptime: 5))
    }
}

@Suite("Pending changes on an untrusted clock")
struct ClockHoldTests {
    let now = at(8, 12, 0)
    let ahead = Clock.Trust.movedForward(by: 24 * 3600)

    func change(_ kind: PendingKind, dueAt: Date) -> PendingChange {
        PendingChange(kind: kind, createdAt: at(7), effectiveAt: dueAt)
    }

    @Test("a due loosening is held while the clock is ahead")
    func heldLoosening() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        let looser = Rule(windows: [window(1080, 1320)], dailyBudgetMinutes: 60)
        var state = makeState([youTube], pending: [change(.setRule(targetID: youTube.id, rule: looser), dueAt: at(8, 11, 0))])

        #expect(!Policy.applyDuePending(&state, now: now, trust: ahead))
        #expect(state.config.targets.first?.rule?.dailyBudgetMinutes == 30)
        #expect(state.pending.count == 1)

        // The same change lands as soon as the clock is back.
        #expect(Policy.applyDuePending(&state, now: now, trust: .trusted))
        #expect(state.config.targets.first?.rule == looser)
        #expect(state.pending.isEmpty)
    }

    @Test("removing a target is a loosening, so it waits too")
    func heldRemoval() {
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30))
        var state = makeState([youTube], pending: [change(.removeTarget(targetID: youTube.id), dueAt: at(8, 11, 0))])
        #expect(!Policy.applyDuePending(&state, now: now, trust: ahead))
        #expect(state.config.targets.count == 1)
    }

    @Test("a lower delay waits, a higher one does not")
    func delay() {
        var lower = makeState([], pending: [change(.setDelay(hours: 1), dueAt: at(8, 11, 0))])
        #expect(!Policy.applyDuePending(&lower, now: now, trust: ahead))
        #expect(lower.config.loosenDelayHours == 24)

        var higher = makeState([], pending: [change(.setDelay(hours: 72), dueAt: at(8, 11, 0))])
        #expect(Policy.applyDuePending(&higher, now: now, trust: ahead))
        #expect(higher.config.loosenDelayHours == 72)
    }

    @Test("a queued change that no longer loosens still applies")
    func tighteningLands() {
        // The rule was loosened to 60 minutes when this was queued, then cut to 15 by hand.
        // Applying 30 now is a tightening, so an untrusted clock does not hold it.
        let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 15))
        let queued = Rule(windows: [window(1230, 1320)], dailyBudgetMinutes: 15)
        var state = makeState([youTube], pending: [change(.setRule(targetID: youTube.id, rule: queued), dueAt: at(8, 11, 0))])
        #expect(Policy.applyDuePending(&state, now: now, trust: ahead))
        #expect(state.config.targets.first?.rule == queued)
        #expect(state.pending.isEmpty)
    }

    @Test("shields are decided from a config that never folded the held change in")
    func shieldsDoNotLoosen() {
        // Blocked all day, with a pending change that would open it right now.
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let open = Rule(windows: [], dailyBudgetMinutes: 240)
        let state = makeState([youTube], pending: [change(.setRule(targetID: youTube.id, rule: open), dueAt: at(8, 11, 0))])

        let held = Policy.effectiveConfig(state, now: now, trust: ahead)
        #expect(Policy.decide(config: held, runtime: state.runtime, now: now, calendar: cal).blockedHosts == ["youtube.com"])

        let landed = Policy.effectiveConfig(state, now: now, trust: .trusted)
        #expect(Policy.decide(config: landed, runtime: state.runtime, now: now, calendar: cal).blockedHosts.isEmpty)
    }

    @Test("the summary reflects the held config too")
    func summaryHolds() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let open = Rule(windows: [], dailyBudgetMinutes: 240)
        let state = makeState([youTube], pending: [change(.setRule(targetID: youTube.id, rule: open), dueAt: at(8, 11, 0))])
        #expect(Policy.summary(state: state, now: now, calendar: cal, trust: ahead).blockedCount == 1)
        #expect(Policy.summary(state: state, now: now, calendar: cal, trust: .trusted).allDayNames == ["YouTube"])
    }
}
