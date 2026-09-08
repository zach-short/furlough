import SwiftUI

/// Shown on the Pending screen while the wall clock is ahead of where the machine says it
/// should be. The queue is frozen until it is back, so moving the date forward buys nothing.
struct ClockBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
            Text("The clock moved forward. Changes wait until it is back.")
                .emberBody(12, .semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Ember.amber)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ember.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ember.amber.opacity(0.3), lineWidth: 1)
        )
    }
}
