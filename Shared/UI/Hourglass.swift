import SwiftUI

/// What one hourglass shows. Direction C from design/HOURGLASS.md, chosen 2026-09-07: the
/// top bulb is the window, exact, and drains with the countdown; the colour of the mound
/// carries the budget, which the Screen Time API only reports at the 5-minute warning and at
/// exhaustion. The same value drives the hero, the 12 pt row chips, the widget and the Live
/// Activity.
struct HourglassState: Equatable {
    enum Glass: Equatable { case cream, amber, dim, grey, pending }
    enum Tone: Equatable { case sand, amber, ember, grey }
    enum Pulse: Equatable {
        case none, slow, fast, breathe

        var period: Double {
            switch self {
            case .none: 0
            case .slow: 3.4
            case .fast: 1.2
            case .breathe: 4.2
            }
        }
    }

    /// How full the top bulb is, 0…1.
    var sandLevel: Double = 0
    /// How tall the bottom mound is, 0…1.
    var moundLevel: Double = 0
    var isRunning = false
    /// The stream stopped dead: the Anchor.
    var isFrozen = false
    var glass: Glass = .cream
    var sand: Tone = .sand
    var mound: Tone = .sand
    var glow: Color?
    var glowStrength: Double = 1
    var pulse: Pulse = .none
    /// A grain falls now and then: the window opens within ten minutes.
    var dropsGrain = false
    var showsCube = false

    /// True when something moves from frame to frame.
    var isAnimated: Bool { isRunning || pulse != .none || dropsGrain }

    /// Inside a window: the top bulb holds what is left of it. `warned` is the 5-minute budget warning.
    static func open(level: Double, warned: Bool) -> HourglassState {
        HourglassState(
            sandLevel: level, moundLevel: 1 - level, isRunning: true,
            glass: warned ? .amber : .cream, mound: warned ? .amber : .sand,
            glow: warned ? Ember.amber : Ember.moss, pulse: warned ? .fast : .slow
        )
    }

    /// Opens later today: every grain waits in the top.
    static func comingSoon(inMinutes minutes: Double) -> HourglassState {
        HourglassState(sandLevel: 1, glow: Ember.amber, glowStrength: 0.55, pulse: .breathe, dropsGrain: minutes < 10)
    }

    /// Nothing left today and the budget was not spent: the sand has settled, the glow is low.
    static let doneForToday = HourglassState(moundLevel: 1, glow: Ember.amber, glowStrength: 0.35)
    /// The budget is spent: every grain at the bottom, ember, still.
    static let usedUp = HourglassState(moundLevel: 1, glass: .dim, mound: .ember, glow: Ember.ember, glowStrength: 0.45)
    static let alwaysBlocked = HourglassState(moundLevel: 0.55, glass: .grey, sand: .grey, mound: .grey)
    /// An empty glass with a pending outline.
    static let unconfigured = HourglassState(glass: .pending)
    /// Sand frozen mid-stream under an ember glow, with the cube at the base.
    static let anchored = HourglassState(
        sandLevel: 0.55, moundLevel: 0.4, isFrozen: true, glow: Ember.ember, glowStrength: 0.9, showsCube: true
    )

    /// Direction C for one target right now.
    static func of(_ target: Target, status: TargetStatus, runtime: RuntimeState, now: Date) -> HourglassState {
        switch status {
        case .anchored:
            return .anchored
        case .unconfigured:
            return .unconfigured
        case .blockedAllDay:
            return .alwaysBlocked
        case .exhausted:
            return .usedUp
        case .open(let until):
            let window = target.rule?.window(containing: Policy.minuteOfDay(now), on: Policy.weekday(now))
            let level = Policy.windowFraction(start: window?.startMinute ?? 0, end: until, now: now)
            return .open(level: level, warned: runtime.wasWarned(target.id, dayKey: Policy.dayKey(now)))
        case .closed(let next):
            guard next.isToday else { return .doneForToday }
            return .comingSoon(inMinutes: Policy.date(at: next, from: now).timeIntervalSince(now) / 60)
        }
    }
}

