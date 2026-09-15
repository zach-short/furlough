import Foundation
import Testing

/// The time zone is the clock `ClockMark` does not watch: the same instant is the same `Date`
/// in every zone, so moving the zone in Settings re-reads every window against different local
/// hours with no drift to notice. These pin the answer — hold the zone the device left for the
/// delay, and let the new zone apply wherever it is tighter — on calendars with explicit zones,
/// never `.current`.
private func zoned(_ identifier: String) -> Calendar {
    var calendar = fixedCalendar()
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}

private let newYork = zoned("America/New_York")
private let tokyo = zoned("Asia/Tokyo")
private let chicago = zoned("America/Chicago")
private let day: TimeInterval = 86_400

@Suite("Clock.zone")
struct ClockZoneTests {
    let now = at(8, 9, 0, calendar: newYork)

    @Test("no mark, or a mark the device agrees with, is settled")
    func settled() {
        #expect(Clock.zone(mark: nil, current: "Asia/Tokyo", now: now, hold: day) == .settled)
        let mark = ZoneMark(identifier: "America/New_York")
        #expect(Clock.zone(mark: mark, current: "America/New_York", now: now, hold: day) == .settled)
    }

    @Test("a move not yet stamped is held from now; a stamped one from when it was first seen")
    func moved() {
        let fresh = ZoneMark(identifier: "America/New_York")
        #expect(Clock.zone(mark: fresh, current: "Asia/Tokyo", now: now, hold: day)
            == .moved(from: "America/New_York", until: now.addingTimeInterval(day)))
        let seen = ZoneMark(identifier: "America/New_York", movedAt: now.addingTimeInterval(-3600))
        #expect(Clock.zone(mark: seen, current: "Asia/Tokyo", now: now, hold: day)
            == .moved(from: "America/New_York", until: now.addingTimeInterval(day - 3600)))
    }

    @Test("the hold expires on its own, and after it only the current zone is consulted")
    func expires() {
        let seen = ZoneMark(identifier: "America/New_York", movedAt: now)
        #expect(Clock.zone(mark: seen, current: "Asia/Tokyo", now: now.addingTimeInterval(day - 1), hold: day) != .settled)
        #expect(Clock.zone(mark: seen, current: "Asia/Tokyo", now: now.addingTimeInterval(day), hold: day) == .settled)
        #expect(Clock.stampZone(seen, current: "Asia/Tokyo", now: now.addingTimeInterval(day), hold: day)
            == ZoneMark(identifier: "Asia/Tokyo"))
        #expect(Clock.zone(mark: seen, current: "Asia/Tokyo", now: now.addingTimeInterval(day), hold: day)
            .heldCalendar(like: tokyo) == nil)
    }

    @Test("the stamp keeps the old zone while the move is held, and writes down when it was seen")
    func stamp() {
        #expect(Clock.stampZone(nil, current: "America/New_York", now: now, hold: day) == ZoneMark(identifier: "America/New_York"))
        let mark = ZoneMark(identifier: "America/New_York")
        #expect(Clock.stampZone(mark, current: "America/New_York", now: now, hold: day) == mark)
        let seen = Clock.stampZone(mark, current: "Asia/Tokyo", now: now, hold: day)
        #expect(seen == ZoneMark(identifier: "America/New_York", movedAt: now))
        // Saving again later keeps the sighting, so the hold cannot be pushed along by saving.
        #expect(Clock.stampZone(seen, current: "Asia/Tokyo", now: now.addingTimeInterval(3600), hold: day) == seen)
        // Coming back forgets the move.
        #expect(Clock.stampZone(seen, current: "America/New_York", now: now.addingTimeInterval(3600), hold: day)
            == ZoneMark(identifier: "America/New_York"))
    }

    // DST moves the offset twice a year with nobody's hand on it; keyed on the identifier, it is invisible.
    @Test("America/New_York across both DST boundaries is settled throughout")
    func daylightSaving() {
        let mark = ZoneMark(identifier: "America/New_York")
        var parts = DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30)
        let spring = newYork.date(from: parts)!
        parts = DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30)
        let fall = newYork.date(from: parts)!
        for moment in [spring, spring.addingTimeInterval(3600), fall, fall.addingTimeInterval(3600)] {
            #expect(Clock.zone(mark: mark, current: "America/New_York", now: moment, hold: day) == .settled)
            #expect(Clock.stampZone(mark, current: "America/New_York", now: moment, hold: day) == mark)
        }
        // The offset really did move between those readings.
        let zone = TimeZone(identifier: "America/New_York")!
        #expect(zone.secondsFromGMT(for: spring) != zone.secondsFromGMT(for: spring.addingTimeInterval(3600)))
    }

    @Test("a held zone this OS cannot name leaves one decision rather than two identical ones")
    func unknownZone() {
        let reading = Clock.ZoneReading.moved(from: "Nowhere/Some_Place", until: now.addingTimeInterval(day))
        #expect(reading.heldCalendar(like: tokyo) == nil)
        #expect(reading.dayCalendar(like: tokyo) == tokyo)
        #expect(Clock.zoneName("Nowhere/Some_Place") == "Some Place")
    }

    @Test("the hold is the base loosening delay, capped by the first week")
    func hold() {
        var state = makeState([])
        #expect(state.zoneHold == 24 * 3600)
        state.config.loosenDelayHours = 72
        #expect(state.zoneHold == 72 * 3600)
        state.config.isInTrial = true
        #expect(state.zoneHold == TimeInterval(Furlough.trialDelayHours) * 3600)
    }

    @Test("the banner says which zone is kept and until when, in the device's own hours")
    func banner() {
        let english = Locale(identifier: "en_US")
        let until = now.addingTimeInterval(day)
        let text = Clock.describeMove(from: "America/New_York", to: "Asia/Tokyo", until: until, now: now, calendar: tokyo, locale: english)
        #expect(plainSpaces(text) == "Your time zone is now Japan Standard Time. Furlough is keeping Eastern Time until 10:00 PM tomorrow.")
        let today = Clock.describeMove(from: "America/New_York", to: "Asia/Tokyo", until: now.addingTimeInterval(1800), now: now, calendar: tokyo, locale: english)
        #expect(plainSpaces(today).hasSuffix("until 10:30 PM."))
    }
}

