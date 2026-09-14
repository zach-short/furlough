import Foundation

/// GMT + en_US_POSIX, so weekdays, day boundaries and formatted strings are the same on any
/// machine. Tests vary only `firstWeekday`.
func fixedCalendar(firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = firstWeekday
    return calendar
}

/// The calendar nearly every test uses: Sunday first.
let cal = fixedCalendar()

/// A formatted time carries a narrow no-break space before AM/PM (U+202F), correct on screen but
/// unwriteable in a test literal (and invisible in a failure diff: "1:00 PM" == "1:00 PM").
/// Flattens it to a plain space so literals stay readable.
func plainSpaces(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
}

/// A moment in September 2026, in `cal`. The 6th is a Sunday, the 12th a Saturday, so the 8th
/// (used most) is a Tuesday.
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
