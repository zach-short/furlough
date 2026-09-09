import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center button: one tap drops the anchor, from the lock screen if that is where
/// the phone is. There is deliberately no release beside it — release stays in the app behind
/// the tag — so the control is a button and not a toggle, and pressing it while anchored does
/// nothing but say so.
struct DropAnchorControl: ControlWidget {
    static let kind = "com.zachshort.furlough.dropAnchor"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: DropAnchorIntent()) {
                Label("Drop Anchor", image: "anchor")
            }
        }
        .displayName("Drop Anchor")
        .description("Locks everything the Anchor holds. Only the paired tag lifts it.")
    }
}
