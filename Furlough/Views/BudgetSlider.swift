import SwiftUI

/// The daily budget slider: 5–240 minutes in steps of 5, Ember-to-Amber fill, glass knob.
/// The track is piecewise linear between the tick anchors so the common range under an hour
/// gets half of the width, which is also why the ticks sit evenly spaced.
struct BudgetSlider: View {
    @Binding var value: Int
    /// The anchor figures under the track. Off in the per-day rows, where seven copies of the
    /// same five numbers would be noise and each row already says its own figure.
    var showsTicks = true
    @State private var dragging = false

    static let anchors = [5, 30, 60, 120, 240]
    static let step = 5
    private let knob: CGFloat = 24

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let usable = max(1, geo.size.width - knob)
                let x = CGFloat(Self.fraction(for: value)) * usable
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
                        .glassEffect(.regular.interactive(), in: .circle)
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
                            value = Self.value(for: fraction)
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
        .accessibilityValue("\(value) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(Self.anchors.last ?? 240, value + Self.step)
            case .decrement: value = max(Self.anchors.first ?? 5, value - Self.step)
            @unknown default: break
            }
        }
    }

    private var ticks: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - knob)
            ForEach(Self.anchors, id: \.self) { tick in
                Text("\(tick)")
                    .font(EmberFont.numerals(9.5))
                    .foregroundStyle(Ember.faint)
                    .position(x: knob / 2 + CGFloat(Self.fraction(for: tick)) * usable, y: 6)
            }
        }
        .frame(height: 12)
    }

    /// 0…1 along the track for a value, linear within each anchor segment.
    static func fraction(for value: Int) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        let clamped = Double(min(max(value, first), last))
        for index in 0..<(anchors.count - 1) {
            let lower = Double(anchors[index])
            let upper = Double(anchors[index + 1])
            if clamped <= upper {
                return (Double(index) + (clamped - lower) / (upper - lower)) / Double(anchors.count - 1)
            }
        }
        return 1
    }

    /// The value at a track position, snapped to the step.
    static func value(for fraction: Double) -> Int {
        let segments = Double(anchors.count - 1)
        let scaled = min(max(fraction, 0), 1) * segments
        let index = min(Int(scaled), anchors.count - 2)
        let lower = Double(anchors[index])
        let upper = Double(anchors[index + 1])
        let raw = lower + (scaled - Double(index)) * (upper - lower)
        return Int((raw / Double(step)).rounded()) * step
    }
}

/// One weekday's budget: its name, its figure, and a slider. The per-day half of the rule
/// editor's budget card on both platforms.
struct DayBudgetRow: View {
    let weekday: Int
    @Binding var minutes: Int

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
            BudgetSlider(value: $minutes, showsTicks: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
