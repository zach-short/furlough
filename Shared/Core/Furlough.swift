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
    /// The Control Center control's kind. Here rather than on `DropAnchorControl` because the
    /// thing that has to ask for a redraw is the drop itself, which runs in the app as well as
    /// in the widget extension where the control lives.
    static let anchorControlKind = "com.zachshort.furlough.dropAnchor"
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
    /// How long the delays are held back after Screen Time access is first granted. Long
    /// enough to cover a first whole week, weekend included, because a weekend is when window
    /// rules are first really exercised. Fixed the moment it is granted, and never extended.
    static let trialDays = 7
    /// What a loosening waits while that week runs. Not nothing: a first week with no wait at
    /// all would teach a habit the second week then breaks. An hour is short enough that a
    /// mistake costs a lunch break, and long enough that it is still a wait.
    static let trialDelayHours = 1
    /// How long after an edit lands it can be taken back, exactly as it was. Long enough for
    /// "wait, no", short enough that it cannot be used as a pause.
    static let undoWindowMinutes = 15
    /// How many tags may release one anchor. More than one because a person can live in more
    /// than one place, and a key three hours away is not a stronger lock — it is a lock nobody
    /// dares close. Capped so the count cannot drift upward until one is always in a pocket.
    static let maxAnchorTags = 3
}
