import Foundation
import UserNotifications

/// The **Drop anchor** button on a notification. Furlough's notifications arrive at the moment
/// of temptation — "Window opened", "Window closing", "5 minutes left", "Time's up" — and until
/// this every one of them was a dead end. Dropping the anchor needs no tag and only ever
/// tightens, which is why it is already safe from Control Center, the widget, a Shortcut and a
/// Focus; this is the same act from the one surface that finds you without being opened.
///
/// Nothing here can lift. The handlers in the two apps call one drop each and post a refusal
/// back; there is no release branch on any of them, not even one that returns early, because a
/// notification that could release would be an unblock button on the Lock Screen.
enum AnchorOffer {
    /// Which notifications carry the button: the four about a moment, and not the ones about a
    /// rule (a queued loosening, the digest) or about the anchor itself, which has just dropped
    /// or just lifted by an `until` the person chose. Built on the pass-off's proposal,
    /// 2026-09-14; cheap to change, and this switch is the whole of it.
    static func carries(_ kind: NotificationKind) -> Bool {
        switch kind {
        case .windowOpened, .windowClosing, .budgetWarning, .budgetSpent: true
        case .anchorDropped, .anchorLifted, .looseningWarning, .looseningLanded, .weeklyDigest: false
        }
    }

    /// The category a notification of `kind` is posted under, or nil for no button.
    static func category(for kind: NotificationKind) -> String? {
        carries(kind) ? Furlough.anchorNotificationCategory : nil
    }

    /// Registered at every app launch on both platforms. The categories are per app and apply
    /// to what its extensions post, so a notification the monitor posts before the app has ever
    /// run this build shows no button — one buttonless notification after an update, at most.
    static func register() {
        // No `.foreground`: the app is launched in the background to handle the tap, and the
        // person stays where they were. No authentication either — the act only tightens.
        let drop = UNNotificationAction(identifier: Furlough.anchorNotificationAction, title: "Drop anchor", options: [])
        let category = UNNotificationCategory(
            identifier: Furlough.anchorNotificationCategory, actions: [drop], intentIdentifiers: [], options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

extension Notifier {
    /// A reply to the person's own tap on the button, so it ignores every mute: a refusal that
    /// went silent would be a tap that looked like it worked.
    static func reply(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { SharedStore.log("notification failed: \(error.localizedDescription)") }
        }
    }
}
