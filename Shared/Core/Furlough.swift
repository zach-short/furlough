import Foundation

/// Constants shared by the app and every extension.
enum Furlough {
    static let appGroupID = "group.com.zachshort.furlough"
    static let storeName = "furlough"
    static let bundleID = "com.zachshort.furlough"
    static let minutesPerDay = 1440
    /// DeviceActivity rejects schedules shorter than 15 minutes.
    static let minimumWindowMinutes = 15
    /// DeviceActivity rejects more than 20 concurrently monitored activities.
    static let maxActivities = 20
    static let warningMinutes = 5
    static let defaultLoosenDelayHours = 24
    static let defaultBudgetMinutes = 30
}
