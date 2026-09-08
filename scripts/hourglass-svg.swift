// Prints the sand polygons of the hourglass, in the 120 × 160 drawing space, as the JS
// constants FurloughMac/Resources/Shield.html draws its glass from. The shield page is a web
// page in a browser, so it cannot call HourglassGeometry the way every other surface does;
// this keeps the picture the same one rather than a hand-drawn likeness of it.
//
//   swiftc -parse-as-library -O scripts/hourglass-svg.swift Shared/UI/HourglassGeometry.swift -o /tmp/hourglass-svg && /tmp/hourglass-svg
//
// Paste the output over the SAND block in Shield.html. Re-run it whenever the geometry moves.
import Foundation

func points(_ polygon: [CGPoint]) -> String {
    polygon.map { "\(round($0.x * 10) / 10),\(round($0.y * 10) / 10)" }.joined(separator: " ")
}

@main
enum HourglassSVG {
    static func main() {
        /// The levels the shield can show: a blocked site is never inside its window, so the top is
        /// either full (opens later) or empty, and the pile is full, half up, or nothing.
        let states: [(String, Double, Double)] = [
            ("soon", 1, 0),
            ("done", 0, 1),
            ("blocked", 0, 0.55),
        ]
        print("  const SAND = {")
        for (name, top, mound) in states {
            let topSand = HourglassGeometry.topSand(edge: HourglassGeometry.topEdge(level: top))
            let pile = HourglassGeometry.pile(peak: HourglassGeometry.peak(level: mound))
            print("    \(name): {")
            print("      top: \"\(points(topSand))\",")
            print("      mound: \"\(points(pile))\",")
            print("    },")
        }
        print("  };")
    }
}
