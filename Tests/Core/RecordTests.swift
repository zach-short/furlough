import Foundation
import Testing

/// A day's record built by hand, for the reading tests.
private func day(
    spent: [UUID] = [],
    shielded: Int = 0,
    anchored: Int = 0,
    queued: Int = 0,
    cancelled: Int = 0,
    landed: Int = 0,
    longestAnchor: Int = 0
) -> DayRecord {
    var record = DayRecord()
    for id in spent {
        var entry = TargetDay()
        entry.spent = true
        record.targets[id.uuidString] = entry
    }
    if shielded > 0 || anchored > 0 {
        var entry = TargetDay()
        entry.shieldedMinutes = shielded
        entry.anchoredMinutes = anchored
        record.targets[UUID().uuidString] = entry
    }
    record.queued = queued
    record.cancelled = cancelled
    record.landed = landed
    record.longestAnchorMinutes = longestAnchor
    return record
}

private func key(_ d: Int) -> String { Policy.dayKey(at(d), calendar: cal) }

@Suite("Record.accumulate")
struct RecordAccumulateTests {
    /// Open noon to 1 PM every day.
    func youTube(id: UUID = UUID()) -> Target {
        makeTarget("YouTube", rule: Rule(windows: [window(720, 780)], dailyBudgetMinutes: 60), id: id)
    }

    func accumulate(_ state: inout SharedState, at now: Date) {
        Record.accumulate(&state, now: now, calendar: cal)
    }

    @Test("the first count only marks where counting starts")
    func firstCallStamps() {
        var state = makeState([youTube()])
        accumulate(&state, at: at(8, 12, 0))
        #expect(state.runtime.recordedThrough == at(8, 12, 0))
        #expect(state.runtime.days.isEmpty)
    }

    @Test("an open window is counted open, a shut one shut")
    func openAndShut() {
        let id = UUID()
        var state = makeState([youTube(id: id)])
        accumulate(&state, at: at(8, 12, 0))
        accumulate(&state, at: at(8, 12, 30))
        var entry = state.runtime.days[key(8)]?.targets[id.uuidString]
        #expect(entry?.openMinutes == 30)
        #expect(entry?.shieldedMinutes == 0)
        // 1 PM to 2 PM: the window has closed behind it.
        accumulate(&state, at: at(8, 13, 0))
        accumulate(&state, at: at(8, 14, 0))
        entry = state.runtime.days[key(8)]?.targets[id.uuidString]
        #expect(entry?.openMinutes == 60)
        #expect(entry?.shieldedMinutes == 60)
    }

    @Test("a span across midnight is split between the two days")
    func acrossMidnight() {
        let id = UUID()
        var state = makeState([youTube(id: id)])
        accumulate(&state, at: at(8, 23, 0))
        accumulate(&state, at: at(9, 1, 0))
        #expect(state.runtime.days[key(8)]?.targets[id.uuidString]?.shieldedMinutes == 60)
        #expect(state.runtime.days[key(9)]?.targets[id.uuidString]?.shieldedMinutes == 60)
    }

    @Test("a phone that was off for a week is not counted as a week held shut")
    func gapIsCapped() {
        let id = UUID()
        var state = makeState([youTube(id: id)])
        accumulate(&state, at: at(1, 12, 0))
        accumulate(&state, at: at(8, 12, 0))
        let total = state.runtime.days.values
            .compactMap { $0.targets[id.uuidString]?.shieldedMinutes }
            .reduce(0, +)
        // At most a day, and an hour of that day was inside the window.
        #expect(total == 23 * 60)
        #expect(state.runtime.recordedThrough == at(8, 12, 0))
    }

    @Test("the part-minute between two counts is carried, not lost")
    func partMinutesAreCarried() {
        let id = UUID()
        var state = makeState([youTube(id: id)])
        accumulate(&state, at: at(8, 14, 0))
        for second in stride(from: 30, through: 120, by: 30) {
            Record.accumulate(&state, now: at(8, 14, 0).addingTimeInterval(Double(second)), calendar: cal)
        }
        #expect(state.runtime.days[key(8)]?.targets[id.uuidString]?.shieldedMinutes == 2)
    }

    @Test("the Anchor's minutes count as shut, and as anchored")
    func anchored() {
        let id = UUID()
        var state = makeState([youTube(id: id)])
        state.config.anchor.kinds = [state.config.targets[0].kind]
        state.config.anchor.isAnchored = true
        state.config.anchor.anchoredAt = at(8, 12, 0)
        // Noon to 12:30 is inside the window, so only the Anchor is holding it.
        Record.accumulate(&state, now: at(8, 12, 0), calendar: cal)
        Record.accumulate(&state, now: at(8, 12, 30), calendar: cal)
        let entry = state.runtime.days[key(8)]?.targets[id.uuidString]
        #expect(entry?.anchoredMinutes == 30)
        #expect(entry?.shieldedMinutes == 30)
        #expect(entry?.openMinutes == 0)
    }

