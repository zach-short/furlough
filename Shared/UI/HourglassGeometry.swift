import CoreGraphics
import Foundation

/// The inside of the glass in the mockup's 120 × 160 space, and how sand sits in it. Pure
/// geometry with no SwiftUI, so the shapes in Hourglass.swift stay thin and a script can check
/// the numbers.
///
/// The sand fills the bulb it is in: the top charge rests against the walls and drains through
/// a funnel into the neck, and the pile below is a cone at the angle of repose that spreads to
/// the walls as it grows. A level is a share of one charge by area, not a height, so the top
/// surface drops slowly while the bulb is wide and quickly as it narrows, and what leaves the
/// top is what arrives below.
enum HourglassGeometry {
    static let centerX: Double = 60
    /// The top cap covers the glass down to here.
    static let lid: Double = 16
    /// The neck. Sand leaves the top bulb at `neckTop`; the stream is clear of the glass by `neckBottom`.
    static let neckTop: Double = 76
    static let neckBottom: Double = 84
    /// The bottom cap starts here.
    static let floor: Double = 144
    /// Air between the sand and the wall, so the wall's stroke stays a line and not an edge of sand.
    static let inset: Double = 1.0
    /// The orifice: the top sand narrows through the neck to the stream's width here, and the
    /// stream starts a unit above so the two overlap as one pour.
    static let topSandBottom: Double = 81
    static let streamTop: Double = 80
    static let orificeHalfWidth: Double = 1.5

    /// The funnel in the top surface: its depth as a share of the half width where sand meets the wall.
    static let funnelDepth: Double = 0.36
    /// How the funnel curves, 1 is a cone, higher is a rounder bowl.
    static let funnelCurve: Double = 1.7
    /// The pile's slope, near the angle of repose of dry sand (about 32°).
    static let pileSlope: Double = 0.62
    /// The pile's tip is rounded over this many units by the impact of the stream.
    static let pileTip: Double = 3.5
    /// Where the pile's tip sits when every grain is below. Sets the size of one charge.
    static let fullPeak: Double = 102

    /// One charge of sand, in square units: the pile at its tallest.
    static let charge: Double = area(of: pile(peak: fullPeak))

    // MARK: Walls

    private static let wallStep = 0.25
    private static let wallFrom = 12.0
    private static let wallTo = 148.0
    /// Half the inside width at every quarter unit from 12 to 148, already inset.
    private static let wall: [Double] = stride(from: wallFrom, through: wallTo, by: wallStep).map { y in
        rightWall(at: y) - centerX - inset
    }

    /// Half the inside width at `y`, inset from the wall.
    static func halfWidth(at y: Double) -> Double {
        let position = (min(max(y, wallFrom), wallTo) - wallFrom) / wallStep
        let index = Int(position)
        guard index < wall.count - 1 else { return wall[wall.count - 1] }
        let fraction = position - Double(index)
        return wall[index] + (wall[index + 1] - wall[index]) * fraction
    }

    /// The right wall of the mockup's body path at `y`: straight sides, the two curves into the neck, and the neck.
    private static func rightWall(at y: Double) -> Double {
        switch y {
        case ..<32: 98
        case ..<neckTop: bezierX(y: y, p0: (98, 32), p1: (98, 52), p2: (80, 64), p3: (68, 76))
        case ...neckBottom: 68
        case ..<128: bezierX(y: y, p0: (68, 84), p1: (80, 96), p2: (98, 108), p3: (98, 128))
        default: 98
        }
    }

    /// The x of a cubic whose y is monotone, by bisection on t.
    private static func bezierX(y: Double, p0: (Double, Double), p1: (Double, Double), p2: (Double, Double), p3: (Double, Double)) -> Double {
        func at(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            let u = 1 - t
            return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
        }
        var low = 0.0, high = 1.0
        for _ in 0..<28 {
            let mid = (low + high) / 2
            if at(mid, p0.1, p1.1, p2.1, p3.1) < y { low = mid } else { high = mid }
        }
        let t = (low + high) / 2
        return at(t, p0.0, p1.0, p2.0, p3.0)
    }

    // MARK: Top sand

    /// Half the top sand's width at `y`: the wall in the bulb, and through the neck a pour that
    /// narrows from the neck's width to the orifice, so the charge runs into the stream rather
    /// than stopping on a line above it.
    static func topSandHalfWidth(at y: Double) -> Double {
        guard y > neckTop else { return halfWidth(at: y) }
        let s = min(1, (y - neckTop) / (topSandBottom - neckTop))
        return orificeHalfWidth + (halfWidth(at: neckTop) - orificeHalfWidth) * pow(1 - s, 1.6)
    }

