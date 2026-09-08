import SwiftUI

/// The Anchor's own mark, drawn here because SF Symbols has none: 8,302 names in the system
/// list and not one anchor, so the thing the feature is named for cannot be borrowed. What
/// stood in for it was `cube.fill`, which said nothing.
///
/// The path is the anchor's skeleton — ring, shank, stock, arms — stroked into a closed
/// outline and handed over as one filled shape, so a caller can `fill` it like a glyph and,
/// where the drawing wants an edge, `stroke` the same outline a second time.
enum AnchorMark {
    /// The space the coordinates below are written in. The mark does not fill it — `fit`
    /// measures the ink rather than trusting the box.
    static let size = CGSize(width: 80, height: 100)

    /// The bar the skeleton is drawn with, in that space: about a semibold glyph's weight.
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

    /// The whole mark as one closed outline, ready to fill. Built once: a union is not cheap,
    /// and the mark never changes.
    static let outline: Path = {
        let bar = skeleton.strokedPath(StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
        return bar.union(fluke(mirrored: false)).union(fluke(mirrored: true))
    }()

    /// What the ink actually covers, which is narrower and shorter than `size`.
    static let ink = outline.cgPath.boundingBoxOfPath

    /// The mark scaled to fill `rect`, centred, keeping its proportions.
    static func fit(in rect: CGRect) -> Path {
        let scale = min(rect.width / ink.width, rect.height / ink.height)
        let x = rect.midX - ink.midX * scale
        let y = rect.midY - ink.midY * scale
        return outline.applying(CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }
}

/// The anchor, filled like a glyph.
struct AnchorShape: Shape {
    func path(in rect: CGRect) -> Path { AnchorMark.fit(in: rect) }
}