@Suite("Decisions under two zones")
struct TwoZoneDecisionTests {
    let night = Rule(windows: [window(1320, 1440)], dailyBudgetMinutes: 60)
    let office = Rule(windows: [window(540, 1020)], dailyBudgetMinutes: 240)

    func state(_ targets: [Target], honouring identifier: String, runtime: RuntimeState = RuntimeState()) -> SharedState {
        var state = makeState(targets, runtime: runtime)
        state.runtime.zone = ZoneMark(identifier: identifier)
        return state
    }

    @Test("New York to Tokyo at 9 AM: a 10 PM window stays shut, and does not open on Tokyo's evening either")
    func newYorkToTokyo() {
        let tiktok = makeTarget("TikTok", rule: night)
        var state = state([tiktok], honouring: "America/New_York")
        let now = at(8, 9, 0, calendar: newYork)
        let zone = state.zone(now: now, current: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(zone == .moved(from: "America/New_York", until: now.addingTimeInterval(day)))
        // What the save that follows the first reading writes down.
        state.runtime.zone = Clock.stampZone(state.runtime.zone, current: "Asia/Tokyo", now: now, hold: state.zoneHold)

        // 10 PM in Tokyo, so Tokyo alone would open it; New York's 9 AM says no.
        #expect(Policy.status(of: tiktok, config: state.config, runtime: state.runtime, now: now, calendar: tokyo) == .open(until: 1440))
        let folded = Policy.status(of: tiktok, config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: tokyo)
        // Next opening on New York's schedule, 10 PM there, read in Tokyo's own hours: 11 AM tomorrow.
        #expect(folded == .closed(nextOpen: NextOpen(minuteOfDay: 660, daysAhead: 1)))
        #expect(Policy.decide(config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: tokyo).blockedHosts == ["tiktok.com"])

        // 10 PM in New York is 11 AM in Tokyo: New York opens it, Tokyo does not, so it stays shut.
        let evening = at(8, 22, 0, calendar: newYork)
        let laterZone = state.zone(now: evening, current: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(Policy.status(of: tiktok, config: state.config, runtime: state.runtime, now: evening, zone: laterZone, calendar: tokyo)
            == .closed(nextOpen: NextOpen(minuteOfDay: 1320, daysAhead: 0)))

        // The hold lapses on its own: a day later Tokyo's evening window is Tokyo's alone.
        let settledNow = now.addingTimeInterval(day)
        let settled = state.zone(now: settledNow, current: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(settled == .settled)
        #expect(Policy.status(of: tiktok, config: state.config, runtime: state.runtime, now: settledNow, zone: settled, calendar: tokyo) == .open(until: 1440))
    }

    @Test("one zone west: the window opens where both agree and closes on the earlier of the two closes")
    func newYorkToChicago() {
        let mail = makeTarget("Mail", rule: office)
        let state = state([mail], honouring: "America/New_York")
        let now = at(8, 9, 30, calendar: chicago)
        let zone = state.zone(now: now, current: TimeZone(identifier: "America/Chicago")!)
        // 10:30 in New York and 9:30 in Chicago are both inside 9–5; New York's 5 PM is Chicago's 4 PM.
        #expect(Policy.status(of: mail, config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: chicago) == .open(until: 960))
        #expect(Policy.decide(config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: chicago).blockedHosts.isEmpty)

        // 4:30 PM in Chicago is 5:30 PM in New York: shut, and the next opening is New York's 9 AM, Chicago's 8.
        let late = at(8, 16, 30, calendar: chicago)
        let lateZone = state.zone(now: late, current: TimeZone(identifier: "America/Chicago")!)
        #expect(Policy.status(of: mail, config: state.config, runtime: state.runtime, now: late, zone: lateZone, calendar: chicago)
            == .closed(nextOpen: NextOpen(minuteOfDay: 480, daysAhead: 1)))
        #expect(Policy.decide(config: state.config, runtime: state.runtime, now: late, zone: lateZone, calendar: chicago).blockedHosts == ["mail.com"])

        // 8:30 AM in Chicago is 9:30 in New York: New York would open it, Chicago's 9 AM has not come.
        let early = at(8, 8, 30, calendar: chicago)
        let earlyZone = state.zone(now: early, current: TimeZone(identifier: "America/Chicago")!)
        #expect(Policy.status(of: mail, config: state.config, runtime: state.runtime, now: early, zone: earlyZone, calendar: chicago)
            == .closed(nextOpen: NextOpen(minuteOfDay: 540, daysAhead: 0)))
    }

    @Test("Tokyo to New York: the tighter of the two still wins, and nothing already shielded is released")
    func tokyoToNewYork() {
        let tiktok = makeTarget("TikTok", rule: night)
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let games = makeTarget("Games", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        // Spent on Tokyo's day, which is what the held zone keeps.
        runtime.exhausted[games.id.uuidString] = "2026-09-08"
        let state = state([tiktok, youTube, games], honouring: "Asia/Tokyo", runtime: runtime)
        // 10:30 PM in Tokyo on the 8th; 9:30 AM in New York the same date.
        let now = at(8, 22, 30, calendar: tokyo)
        let zone = state.zone(now: now, current: TimeZone(identifier: "America/New_York")!)
        let decision = Policy.decide(config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: newYork)
        #expect(decision.statuses[tiktok.id] == .closed(nextOpen: NextOpen(minuteOfDay: 1320, daysAhead: 0)))
        #expect(decision.statuses[youTube.id] == .blockedAllDay)
        #expect(decision.statuses[games.id] == .exhausted(nextOpen: NextOpen(minuteOfDay: 0, daysAhead: 1)))
        #expect(decision.blockedHosts == ["tiktok.com", "youtube.com", "games.com"])
    }

    @Test("a spent budget stays spent across a day that rolled only because the zone moved")
    func spentStaysSpent() {
        let games = makeTarget("Games", rule: Rule(windows: [], dailyBudgetMinutes: 30))
        var runtime = RuntimeState()
        runtime.exhausted[games.id.uuidString] = "2026-09-08"
        let state = state([games], honouring: "America/New_York", runtime: runtime)
        // Noon in New York on the 8th is 1 AM in Tokyo on the 9th: Tokyo's day key has rolled.
        let now = at(8, 12, 0, calendar: newYork)
        let zone = state.zone(now: now, current: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(Policy.dayKey(now, calendar: tokyo) == "2026-09-09")
        #expect(Policy.dayKey(now, zone: zone, calendar: tokyo) == "2026-09-08")
        #expect(Policy.status(of: games, config: state.config, runtime: state.runtime, now: now, calendar: tokyo) == .open(until: 1440))
        // New York's day ends at 1 PM in Tokyo, which is when the budget really refills.
        #expect(Policy.status(of: games, config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: tokyo)
            == .exhausted(nextOpen: NextOpen(minuteOfDay: 780, daysAhead: 0)))
        // The Mac's ledger keys on the same helper, so it is not replaced either.
        #expect(Policy.dayKey(now, zone: zone, calendar: tokyo) == Policy.dayKey(now, calendar: newYork))
        // Settled, the day is the device's own again.
        #expect(Policy.dayKey(now, zone: .settled, calendar: tokyo) == "2026-09-09")
    }

    @Test("two decisions that disagree about which target is open shut both")
    func disagreement() {
        let mail = makeTarget("Mail", rule: office)
        let tiktok = makeTarget("TikTok", rule: night)
        let state = state([mail, tiktok], honouring: "America/New_York")
        // 10 AM in New York, 11 PM in Tokyo: New York opens Mail and not TikTok, Tokyo the reverse.
        let now = at(8, 10, 0, calendar: newYork)
        let zone = state.zone(now: now, current: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(Policy.statuses(config: state.config, runtime: state.runtime, now: now, calendar: newYork)[mail.id]?.isAllowed == true)
        #expect(Policy.statuses(config: state.config, runtime: state.runtime, now: now, calendar: tokyo)[tiktok.id]?.isAllowed == true)
        let folded = Policy.statuses(config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: tokyo)
        #expect(folded[mail.id]?.isAllowed == false)
        #expect(folded[tiktok.id]?.isAllowed == false)
        let summary = Policy.summary(state: state, now: now, zone: zone, calendar: tokyo)
        #expect(summary.openNames.isEmpty)
        #expect(summary.blockedCount == 2)
    }

    @Test("the next transition is the sooner of the two zones' edges")
    func transitions() {
        let mail = makeTarget("Mail", rule: office)
        let state = state([mail], honouring: "America/New_York")
        let now = at(8, 9, 30, calendar: chicago)
        let zone = state.zone(now: now, current: TimeZone(identifier: "America/Chicago")!)
        // Chicago's next edge is 5 PM; New York's 5 PM is Chicago's 4.
        #expect(Policy.nextTransition(config: state.config, after: now, calendar: chicago) == at(8, 17, 0, calendar: chicago))
        #expect(Policy.nextTransition(config: state.config, after: now, zone: zone, calendar: chicago) == at(8, 16, 0, calendar: chicago))
    }

    @Test("settled, the two-zone entry points are the one-zone ones")
    func settledIsPlain() {
        let mail = makeTarget("Mail", rule: office)
        let state = state([mail], honouring: "America/Chicago")
        let now = at(8, 9, 30, calendar: chicago)
        let zone = state.zone(now: now, current: TimeZone(identifier: "America/Chicago")!)
        #expect(zone == .settled)
        let plain = Policy.decide(config: state.config, runtime: state.runtime, now: now, calendar: chicago)
        let folded = Policy.decide(config: state.config, runtime: state.runtime, now: now, zone: zone, calendar: chicago)
        #expect(plain.statuses == folded.statuses)
        #expect(plain.blockedHosts == folded.blockedHosts)
    }
}

@Suite("Policy.tighter")
struct TighterTests {
    let now = at(8, 10, 0, calendar: newYork)
    let soon = NextOpen(minuteOfDay: 1320, daysAhead: 0)
    let later = NextOpen(minuteOfDay: 540, daysAhead: 1)

    func tighter(_ a: TargetStatus, _ b: TargetStatus) -> TargetStatus {
        Policy.tighter(a, in: newYork, b, in: newYork, now: now)
    }

    @Test("anchored beats everything, then blocked all day")
    func anchoredAndBlocked() {
        let everything: [TargetStatus] = [.anchored, .blockedAllDay, .exhausted(nextOpen: soon), .closed(nextOpen: soon), .open(until: 1020), .unconfigured]
        for status in everything {
            #expect(tighter(.anchored, status) == .anchored)
            #expect(tighter(status, .anchored) == .anchored)
        }
        for status in everything.dropFirst() {
            #expect(tighter(.blockedAllDay, status) == .blockedAllDay)
            #expect(tighter(status, .blockedAllDay) == .blockedAllDay)
        }
    }

    @Test("shielded beats open, and a spent budget is named over a closed window")
    func shieldedBeatsOpen() {
        #expect(tighter(.exhausted(nextOpen: soon), .open(until: 1020)) == .exhausted(nextOpen: soon))
        #expect(tighter(.open(until: 1020), .exhausted(nextOpen: soon)) == .exhausted(nextOpen: soon))
        #expect(tighter(.closed(nextOpen: soon), .open(until: 1020)) == .closed(nextOpen: soon))
        #expect(tighter(.open(until: 1020), .closed(nextOpen: soon)) == .closed(nextOpen: soon))
        #expect(tighter(.exhausted(nextOpen: soon), .closed(nextOpen: later)) == .exhausted(nextOpen: later))
        #expect(tighter(.closed(nextOpen: later), .exhausted(nextOpen: soon)) == .exhausted(nextOpen: later))
        #expect(tighter(.closed(nextOpen: soon), .unconfigured) == .closed(nextOpen: soon))
        #expect(tighter(.unconfigured, .exhausted(nextOpen: soon)) == .exhausted(nextOpen: soon))
    }

    @Test("between two shut answers the later reopening wins, and never beats any date")
    func laterReopening() {
        #expect(tighter(.closed(nextOpen: soon), .closed(nextOpen: later)) == .closed(nextOpen: later))
        #expect(tighter(.closed(nextOpen: later), .closed(nextOpen: soon)) == .closed(nextOpen: later))
        #expect(tighter(.exhausted(nextOpen: soon), .exhausted(nextOpen: later)) == .exhausted(nextOpen: later))
        #expect(tighter(.exhausted(nextOpen: nil), .exhausted(nextOpen: later)) == .exhausted(nextOpen: nil))
        #expect(tighter(.exhausted(nextOpen: later), .closed(nextOpen: soon)) == .exhausted(nextOpen: later))
    }

    @Test("between two open answers the earlier close wins; open beats unconfigured")
    func earlierClose() {
        #expect(tighter(.open(until: 1020), .open(until: 1080)) == .open(until: 1020))
        #expect(tighter(.open(until: 1080), .open(until: 1020)) == .open(until: 1020))
        #expect(tighter(.open(until: 1020), .unconfigured) == .open(until: 1020))
        #expect(tighter(.unconfigured, .open(until: 1020)) == .open(until: 1020))
        #expect(tighter(.unconfigured, .unconfigured) == .unconfigured)
    }

    @Test("a minute from the held zone is answered in the device's own frame")
    func rebased() {
        // 5 PM in New York is 4 PM in Chicago; a 6 PM close in Chicago is the later of the two.
        #expect(Policy.tighter(.open(until: 1020), in: newYork, .open(until: 1080), in: chicago, now: at(8, 10, 0, calendar: chicago)) == .open(until: 960))
        // A reopening tomorrow at 9 in New York is 8 in Chicago.
        #expect(Policy.tighter(.closed(nextOpen: later), in: newYork, .open(until: 1080), in: chicago, now: at(8, 10, 0, calendar: chicago))
            == .closed(nextOpen: NextOpen(minuteOfDay: 480, daysAhead: 1)))
    }
}

@Suite("Decoding the zone mark")
struct ZoneDecodingTests {
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

    @Test("a store written before the zone was watched reads as settled")
    func withoutMark() throws {
        let runtime = try decoder.decode(RuntimeState.self, from: Data(#"{"exhausted":{},"warned":{}}"#.utf8))
        #expect(runtime.zone == nil)
        var state = SharedState()
        state.runtime = runtime
        #expect(state.zone(now: at(8), current: TimeZone(identifier: "Asia/Tokyo")!) == .settled)
    }

    @Test("a mark survives a round trip, sighting and all")
    func roundTrip() throws {
        var state = makeState([])
        state.runtime.zone = ZoneMark(identifier: "America/New_York", movedAt: at(8, 9, 0))
        let restored = try decoder.decode(SharedState.self, from: encoder.encode(state))
        #expect(restored.runtime.zone == state.runtime.zone)
    }
}
