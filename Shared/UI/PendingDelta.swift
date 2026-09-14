import SwiftUI

/// Old→new pair for a pending card, shared so phone/Mac can't drift. Faint for "now", Cream
/// for "becomes" — no extra amber needed since the date below is already Pending-coloured.
struct PendingDeltaView: View {
    let delta: PendingText.Delta

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 6, verticalSpacing: 2) {
            GridRow {
                Text("Now")
                    .emberBody(11.5, .semibold)
                    .foregroundStyle(Ember.faint)
                    .gridColumnAlignment(.leading)
                Text(delta.now)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
            }
            GridRow {
                Text("Becomes")
                    .emberBody(11.5, .semibold)
                    .foregroundStyle(Ember.faint)
                Text(delta.becomes)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.cream)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
