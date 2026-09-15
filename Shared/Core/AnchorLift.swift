import Foundation

extension Policy {
    /// When an anchor dropped at `now` lifts, for a lift asked for as a time of day: today at
    /// that minute if it is at least `Furlough.minimumWindowMinutes` away — DeviceActivity will
    /// not wake the monitor for less — otherwise tomorrow at it. The Anchor screen's own rule,
    /// shared with the Drop Anchor intent so "until 7 AM" in a nightly automation means the same
    /// thing it means on the screen: the next 7 AM, never one already gone.
    static func liftDate(atMinute minute: Int, from now: Date, calendar: Calendar = .current) -> Date {
        let soonest = now.addingTimeInterval(TimeInterval(Furlough.minimumWindowMinutes * 60))
        let today = date(atMinute: minute, of: now, calendar: calendar)
        if today >= soonest { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return date(atMinute: minute, of: tomorrow, calendar: calendar)
    }
}
