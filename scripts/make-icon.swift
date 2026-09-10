// Draws the app icon from the app's own hourglass: the same paths, the same geometry and the
// same colours `HourglassView` puts on the phone, taken through `HourglassStill` so Core
// Graphics can draw them here on a Mac with no phone in the loop. The icon that came before
// was a picture of an hourglass generated elsewhere; this one is the hourglass.
//
//   swiftc -parse-as-library -O scripts/make-icon.swift \
//     Shared/UI/Hourglass.swift Shared/UI/HourglassGeometry.swift Shared/UI/HourglassStill.swift \
//     Shared/UI/Theme.swift Shared/UI/AnchorMark.swift \
//     $(ls Shared/Core/*.swift | grep -v ShieldReconciler) -o /tmp/make-icon
//   /tmp/make-icon out.png [mode] [wall] [size]
//
// `mode` is which glass to show (see `states`), `wall` the ground behind it, `size` the edge in
// pixels. The defaults are what ships.
//
// Under 40 px it draws a chip instead (`chip`): the same hourglass in whole pixels, for the
// Mac's 16 and 32, where the drawing has too few pixels to be one. Everything from 64 up is
// the drawing, unchanged.
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
enum MakeIcon {
    /// The glasses worth putting on a home screen, by name.
    static let states: [String: HourglassState] = [
        // Mid-pour: sand in both bulbs and a stream between them, which is what an hourglass
        // looks like when it is doing its job. The app's own running glass, minus the moss
        // glow that only means "not warned yet" inside the app.
        "running": HourglassState(
            sandLevel: 0.56, moundLevel: 0.44, isRunning: true, glow: Ember.amber, glowStrength: 0.8
        ),
        "open": .open(level: 0.56, warned: false),
        "warned": .open(level: 0.25, warned: true),
        "anchored": .anchored,
        "soon": .comingSoon(inMinutes: 30),
        "used": .usedUp,
    ]

    static func main() {
        let args = CommandLine.arguments
        let out = args.count > 1 ? args[1] : "icon-1024.png"
        let mode = args.count > 2 ? args[2] : "running"
        let wall = args.count > 3 ? args[3] : "pool"
        let size = args.count > 4 ? (Double(args[4]) ?? 1024) : 1024
        guard let state = states[mode] else {
            print("unknown mode \(mode); one of \(states.keys.sorted().joined(separator: ", "))")
            exit(1)
        }
        let small = size < chipBelow
        guard let image = small ? chip(state, size: size) : render(state, wall: wall, size: size),
              write(image, to: out)
        else {
            print("could not render")
            exit(1)
        }
        print("wrote \(out) (\(Int(size))px, \(mode)\(small ? " as a chip" : " on \(wall)"))")
    }

    /// Below this the icon is drawn as a chip rather than as the glass. 40 px is where the
    /// caps stop landing on whole pixels: it takes the Mac's 16 and 32, and leaves 64 and up
    /// on the drawing, which is already legible there.
    static let chipBelow = 40.0

    /// The icon: the ground, one warm glow, and the glass over both. No alpha — the App Store
    /// takes the 1024 flat.
    static func render(_ state: HourglassState, wall: String, size: Double) -> CGImage? {
        let side = Int(size.rounded())
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // Top left origin, like every surface the drawing was written for.
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)

        fill(context, rect, Ember.ground)
        switch wall {
        case "room":
            // `EmberWall` parked where Reduce Motion parks it: ember low left, amber top right.
            glow(context, Ember.ember.opacity(0.6), at: CGPoint(x: 0.28, y: 1.04), rx: 0.58, ry: 0.35, fade: 0.62, in: rect)
            glow(context, Ember.amber.opacity(0.14), at: CGPoint(x: 0.90, y: -0.04), rx: 0.60, ry: 0.40, fade: 0.60, in: rect)
        default:
            // A pool of ember under the glass, and a breath of amber above it: the room's own
            // light, but symmetric, which is what a square 1024 wants.
            glow(context, Ember.ember.opacity(0.52), at: CGPoint(x: 0.5, y: 0.92), rx: 0.62, ry: 0.40, fade: 0.72, in: rect)
            glow(context, Ember.amber.opacity(0.10), at: CGPoint(x: 0.5, y: 0.06), rx: 0.62, ry: 0.42, fade: 0.70, in: rect)
        }

