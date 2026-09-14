import SwiftUI

/// One day as a 24-hour bar, above the list of pickers that edits it. Hoisted out of the two
/// week views with the grid, for the same reason: it was duplicated verbatim.
struct DayBar: View {
    let spans: [TimeWindow]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    ForEach([6, 12, 18], id: \.self) { hour in
                        Rectangle()
                            .fill(Ember.cardBorder)
                            .frame(width: 1)
                            .offset(x: CGFloat(hour) / 24 * width)
                    }
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Ember.amber.opacity(0.92))
                            .frame(width: max(2, CGFloat(span.durationMinutes) / CGFloat(Furlough.minutesPerDay) * width))
                            .offset(x: CGFloat(span.startMinute) / CGFloat(Furlough.minutesPerDay) * width)
                    }
                }
            }
            .frame(height: 26)
            GeometryReader { geo in
                ForEach([6, 12, 18], id: \.self) { hour in
                    Text(TimeFormat.shortMinute(hour * 60))
                        .font(EmberFont.numerals(9))
                        .foregroundStyle(Ember.faint)
                        .position(x: CGFloat(hour) / 24 * geo.size.width, y: 6)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement()
        .accessibilityLabel("Hours")
        .accessibilityValue(spans.isEmpty ? "No windows" : spans.map { TimeFormat.window($0) }.joined(separator: ", "))
    }
}
