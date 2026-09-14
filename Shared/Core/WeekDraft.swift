import Foundation

/// Spans are joined per day and merged back into shared windows across days, keeping the
/// window list minimal.
///
/// The bridge between a rule's windows — a span plus the days it applies to — and the way a week
/// is drawn, which is one list of spans per day. It lived twice, once in each app's week view,
/// until the grid became editable and both sides needed the same arithmetic.
struct WeekDraft: Equatable {
    private var spans: [Int: [TimeWindow]] = [:]

    init(windows: [TimeWindow]) {
        for weekday in 1...7 {
            spans[weekday] = TimeWindow.joined(windows.filter { $0.applies(on: weekday) }.map(\.span))
        }
    }

    func spans(on weekday: Int) -> [TimeWindow] { spans[weekday] ?? [] }

    /// No spans on any day: the rule is open all day, every day, up to the budget.
    var isAllDay: Bool { spans.values.allSatisfy(\.isEmpty) }

    mutating func set(_ hours: [TimeWindow], on weekday: Int) {
        spans[weekday] = TimeWindow.joined(hours.map(\.span))
    }

    /// Adds the hours of `source` to every day in `days`, on top of what each already had.
    mutating func apply(from source: Int, to days: Weekdays) {
        let hours = spans(on: source)
        for weekday in 1...7 where weekday != source && days.contains(weekday: weekday) {
            spans[weekday] = TimeWindow.joined(spans(on: weekday) + hours)
        }
    }

    /// One window per distinct span, on every day that has it.
    var windows: [TimeWindow] {
        var days: [TimeWindow: Weekdays] = [:]
        for weekday in 1...7 {
            for span in spans(on: weekday) {
                days[span, default: []].formUnion(Weekdays(weekday: weekday))
            }
        }
        return days
            .map { TimeWindow(startMinute: $0.key.startMinute, endMinute: $0.key.endMinute, days: $0.value) }
            .sorted()
    }
}

// MARK: Editing a day where it is drawn
//
// The arithmetic behind a drag on the week grid: the room a span has between its neighbours,
// where it lands when it is moved or resized, and where a new one goes. Pure and here rather
// than in the view because it is the whole substance of the gesture — a view cannot be tested
// and this can. Every one of these takes and returns one day's spans, sorted and never
// overlapping, which is what `spans(on:)` always holds; the grid writes the answer back through
// `set(_:on:)` so joining and the merge into windows stay in the one place that knows how.

extension WeekDraft {
    /// A drag lands on a quarter hour. Deliberately the same number as the shortest window a
    /// rule may carry, so a snapped edit can never leave one too short to enforce.
    static let snapMinutes = Furlough.minimumWindowMinutes

    /// What a fresh window is worth on empty track, before the gap it falls in trims it. Two
    /// hours rather than the hour the day's list starts one at, because on the grid the block is
    /// the only answer you get: an hour of track is under twenty points tall and too short to
    /// print its own start time.
    static let addedWindowMinutes = 120

    static func snapped(_ minute: Int) -> Int {
        let step = max(1, snapMinutes)
        let rounded = Int((Double(minute) / Double(step)).rounded()) * step
        return min(Furlough.minutesPerDay, max(0, rounded))
    }

    /// How far the span at `index` may reach either way before it meets a neighbour: the
    /// previous span's end and the next one's start, or the ends of the day. Every clamp below
    /// falls out of these two numbers.
    static func room(in spans: [TimeWindow], at index: Int) -> ClosedRange<Int> {
        guard spans.indices.contains(index) else { return 0...Furlough.minutesPerDay }
        let lower = index > 0 ? spans[index - 1].endMinute : 0
        let upper = index < spans.count - 1 ? spans[index + 1].startMinute : Furlough.minutesPerDay
        return lower...max(lower, upper)
    }

    /// The day with the span at `index` moved to start at `minute`. Its length never changes:
    /// a move that would run into a neighbour stops against it.
    static func moved(_ spans: [TimeWindow], at index: Int, startingAt minute: Int) -> [TimeWindow] {
        guard spans.indices.contains(index) else { return spans }
        let room = room(in: spans, at: index)
        let length = spans[index].durationMinutes
        let latest = max(room.lowerBound, room.upperBound - length)
        let start = min(max(snapped(minute), room.lowerBound), latest)
        var edited = spans
        edited[index] = TimeWindow(startMinute: start, endMinute: start + length)
        return edited
    }

    /// The day with the top edge of the span at `index` dragged to `minute`: never past its
    /// own end less the minimum, never into the span above.
    static func resized(_ spans: [TimeWindow], at index: Int, startTo minute: Int) -> [TimeWindow] {
        guard spans.indices.contains(index) else { return spans }
        let room = room(in: spans, at: index)
        let end = spans[index].endMinute
        let start = min(max(snapped(minute), room.lowerBound), end - Furlough.minimumWindowMinutes)
        var edited = spans
        edited[index] = TimeWindow(startMinute: start, endMinute: end)
        return edited
    }

    /// The day with the bottom edge of the span at `index` dragged to `minute`.
    static func resized(_ spans: [TimeWindow], at index: Int, endTo minute: Int) -> [TimeWindow] {
        guard spans.indices.contains(index) else { return spans }
        let room = room(in: spans, at: index)
        let start = spans[index].startMinute
        let end = max(min(snapped(minute), room.upperBound), start + Furlough.minimumWindowMinutes)
        var edited = spans
        edited[index] = TimeWindow(startMinute: start, endMinute: end)
        return edited
    }

    /// The day with a window added around `minute`, centred on it and pushed whole into the gap
    /// it fell in. Nil when that minute is already inside a window, or when the gap is too small
    /// to hold one — the grid does nothing rather than adding something it would have to refuse.
    static func added(to spans: [TimeWindow], at minute: Int, length: Int = addedWindowMinutes) -> [TimeWindow]? {
        guard (0..<Furlough.minutesPerDay).contains(minute) else { return nil }
        guard !spans.contains(where: { $0.contains(minuteOfDay: minute) }) else { return nil }
        let lower = spans.filter { $0.endMinute <= minute }.map(\.endMinute).max() ?? 0
        let upper = spans.filter { $0.startMinute > minute }.map(\.startMinute).min() ?? Furlough.minutesPerDay
        guard upper - lower >= Furlough.minimumWindowMinutes else { return nil }
        let span = min(max(length, Furlough.minimumWindowMinutes), upper - lower)
        let start = min(max(snapped(minute - span / 2), lower), upper - span)
        return (spans + [TimeWindow(startMinute: start, endMinute: start + span)]).sorted()
    }

    /// The day without the span at `index`.
    static func removed(_ spans: [TimeWindow], at index: Int) -> [TimeWindow] {
        guard spans.indices.contains(index) else { return spans }
        var edited = spans
        edited.remove(at: index)
        return edited
    }
}
