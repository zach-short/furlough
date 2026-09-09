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
    /// out to them. Nothing is ever fetched — `openURL` hands the address to Safari, and
    /// Furlough itself still makes no network request of any kind.
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
    /// How many tags may release one anchor. More than one because a person can live in more
    /// than one place, and a key three hours away is not a stronger lock — it is a lock nobody
    /// dares close. Capped so the count cannot drift upward until one is always in a pocket.
    static let maxAnchorTags = 3
}
