import SwiftUI

/// The old → new pair on a pending card. One control, so the phone and the Mac cannot drift.
///
/// The line you have today is drawn back in Faint and the one replacing it in Cream, so the
/// card reads as a change at a glance without spending another amber on it — the effective
/// date under it is already the Pending colour.
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
