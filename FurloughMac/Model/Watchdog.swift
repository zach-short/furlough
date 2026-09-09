import Foundation
import ServiceManagement

/// A launchd agent that opens Furlough again when it is not running.
///
/// Force Quit stays the documented escape on the Mac, and it still works: quitting Furlough
/// that way lifts every block at once. What it no longer does is buy anything worth having —
/// within ten seconds the agent opens Furlough again and the rules come back. That is the same
/// bargain as the phone, where turning Screen Time access off works and is meant to be a
/// deliberate act rather than a shortcut.
///
/// The agent runs `open -g -b <bundle id>` rather than launching the executable, for two
/// reasons. `open` hands off to a copy that is already running instead of starting a second
/// one, which is what made a plain `KeepAlive` agent unusable here: launchd and a user launch
/// would race and leave two enforcers ticking against one store. And `-g` leaves Furlough in
/// the background, so a reopen never steals focus from whatever the user is doing.
///
/// It runs that only when Furlough is not already up. launchd fires the job on its interval
/// whatever the app is doing, and the handoff to a running copy is not free: it arrives as the
/// same reopen Apple Event a Dock click sends, and `applicationShouldHandleReopen` answers it
/// by raising the window and making Furlough a regular app again. Unguarded, that put the
/// window back on screen every ten seconds — minimised or closed, it came straight back.
enum Watchdog {
    static let label = "com.zachshort.furlough.mac.watchdog"

    /// Passed by the agent so the app can tell its reopen from a person's launch and bring
    /// back no window. It lives here rather than in the delegate because the plist that sends
    /// it is this file's business.
    static let backgroundFlag = "--background"

    /// Bumped whenever the bundled plist changes. `SMAppService` hands launchd a copy of the
    /// job at registration and does not re-read it when the app is replaced, so an agent
    /// registered by an older build would keep running the old command — here, one that pokes
    /// a running Furlough every ten seconds and puts the window back with it.
    private static let plistVersion = 5
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
                SharedStore.log("watchdog on: Furlough reopens within seconds of being quit")
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
        guard SharedStore.defaults.integer(forKey: versionKey) != plistVersion else {
            if set(true) { SharedStore.defaults.set(plistVersion, forKey: versionKey) }
            return
        }
        SharedStore.log("watchdog: the agent changed, registering it again")
        Task.detached { await replaceRegistration() }
    }

    #if DEBUG || TESTING_TOOLS
    /// Takes the agent away and forgets which plist went in, for Settings > Testing > Reset
    /// everything. Forgetting the version matters as much as unregistering: a fresh install has
    /// no record either, so the onboarding that follows registers down the same path a real
    /// first run takes rather than the shortcut a remembered version opens.
    ///
    /// Returns what `set` returned, so a reset can say that the agent refused to come off. The
    /// version is forgotten either way: an agent still running an old plist is exactly the one
    /// the next onboarding should register again from scratch.
    @discardableResult
    static func forget() -> Bool {
        let off = set(false)
        SharedStore.defaults.removeObject(forKey: versionKey)
        return off
    }
    #endif

    /// Takes the agent away and puts it back, for a launch that finds the bundled plist changed.
    ///
    /// Registering over a job launchd already holds updates its arguments but not the code
    /// requirement the job was pinned to when it first went in. Change the program — as the
    /// guard did, from `open` to `sh` — and the job stops running at all: launchd reports
    /// `spawn failed` and every run exits 78, while `status` still cheerfully says `.enabled`,
    /// so `set(true)` sees an agent that is already on and does nothing. A Mac in that state
    /// has no watchdog and no sign of it. Hence unregistering first, and waiting for it to
    /// land: `unregister()` returns before launchd has let go, and registering back into that
    /// window is what leaves the old pin in place.
    private static func replaceRegistration() async {
        if isOn {
            // The async `unregister()` waits for launchd to actually let go, where the throwing
            // one returns straight away; in here it is the overload the compiler picks anyway.
            do { try await service.unregister() } catch {
                SharedStore.log("watchdog: \(error.localizedDescription)")
            }
            // Belt and braces: `status` is read back through Background Task Management, which
            // can still be a step behind the job itself.
            var waited = 0
            while isOn, waited < 40 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
        }
        do {
            try service.register()
            SharedStore.defaults.set(plistVersion, forKey: versionKey)
            SharedStore.log("watchdog on: Furlough reopens within seconds of being quit")
        } catch {
            SharedStore.log("watchdog: \(error.localizedDescription)")
        }
    }
}
