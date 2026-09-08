import SwiftUI

/// Tiny hourglasses in status colours, one per hero page. Tapping one turns to that page.
/// Shared, because the Mac's home shows the same strip under its hero as the phone does.
struct HeroIndicator: View {
    let pages: [Target]
    let glasses: [UUID: HourglassState]
    @Binding var featured: UUID?

    var body: some View {
        IndicatorStrip {
            ForEach(pages) { target in
                let current = target.id == featured
                HourglassView(state: glasses[target.id] ?? .unconfigured)
                    .scaleEffect(IndicatorStrip.glassScale * (current ? 1.35 : 1))
                    .opacity(current ? 1 : 0.5)
                    .contentShape(Rectangle())
                    .onTapGesture { featured = target.id }
            }
        }
        .animation(.snappy, value: featured)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }
}

/// Lays the indicator's glasses out in the width it is offered rather than the width they
/// would like: 11 pt glasses in 19 pt tap slots, 9 pt apart, centred. When the slots no
/// longer fit, the gaps close first, then the slots shrink together, so the strip is never
/// wider than the screen. (A plain `HStack` of fixed-size glasses reports its full width
/// whatever it is offered, and a vertical `ScrollView` then grows to match and clips both
/// edges of every row below.)
struct IndicatorStrip: Layout {
    /// A slot at full size: the 11 × 15 glass with a 4 pt tap margin around it.
    static let slot = CGSize(width: 19, height: 23)
    static let gap: CGFloat = 9
    /// Each glass is drawn at its slot's size and scaled down to 11 × 15 inside it, so the
    /// tap margin shrinks with the slot instead of eating the glass.
    static let glassScale: CGFloat = 15 / slot.height

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let fit = Self.fit(count: subviews.count, in: available)
        return CGSize(width: available ?? fit.width, height: fit.slot.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fit = Self.fit(count: subviews.count, in: bounds.width)
        var x = bounds.midX - fit.width / 2
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(fit.slot))
            x += fit.slot.width + fit.gap
        }
    }

    /// The slot size, gap and total width for `count` glasses in `width` (nil: unconstrained).
    static func fit(count: Int, in width: CGFloat?) -> (slot: CGSize, gap: CGFloat, width: CGFloat) {
        let gaps = CGFloat(max(count - 1, 0))
        let ideal = CGFloat(count) * slot.width + gaps * gap
        guard let width, width < ideal, count > 0 else { return (slot, gap, ideal) }
        let tight = CGFloat(count) * slot.width
        if tight <= width {
            return (slot, gaps > 0 ? (width - tight) / gaps : 0, width)
        }
        let scale = width / tight
        return (CGSize(width: slot.width * scale, height: slot.height * scale), 0, width)
    }
}