extension HourglassState.Glass {
    var fill: Color {
        switch self {
        case .cream: .white.opacity(0.07)
        case .amber: Ember.amber.opacity(0.12)
        case .dim: .white.opacity(0.045)
        case .grey: .white.opacity(0.035)
        case .pending: Ember.pending.opacity(0.03)
        }
    }

    /// The 1 pt edge: bright top left, faint middle, bright bottom right.
    var stroke: LinearGradient {
        let (color, top, middle, bottom): (Color, Double, Double, Double) = switch self {
        case .cream: (.white, 0.6, 0.14, 0.45)
        case .amber: (Ember.amber, 0.95, 0.35, 0.8)
        case .dim: (.white, 0.38, 0.1, 0.3)
        case .grey: (.white, 0.3, 0.1, 0.24)
        case .pending: (Ember.pending, 0.95, 0.55, 0.9)
        }
        return LinearGradient(
            stops: [
                .init(color: color.opacity(top), location: 0),
                .init(color: color.opacity(middle), location: 0.5),
                .init(color: color.opacity(bottom), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var capOpacity: Double {
        switch self {
        case .cream, .amber: 0.92
        case .dim, .grey: 0.55
        case .pending: 0.35
        }
    }
}

extension HourglassState.Tone {
    /// Top to bottom over the whole glass, so the top sand is light and the mound is deep.
    var gradient: LinearGradient {
        switch self {
        case .sand:
            Ember.sand
        case .amber:
            LinearGradient(
                stops: [.init(color: Ember.sandLight, location: 0), .init(color: Ember.amber, location: 0.6), .init(color: Ember.amber, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        case .ember:
            LinearGradient(
                stops: [.init(color: Ember.ember, location: 0), .init(color: Ember.ember, location: 0.5), .init(color: Color(hex: 0x9C3524), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        case .grey:
            LinearGradient(
                stops: [.init(color: Color(hex: 0x8B847A), location: 0), .init(color: Color(hex: 0x6A635B), location: 0.6), .init(color: Color(hex: 0x4E4841), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// The glass hourglass from the mockups, drawn as vectors in a 120 × 160 space and coloured
/// by `state`. `phase` is a running clock in seconds that moves the stream, the glow pulse and
/// the falling grain; hold it constant for a still picture (widgets, the Live Activity).
/// Under 40 pt tall it switches to a bolder chip drawing for rows and the page indicator.
struct HourglassView: View {
    var state: HourglassState
    var phase: TimeInterval = 0
    /// False under Reduce Motion: the stream is a solid line and nothing pulses.
    var motion = true
    /// Seconds since the view appeared, for the one-time outline pulse of an empty glass.
    var appearSeconds: TimeInterval?

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 120, geo.size.height / 160)
            let mini = 160 * scale < 40
            let origin = CGPoint(x: (geo.size.width - 120 * scale) / 2, y: (geo.size.height - 160 * scale) / 2)
            let landing = 144 - 38 * state.moundLevel - 1.5
            let streamWidth = (mini ? 6 : 3) * scale
            let capHeight: Double = mini ? 10 : 8
            ZStack(alignment: .topLeading) {
                if let glow = state.glow {
                    let pulse = pulseValue
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: glow.opacity(0.95 * state.glowStrength), location: 0),
                                .init(color: glow.opacity(0), location: 1),
                            ],
                            center: .center, startRadius: 0, endRadius: 46 * scale
                        ))
                        .frame(width: 92 * scale, height: 92 * scale)
                        .scaleEffect(x: 1, y: 34 / 46)
                        .scaleEffect(0.94 + 0.12 * pulse)
                        .opacity(0.72 + 0.28 * pulse)
                        .position(x: origin.x + 60 * scale, y: origin.y + 118 * scale)
                }
                HourglassPartShape(part: .body)
                    .fill(state.glass.fill)
                HourglassPartShape(part: .body)
                    .stroke(state.glass.stroke, style: StrokeStyle(lineWidth: (mini ? 7 : 2.5) * scale, lineJoin: .round))
                    .opacity(outlineOpacity)
                TopSandShape(level: state.sandLevel)
                    .fill(state.sand.gradient)
                if state.isRunning || state.isFrozen {
                    let solid = state.isFrozen || !motion
                    HourglassPartShape(part: .stream(landing: landing))
                        .stroke(Ember.sandLight.opacity(solid && !state.isFrozen ? 0.95 : 0.5), style: StrokeStyle(lineWidth: streamWidth, lineCap: .round))
                    if state.isFrozen || motion {
                        HourglassPartShape(part: .stream(landing: landing))
                            .stroke(
                                Ember.sandLight,
                                style: StrokeStyle(
                                    lineWidth: streamWidth, lineCap: .round,
                                    dash: [3 * scale, 3.5 * scale], dashPhase: (state.isFrozen ? 0 : dashPhase) * scale
                                )
                            )
                    }
                }
                if let grainY {
                    Circle()
                        .fill(Ember.sandLight)
                        .frame(width: (mini ? 8 : 3.8) * scale, height: (mini ? 8 : 3.8) * scale)
                        .position(x: origin.x + 60 * scale, y: origin.y + grainY * scale)
                }
                MoundShape(level: state.moundLevel)
                    .fill(state.mound.gradient)
                HourglassPartShape(part: .cap(top: true, height: capHeight))
                    .fill(Ember.cream.opacity(state.glass.capOpacity))
                HourglassPartShape(part: .cap(top: false, height: capHeight))
                    .fill(Ember.cream.opacity(state.glass.capOpacity))
                if !mini {
                    HourglassPartShape(part: .highlight)
                        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                    if state.showsCube {
                        HourglassPartShape(part: .cube)
                            .fill(Ember.ember)
                        HourglassPartShape(part: .cube)
                            .stroke(Ember.cream.opacity(0.7), style: StrokeStyle(lineWidth: 1 * scale, lineJoin: .round))
                        HourglassPartShape(part: .cubeEdges)
                            .stroke(Ember.cream.opacity(0.7), style: StrokeStyle(lineWidth: 1 * scale, lineJoin: .round))
                    }
                }
            }
        }
        .aspectRatio(120 / 160, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// 0…1 along the glow's breath; 0.5 when nothing pulses.
    private var pulseValue: Double {
        guard motion, state.pulse != .none else { return 0.5 }
        return (sin(phase / state.pulse.period * 2 * .pi) + 1) / 2
    }

    /// Grains run down the stream: about 26 units a second in the 120-space.
    private var dashPhase: Double {
        -(phase * 26).truncatingRemainder(dividingBy: 6.5)
    }

    /// Where the falling grain is, in the 120-space, or nil between drops.
    private var grainY: Double? {
        guard state.dropsGrain, motion else { return nil }
        let cycle = phase.truncatingRemainder(dividingBy: 3.2)
        guard cycle < 1.2 else { return nil }
        return 72 + 70 * pow(cycle / 1.2, 1.5)
    }

    /// The pending outline fades up once when it appears.
    private var outlineOpacity: Double {
        guard state.glass == .pending, motion, let seconds = appearSeconds, seconds < 0.72 else { return 1 }
        return 0.35 + 0.65 * (seconds / 0.72)
    }
}

/// The hourglass in motion: stream, pulse and grain driven by a frame clock that pauses when
/// nothing moves. Reduce Motion keeps the level changes and drops the rest.
struct LivingHourglass: View {
    var state: HourglassState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt: Date?
    @State private var settled = false

    var body: some View {
        let running = !reduceMotion && (state.isAnimated || !settled)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !running)) { context in
            HourglassView(
                state: state,
                phase: context.date.timeIntervalSinceReferenceDate,
                motion: !reduceMotion,
                appearSeconds: appearedAt.map { context.date.timeIntervalSince($0) }
            )
        }
        .onAppear { appearedAt = .now }
        .task(id: state.isAnimated) {
            settled = false
            guard !state.isAnimated else { return }
            try? await Task.sleep(for: .seconds(2))
            settled = true
        }
    }
}

/// The fixed pieces of the drawing. Coordinates are the mockup's 120 × 160 SVG space.
enum HourglassPart {
    case body
    case stream(landing: Double)
    case cap(top: Bool, height: Double)
    case highlight
    case cube
    case cubeEdges

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
        case .stream(let landing):
            p.move(to: CGPoint(x: 60, y: 70))
            p.addLine(to: CGPoint(x: 60, y: max(72, landing)))
        case .cap(let top, let height):
            p.addRoundedRect(in: CGRect(x: 18, y: top ? 16 - height : 144, width: 84, height: height), cornerSize: CGSize(width: 4, height: 4))
        case .highlight:
            p.move(to: CGPoint(x: 31, y: 20))
            p.addCurve(to: CGPoint(x: 45, y: 50), control1: CGPoint(x: 31, y: 34), control2: CGPoint(x: 37, y: 42))
        case .cube:
            p.move(to: CGPoint(x: 60, y: 138))
            p.addLine(to: CGPoint(x: 67, y: 142))
            p.addLine(to: CGPoint(x: 67, y: 150))
            p.addLine(to: CGPoint(x: 60, y: 154))
            p.addLine(to: CGPoint(x: 53, y: 150))
            p.addLine(to: CGPoint(x: 53, y: 142))
            p.closeSubpath()
        case .cubeEdges:
            p.move(to: CGPoint(x: 53, y: 142))
            p.addLine(to: CGPoint(x: 60, y: 146))
            p.addLine(to: CGPoint(x: 67, y: 142))
            p.move(to: CGPoint(x: 60, y: 146))
            p.addLine(to: CGPoint(x: 60, y: 154))
        }
        return p
    }
}

/// Scales a fixed part from the 120 × 160 space to fit the given rect, centred.
struct HourglassPartShape: Shape {
    var part: HourglassPart

    func path(in rect: CGRect) -> Path {
        HourglassGeometry.fit(part.path(), in: rect)
    }
}

/// The sand in the top bulb, from 0 (empty) to 1 (full). Animatable.
struct TopSandShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let level = max(0, min(1, level))
        guard level > 0.002 else { return Path() }
        let surface = 36 + (1 - level) * 30
        let below = Path(CGRect(x: 0, y: surface, width: 120, height: 68 - surface))
        return HourglassGeometry.fit(HourglassGeometry.fullTopSand.intersection(below), in: rect)
    }
}

/// The mound in the bottom bulb, from 0 (nothing) to 1 (the full pile). A small pile is
/// narrow as well as low. Animatable.
struct MoundShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let h = 38 * max(0, min(1, level))
        guard h > 0.15 else { return Path() }
        let w = 12 + 18 * (h / 38)
        var p = Path()
        p.move(to: CGPoint(x: 60 - w, y: 144 - 0.21 * h))
        p.addCurve(
            to: CGPoint(x: 60, y: 144 - h),
            control1: CGPoint(x: 60 - w, y: 144 - 0.63 * h), control2: CGPoint(x: 60 - w * 0.53, y: 144 - 0.89 * h)
        )
        p.addCurve(
            to: CGPoint(x: 60 + w, y: 144 - 0.21 * h),
            control1: CGPoint(x: 60 + w * 0.53, y: 144 - 0.89 * h), control2: CGPoint(x: 60 + w, y: 144 - 0.63 * h)
        )
        p.addLine(to: CGPoint(x: 60 + w, y: 144))
        p.addLine(to: CGPoint(x: 60 - w, y: 144))
        p.closeSubpath()
        return HourglassGeometry.fit(p, in: rect)
    }
}

enum HourglassGeometry {
    static func fit(_ path: Path, in rect: CGRect) -> Path {
        let scale = min(rect.width / 120, rect.height / 160)
        let dx = rect.minX + (rect.width - 120 * scale) / 2
        let dy = rect.minY + (rect.height - 160 * scale) / 2
        return path.applying(CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale))
    }

    /// The top bulb full of sand, its surface flat at y 36 and its point in the neck at 66.
    static var fullTopSand: Path {
        var p = Path()
        p.move(to: CGPoint(x: 40, y: 36))
        p.addLine(to: CGPoint(x: 80, y: 36))
        p.addCurve(to: CGPoint(x: 60, y: 66), control1: CGPoint(x: 80, y: 48), control2: CGPoint(x: 68, y: 58))
        p.addCurve(to: CGPoint(x: 40, y: 36), control1: CGPoint(x: 52, y: 58), control2: CGPoint(x: 40, y: 48))
        p.closeSubpath()
        return p
    }
}
