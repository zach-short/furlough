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

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Starts enforcement, keeps notifications visible while Furlough is in front, and refuses
/// to quit while something is blocked. Logging out, restarting and shutting down are always
/// allowed; Force Quit always works too, and is the Mac's documented escape.
final class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        MacModel.shared.start()
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
