import SwiftUI

/// Shown when the device clock disagrees with Furlough's own; informational only, nothing is
/// broken or blocked on it.
struct ClockBanner: View {
    let drift: TimeInterval

    private var text: String {
        let amount = Clock.describe(drift)
        let direction = drift > 0 ? "ahead" : "behind"
        return "Your clock is \(amount) \(direction). Furlough is keeping its own time until it is back."
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
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
