import Foundation
import Testing

@Suite("WeekDraft")
struct WeekDraftTests {
    @Test("windows become per-day spans and come back as the same windows")
    func roundTrip() {
        let windows = [window(540, 660), window(1200, 1440, .weekdays)]
        let draft = WeekDraft(windows: windows)

        #expect(draft.spans(on: 1) == [window(540, 660)])
        #expect(draft.spans(on: 4) == [window(540, 660), window(1200, 1440)])
        #expect(draft.windows == windows.sorted())
    }

    /// The pair a night is stored as lives on two days one apart. The editors fold it into one
    /// row and split it again on the way back, so the draft must survive that cycle untouched.
    @Test("a window across midnight survives the fold and the split")
    func night() {
        let stored = [window(1200, 1440, .friday), window(0, 120, .saturday)]
        let draft = WeekDraft(windows: stored)

        #expect(draft.spans(on: 6) == [window(1200, 1440)])
        #expect(draft.spans(on: 7) == [window(0, 120)])

        let folded = TimeWindow.folded(draft.windows)
        #expect(folded == [window(1200, 120, .friday)])
        #expect(WeekDraft(windows: folded.flatMap(\.split)) == draft)
    }

    @Test("spans that touch or overlap become one")
    func joining() {
        var draft = WeekDraft(windows: [])
        draft.set([window(540, 660), window(660, 720)], on: 2)
        #expect(draft.spans(on: 2) == [window(540, 720)])

        draft.set([window(540, 700), window(660, 720)], on: 2)
        #expect(draft.spans(on: 2) == [window(540, 720)])

        draft.set([window(540, 600), window(660, 720)], on: 2)
        #expect(draft.spans(on: 2) == [window(540, 600), window(660, 720)])
    }

    @Test("applying a day's hours adds to what the others already had")
    func apply() {
        var draft = WeekDraft(windows: [window(540, 600, .tuesday), window(1200, 1260, .wednesday)])
        draft.apply(from: 3, to: [.wednesday, .thursday])

        #expect(draft.spans(on: 3) == [window(540, 600)])
        #expect(draft.spans(on: 4) == [window(540, 600), window(1200, 1260)])
        #expect(draft.spans(on: 5) == [window(540, 600)])
    }

    @Test("no spans anywhere is the open week; one window ends it")
    func allDay() {
        var draft = WeekDraft(windows: [])
        #expect(draft.isAllDay)
        #expect(draft.windows.isEmpty)

        draft.set([window(540, 600)], on: 4)
        #expect(!draft.isAllDay)
        #expect(draft.windows == [window(540, 600, .wednesday)])
    }

    @Test("a day emptied keeps the others, and emptying the last one opens the week again")
    func emptied() {
        var draft = WeekDraft(windows: [window(540, 600, [.tuesday, .wednesday])])
        draft.set([], on: 3)

        #expect(draft.spans(on: 3).isEmpty)
        #expect(draft.windows == [window(540, 600, .wednesday)])
        #expect(!draft.isAllDay)

        draft.set([], on: 4)
        #expect(draft.isAllDay)
    }

    // MARK: The drag

    @Test("a dragged minute lands on the quarter hour, inside the day")
    func snapping() {
        #expect(WeekDraft.snapMinutes == Furlough.minimumWindowMinutes)
        #expect(WeekDraft.snapped(0) == 0)
        #expect(WeekDraft.snapped(7) == 0)
        #expect(WeekDraft.snapped(8) == 15)
        #expect(WeekDraft.snapped(1207) == 1200)
        #expect(WeekDraft.snapped(-40) == 0)
        #expect(WeekDraft.snapped(2000) == Furlough.minutesPerDay)
    }

    @Test("the room a span has is its neighbours' edges, or the ends of the day")
    func room() {
        let day = [window(0, 120), window(540, 600), window(1200, 1440)]

        #expect(WeekDraft.room(in: day, at: 0) == 0...540)
        #expect(WeekDraft.room(in: day, at: 1) == 120...1200)
        #expect(WeekDraft.room(in: day, at: 2) == 600...1440)
        #expect(WeekDraft.room(in: [window(540, 600)], at: 0) == 0...Furlough.minutesPerDay)
        #expect(WeekDraft.room(in: day, at: 9) == 0...Furlough.minutesPerDay)
    }

