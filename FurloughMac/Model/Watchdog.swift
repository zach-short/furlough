import Foundation
import ServiceManagement

/// A launchd agent that reopens Furlough when it is not running.
///
/// Runs `open -g -b <bundle id>`, not the executable directly: `open` hands off to an
/// already-running copy instead of starting a second one (a plain `KeepAlive` agent would
/// race a user launch into two enforcers on one store), and `-g` keeps it backgrounded. Only
/// runs when Furlough is not already up — the handoff to a running copy arrives as the same
/// reopen Apple Event a Dock click sends, which without that guard raised the window every
/// interval.
enum Watchdog {
    static let label = "com.zachshort.furlough.mac.watchdog"

    /// Distinguishes the agent's relaunch from a user launch, so no window is shown.
    static let backgroundFlag = "--background"

    /// Bump when the plist changes: `SMAppService` doesn't re-read it on app replacement, so
    /// an old build's agent keeps running its stale command.
    private static let plistVersion = 5
    private static let versionKey = "furlough.watchdog.plistVersion"

    /// Bundled at `Contents/Library/LaunchAgents/` by the copy-files phase in `project.yml`.
    private static var service: SMAppService { SMAppService.agent(plistName: "\(label).plist") }

    static var status: SMAppService.Status { service.status }
    static var isOn: Bool { status == .enabled }

    /// Once refused in System Settings, re-registering can't (and shouldn't) override it.
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

    /// Idempotent; leaves a user-disabled agent alone rather than re-asking every launch.
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
    /// Forgets the plist version too, not just unregisters: a fresh install has no record
    /// either, so onboarding re-registers from scratch rather than taking the
    /// remembered-version shortcut.
    @discardableResult
    static func forget() -> Bool {
        let off = set(false)
        SharedStore.defaults.removeObject(forKey: versionKey)
        return off
    }
    #endif

    /// Registering over an existing job updates its args but not the code requirement it was
    /// pinned to — changing the program silently breaks it (`spawn failed`, exit 78) while
    /// `status` still reports `.enabled`. So unregister first and wait for launchd to actually
    /// let go before registering again.
    private static func replaceRegistration() async {
        if isOn {
            // The async overload waits for launchd to actually let go, unlike the throwing one.
            do { try await service.unregister() } catch {
                SharedStore.log("watchdog: \(error.localizedDescription)")
            }
            // `status` reads through Background Task Management, which can lag the job itself.
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
