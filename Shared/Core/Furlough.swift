import Foundation

/// Constants shared by the app and every extension.
enum Furlough {
    static let appGroupID = "group.com.zachshort.furlough"
    /// Starts with the team identifier rather than "group." — on the Mac that needs no
    /// provisioning profile, so no registered Mac: the signing team is the proof.
    static let macAppGroupID = "X9V4L6HR2R.com.zachshort.furlough"
    static let storeName = "furlough"
    static let bundleID = "com.zachshort.furlough"
    /// Here rather than on `DropAnchorControl` because the drop itself (not just the control)
    /// needs to ask for a redraw.
    static let anchorControlKind = "com.zachshort.furlough.dropAnchor"
    /// The notifications that carry a Drop anchor button, and the button itself; registered by
    /// both apps at launch (`AnchorOffer.register`) and read back by their notification delegates.
    static let anchorNotificationCategory = "com.zachshort.furlough.notification.moment"
    static let anchorNotificationAction = "com.zachshort.furlough.notification.dropAnchor"
    static let minutesPerDay = 1440
    /// DeviceActivity rejects schedules shorter than 15 minutes.
    static let minimumWindowMinutes = 15
    /// DeviceActivity rejects more than 20 concurrently monitored activities.
    static let maxActivities = 20
    static let warningMinutes = 5
    static let defaultLoosenDelayHours = 24
    /// A floor so a low base delay times the essential tier can't round to nothing.
    static let minimumLoosenDelayHours = 1
    static let defaultBudgetMinutes = 30
    /// Covers a first whole week including a weekend, when window rules first get exercised.
    /// Fixed the moment access is granted, never extended.
    static let trialDays = 7
    /// Not zero — a first week with no wait would teach a habit the second week then breaks.
    static let trialDelayHours = 1
    /// Long enough for "wait, no", short enough it can't be used as a pause.
    static let undoWindowMinutes = 15
    /// Monday (weekday 2) because the week it reports just finished; 9am because it's a thing
    /// to read once the day has started, not to be woken by.
    static let digestWeekday = 2
    static let digestHour = 9
    /// More than one tag since a person can live in more than one place; capped so it can't
    /// drift upward until one is always in a pocket.
    static let maxAnchorTags = 3
}
