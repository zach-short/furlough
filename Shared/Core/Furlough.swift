import Foundation

/// Constants shared by the app and every extension.
enum Furlough {
    static let appGroupID = "group.com.zachshort.furlough"
    /// The Mac app and its widget share this container. It starts with the team identifier
    /// rather than "group." because on the Mac a group named that way needs no provisioning
    /// profile, and so no registered Mac: the signing team is the proof.
    static let macAppGroupID = "X9V4L6HR2R.com.zachshort.furlough"
    static let storeName = "furlough"
    /// The public site. The help pages that need no live data live there rather than in the
    /// binary, so their wording can be corrected without an App Store review; the app links
    /// out to them. Nothing is ever fetched — `openURL` hands the address to Safari. The one
    /// thing Furlough writes off the device is the Anchor's state, to the user's own iCloud
    /// key-value store (`AnchorCloud`); it still makes no request to any server of its own.
    static let siteURL = "https://furloughapp.com"
    /// The address of one help page on the site. Optional rather than force-unwrapped because
    /// nothing in this file is worth a crash; a page whose URL would not parse simply does
    /// nothing when tapped, and every path here is a literal, so none of them can.
    static func helpURL(_ page: String) -> URL? {
        URL(string: "\(siteURL)/help/\(page)/")
    }
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
