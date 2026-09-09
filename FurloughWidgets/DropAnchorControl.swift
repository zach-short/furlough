import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center button: one tap drops the anchor, from the lock screen if that is where
/// the phone is. There is deliberately no release beside it — release stays in the app behind
/// the tag — so the control is a button and not a toggle, and pressing it while anchored does
/// nothing but say so.
///
/// It draws the anchor's state even so. A button that reads the same before and after is the
/// worst thing this path could be, because the whole point is that no app comes to the front
/// to confirm: the drop happens, the shields bite, and the only thing you can look at is the
/// button you just pressed (seen on the phone, 2026-09-09). So the value provider reads the
/// same store the widget does, and every drop and every release asks for a redraw through
/// `Furlough.anchorControlKind`.
struct DropAnchorControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Furlough.anchorControlKind, provider: Provider()) { anchored in
            ControlWidgetButton(action: DropAnchorIntent()) {
                // The anchor is Furlough's own symbol, not an SF one — and here, unlike the
                // Spotlight shortcut, it can be: this renders inside the widget extension,
                // which carries Ember.xcassets.
                Label(anchored ? "Anchored" : "Drop Anchor", image: "anchor")
            }
            // Ember while it holds, Amber while it is only offered: the same two colours the
            // hourglass uses for stopped and running, so the control agrees with every other
            // surface at a glance.
            .tint(anchored ? Ember.ember : Ember.amber)
        }
        .displayName("Drop Anchor")
        .description("Locks everything the Anchor holds. Only the paired tag lifts it.")
    }

    /// Whether the anchor is holding right now, on Furlough's clock rather than the device's,
    /// so a phone moved forward does not draw a released anchor.
    struct Provider: ControlValueProvider {
        let previewValue = false

        func currentValue() async throws -> Bool {
            let state = SharedStore.load()
            return state.config.anchor.isHolding(at: state.now)
        }
    }
}