    @Test("a moved span keeps its length and stops against its neighbours")
    func moving() {
        let day = [window(120, 180), window(540, 600), window(1380, 1440)]

        #expect(WeekDraft.moved(day, at: 1, startingAt: 600)[1] == window(600, 660))
        // Snapped on the way, not after: 607 is a quarter hour from 600, not 601.
        #expect(WeekDraft.moved(day, at: 1, startingAt: 607)[1] == window(600, 660))
        // Up against the one above, and down against the one below, length intact.
        #expect(WeekDraft.moved(day, at: 1, startingAt: 0)[1] == window(180, 240))
        #expect(WeekDraft.moved(day, at: 1, startingAt: 1400)[1] == window(1320, 1380))
        #expect(WeekDraft.moved(day, at: 0, startingAt: -300)[0] == window(0, 60))
        #expect(WeekDraft.moved(day, at: 2, startingAt: 2000)[2] == window(1380, 1440))
        // The neighbours never move.
        #expect(WeekDraft.moved(day, at: 1, startingAt: 0)[0] == day[0])
        #expect(WeekDraft.moved(day, at: 1, startingAt: 0)[2] == day[2])
    }

    @Test("a resized edge stops at the minimum and at the neighbour")
    func resizing() {
        let day = [window(120, 180), window(540, 600), window(1380, 1440)]

        #expect(WeekDraft.resized(day, at: 1, startTo: 480)[1] == window(480, 600))
        #expect(WeekDraft.resized(day, at: 1, endTo: 720)[1] == window(540, 720))
        // Never shorter than a window may be, from either edge.
        #expect(WeekDraft.resized(day, at: 1, startTo: 700)[1] == window(585, 600))
        #expect(WeekDraft.resized(day, at: 1, endTo: 300)[1] == window(540, 555))
        // Never into the span above or below.
        #expect(WeekDraft.resized(day, at: 1, startTo: 60)[1] == window(180, 600))
        #expect(WeekDraft.resized(day, at: 1, endTo: 1400)[1] == window(540, 1380))
        #expect(WeekDraft.resized(day, at: 2, endTo: 2000)[2] == window(1380, 1440))
    }

    @Test("empty track takes a new window, centred on the tap and pushed into the gap")
    func adding() {
        let day = [window(120, 180), window(1380, 1440)]

        #expect(WeekDraft.added(to: day, at: 600) == [window(120, 180), window(540, 660), window(1380, 1440)])
        // Inside one already: nothing, so a tap that misses does not stack a window on a window.
        #expect(WeekDraft.added(to: day, at: 150) == nil)
        // A gap too small to hold one is left alone; one that can only hold part gets that part.
        #expect(WeekDraft.added(to: [window(0, 1430)], at: 1435) == nil)
        #expect(WeekDraft.added(to: [window(0, 1400)], at: 1420) == [window(0, 1400), window(1400, 1440)])
        // Against the ends of the day, where half a window would fall off it.
        #expect(WeekDraft.added(to: [], at: 10) == [window(0, 120)])
        #expect(WeekDraft.added(to: [], at: 1435) == [window(1320, 1440)])
    }

    @Test("a removed span leaves the rest of the day where it was")
    func removing() {
        let day = [window(120, 180), window(540, 600)]

        #expect(WeekDraft.removed(day, at: 0) == [window(540, 600)])
        #expect(WeekDraft.removed(day, at: 1) == [window(120, 180)])
        #expect(WeekDraft.removed(day, at: 4) == day)
    }

    /// What the grid actually does with the answers above: hand them to `set(_:on:)` and let it
    /// join, so a block dragged flush against its neighbour becomes one window rather than two
    /// that touch.
    @Test("a drag written back through set joins what it meets")
    func draggedFlush() {
        var draft = WeekDraft(windows: [window(540, 600, .wednesday), window(720, 780, .wednesday)])
        let day = draft.spans(on: 4)
        draft.set(WeekDraft.moved(day, at: 0, startingAt: 660), on: 4)

        #expect(draft.spans(on: 4) == [window(660, 780)])
        #expect(draft.windows == [window(660, 780, .wednesday)])
    }
}
