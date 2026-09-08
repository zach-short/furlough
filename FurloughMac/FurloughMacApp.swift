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
        // Deliberately not `.defaultLaunchBehavior(.suppressed)` for the menu bar case. A
        // suppressed scene is never built, and then there is no window for AppKit to raise —
        // reopening Furlough switched the activation policy and put nothing on screen, which
        // on a Mac with no menu bar item is an app with no way in at all. So the window is
        // always built and put away instead; `MacAppDelegate` hides it at launch.
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
    private var closeWatcher: NSObjectProtocol?

    /// The watchdog agent passes `--background`, so a reopen it caused can be told from a
    /// person double-clicking Furlough. Nothing else passes it.
    static var isWatchdogLaunch: Bool { CommandLine.arguments.contains(Watchdog.backgroundFlag) }

    /// Whether this launch should put a window on screen. Only a first run does: after that
    /// Furlough goes straight to the menu bar, and the window is opened on request.
    @MainActor
    static var opensWindowAtLaunch: Bool { !isWatchdogLaunch && !MacModel.shared.isOnboarded }

    /// The `Window` scene's window, for the menu bar's way back to it. Matched on the scene id
    /// SwiftUI stamps on it, falling back to the one titled window that is not the shield.
    @MainActor
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }
            ?? NSApp.windows.first { !($0 is NSPanel) && $0.styleMask.contains(.titled) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First, before the window or a Dock icon can appear, so an onboarded Mac goes quietly
        // to the menu bar rather than blinking a window on the way.
        if !Self.opensWindowAtLaunch { NSApp.setActivationPolicy(.accessory) }
        UNUserNotificationCenter.current().delegate = self
        MacModel.shared.start()
        let menuBar = MenuBarController(model: MacModel.shared)
        menuBar.install()
        self.menuBar = menuBar
        if Self.opensWindowAtLaunch { Self.showWindow() } else { putTheWindowAway() }
        watchForTheWindowClosing()
    }

    /// Brings the window up, and makes Furlough a regular app for as long as it is there.
    ///
    /// The policy change is not cosmetic. An accessory app has no menu bar menus, and with them
    /// goes the Edit menu — which is where ⌘C and ⌘V live, so the nickname and host fields would
    /// quietly stop taking a paste. Regular while a window is up, accessory again once it closes.
    @MainActor
    static func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Suppressed at launch, so there is nothing to raise. Opening the bundle asks AppKit
            // for the same reopen that double-clicking Furlough does, and that path builds it.
            // It cannot loop: the reopen handler below never calls back into here.
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    /// Opening Furlough again while it is running is the way back to the window that always
    /// exists — no Dock icon and, on some Macs, no menu bar item, but this still works.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Self.mainWindow?.makeKeyAndOrderFront(nil)
        return true
    }

    /// Closing the window puts Furlough back in the menu bar. It does not stop enforcement:
    /// without this, an app with no window left would terminate and the rules would go with it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func watchForTheWindowClosing() {
        closeWatcher = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            // Deferred, and asked as "is anything left" rather than "was that the main window":
            // the closing window is still in `NSApp.windows` while it closes, and a Notification
            // cannot cross into the main actor anyway. The shield is an NSPanel and does not
            // count, so blocking something never drags the Dock icon back.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let stillShowing = NSApp.windows.contains {
                        !($0 is NSPanel) && $0.isVisible && $0.styleMask.contains(.titled)
                    }
                    if !stillShowing { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }

    /// Hides the window Furlough is not meant to show at this launch, keeping it built so
    /// there is always something to raise later.
    ///
    /// Asked three times on purpose, because there are three moments it can appear: one SwiftUI
    /// builds during launch, one AppKit restores from the state saved when Furlough was last
    /// force quit — exactly the case the watchdog exists for — and one that lands a turn later.
    /// None of the three is guaranteed to have happened by now.
    @MainActor
    private func putTheWindowAway() {
        Self.mainWindow?.orderOut(nil)
        DispatchQueue.main.async { MainActor.assumeIsolated { Self.mainWindow?.orderOut(nil) } }
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
