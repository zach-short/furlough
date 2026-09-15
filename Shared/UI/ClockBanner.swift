import SwiftUI

/// Shown when the device clock disagrees with Furlough's own, or when the device has moved to
/// another time zone and the one it left is still being honoured; informational only, nothing
/// is broken or blocked on it.
struct ClockBanner: View {
    enum Reason: Equatable {
        /// The wall clock is off by this much; Furlough runs on its own projection.
        case drift(TimeInterval)
        /// The device is in another zone; `from` is honoured until `until`.
        case zone(from: String, until: Date)
    }

    let reason: Reason
    var now: Date = .now

    init(drift: TimeInterval) { reason = .drift(drift) }

    init(zone from: String, until: Date, now: Date = .now) {
        reason = .zone(from: from, until: until)
        self.now = now
    }

    private var text: String {
        switch reason {
        case .drift(let drift):
            let amount = Clock.describe(drift)
            let direction = drift > 0 ? "ahead" : "behind"
            return "Your clock is \(amount) \(direction). Furlough is keeping its own time until it is back."
        case .zone(let from, let until):
            return Clock.describeMove(from: from, to: TimeZone.current.identifier, until: until, now: now)
        }
    }

    private var symbol: String {
        switch reason {
        case .drift: "clock.badge.exclamationmark"
        case .zone: "globe.badge.chevron.backward"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
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
