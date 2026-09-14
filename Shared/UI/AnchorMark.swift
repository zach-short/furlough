import SwiftUI

/// Hand-drawn: SF Symbols has no anchor glyph (8,302 names, none of them this — `cube.fill`
/// stood in before). The skeleton is stroked into one closed outline so callers can both
/// `fill` and `stroke` it like a glyph.
enum AnchorMark {
    /// Nominal coordinate space only — `fit` measures actual ink (`ink`), not this box.
    static let size = CGSize(width: 80, height: 100)

    /// Stroke width, ~a semibold glyph's weight.
    static let weight: Double = 7

    /// Ring, shank, stock, arms. A centre line, not yet a shape.
    private static var skeleton: Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 29.5, y: 4.5, width: 21, height: 21))
        p.move(to: CGPoint(x: 40, y: 26))
        p.addLine(to: CGPoint(x: 40, y: 82))
        p.move(to: CGPoint(x: 17, y: 38))
        p.addLine(to: CGPoint(x: 63, y: 38))
        p.move(to: CGPoint(x: 12, y: 58))
        p.addCurve(to: CGPoint(x: 40, y: 84), control1: CGPoint(x: 12, y: 74), control2: CGPoint(x: 24, y: 84))
        p.addCurve(to: CGPoint(x: 68, y: 58), control1: CGPoint(x: 56, y: 84), control2: CGPoint(x: 68, y: 74))
        return p
    }

    /// The blade at the end of an arm, pointing up and out. Mirrored for the other side.
    private static func fluke(mirrored: Bool) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 7, y: 41))
        p.addLine(to: CGPoint(x: 2, y: 59))
        p.addLine(to: CGPoint(x: 18, y: 68))
        p.closeSubpath()
        guard mirrored else { return p }
        return p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -size.width, y: 0))
    }

    /// Built once — Path union is expensive and this never changes.
    static let outline: Path = {
        let bar = skeleton.strokedPath(StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
        return bar.union(fluke(mirrored: false)).union(fluke(mirrored: true))
    }()

    /// What the ink actually covers, which is narrower and shorter than `size`.
    static let ink = outline.cgPath.boundingBoxOfPath

    static func fit(in rect: CGRect) -> Path {
        let scale = min(rect.width / ink.width, rect.height / ink.height)
        let x = rect.midX - ink.midX * scale
        let y = rect.midY - ink.midY * scale
        return outline.applying(CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }
}

struct AnchorShape: Shape {
    func path(in rect: CGRect) -> Path { AnchorMark.fit(in: rect) }
}
