import CoreGraphics
import SwiftUI

/// One frame of the hourglass drawn straight into a Core Graphics context, for the one surface
/// that cannot host a SwiftUI view: the shield extension's icon. iOS asks a
/// `ShieldConfigurationDataSource` for its configuration off the main thread, and SwiftUI's
/// `ImageRenderer` is main-actor work, so a render that waited for the main thread never ran
/// and the shield showed its symbol fallback every time (seen on the phone 2026-09-08). Core
/// Graphics has no such tie: the same paths and the same colours as `HourglassView`, on
/// whatever thread the call arrives on.
///
/// This is `HourglassView` with `motion: false`, the way the still was always taken: a solid
/// stream, no grains, no pulse. Keep the two in step when the drawing changes.
enum HourglassStill {
    /// The drawing's own space; the shapes lay themselves out in it unscaled.
    private static let space = CGRect(x: 0, y: 0, width: 120, height: 160)

    /// The still at `size` points on a screen of `scale`, or nil if a bitmap could not be made.
    static func cgImage(_ state: HourglassState, size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        // Core Graphics puts the origin bottom left; the drawing, like every UIKit and SwiftUI
        // surface it matches, has it top left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        draw(state, in: context, rect: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    /// Draws `state` into `rect` on a context whose origin is top left, the glass centred and
    /// fitted the way `HourglassView` fits it.
    static func draw(_ state: HourglassState, in context: CGContext, rect: CGRect) {
        let scale = min(rect.width / 120, rect.height / 160)
        guard scale > 0 else { return }
        let mini = 160 * scale < 40
        let origin = CGPoint(
            x: rect.minX + (rect.width - 120 * scale) / 2,
            y: rect.minY + (rect.height - 160 * scale) / 2
        )
        context.saveGState()
        defer { context.restoreGState() }
        // From here on everything is in the drawing's 120 × 160 space. SwiftUI's gradients span
        // the view rather than the glass, so `view` is that frame carried into the same space.
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        let view = CGRect(
            x: (rect.minX - origin.x) / scale, y: (rect.minY - origin.y) / scale,
            width: rect.width / scale, height: rect.height / scale
        )

        let peak = HourglassGeometry.peak(level: state.moundLevel)
        let landing = peak - 0.5
        let capHeight: Double = mini ? 10 : 8
        let streaming = state.isRunning || state.isFrozen

        // The glow behind the base, at the middle of its breath: a still has no pulse.
        if let glow = state.glow {
            context.saveGState()
            context.translateBy(x: 60, y: 118)
            context.scaleBy(x: 1, y: 34 / 46)
            context.setAlpha(0.72 + 0.28 * 0.5)
            context.addEllipse(in: CGRect(x: -46, y: -46, width: 92, height: 92))
            context.clip()
            radial(
                context,
                stops: [.init(color: glow.opacity(0.95 * state.glowStrength), location: 0), .init(color: glow.opacity(0), location: 1)],
                center: .zero, radius: 46
            )
            context.restoreGState()
        }

        let body = HourglassPartShape(part: .body).path(in: space).cgPath
        fill(context, body, state.glass.fill)

        if state.sandLevel > 0.002 {
            let edge = HourglassGeometry.topEdge(level: state.sandLevel)
            let sand = TopSandShape(level: state.sandLevel).path(in: space).cgPath
            linear(context, in: sand, stops: state.sand.stops, from: CGPoint(x: view.midX, y: view.minY), to: CGPoint(x: view.midX, y: view.maxY))
            // The funnel: a shadow in the bowl where the sand slides down to the neck.
            radial(
                context, in: sand,
                stops: [.init(color: .black.opacity(mini ? 0.2 : 0.34), location: 0), .init(color: .clear, location: 1)],
                center: HourglassGeometry.funnelBottom(edge: edge),
                radius: max(1, HourglassGeometry.halfWidth(at: edge) * 1.15)
            )
        }

        if streaming {
            let stream = StreamShape(landing: landing, topWidth: mini ? 6 : 3, bottomWidth: mini ? 5 : 2.2).path(in: space).cgPath
            fill(context, stream, Ember.sandLight.opacity(0.95))
        }

        if state.moundLevel > 0.002 {
            let mound = MoundShape(level: state.moundLevel).path(in: space).cgPath
            linear(context, in: mound, stops: state.mound.stops, from: CGPoint(x: view.midX, y: view.minY), to: CGPoint(x: view.midX, y: view.maxY))
            // Fresh sand at the tip, where the stream lands, is lighter than the settled slopes.
            radial(
                context, in: mound,
                stops: [.init(color: Ember.sandLight.opacity(mini ? 0.18 : 0.28), location: 0), .init(color: .clear, location: 1)],
                center: CGPoint(x: HourglassGeometry.centerX, y: peak + 1.5), radius: 11
            )
        }

        // The edge, a gradient along the stroke's own outline.
        let edge = body.copy(strokingWithWidth: mini ? 7 : 2.5, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        linear(context, in: edge, stops: state.glass.strokeStops, from: CGPoint(x: view.minX, y: view.minY), to: CGPoint(x: view.maxX, y: view.maxY))

        let cap = state.glass.capColor.opacity(state.glass.capOpacity)
        fill(context, HourglassPartShape(part: .cap(top: true, height: capHeight)).path(in: space).cgPath, cap)
        fill(context, HourglassPartShape(part: .cap(top: false, height: capHeight)).path(in: space).cgPath, cap)

        if !mini, state.glass != .ink {
            stroke(context, HourglassPartShape(part: .highlight).path(in: space).cgPath, Color.white.opacity(0.55), width: 2, cap: .round)
            if state.showsAnchor {
                let anchor = HourglassPartShape(part: .anchor).path(in: space).cgPath
                fill(context, anchor, Ember.ember)
                stroke(context, anchor, Ember.cream.opacity(0.7), width: 1, join: .round)
            }
        }
    }

    // MARK: - Strokes and fills in SwiftUI's colours

    private static func cgColor(_ color: Color) -> CGColor {
        color.resolve(in: EnvironmentValues()).cgColor
    }

    private static func gradient(_ stops: [Gradient.Stop]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map { cgColor($0.color) } as CFArray,
            locations: stops.map(\.location)
        )
    }

    private static func fill(_ context: CGContext, _ path: CGPath, _ color: Color) {
        context.saveGState()
        context.addPath(path)
        context.setFillColor(cgColor(color))
        context.fillPath()
        context.restoreGState()
    }

    private static func stroke(
        _ context: CGContext, _ path: CGPath, _ color: Color, width: CGFloat,
        cap: CGLineCap = .butt, join: CGLineJoin = .miter
    ) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(cgColor(color))
        context.setLineWidth(width)
        context.setLineCap(cap)
        context.setLineJoin(join)
        context.strokePath()
        context.restoreGState()
    }

    /// A linear gradient clipped to `path`, running past both ends the way SwiftUI's does.
    private static func linear(_ context: CGContext, in path: CGPath, stops: [Gradient.Stop], from: CGPoint, to: CGPoint) {
        guard let gradient = gradient(stops) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// A radial gradient from `center` out to `radius`, clipped to `path` when given.
    private static func radial(_ context: CGContext, in path: CGPath? = nil, stops: [Gradient.Stop], center: CGPoint, radius: CGFloat) {
        guard let gradient = gradient(stops) else { return }
        context.saveGState()
        if let path {
            context.addPath(path)
            context.clip()
        }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
        context.restoreGState()
    }
}

#if canImport(UIKit)
import UIKit

extension HourglassStill {
    /// The still as the `UIImage` a shield's icon slot takes.
    static func uiImage(_ state: HourglassState, size: CGSize, scale: CGFloat) -> UIImage? {
        cgImage(state, size: size, scale: scale).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }
}
#endif
