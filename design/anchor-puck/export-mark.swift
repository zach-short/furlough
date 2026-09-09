// Flattens AnchorMark.outline into polygons and emits an OpenSCAD module, so the
// engraving in the puck is the app's own mark rather than a redraw of it.
import Foundation
import CoreGraphics
import SwiftUI

let STEPS = 28

func flatten(_ path: CGPath) -> [[CGPoint]] {
    var polys: [[CGPoint]] = []
    var cur: [CGPoint] = []
    var start = CGPoint.zero
    var pt = CGPoint.zero

    func close() {
        if cur.count > 2 { polys.append(cur) }
        cur = []
    }

    path.applyWithBlock { ptr in
        let e = ptr.pointee
        switch e.type {
        case .moveToPoint:
            close()
            pt = e.points[0]; start = pt; cur = [pt]
        case .addLineToPoint:
            pt = e.points[0]; cur.append(pt)
        case .addQuadCurveToPoint:
            let c = e.points[0], end = e.points[1]
            for i in 1...STEPS {
                let t = Double(i) / Double(STEPS), m = 1 - t
                cur.append(CGPoint(x: m*m*pt.x + 2*m*t*c.x + t*t*end.x,
                                   y: m*m*pt.y + 2*m*t*c.y + t*t*end.y))
            }
            pt = end
        case .addCurveToPoint:
            let c1 = e.points[0], c2 = e.points[1], end = e.points[2]
            for i in 1...STEPS {
                let t = Double(i) / Double(STEPS), m = 1 - t
                cur.append(CGPoint(x: m*m*m*pt.x + 3*m*m*t*c1.x + 3*m*t*t*c2.x + t*t*t*end.x,
                                   y: m*m*m*pt.y + 3*m*m*t*c1.y + 3*m*t*t*c2.y + t*t*t*end.y))
            }
            pt = end
        case .closeSubpath:
            close()
            pt = start
        @unknown default:
            break
        }
    }
    close()
    return polys
}

// Drop points closer together than the printer could ever resolve.
func thin(_ poly: [CGPoint], _ eps: Double) -> [CGPoint] {
    var out: [CGPoint] = []
    for p in poly {
        if let last = out.last, hypot(p.x - last.x, p.y - last.y) < eps { continue }
        out.append(p)
    }
    if let f = out.first, let l = out.last, out.count > 1,
       hypot(f.x - l.x, f.y - l.y) < eps { out.removeLast() }
    return out
}

@main
struct ExportMark {
    static func main() throws {
        let raw = flatten(AnchorMark.outline.cgPath)
        guard !raw.isEmpty else { fatalError("no geometry in AnchorMark.outline") }

        let ink = AnchorMark.ink
        let scale = 1.0 / max(ink.width, ink.height)
        let cx = ink.midX, cy = ink.midY

        // Normalise: centred on the origin, longest side 1.0, y flipped for OpenSCAD's y-up.
        var polys = raw.map { poly in
            thin(poly, 0.35).map { CGPoint(x: ($0.x - cx) * scale, y: -($0.y - cy) * scale) }
        }
        polys = polys.filter { $0.count > 2 }

        var points: [String] = []
        var paths: [String] = []
        var n = 0
        for poly in polys {
            paths.append("[" + (n..<(n + poly.count)).map(String.init).joined(separator: ",") + "]")
            for p in poly {
                points.append(String(format: "[%.4f,%.4f]", p.x, p.y))
            }
            n += poly.count
        }

        let scad = """
        // The Furlough anchor mark, flattened straight out of Shared/UI/AnchorMark.swift.
        // Generated — do not hand-edit; re-run design/anchor-puck/export-mark.swift instead.
        //
        // Normalised: centred on the origin, longest side 1.0, y up. scale() it to size.
        // \(polys.count) contour(s), \(n) points.

        module anchor_mark() {
            polygon(
                points = [\(points.joined(separator: ","))],
                paths = [\(paths.joined(separator: ","))]
            );
        }

        """
        try scad.write(toFile: "anchor-mark.scad", atomically: true, encoding: .utf8)

        let json = "[" + polys.map { poly in
            "[" + poly.map { String(format: "[%.4f,%.4f]", $0.x, $0.y) }.joined(separator: ",") + "]"
        }.joined(separator: ",") + "]"
        try json.write(toFile: "mark.json", atomically: true, encoding: .utf8)

        let w = ink.width * scale, h = ink.height * scale
        print(String(format: "contours %d  points %d  aspect %.3f x %.3f", polys.count, n, w, h))
    }
}
