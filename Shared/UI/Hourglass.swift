import SwiftUI

/// The glowing glass hourglass from the mockups, drawn as vectors in a 120 × 160 space.
/// `isOpen` shows sand still running; when it turns false the sand settles into the bottom.
/// The ember glow beneath pulses slowly unless Reduce Motion is on.
struct HourglassView: View {
    var isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 120, geo.size.height / 160)
            let origin = CGPoint(x: (geo.size.width - 120 * scale) / 2, y: (geo.size.height - 160 * scale) / 2)
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(RadialGradient(
                        colors: [Ember.amber.opacity(0.95), Ember.ember.opacity(0)],
                        center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 46 * scale
                    ))
                    .frame(width: 92 * scale, height: 68 * scale)
                    .blur(radius: 7 * scale)
                    .scaleEffect(pulsing ? 1.06 : 0.94)
                    .opacity(pulsing ? 1 : 0.75)
                    .offset(x: origin.x + 14 * scale, y: origin.y + 84 * scale)

                HourglassPart.body.shape
                    .fill(Color.white.opacity(0.07))
                HourglassPart.body.shape
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.6), location: 0),
                                .init(color: .white.opacity(0.14), location: 0.5),
                                .init(color: .white.opacity(0.45), location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5 * scale, lineJoin: .round)
                    )

                HourglassPart.topSand.shape
                    .fill(Ember.sand)
                    .opacity(isOpen ? 0.85 : 0)
                    .scaleEffect(isOpen ? 1 : 0.2, anchor: UnitPoint(x: 0.5, y: 66 / 160))
                HourglassPart.stream.shape
                    .fill(Ember.sandLight.opacity(0.95))
                    .opacity(isOpen ? 1 : 0)
                HourglassPart.bottomSand.shape
                    .fill(Ember.sand)
                    .scaleEffect(x: 1, y: isOpen ? 1 : 1.18, anchor: UnitPoint(x: 0.5, y: 144 / 160))

                HourglassPart.topCap.shape.fill(Ember.cream.opacity(0.92))
                HourglassPart.bottomCap.shape.fill(Ember.cream.opacity(0.92))
                HourglassPart.highlight.shape
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: isOpen)
        }
        .aspectRatio(120 / 160, contentMode: .fit)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// One piece of the hourglass drawing. Coordinates are the mockup's 120 × 160 SVG space.
enum HourglassPart {
    case body, topSand, stream, bottomSand, topCap, bottomCap, highlight

    var shape: HourglassShape { HourglassShape(part: self) }

    func path() -> Path {
        var p = Path()
        switch self {
        case .body:
            p.move(to: CGPoint(x: 22, y: 12))
            p.addLine(to: CGPoint(x: 98, y: 12))
            p.addLine(to: CGPoint(x: 98, y: 32))
            p.addCurve(to: CGPoint(x: 68, y: 76), control1: CGPoint(x: 98, y: 52), control2: CGPoint(x: 80, y: 64))
            p.addLine(to: CGPoint(x: 68, y: 84))
            p.addCurve(to: CGPoint(x: 98, y: 128), control1: CGPoint(x: 80, y: 96), control2: CGPoint(x: 98, y: 108))
            p.addLine(to: CGPoint(x: 98, y: 148))
            p.addLine(to: CGPoint(x: 22, y: 148))
            p.addLine(to: CGPoint(x: 22, y: 128))
            p.addCurve(to: CGPoint(x: 52, y: 84), control1: CGPoint(x: 22, y: 108), control2: CGPoint(x: 40, y: 96))
            p.addLine(to: CGPoint(x: 52, y: 76))
            p.addCurve(to: CGPoint(x: 22, y: 32), control1: CGPoint(x: 40, y: 64), control2: CGPoint(x: 22, y: 52))
            p.closeSubpath()
        case .topSand:
            p.move(to: CGPoint(x: 40, y: 36))
            p.addLine(to: CGPoint(x: 80, y: 36))
            p.addCurve(to: CGPoint(x: 60, y: 66), control1: CGPoint(x: 80, y: 48), control2: CGPoint(x: 68, y: 58))
            p.addCurve(to: CGPoint(x: 40, y: 36), control1: CGPoint(x: 52, y: 58), control2: CGPoint(x: 40, y: 48))
            p.closeSubpath()
        case .stream:
            p.addRoundedRect(in: CGRect(x: 58.5, y: 70, width: 3, height: 36), cornerSize: CGSize(width: 1.5, height: 1.5))
        case .bottomSand:
            p.move(to: CGPoint(x: 30, y: 136))
            p.addCurve(to: CGPoint(x: 60, y: 106), control1: CGPoint(x: 30, y: 120), control2: CGPoint(x: 44, y: 110))
            p.addCurve(to: CGPoint(x: 90, y: 136), control1: CGPoint(x: 76, y: 110), control2: CGPoint(x: 90, y: 120))
            p.addLine(to: CGPoint(x: 90, y: 144))
            p.addLine(to: CGPoint(x: 30, y: 144))
            p.closeSubpath()
        case .topCap:
            p.addRoundedRect(in: CGRect(x: 18, y: 8, width: 84, height: 8), cornerSize: CGSize(width: 4, height: 4))
        case .bottomCap:
            p.addRoundedRect(in: CGRect(x: 18, y: 144, width: 84, height: 8), cornerSize: CGSize(width: 4, height: 4))
        case .highlight:
            p.move(to: CGPoint(x: 31, y: 20))
            p.addCurve(to: CGPoint(x: 45, y: 50), control1: CGPoint(x: 31, y: 34), control2: CGPoint(x: 37, y: 42))
        }
        return p
    }
}

/// Scales a part from the 120 × 160 space to fit the given rect, centred.
struct HourglassShape: Shape {
    var part: HourglassPart

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 120, rect.height / 160)
        let dx = rect.minX + (rect.width - 120 * scale) / 2
        let dy = rect.minY + (rect.height - 160 * scale) / 2
        return part.path().applying(CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale))
    }
}
