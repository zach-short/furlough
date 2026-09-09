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
        guard let image = render(state, wall: wall, size: size), write(image, to: out) else {
            print("could not render")
            exit(1)
        }
        print("wrote \(out) (\(Int(size))px, \(mode) on \(wall))")
    }

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

    // MARK: - Paint

    private static func cgColor(_ color: Color) -> CGColor {
        color.resolve(in: EnvironmentValues()).cgColor
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, _ color: Color) {
        context.setFillColor(cgColor(color))
        context.fill(rect)
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