    /// The top sand with its wall edge at `edge`: up the left side from the orifice, the funnel across, down the right.
    static func topSand(edge: Double) -> [CGPoint] {
        let edge = min(max(edge, lid), topSandBottom)
        guard edge < topSandBottom - 0.05 else { return [] }
        let half = topSandHalfWidth(at: edge)
        let depth = funnelDepth(edge: edge, half: half)
        let step = 0.5
        var points: [CGPoint] = [CGPoint(x: centerX - orificeHalfWidth, y: topSandBottom)]
        // Left side, bottom to top.
        for y in stride(from: topSandBottom - step, to: edge, by: -step) {
            points.append(CGPoint(x: centerX - topSandHalfWidth(at: y), y: y))
        }
        // The funnel, left to right, kept inside the sand's sides where they narrow under it.
        let samples = 32
        for k in 0...samples {
            let u = Double(k) / Double(samples) * 2 - 1
            let y = edge + depth * (1 - pow(abs(u), funnelCurve))
            let side = topSandHalfWidth(at: y)
            points.append(CGPoint(x: min(max(centerX + u * half, centerX - side), centerX + side), y: y))
        }
        // Right side, top to bottom, ending at the orifice.
        for y in stride(from: edge + step, to: topSandBottom, by: step) {
            points.append(CGPoint(x: centerX + topSandHalfWidth(at: y), y: y))
        }
        points.append(CGPoint(x: centerX + orificeHalfWidth, y: topSandBottom))
        return points
    }

    /// The bottom of the funnel for a wall edge.
    static func funnelBottom(edge: Double) -> CGPoint {
        CGPoint(x: centerX, y: edge + funnelDepth(edge: edge, half: topSandHalfWidth(at: edge)))
    }

    /// The funnel's depth: a share of the width, shallower as the last sand runs out of room above the neck.
    private static func funnelDepth(edge: Double, half: Double) -> Double {
        min(funnelDepth * half, (topSandBottom - edge) * 0.8)
    }

    private static let topTable: [(edge: Double, area: Double)] = stride(from: lid, through: topSandBottom, by: 0.25).map { edge in
        (edge, area(of: topSand(edge: edge)))
    }

    /// Where the sand meets the wall when the top holds this share of a charge.
    static func topEdge(level: Double) -> Double {
        invert(topTable.map { ($0.edge, $0.area) }, area: max(0, min(1, level)) * charge)
    }

    /// The share of a charge the top bulb can hold before the sand reaches the lid.
    static var topCapacity: Double { topTable[0].area / charge }

    // MARK: Pile

    /// The pile's surface at `x` for a tip at `peak`: a cone with a rounded tip, never below the floor.
    static func pileSurface(x: Double, peak: Double) -> Double {
        let d = x - centerX
        return min(floor, peak + pileSlope * ((d * d + pileTip * pileTip).squareRoot() - pileTip))
    }

    /// The pile with its tip at `peak`: the cone where it clears the walls, the walls where it does not.
    static func pile(peak: Double) -> [CGPoint] {
        let peak = min(max(peak, neckBottom), floor)
        guard peak < floor - 0.05 else { return [] }
        let wide = halfWidth(at: floor)
        var right: [CGPoint] = []
        let samples = 28
        for k in 0...samples {
            let x = centerX + wide * Double(k) / Double(samples)
            let y = pileSurface(x: x, peak: peak)
            right.append(CGPoint(x: min(x, centerX + halfWidth(at: y)), y: y))
        }
        // Down the wall from where the cone met it, then along the floor.
        if let last = right.last, last.y < floor {
            for y in stride(from: last.y + 1, to: floor, by: 1) {
                right.append(CGPoint(x: centerX + halfWidth(at: y), y: y))
            }
        }
        right.append(CGPoint(x: centerX + wide, y: floor))
        let left = right.reversed().map { CGPoint(x: 2 * centerX - $0.x, y: $0.y) }
        return left + right.dropFirst()
    }

    private static let pileTable: [(peak: Double, area: Double)] = stride(from: neckBottom, through: floor, by: 0.25).map { peak in
        (peak, area(of: pile(peak: peak)))
    }

    /// The y of the pile's tip when the bottom holds this share of a charge.
    static func peak(level: Double) -> Double {
        invert(pileTable.map { ($0.peak, $0.area) }, area: max(0, min(1, level)) * charge)
    }

    // MARK: Helpers

    /// Shoelace area of a simple polygon.
    static func area(of polygon: [CGPoint]) -> Double {
        guard polygon.count > 2 else { return 0 }
        var sum = 0.0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// The parameter whose area is `area`, on a table whose areas fall as the parameter rises.
    private static func invert(_ table: [(Double, Double)], area: Double) -> Double {
        guard let first = table.first, let last = table.last else { return 0 }
        if area >= first.1 { return first.0 }
        if area <= last.1 { return last.0 }
        var low = 0, high = table.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if table[mid].1 > area { low = mid } else { high = mid }
        }
        let (p0, a0) = table[low], (p1, a1) = table[high]
        guard a0 != a1 else { return p0 }
        return p0 + (p1 - p0) * (a0 - area) / (a0 - a1)
    }
}

