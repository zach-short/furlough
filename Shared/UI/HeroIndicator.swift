import SwiftUI

/// One hourglass per hero page; tap to jump. Shared between Mac and phone home screens.
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

/// Custom layout: a plain `HStack` reports its full width regardless of what's offered, so a
/// `ScrollView` grows to match and clips rows below. This shrinks slots (gaps first, then
/// glasses) to fit instead.
struct IndicatorStrip: Layout {
    /// 11 × 15 glass plus 4pt tap margin.
    static let slot = CGSize(width: 19, height: 23)
    static let gap: CGFloat = 9
    /// Scales the drawn glass down to 11 × 15 so the tap margin shrinks with the slot rather
    /// than eating the glass.
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