    @Test("a target with no rule is holding nothing, so nothing is counted for it")
    func unconfigured() {
        let id = UUID()
        var state = makeState([makeTarget("Unset", rule: nil, id: id)])
        accumulate(&state, at: at(8, 12, 0))
        accumulate(&state, at: at(8, 13, 0))
        #expect(state.runtime.days[key(8)]?.targets[id.uuidString] == nil)
    }
}

@Suite("Record: the streak")
struct RecordStreakTests {
    let spender = UUID()

    @Test("days in a row with nothing spent")
    func inARow() {
        let days = [key(6): day(), key(7): day(), key(8): day()]
        #expect(Record.streak(days, upTo: at(8, 12), calendar: cal) == 3)
    }

    @Test("a spend ends it, on the day it happened")
    func aSpendEndsIt() {
        let days = [key(5): day(), key(6): day(spent: [spender]), key(7): day(), key(8): day()]
        #expect(Record.streak(days, upTo: at(8, 12), calendar: cal) == 2)
    }

    @Test("a spend today means no streak at all")
    func spentToday() {
        let days = [key(7): day(), key(8): day(spent: [spender])]
        #expect(Record.streak(days, upTo: at(8, 12), calendar: cal) == 0)
    }

    @Test("a day with no entries does not break it")
    func aDayWithNoEntries() {
        // Nothing at all on the 7th: the phone was off, or nothing happened. A spend is only
        // ever written when it happens, so silence is not a spend.
        let days = [key(6): day(), key(8): day()]
        #expect(Record.streak(days, upTo: at(8, 12), calendar: cal) == 3)
    }

    @Test("it runs across a week boundary")
    func acrossAWeek() {
        // The 6th is a Sunday, so the 5th is the last day of the week before.
        let days = [key(4): day(), key(5): day(), key(6): day(), key(7): day(), key(8): day()]
        #expect(Record.streak(days, upTo: at(8, 12), calendar: cal) == 5)
    }

    @Test("it stops at the earliest day on record, so a fresh install claims nothing")
    func boundedByTheRecord() {
        let days = [key(8): day()]
        #expect(Record.streak(days, upTo: at(8, 12), calendar: cal) == 1)
    }

    @Test("no record at all is no streak")
    func empty() {
        #expect(Record.streak([:], upTo: at(8, 12), calendar: cal) == 0)
    }

    @Test("a streak that broke yesterday says so")
    func broke() {
        let days = [key(7): day(spent: [spender]), key(8): day()]
        #expect(Record.brokeYesterday(days, upTo: at(8, 12), calendar: cal))
        #expect(!Record.brokeYesterday([key(8): day(spent: [spender])], upTo: at(8, 12), calendar: cal))
    }
}

@Suite("Record: the week")
struct RecordWeekTests {
    @Test("the week runs from its first day through today, never into tomorrow")
    func keys() {
        // The 6th is a Sunday and `cal` starts its weeks there.
        #expect(Record.weekKeys(upTo: at(8, 12), calendar: cal) == [key(8), key(7), key(6)])
    }

    @Test("a week that starts on Monday reaches back a day further")
    func mondayFirst() {
        let monday = fixedCalendar(firstWeekday: 2)
        let keys = Record.weekKeys(upTo: at(8, 12, calendar: monday), calendar: monday)
        #expect(keys.count == 2)
    }

    @Test("only this week's minutes are added up")
    func thisWeekOnly() {
        var state = makeState([])
        state.runtime.days = [
            key(5): day(shielded: 100),
            key(6): day(shielded: 200),
            key(8): day(shielded: 300, anchored: 60),
        ]
        let card = Record.card(state, now: at(8, 12), calendar: cal)
        #expect(card.shieldedMinutes == 500)
        #expect(card.anchoredMinutes == 60)
    }
}

@Suite("Record: loosenings and the Anchor")
struct RecordLooseningTests {
    @Test("queueing appends the change and counts it")
    func queueing() {
        var state = makeState([])
        let change = PendingChange(kind: .setDelay(hours: 12), effectiveAt: at(9, 12))
        Record.queue(change, in: &state, now: at(8, 12), calendar: cal)
        #expect(state.pending.count == 1)
        #expect(state.runtime.days[key(8)]?.queued == 1)
    }

    @Test("a landing is counted where it lands")
    func landing() {
        let target = makeTarget("YouTube", rule: Rule(windows: [window(720, 780)], dailyBudgetMinutes: 30))
        var state = makeState([target], pending: [
            PendingChange(kind: .setDelay(hours: 12), effectiveAt: at(8, 11)),
            PendingChange(kind: .setRule(targetID: target.id, rule: .unrestricted), effectiveAt: at(8, 11)),
        ])
        #expect(Policy.applyDuePending(&state, now: at(8, 12), calendar: cal))
        #expect(state.runtime.days[key(8)]?.landed == 2)
        #expect(state.pending.isEmpty)
    }

