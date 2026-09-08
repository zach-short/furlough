import Foundation

/// A calendar that does not move: GMT and en_US_POSIX, so weekdays, day boundaries and
/// formatted strings are the same on any machine. Tests vary only `firstWeekday`.
func fixedCalendar(firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = firstWeekday
    return calendar
}

/// The calendar nearly every test uses: Sunday first.
let cal = fixedCalendar()

/// A moment in September 2026, in `cal`. The 6th is a Sunday and the 12th a Saturday, so the
/// 8th (used most) is a Tuesday, Calendar weekday 3.
func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar = cal) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 9
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components) ?? .distantPast
}

/// Minutes of the day as a window on every day, unless days are given.
func window(_ start: Int, _ end: Int, _ days: Weekdays = .all) -> TimeWindow {
    TimeWindow(startMinute: start, endMinute: end, days: days)
}

func makeTarget(_ name: String, rule: Rule?, id: UUID = UUID()) -> Target {
    Target(id: id, kind: .host("\(name.lowercased()).com"), nickname: name, rule: rule, addedAt: at(1))
}

func makeConfig(_ targets: [Target], delayHours: Int = 24) -> Config {
    var config = Config()
    config.targets = targets
    config.loosenDelayHours = delayHours
    return config
}

func makeState(_ targets: [Target], pending: [PendingChange] = [], runtime: RuntimeState = RuntimeState()) -> SharedState {
    var state = SharedState()
    state.config = makeConfig(targets)
    state.pending = pending
    state.runtime = runtime
    return state
}
