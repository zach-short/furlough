import Foundation
import ServiceManagement

/// A launchd agent that opens Furlough again when it is not running.
///
/// Force Quit stays the documented escape on the Mac, and it still works: quitting Furlough
/// that way lifts every block at once. What it no longer does is buy the rest of the day —
/// within a minute the agent opens Furlough again and the rules come back. That is the same
/// bargain as the phone, where turning Screen Time access off works and is meant to be a
/// deliberate act rather than a shortcut.
///
/// The agent runs `open -g -b <bundle id>` rather than launching the executable, for two
/// reasons. `open` hands off to a copy that is already running instead of starting a second
/// one, which is what made a plain `KeepAlive` agent unusable here: launchd and a user launch
/// would race and leave two enforcers ticking against one store. And `-g` leaves Furlough in
/// the background, so a reopen never steals focus from whatever the user is doing.
enum Watchdog {
    static let label = "com.zachshort.furlough.mac.watchdog"

    /// Passed by the agent so the app can tell its reopen from a person's launch and bring
    /// back no window. It lives here rather than in the delegate because the plist that sends
    /// it is this file's business.
    static let backgroundFlag = "--background"

    /// Bumped whenever the bundled plist changes. `SMAppService` hands launchd a copy of the
    /// job at registration and does not re-read it when the app is replaced, so an agent
    /// registered by an older build would keep running the old command — here, one with no
    /// `--background`, which would put the window back on every watchdog reopen.
    private static let plistVersion = 2
    private static let versionKey = "furlough.watchdog.plistVersion"

    /// Bundled at `Contents/Library/LaunchAgents/` by the copy-files phase in `project.yml`.
    private static var service: SMAppService { SMAppService.agent(plistName: "\(label).plist") }

    static var status: SMAppService.Status { service.status }
    static var isOn: Bool { status == .enabled }

    /// True when the user has switched the agent off in System Settings > General > Login Items.
    /// Registering again cannot override that, and should not try to.
    static var isRefusedByUser: Bool { status == .requiresApproval }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on {
                guard status != .enabled else { return true }
                try service.register()
                SharedStore.log("watchdog on: Furlough reopens within a minute of being quit")
            } else {
                guard status == .enabled else { return true }
                try service.unregister()
                SharedStore.log("watchdog off")
            }
            return true
        } catch {
            SharedStore.log("watchdog: \(error.localizedDescription)")
            return false
        }
    }

    /// Called once enforcement is set up. Registering is idempotent, and a user who has turned
    /// the agent off in System Settings is left alone rather than asked again every launch.
    static func enableIfNeeded() {
        guard !isRefusedByUser else {
            SharedStore.log("watchdog is switched off in System Settings > General > Login Items")
            return
        }
        if isOn, SharedStore.defaults.integer(forKey: versionKey) != plistVersion {
            SharedStore.log("watchdog: the agent changed, registering it again")
            set(false)
        }
        if set(true) { SharedStore.defaults.set(plistVersion, forKey: versionKey) }
    }
}