    @Test("nothing due counts nothing")
    func nothingDue() {
        var state = makeState([], pending: [PendingChange(kind: .setDelay(hours: 12), effectiveAt: at(9, 12))])
        #expect(!Policy.applyDuePending(&state, now: at(8, 12), calendar: cal))
        #expect(state.runtime.days.isEmpty)
    }

    @Test("cancelled and landed are counted over the whole record")
    func totals() {
        var state = makeState([])
        state.runtime.days = [key(6): day(cancelled: 2, landed: 1), key(8): day(cancelled: 1)]
        let card = Record.card(state, now: at(8, 12), calendar: cal)
        #expect(card.cancelled == 3)
        #expect(card.landed == 1)
        #expect(Record.looseningLine(card) == "3 cancelled, 1 landed")
    }

    @Test("a released Anchor is recorded whole, on the day it was released")
    func anchorReleased() {
        var state = makeState([])
        state.config.anchor.isAnchored = true
        state.config.anchor.anchoredAt = at(7, 20, 0)
        Record.noteAnchorReleased(&state, now: at(8, 6, 0), calendar: cal)
        // Ten hours, from the evening of the 7th to the morning of the 8th, as one number.
        #expect(state.runtime.days[key(8)]?.longestAnchorMinutes == 600)
        #expect(state.runtime.days[key(7)] == nil)
    }

    @Test("an Anchor still holding counts from when it was set")
    func anchorHolding() {
        var state = makeState([])
        state.runtime.days = [key(6): day(longestAnchor: 60)]
        state.config.anchor.isAnchored = true
        state.config.anchor.anchoredAt = at(8, 9, 0)
        let card = Record.card(state, now: at(8, 12, 0), calendar: cal)
        #expect(card.longestAnchorMinutes == 180)
        #expect(Record.anchorLine(card) == "3 hours")
    }
}

@Suite("Record: keeping and forgetting")
struct RecordPruneTests {
    @Test("anything older than sixty days is dropped")
    func prunes() {
        var days = [key(8): day(shielded: 10)]
        // 60 days back from 8 September 2026 is 11 July; the 10th is one day past the edge.
        days[Policy.dayKey(at(8).addingTimeInterval(-60 * 86400), calendar: cal)] = day(shielded: 10)
        days[Policy.dayKey(at(8).addingTimeInterval(-59 * 86400), calendar: cal)] = day(shielded: 10)
        Record.prune(&days, on: at(8, 12), calendar: cal)
        #expect(days.count == 2)
        #expect(days[key(8)] != nil)
    }

    @Test("state stored before the record existed still loads")
    func decodesOldState() throws {
        // A runtime as it was written before `days` and `recordedThrough` had names.
        let json = """
        {"exhausted":{"x":"2026-09-08"},"warned":{},"lastReconcile":"2026-09-08T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let runtime = try decoder.decode(RuntimeState.self, from: Data(json.utf8))
        #expect(runtime.exhausted["x"] == "2026-09-08")
        #expect(runtime.days.isEmpty)
        #expect(runtime.recordedThrough == nil)
    }
}

@Suite("Record: what the screens say")
struct RecordCopyTests {
    func card(_ body: (inout Record.Card) -> Void) -> Record.Card {
        var card = Record.Card()
        body(&card)
        return card
    }

    @Test("a streak is stated, never celebrated")
    func streakLines() {
        #expect(Record.streakLine(card { $0.streakDays = 0 }) == "Not today.")
        #expect(Record.streakLine(card { $0.streakDays = 1 }) == "1 day, so far.")
        #expect(Record.streakLine(card { $0.streakDays = 9 }) == "9 days in a row.")
    }

    @Test("a streak that broke says so plainly")
    func brokenStreak() {
        #expect(Record.streakLine(card { $0.streakDays = 1; $0.brokeYesterday = true }) == "Back to day one.")
        #expect(Record.streakLine(card { $0.streakDays = 3; $0.brokeYesterday = true }) == "3 days, after a break.")
    }

    @Test("time held shut is the total, with the anchored share on a row of its own")
    func shieldedLines() {
        #expect(Record.shieldedLine(card { $0.shieldedMinutes = 0 }) == "Nothing held shut yet.")
        #expect(Record.shieldedLine(card { $0.shieldedMinutes = 120 }) == "2 hours")
        #expect(Record.anchoredLine(card { $0.shieldedMinutes = 120 }) == nil)
        #expect(Record.anchoredLine(card { $0.anchoredMinutes = 90 }) == "1 h 30 min")
    }

    @Test("an empty record has nothing to show")
    func emptiness() {
        #expect(Record.card(makeState([]), now: at(8, 12), calendar: cal).isEmpty)
        var state = makeState([])
        state.runtime.days = [key(8): day(shielded: 30)]
        #expect(!Record.card(state, now: at(8, 12), calendar: cal).isEmpty)
    }

    @Test("nothing has waited yet, and no anchor has ever held")
    func absences() {
        #expect(Record.looseningLine(Record.Card()) == "Nothing has waited yet.")
        #expect(Record.anchorLine(Record.Card()) == "Never anchored.")
    }
}
