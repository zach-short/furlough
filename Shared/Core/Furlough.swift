import Foundation

/// Constants shared by the app and every extension.
enum Furlough {
    static let appGroupID = "group.com.zachshort.furlough"
    /// The Mac app and its widget share this container. It starts with the team identifier
    /// rather than "group." because on the Mac a group named that way needs no provisioning
    /// profile, and so no registered Mac: the signing team is the proof.
    static let macAppGroupID = "X9V4L6HR2R.com.zachshort.furlough"
    static let storeName = "furlough"
    static let bundleID = "com.zachshort.furlough"
    static let minutesPerDay = 1440
    /// DeviceActivity rejects schedules shorter than 15 minutes.
    static let minimumWindowMinutes = 15
    /// DeviceActivity rejects more than 20 concurrently monitored activities.
    static let maxActivities = 20
    static let warningMinutes = 5
    static let defaultLoosenDelayHours = 24
    /// However short the base delay and however essential the app, a loosening still
    /// waits this long. Without it a low base times the essential tier rounds to nothing.
    static let minimumLoosenDelayHours = 1
    static let defaultBudgetMinutes = 30
}