        // The glass in the middle, its ink about 62 % of the edge: big enough to read at 40 pt,
        // short of the corners the platform rounds away.
        let width = size * 0.56
        let height = width * 160 / 120
        HourglassStill.draw(state, in: context, rect: CGRect(
            x: (size - width) / 2, y: (size - height) / 2, width: width, height: height
        ))
        return context.makeImage()
    }

    // MARK: - The chip

    /// The small sizes, said in whole pixels. Under `chipBelow` the mid-pour drawing stops
    /// being a drawing: at 16 px the glass is nine pixels across, its caps land on half a
    /// pixel, and the ember pool spreads into the mound until the Finder row is a brown smudge
    /// (seen on the Mac 2026-09-09). This is the same hourglass with everything that only
    /// reads at size left out — no pool, no funnel shadow, no rim, no highlight — laid out on
    /// a 16-unit grid and snapped to the output pixels, so no horizontal edge straddles one.
    /// It still answers to the state: the bulb empties, the mound grows, the pour stops.
    static func chip(_ state: HourglassState, size: Double) -> CGImage? {
        let side = Int(size.rounded())
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        let unit = size / 16

        // The grid, in units, top down: cap, bulb, waist, bulb, cap. The glass is 10 units of
        // 16 across and 12 tall, which is far more of the tile than the drawing's 56 %: at this
        // size the subject has to carry the whole square or it reads as an empty tile.
        let cx = 8.0, top = 3.0, waist = 8.0, base = 13.0, half = 5.0

        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * unit, y: y * unit) }
        /// A bar rounded out to whole pixels, never thinner than one: a cap that rounds away
        /// is a cap that is not there.
        func bar(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            let x0 = (x * unit).rounded(), y0 = (y * unit).rounded()
            return CGRect(
                x: x0, y: y0,
                width: max(1, ((x + w) * unit).rounded() - x0),
                height: max(1, ((y + h) * unit).rounded() - y0)
            )
        }
        func wedge(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGPath {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.closeSubpath()
            return path
        }
        /// How wide the upper bulb is at `y`: it narrows from the cap to the waist.
        func halfWidth(_ y: Double) -> Double { half * (waist - y) / (waist - top) }

        // 32 px has a pixel to spend on an outline and 16 px does not: a one-pixel rim around
        // a shape ten pixels wide is most of the shape, and the glass fills in with grey. The
        // two carry the silhouette differently — 32 by its edge, 16 by its body.
        let rim = unit >= 2

        fill(context, CGRect(x: 0, y: 0, width: size, height: size), Ember.ground)

        // Both bulbs, so a half-empty top still reads as glass rather than as nothing.
        let body = CGMutablePath()
        body.addPath(wedge(at(cx - half, top), at(cx + half, top), at(cx, waist)))
        body.addPath(wedge(at(cx - half, base), at(cx + half, base), at(cx, waist)))
        fill(context, body, chipBody(state.glass, rim: rim))

        // Where the sand sits comes from the glass's own geometry, not from a fraction of the
        // grid: a level is a share of a charge by area, so the surface falls slowly while the
        // bulb is wide and fast as it narrows. Mapping it keeps the chip and the drawing
        // telling the same time.
        let sandEdge = lerp(
            HourglassGeometry.topEdge(level: state.sandLevel),
            from: (HourglassGeometry.lid, HourglassGeometry.neckTop), to: (top, waist)
        )
        let moundPeak = lerp(
            HourglassGeometry.peak(level: state.moundLevel),
            from: (HourglassGeometry.neckBottom, HourglassGeometry.floor), to: (waist, base)
        )

        // Sand in the top bulb: a wedge resting on the neck, as wide as the bulb is where it
        // rests. No funnel — a dip 36 % of a four-pixel span is one grey pixel.
        if state.sandLevel > 0.002 {
            let w = halfWidth(sandEdge)
            linear(
                context, in: wedge(at(cx - w, sandEdge), at(cx + w, sandEdge), at(cx, waist)),
                stops: state.sand.stops, from: at(cx, top), to: at(cx, base)
            )
        }

        // The pour, from the neck down to the pile it is building. One pixel at 16, two at 32:
        // any wider and the sand above it becomes a bowl on a stem, which is a glass of wine.
        if state.isRunning || state.isFrozen {
            let w = max(1, (unit * 0.6).rounded())
            let y0 = ((waist - 0.8) * unit).rounded()
            let y1 = max(y0 + 1, (moundPeak * unit).rounded())
            fill(
                context,
                CGRect(x: (cx * unit).rounded() - w / 2, y: y0, width: w, height: y1 - y0),
                Ember.sandLight.opacity(0.8)
            )
        }

        // The mound, a low pile on the floor of the glass.
        if state.moundLevel > 0.002 {
            linear(
                context, in: wedge(at(cx - half * 0.95, base), at(cx + half * 0.95, base), at(cx, moundPeak)),
                stops: state.mound.stops, from: at(cx, top), to: at(cx, base)
            )
        }

        // The rim, where there is room for one. Without it the lower bulb has no edge of its
        // own, the sand above sits on the pour like a bowl on a stem, and the whole thing
        // reads as a wine glass. One pixel of outline is what makes it an hourglass again.
        if rim {
            stroke(context, body, state.glass.strokeStops.last?.color ?? .white, width: (unit * 0.55).rounded())
        }

        // The caps last, over both ends of the glass, a hair wider than it is.
        let cap = state.glass.capColor.opacity(state.glass.capOpacity)
        fill(context, bar(cx - half - 0.4, top - 1.3, 2 * half + 0.8, 1.4), cap)
        fill(context, bar(cx - half - 0.4, base - 0.1, 2 * half + 0.8, 1.4), cap)
        return context.makeImage()
    }

    /// The body fill a chip needs. `Glass.fill` is tuned for a large glass on a dark wall —
    /// 7 % white for the cream glass — which is nothing at all across nine pixels, so the chip
    /// takes the same hue at the weight that survives. With a rim to draw the shape the body
    /// stays a hint; without one it has to be the shape, and carries roughly twice the weight.
    private static func chipBody(_ glass: HourglassState.Glass, rim: Bool) -> Color {
        let weight = rim ? 1.0 : 1.9
        return switch glass {
        case .cream, .dim, .grey: .white.opacity(0.11 * weight)
        case .amber: Ember.amber.opacity(0.20 * weight)
        case .pending: Ember.pending.opacity(0.17 * weight)
        case .ink: .black.opacity(0.11 * weight)
        }
    }

    /// `value` carried from one span to another, both given as (start, end).
    private static func lerp(_ value: Double, from: (Double, Double), to: (Double, Double)) -> Double {
        let share = (value - from.0) / (from.1 - from.0)
        return to.0 + (to.1 - to.0) * min(1, max(0, share))
    }

    // MARK: - Paint

    private static func cgColor(_ color: Color) -> CGColor {
        color.resolve(in: EnvironmentValues()).cgColor
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, _ color: Color) {
        context.setFillColor(cgColor(color))
        context.fill(rect)
    }

    private static func fill(_ context: CGContext, _ path: CGPath, _ color: Color) {
        context.saveGState()
        context.addPath(path)
        context.setFillColor(cgColor(color))
        context.fillPath()
        context.restoreGState()
    }

    private static func stroke(_ context: CGContext, _ path: CGPath, _ color: Color, width: Double) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(cgColor(color))
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    /// A linear gradient clipped to `path`, running past both ends the way SwiftUI's does, so
    /// the chip's sand carries the same top-to-bottom ramp the glass does.
    private static func linear(
        _ context: CGContext, in path: CGPath, stops: [Gradient.Stop], from: CGPoint, to: CGPoint
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map { cgColor($0.color) } as CFArray,
            locations: stops.map(\.location)
        ) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    /// One of the wall's glows: an ellipse of `color` at a fraction of the frame, fading to
    /// nothing at `fade` of its radius, the way `EmberWall` draws it.
    private static func glow(
        _ context: CGContext, _ color: Color, at center: CGPoint,
        rx: Double, ry: Double, fade: Double, in rect: CGRect
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [cgColor(color), cgColor(color.opacity(0))] as CFArray,
            locations: [0, fade]
        ) else { return }
        context.saveGState()
        context.translateBy(x: center.x * rect.width, y: center.y * rect.height)
        context.scaleBy(x: 1, y: ry / rx)
        let radius = rx * rect.width
        context.drawRadialGradient(
            gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: []
        )
        context.restoreGState()
    }

    private static func write(_ image: CGImage, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
