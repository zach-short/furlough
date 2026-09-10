import Foundation

/// The one line Settings gives to whether anything is wrong.
///
/// Five status rows and two timestamps used to sit on the settings screen under Enforcement,
/// above the two controls a person actually came to change. They are all still there, one screen
/// in — what belongs on the front is the answer, not the working: either nothing is wrong, or the
/// first thing that is.
///
/// First, not worst-and-first: the checks are ordered by what they cost, so the line names the
/// thing furthest upstream. Screen Time access being off means nothing at all is enforced, and
/// says so even if notifications are off too, because fixing the notifications would leave the
/// row saying the same thing for a different reason.
///
/// A value built from a reading rather than a view that inspects the app, so the Mac can hand it
/// its own answers to the same questions and get the same sentence back.
struct Diagnostics: Equatable, Sendable {
    /// How loudly the row says it. `warn` is for something switched off that costs you knowing;
    /// `bad` is for something Furlough needs and has not got.
    enum Level: Equatable, Sendable {
        case well
        case warn
        case bad
    }

    var line: String
    var level: Level

    var isWell: Bool { level == .well }

    /// What the app can see about itself. Every field is a question the settings screen already
    /// asked and answered in a row of its own.
    struct Reading: Equatable, Sendable {
        var screenTimeAllowed: Bool
        var appGroupAvailable: Bool
        /// `nil` on a phone that has not been asked yet, which for this row is the same as off:
        /// either way no notification arrives, and either way the fix is the same button.
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

    /// What the row reads under its line, whichever way the line went. Named here rather than in
    /// the view so the Mac's copy of this row says the same thing.
    static let detail = "Screen Time, notifications, shields"

    // MARK: The Mac

    /// The same row, asked about a Mac. Different questions, because the Mac enforces on its own
    /// — there is no Screen Time access to be without, and nothing here registers a schedule.
    /// What it can be without is the two ways it reads the web.
    struct MacReading: Equatable, Sendable {
        /// The web filter's state, reduced to what this row cares about. `WebFilter.Status` has
        /// nine cases and belongs to the Mac app; this is the four answers they come to.
        enum Filter: Equatable, Sendable {
            case notInstalled
            /// Installed, and macOS has not finished being asked yet.
            case waiting
            case on
            /// Installed and refused: switched off in System Settings, or denied the permission.
            case broken
        }

        var filter: Filter
        /// The first browser that refused Automation, if any. Named, because "a browser" sends
        /// somebody looking through five of them.
        var refusedBrowser: String?
        var appGroupAvailable: Bool
        /// `nil` before macOS has been asked, which for this row is the same as off.
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

    /// Ordered by what it costs, as on the phone. A filter that was installed and then switched
    /// off is first because it is the widest hole and the one nobody meant to open: every app on
    /// the Mac stops being filtered, and the tab reader only covers the browsers it can read. A
    /// refused browser is next, because it is that hole in one place. The App Group only costs
    /// the widget, and notifications only cost knowing.
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
        // Last of the warnings rather than first: not installing it is a thing somebody was
        // offered and declined, where the four above are things that went wrong.
        if reading.filter == .notInstalled {
            return Diagnostics(line: "The web filter is not installed", level: .warn)
        }
        return Diagnostics(line: "All good", level: .well)
    }

    /// The Mac row's second line. Its own, because the Mac has no shields and no Screen Time.
    static let macDetail = "The web filter, browsers, notifications"
}
