import Foundation

/// The one line Settings gives to whether anything is wrong. Checks are ordered by what they
/// cost, first not worst-and-first, so the line names the thing furthest upstream (e.g. Screen
/// Time access off, not notifications, even if both are off). Built from a `Reading` rather
/// than inspecting the app directly, so the Mac can feed it its own answers to the same questions.
struct Diagnostics: Equatable, Sendable {
    /// `warn` is for something switched off that costs you knowing; `bad` is for something
    /// Furlough needs and has not got.
    enum Level: Equatable, Sendable {
        case well
        case warn
        case bad
    }

    var line: String
    var level: Level

    var isWell: Bool { level == .well }

    struct Reading: Equatable, Sendable {
        var screenTimeAllowed: Bool
        var appGroupAvailable: Bool
        /// `nil` (not yet asked) is treated the same as off: either way no notification arrives.
        var notificationsAllowed: Bool?
        var registrationError: String?

        init(
            screenTimeAllowed: Bool,
            appGroupAvailable: Bool,
            notificationsAllowed: Bool?,
            registrationError: String? = nil
        ) {
            self.screenTimeAllowed = screenTimeAllowed
            self.appGroupAvailable = appGroupAvailable
            self.notificationsAllowed = notificationsAllowed
            self.registrationError = registrationError
        }
    }

    static func summary(_ reading: Reading) -> Diagnostics {
        if !reading.screenTimeAllowed {
            return Diagnostics(line: "Screen Time access is off", level: .bad)
        }
        if !reading.appGroupAvailable {
            return Diagnostics(line: "The App Group is missing", level: .bad)
        }
        if reading.registrationError != nil {
            return Diagnostics(line: "A schedule did not register", level: .bad)
        }
        if reading.notificationsAllowed != true {
            return Diagnostics(line: "Notifications are off", level: .warn)
        }
        return Diagnostics(line: "All good", level: .well)
    }

    /// Named here rather than in the view so the Mac's copy of this row says the same thing.
    static let detail = "Screen Time, notifications, shields"

    // MARK: The Mac

    /// The same row, asked about a Mac, which enforces on its own and has no Screen Time access
    /// to be without.
    struct MacReading: Equatable, Sendable {
        /// Reduces `WebFilter.Status` (nine cases, belongs to the Mac app) to the four answers
        /// this row cares about.
        enum Filter: Equatable, Sendable {
            case notInstalled
            /// Installed, and macOS has not finished being asked yet.
            case waiting
            case on
            /// Installed and refused: switched off in System Settings, or denied the permission.
            case broken
        }

        var filter: Filter
        /// The first browser that refused Automation, if any. Named, so it doesn't send
        /// somebody looking through five of them.
        var refusedBrowser: String?
        var appGroupAvailable: Bool
        var notificationsAllowed: Bool?

        init(
            filter: Filter,
            refusedBrowser: String? = nil,
            appGroupAvailable: Bool,
            notificationsAllowed: Bool?
        ) {
            self.filter = filter
            self.refusedBrowser = refusedBrowser
            self.appGroupAvailable = appGroupAvailable
            self.notificationsAllowed = notificationsAllowed
        }
    }

    /// Ordered by what it costs: a switched-off filter is the widest hole (every app stops being
    /// filtered), a refused browser is that hole in one place, the App Group only costs the
    /// widget, notifications only cost knowing.
    static func macSummary(_ reading: MacReading) -> Diagnostics {
        if reading.filter == .broken {
            return Diagnostics(line: "The web filter is switched off", level: .bad)
        }
        if let browser = reading.refusedBrowser {
            return Diagnostics(line: "Furlough cannot read \(browser)", level: .bad)
        }
        if !reading.appGroupAvailable {
            return Diagnostics(line: "The App Group is missing", level: .bad)
        }
        if reading.filter == .waiting {
            return Diagnostics(line: "The web filter is waiting on System Settings", level: .warn)
        }
        if reading.notificationsAllowed != true {
            return Diagnostics(line: "Notifications are off", level: .warn)
        }
        // Last of the warnings: not installing it was declined, where the others went wrong.
        if reading.filter == .notInstalled {
            return Diagnostics(line: "The web filter is not installed", level: .warn)
        }
        return Diagnostics(line: "All good", level: .well)
    }

    static let macDetail = "The web filter, browsers, notifications"
}