/// One drawn grain: a small ellipse, stretched along its fall when it is moving fast.
struct SandGrain: Equatable {
    var x: Double
    var y: Double
    var radius: Double
    /// Extra height along the fall, in units.
    var stretch: Double = 0
    var alpha: Double = 1
}

/// The stream: grains leave the neck at a steady rate, fall under gravity in a slightly
/// wandering column that spreads as it drops, and scatter where they land. Everything is a
/// function of `phase`, so any still phase shows a full stream and the same phase always
/// draws the same frame; the frozen glass is the stream at one phase.
enum HourglassStream {
    /// Grains a second.
    static let rate: Double = 34
    /// Units a second leaving the neck.
    static let exitSpeed: Double = 16
    /// Units a second squared.
    static let gravity: Double = 150
    /// Half the column's width at the neck, and how much it spreads by the bottom of the fall.
    static let spread: Double = 1.0
    static let widening: Double = 0.9
    /// How long a bounced chip is visible.
    static let splashLife: Double = 0.42
    /// The share of grains that throw chips when they land.
    static let splashChance: Double = 0.4

    /// Seconds a grain takes from `top` to `landing`.
    static func fallTime(top: Double, landing: Double) -> Double {
        let drop = max(0, landing - top)
        return (-exitSpeed + (exitSpeed * exitSpeed + 2 * gravity * drop).squareRoot()) / gravity
    }

    /// Every grain in the air and every chip on the pile at `phase`, in the 120-space.
    /// `surface` gives the pile's surface at an x, so chips roll on it instead of through it.
    static func grains(phase: Double, top: Double, landing: Double, surface: (Double) -> Double) -> [SandGrain] {
        let flight = fallTime(top: top, landing: landing)
        guard flight > 0.01 else { return [] }
        var grains: [SandGrain] = []
        let first = Int((phase - flight - splashLife) * rate) - 1
        let last = Int(phase * rate) + 1
        for i in first...last {
            let born = (Double(i) + 0.45 * (noise(i, 0) - 0.5)) / rate
            let t = phase - born
            guard t >= 0, t < flight + splashLife else { continue }
            let side = noise(i, 1) * 2 - 1
            let sway = 0.35 * sin(born * 2.1) + 0.2 * sin(born * 5.3)
            let radius = 1.05 + 0.5 * noise(i, 2)
            if t < flight {
                let y = top + exitSpeed * t + 0.5 * gravity * t * t
                let x = HourglassGeometry.centerX + sway + side * (spread + widening * t / flight)
                let speed = exitSpeed + gravity * t
                grains.append(SandGrain(x: x, y: y, radius: radius, stretch: speed * 0.011, alpha: 0.8 + 0.2 * noise(i, 3)))
            } else if noise(i, 4) < splashChance {
                let age = t - flight
                let land = HourglassGeometry.centerX + sway + side * (spread + widening)
                for j in 0..<2 {
                    let sign: Double = j == 0 ? -1 : 1
                    let vx = sign * (8 + 14 * noise(i, 5 + j))
                    let vy = -(18 + 18 * noise(i, 7 + j))
                    let x = land + vx * age
                    let y = min(landing + vy * age + 0.5 * gravity * age * age, surface(x) - 0.8)
                    grains.append(SandGrain(x: x, y: y, radius: 0.85 + 0.45 * noise(i, 9 + j), alpha: 1 - age / splashLife))
                }
            }
        }
        return grains
    }

    /// A single grain that slips through now and then: falls, hops once, and is gone. Nil between drops.
    static func loneGrain(phase: Double, top: Double, landing: Double, every period: Double = 3.2) -> SandGrain? {
        let t = phase.truncatingRemainder(dividingBy: period)
        let flight = fallTime(top: top, landing: landing)
        if t < flight {
            let speed = exitSpeed + gravity * t
            return SandGrain(x: HourglassGeometry.centerX, y: top + exitSpeed * t + 0.5 * gravity * t * t, radius: 1.6, stretch: speed * 0.008)
        }
        let hop = 24.0
        let age = t - flight
        let rest = 2 * hop / gravity
        guard age < rest + 0.35 else { return nil }
        let y = age < rest ? landing - hop * age + 0.5 * gravity * age * age : landing
        let fade = age < rest ? 1 : 1 - (age - rest) / 0.35
        return SandGrain(x: HourglassGeometry.centerX + 3.5 * min(age, rest), y: y, radius: 1.6, alpha: fade)
    }

    /// A steady value in 0..<1 for a grain and a salt.
    static func noise(_ i: Int, _ salt: Int) -> Double {
        var z = UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(salt) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
