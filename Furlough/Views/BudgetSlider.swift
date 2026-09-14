import SwiftUI

/// Track is piecewise-linear between anchors, so the common sub-hour range gets half the width.
struct BudgetSlider: View {
    @Binding var value: Int
    /// Off in per-day rows, where seven repeats of the same ticks would be noise.
    var showsTicks = true
    @State private var dragging = false

    /// Only meaningful where windows already narrow the day; otherwise it's a rule that enforces nothing.
    var allowsNoBudget = false

    static let anchors = [5, 30, 60, 120, 240]
    /// Matches `Furlough.minutesPerDay`, the exact figure `Rule.unrestricted` carries — not an arbitrary max.
    static let noBudget = Furlough.minutesPerDay
    static let step = 5
    private let knob: CGFloat = 24

    /// Positional code should read this, not `anchors`.
    static func stops(allowsNoBudget: Bool) -> [Int] {
        allowsNoBudget ? anchors + [noBudget] : anchors
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let usable = max(1, geo.size.width - knob)
                let x = CGFloat(Self.fraction(for: value, allowsNoBudget: allowsNoBudget)) * usable
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)
                    Capsule()
                        .fill(Ember.sliderFill)
                        .frame(width: x + knob / 2, height: 6)
                        .shadow(color: Ember.amber.opacity(0.45), radius: 6)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: knob, height: knob)
                        .emberGlass(interactive: true, in: .circle)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .scaleEffect(dragging ? 1.12 : 1)
                        .offset(x: x)
                }
                .frame(height: knob)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            dragging = true
                            let fraction = Double(min(max(0, gesture.location.x - knob / 2), usable) / usable)
                            value = Self.value(for: fraction, allowsNoBudget: allowsNoBudget)
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(height: knob)
            if showsTicks { ticks }
        }
        .animation(.easeOut(duration: 0.15), value: dragging)
        .sensoryFeedback(.selection, trigger: value) { _, _ in dragging }
        .accessibilityElement()
        .accessibilityLabel("Daily budget")
        .accessibilityValue(value >= Self.noBudget ? "No budget" : "\(value) minutes")
        .accessibilityAdjustableAction { direction in
            let ceiling = Self.anchors.last ?? 240
            switch direction {
            case .increment:
                if value >= ceiling {
                    if allowsNoBudget { value = Self.noBudget }
                } else {
                    value = min(ceiling, value + Self.step)
                }
            case .decrement:
                value = value > ceiling ? ceiling : max(Self.anchors.first ?? 5, value - Self.step)
            @unknown default: break
            }
        }
    }

    private var ticks: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - knob)
            ForEach(Self.stops(allowsNoBudget: allowsNoBudget), id: \.self) { tick in
                // Named rather than counted: "1440" would read as a chosen figure, not a state.
                Text(tick >= Self.noBudget ? "None" : "\(tick)")
                    .font(EmberFont.numerals(9.5))
                    .foregroundStyle(Ember.faint)
                    .position(
                        x: knob / 2 + CGFloat(Self.fraction(for: tick, allowsNoBudget: allowsNoBudget)) * usable,
                        y: 6
                    )
            }
        }
        .frame(height: 12)
    }

    /// 0…1 along the track for a value, linear within each segment between stops.
    static func fraction(for value: Int, allowsNoBudget: Bool = false) -> Double {
        let stops = stops(allowsNoBudget: allowsNoBudget)
        guard let first = stops.first, let last = stops.last, stops.count > 1 else { return 0 }
        if value >= last { return 1 }
        let clamped = Double(min(max(value, first), last))
        for index in 0..<(stops.count - 1) {
            let lower = Double(stops[index])
            let upper = Double(stops[index + 1])
            if clamped <= upper {
                return (Double(index) + (clamped - lower) / (upper - lower)) / Double(stops.count - 1)
            }
        }
        return 1
    }

    /// The value at a track position, snapped to the step.
    static func value(for fraction: Double, allowsNoBudget: Bool = false) -> Int {
        let stops = stops(allowsNoBudget: allowsNoBudget)
        let segments = Double(stops.count - 1)
        let scaled = min(max(fraction, 0), 1) * segments
        let index = min(Int(scaled), stops.count - 2)
        // One detent, not a range: nothing between 240 and no-limit is worth choosing.
        if allowsNoBudget, index == stops.count - 2 {
            return (scaled - Double(index)) >= 0.5 ? noBudget : (anchors.last ?? 240)
        }
        let lower = Double(stops[index])
        let upper = Double(stops[index + 1])
        let raw = lower + (scaled - Double(index)) * (upper - lower)
        return Int((raw / Double(step)).rounded()) * step
    }
}

struct DayBudgetRow: View {
    let weekday: Int
    @Binding var minutes: Int
    var allowsNoBudget = false

    private var name: String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer()
                if minutes >= BudgetSlider.noBudget {
                    Text("No budget")
                        .emberBody(13)
                        .foregroundStyle(Ember.cream)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(minutes)")
                            .emberNumerals(15)
                            .contentTransition(.numericText())
                        Text("MIN")
                            .font(EmberFont.label(9))
                            .tracking(0.06 * 9)
                            .foregroundStyle(Ember.muted)
                    }
                }
            }
            BudgetSlider(value: $minutes, showsTicks: false, allowsNoBudget: allowsNoBudget)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
