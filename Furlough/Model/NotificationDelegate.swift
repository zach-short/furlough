import UIKit
import UserNotifications
import WidgetKit

/// Registers the Drop anchor button's category at every launch and handles the tap. An app
/// delegate rather than a view's task because the notification center's delegate has to be in
/// place before the app finishes launching, or a tap on a notification while the app is not
/// running launches it in the background to find nobody listening.
///
/// The one thing this can do is drop. There is no lift branch, not even one that returns early
/// — see `AnchorOffer`.
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AnchorOffer.register()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Furlough.anchorNotificationAction else { return }
        switch AnchorDrop.drop(reason: "notification") {
        case .anchored:
            // The same follow-ups the intent does from this process: the Lock Screen, the
            // widget and the control all show "Drop Anchor" until told otherwise.
            LiveActivityManager.sync(state: SharedStore.load())
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadControls(ofKind: Furlough.anchorControlKind)
        case .refused(let why):
            // A notification action cannot raise an alert, so the refusal comes back the same way.
            Notifier.reply(id: "anchor-refused", title: "Anchor not dropped", body: why.message)
        }
        // If the app is alive, its screens follow; if it was launched only for this, `activate`
        // reloads on the next foreground the way it does after any drop from elsewhere.
        await MainActor.run { AppModel.shared.changedElsewhere() }
    }
}
