import AppKit
import SwiftUI
import UserNotifications

@main
struct FurloughMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @State private var model = MacModel.shared

    var body: some Scene {
        Window("Furlough", id: "main") {
            MacRootView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        // A reopen by the watchdog exists to resume enforcement, so it brings back no window.
        // The menu bar item is the status surface for that case, and clicking the Dock icon
        // or "Open Furlough" brings the window back. A launch by a person is unchanged.
        .defaultLaunchBehavior(MacAppDelegate.isWatchdogLaunch ? .suppressed : .presented)
    }
}

/// Starts enforcement, keeps notifications visible while Furlough is in front, and refuses
/// to quit while something is blocked. Logging out, restarting and shutting down are always
/// allowed; Force Quit always works too, and is the Mac's documented escape.
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Built in `applicationDidFinishLaunching` rather than here: the delegate is not
    /// `@MainActor`, so a property initialiser cannot reach `MacModel.shared`.
    private var menuBar: MenuBarController?
    private var restoreWatcher: NSObjectProtocol?

    /// The watchdog agent passes `--background`, so a reopen it caused can be told from a
    /// person double-clicking Furlough. Nothing else passes it.
    static var isWatchdogLaunch: Bool { CommandLine.arguments.contains(Watchdog.backgroundFlag) }

    /// The `Window` scene's window, for the menu bar's way back to it. Matched on the scene id
    /// SwiftUI stamps on it, falling back to the one titled window that is not the shield.
    @MainActor
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }
            ?? NSApp.windows.first { !($0 is NSPanel) && $0.styleMask.contains(.titled) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        MacModel.shared.start()
        let menuBar = MenuBarController(model: MacModel.shared)
        menuBar.install()
        self.menuBar = menuBar
        if Self.isWatchdogLaunch { putTheWindowAway() }
    }

    /// `.defaultLaunchBehavior(.suppressed)` keeps SwiftUI from opening the window, but AppKit
    /// still restores the one it saved when Furlough was last force-quit — which is exactly the
    /// case the watchdog exists for — so it has to be put away again after restoration. Asked
    /// twice on purpose: once now for the window restoration may already have built, and once
    /// when AppKit says it has finished, since the two orders are not guaranteed.
    @MainActor
    private func putTheWindowAway() {
        Self.mainWindow?.orderOut(nil)
        restoreWatcher = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification, object: nil, queue: .main
        ) { _ in
            // Captures nothing: the delegate is not Sendable, and the notification fires once
            // per launch anyway, so there is nothing to tear down.
            MainActor.assumeIsolated { Self.mainWindow?.orderOut(nil) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isSystemQuit { return .terminateNow }
        let decision = MacModel.shared.enforcer.lastDecision
        guard decision.isAnythingShielded else { return .terminateNow }
        let count = decision.blockedApps.count + decision.blockedHosts.count
        let alert = NSAlert()
        alert.messageText = "Furlough is blocking \(count) \(count == 1 ? "thing" : "things")."
        alert.informativeText = "It keeps running until every rule is open. Force Quit ends enforcement until Furlough is opened again; that is the one escape, and it is meant to be a deliberate one."
        alert.addButton(withTitle: "Keep Running")
        alert.runModal()
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    /// The quit Apple Event carries a reason when the system is logging out or shutting down.
    private var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) else { return false }
        let code = reason.enumCodeValue
        return [kAELogOut, kAEReallyLogOut, kAEShutDown, kAERestart].contains { OSType($0) == code }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
