import AppKit
import SwiftUI
import UserNotifications

@main
struct FurloughMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @State private var model = MacModel.shared
    /// Held here, not inside Help: the window that opens Help decides which page it lands on.
    @State private var help = HelpRoute()
    /// What the menu bar asks the window to do. Same reason it lives here: commands are built
    /// in the scene, and the window is what can act.
    @State private var menu = MacMenuRoute()

    var body: some Scene {
        Window("Furlough", id: "main") {
            MacRootView()
                .environment(model)
                .environment(help)
                .environment(menu)
                .frame(minWidth: 880, minHeight: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)
        // Not `.suppressed` like Help: a suppressed scene is never built, so reopening after a
        // menu-bar-only launch would have no window to raise. Built always; `MacAppDelegate`
        // hides it instead.
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Replaces the stock Help item, which opened a help book Furlough doesn't ship.
            CommandGroup(replacing: .help) { HelpMenuItem(route: help) }
            // An app whose Quit is refused while anything is blocked, and whose window is
            // hidden after onboarding, is exactly the one that should be reachable from up
            // here. Every item goes through the same path the toolbar uses — see `MacMenuRoute`.
            CommandGroup(after: .sidebar) { HalfMenuItems(route: menu) }
            CommandMenu("Rules") { RulesMenuItems(route: menu) }
            CommandMenu("Anchor") { AnchorMenuItems(route: menu, model: model) }
        }

        Window("Furlough Help", id: HelpRoute.windowID) {
            HelpWindow()
                .environment(model)
                .environment(help)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 720)
        // Never opens on its own: a Help window left open at a force quit shouldn't reappear
        // when the watchdog relaunches Furlough.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// Starts enforcement; refuses to quit while something is blocked (Force Quit is the
/// documented escape).
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Built in `applicationDidFinishLaunching` rather than here: the delegate is not
    /// `@MainActor`, so a property initialiser cannot reach `MacModel.shared`.
    private var menuBar: MenuBarController?
    private var restoreWatcher: NSObjectProtocol?
    private var closeWatcher: NSObjectProtocol?

    /// Nothing else passes `--background`; it's how a watchdog reopen is told from a user launch.
    static var isWatchdogLaunch: Bool { CommandLine.arguments.contains(Watchdog.backgroundFlag) }

    @MainActor
    static var opensWindowAtLaunch: Bool { !isWatchdogLaunch && !MacModel.shared.isOnboarded }

    /// Matched by SwiftUI's scene id, falling back to the one titled window that's neither the
    /// shield nor Help.
    @MainActor
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }
            ?? NSApp.windows.first { isAppWindow($0) && !isHelpWindow($0) }
    }

    /// A window of Furlough's own: not the shield, which is a panel, and not the status item.
    @MainActor
    static func isAppWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    @MainActor
    static func isHelpWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.contains(HelpRoute.windowID) == true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set before the window can appear, so onboarded Macs don't blink a window on the way
        // to the menu bar.
        if !Self.opensWindowAtLaunch { NSApp.setActivationPolicy(.accessory) }
        UNUserNotificationCenter.current().delegate = self
        MacModel.shared.start()
        let menuBar = MenuBarController(model: MacModel.shared)
        menuBar.install()
        self.menuBar = menuBar
        if Self.opensWindowAtLaunch { Self.showWindow() } else { putTheWindowAway() }
        watchForTheWindowClosing()
    }

    /// Regular, not accessory, while the window is up: an accessory app has no Edit menu, so
    /// ⌘V would silently stop working in text fields.
    @MainActor
    static func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Nothing to raise (suppressed at launch); opening the bundle triggers the same
            // reopen path as a double-click, which builds it — no loop back into here.
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    /// Works even with no Dock icon or menu bar item, since the window always exists, just hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Self.mainWindow?.makeKeyAndOrderFront(nil)
        return true
    }

    /// Without this, closing the last window would terminate the app and enforcement with it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func watchForTheWindowClosing() {
        closeWatcher = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            // Deferred: the closing window is still in `NSApp.windows` during `willClose`, so
            // check what's left rather than which one closed. The shield (an NSPanel) doesn't count.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let stillShowing = NSApp.windows.contains { Self.isAppWindow($0) && $0.isVisible }
                    if !stillShowing { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }

    /// Called three times: SwiftUI's own build, AppKit's window restoration (from a force
    /// quit), and one that lands a turn later — none guaranteed to have happened yet.
    @MainActor
    private func putTheWindowAway() {
        Self.orderOutEveryWindow()
        DispatchQueue.main.async { MainActor.assumeIsolated { Self.orderOutEveryWindow() } }
        restoreWatcher = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification, object: nil, queue: .main
        ) { _ in
            // No capture needed: fires once per launch, and the delegate isn't Sendable.
            MainActor.assumeIsolated { Self.orderOutEveryWindow() }
        }
    }

    /// All windows, not just main: macOS restores whatever was open at the last force quit,
    /// Help included.
    @MainActor
    private static func orderOutEveryWindow() {
        for window in NSApp.windows where isAppWindow(window) { window.orderOut(nil) }
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
