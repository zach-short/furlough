import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button: drops the anchor only (release stays behind the NFC tag in-app), so
/// it's a button, not a toggle. Draws live anchor state from the same store the widget reads —
/// a static icon looked broken with no app coming to front to confirm the drop (seen 2026-09-09).
struct DropAnchorControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Furlough.anchorControlKind, provider: Provider()) { anchored in
            ControlWidgetButton(action: DropAnchorIntent()) {
                // Furlough's own anchor asset, not an SF Symbol — fine here since this runs in
                // the widget extension, which carries Ember.xcassets.
                Label(anchored ? "Anchored" : "Drop Anchor", image: "anchor")
            }
            // Same colours the hourglass uses for stopped/running, so this agrees at a glance.
            .tint(anchored ? Ember.ember : Ember.amber)
        }
        .displayName("Drop Anchor")
        .description("Locks everything the Anchor holds. Only the paired tag lifts it.")
    }

    /// Uses Furlough's clock, not the device's, so a phone moved forward doesn't draw a released anchor.
    struct Provider: ControlValueProvider {
        let previewValue = false

        func currentValue() async throws -> Bool {
            let state = SharedStore.load()
            return state.config.anchor.isHolding(at: state.now)
        }
    }
}
