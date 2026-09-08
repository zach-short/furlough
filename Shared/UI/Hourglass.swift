import SwiftUI

/// What one hourglass shows. Direction C from design/HOURGLASS.md, chosen 2026-09-07: the
/// top bulb is the window, exact, and drains with the countdown; the colour of the mound
/// carries the budget, which the Screen Time API only reports at the 5-minute warning and at
/// exhaustion. The same value drives the hero, the 12 pt row chips, the widget and the Live
/// Activity.
struct HourglassState: Equatable {
    /// `ink` is the glass on a light ground rather than the app's dark room: the Mac's menu
    /// bar follows the desktop picture, and cream caps on a white bar are not there at all.
    enum Glass: Equatable { case cream, amber, dim, grey, pending, ink }
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
    var showsAnchor = false

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
    /// Sand frozen mid-stream under an ember glow, with the anchor at the base.
    static let anchored = HourglassState(
        sandLevel: 0.55, moundLevel: 0.4, isFrozen: true, glow: Ember.ember, glowStrength: 0.9, showsAnchor: true
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
        case .ink: .black.opacity(0.05)
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
        case .ink: (.black, 0.8, 0.45, 0.7)
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
        case .ink: 0.85
        }
    }

    /// The caps are cream against the dark room, and the room's own dark against a light one.
    var capColor: Color {
        switch self {
        case .ink: Ember.ground
        default: Ember.cream
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

extension HourglassState {
    /// The widget's glass: the open target closing soonest, else whatever opens next, else an
    /// all-day app draining towards midnight.
    static func of(_ summary: Policy.Summary, now: Date) -> HourglassState {
        if let until = summary.openUntil, until > now, !summary.openNames.isEmpty {
            let start = summary.openStart ?? now
            let total = until.timeIntervalSince(start)
            let level = total > 0 ? min(1, max(0, until.timeIntervalSince(now) / total)) : 0
            return .open(level: level, warned: summary.openWarned)
        }
        if let next = summary.nextOpenAt {
            if summary.nextOpenIsExhausted { return .usedUp }
            if Calendar.current.isDate(next, inSameDayAs: now) {
                return .comingSoon(inMinutes: next.timeIntervalSince(now) / 60)
            }
            return .doneForToday
        }
        if !summary.allDayNames.isEmpty {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            let total = end.timeIntervalSince(start)
            let level = total > 0 ? min(1, max(0, end.timeIntervalSince(now) / total)) : 0
            return .open(level: level, warned: summary.allDayWarned)
        }
        if summary.isEmpty { return .unconfigured }
        return summary.isAnchored ? .anchored : .alwaysBlocked
    }
}

/// The glass hourglass from the mockups, drawn as vectors in a 120 × 160 space and coloured
/// by `state`. `phase` is a running clock in seconds that moves the stream, the glow pulse and
/// the falling grain; hold it constant for a still picture (widgets, the Live Activity), which
/// still shows a full stream since every grain is a function of the phase.
/// Under 40 pt tall it switches to a bolder chip drawing for rows and the page indicator.
struct HourglassView: View {
    var state: HourglassState
    var phase: TimeInterval = 0
    /// False under Reduce Motion: the stream is a solid column and nothing pulses.
    var motion = true
    /// Seconds since the view appeared, for the one-time outline pulse of an empty glass.
    var appearSeconds: TimeInterval?

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 120, geo.size.height / 160)
            let mini = 160 * scale < 40
            let origin = CGPoint(x: (geo.size.width - 120 * scale) / 2, y: (geo.size.height - 160 * scale) / 2)
            let peak = HourglassGeometry.peak(level: state.moundLevel)
            let landing = peak - 0.5
            let capHeight: Double = mini ? 10 : 8
            let streaming = state.isRunning || state.isFrozen
            /// Grains, not a column: the full drawing with motion, or the frozen glass, which is one frame of it.
            let grainy = streaming && !mini && motion
            let streamPhase = state.isFrozen ? HourglassView.frozenPhase : phase
            let unit = { (point: CGPoint) in
                UnitPoint(x: (origin.x + point.x * scale) / geo.size.width, y: (origin.y + point.y * scale) / geo.size.height)
            }
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
                if state.sandLevel > 0.002 {
                    let edge = HourglassGeometry.topEdge(level: state.sandLevel)
                    TopSandShape(level: state.sandLevel)
                        .fill(state.sand.gradient)
                    // The funnel: a shadow in the bowl where the sand slides down to the neck.
                    TopSandShape(level: state.sandLevel)
                        .fill(RadialGradient(
                            colors: [.black.opacity(mini ? 0.2 : 0.34), .clear],
                            center: unit(HourglassGeometry.funnelBottom(edge: edge)),
                            startRadius: 0, endRadius: max(1, HourglassGeometry.halfWidth(at: edge) * 1.15 * scale)
                        ))
                }
                if streaming {
                    StreamShape(landing: landing, topWidth: mini ? 6 : 3, bottomWidth: mini ? 5 : 2.2)
                        .fill(Ember.sandLight.opacity(grainy ? 0.26 : 0.95))
                    if grainy {
                        let grains = HourglassStream.grains(phase: streamPhase, top: HourglassGeometry.streamTop, landing: landing) {
                            HourglassGeometry.pileSurface(x: $0, peak: peak)
                        }
                        ForEach(GrainsShape.Layer.allCases, id: \.self) { layer in
                            GrainsShape(grains: grains.filter { layer.holds($0) })
                                .fill(Ember.sandLight.opacity(layer.opacity))
                        }
                        // Dust where the stream lands.
                        Ellipse()
                            .fill(RadialGradient(
                                colors: [Ember.sandLight.opacity(0.42 * dustFlicker(streamPhase)), .clear],
                                center: .center, startRadius: 0, endRadius: 9 * scale
                            ))
                            .frame(width: 18 * scale, height: 8 * scale)
                            .position(x: origin.x + 60 * scale, y: origin.y + (landing + 0.5) * scale)
                    }
                }
                if let grain = loneGrain(landing: landing) {
                    GrainsShape(grains: [grain])
                        .fill(Ember.sandLight.opacity(grain.alpha))
                }
                if state.moundLevel > 0.002 {
                    MoundShape(level: state.moundLevel)
                        .fill(state.mound.gradient)
                    // Fresh sand at the tip, where the stream lands, is lighter than the settled slopes.
                    MoundShape(level: state.moundLevel)
                        .fill(RadialGradient(
                            colors: [Ember.sandLight.opacity(mini ? 0.18 : 0.28), .clear],
                            center: unit(CGPoint(x: HourglassGeometry.centerX, y: peak + 1.5)),
                            startRadius: 0, endRadius: 11 * scale
                        ))
                }
                HourglassPartShape(part: .body)
                    .stroke(state.glass.stroke, style: StrokeStyle(lineWidth: (mini ? 7 : 2.5) * scale, lineJoin: .round))
                    .opacity(outlineOpacity)
                HourglassPartShape(part: .cap(top: true, height: capHeight))
                    .fill(state.glass.capColor.opacity(state.glass.capOpacity))
                HourglassPartShape(part: .cap(top: false, height: capHeight))
                    .fill(state.glass.capColor.opacity(state.glass.capOpacity))
                if !mini, state.glass != .ink {
                    HourglassPartShape(part: .highlight)
                        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                    if state.showsAnchor {
                        HourglassPartShape(part: .anchor)
                            .fill(Ember.ember)
                        HourglassPartShape(part: .anchor)
                            .stroke(Ember.cream.opacity(0.7), style: StrokeStyle(lineWidth: 1 * scale, lineJoin: .round))
                    }
                }
            }
        }
        .aspectRatio(120 / 160, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The frame the Anchor stops the stream on: chosen so grains fill the fall and a few chips are mid-air.
    static let frozenPhase: TimeInterval = 2.75

    /// 0…1 along the glow's breath; 0.5 when nothing pulses.
    private var pulseValue: Double {
        guard motion, state.pulse != .none else { return 0.5 }
        return (sin(phase / state.pulse.period * 2 * .pi) + 1) / 2
    }

    /// The landing dust shimmers with the arrivals, 0.6…1.
    private func dustFlicker(_ phase: TimeInterval) -> Double {
        0.8 + 0.2 * sin(phase * 13.1) * sin(phase * 7.3)
    }

    /// The grain that slips through when the window is minutes away, or nil between drops.
    private func loneGrain(landing: Double) -> SandGrain? {
        guard state.dropsGrain, motion, !state.isRunning else { return nil }
        return HourglassStream.loneGrain(phase: phase, top: HourglassGeometry.streamTop, landing: landing)
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
    case cap(top: Bool, height: Double)
    case highlight
    case anchor

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
        case .cap(let top, let height):
            p.addRoundedRect(in: CGRect(x: 18, y: top ? 16 - height : 144, width: 84, height: height), cornerSize: CGSize(width: 4, height: 4))
        case .highlight:
            p.move(to: CGPoint(x: 31, y: 20))
            p.addCurve(to: CGPoint(x: 45, y: 50), control1: CGPoint(x: 31, y: 34), control2: CGPoint(x: 37, y: 42))
        case .anchor:
            // Standing on the base, half in the pile: the mark for a glass that has stopped.
            p = AnchorMark.fit(in: CGRect(x: 50, y: 130, width: 20, height: 25))
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

/// The sand in the top bulb, from 0 (empty) to 1 (one charge), resting against the walls with
/// a funnel down to the neck. Animatable.
struct TopSandShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        HourglassGeometry.fit(HourglassGeometry.polygon(HourglassGeometry.topSand(edge: HourglassGeometry.topEdge(level: level))), in: rect)
    }
}

/// The pile in the bottom bulb, from 0 (nothing) to 1 (one charge): a cone that spreads to the
/// walls as it grows. Animatable.
struct MoundShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        HourglassGeometry.fit(HourglassGeometry.polygon(HourglassGeometry.pile(peak: HourglassGeometry.peak(level: level))), in: rect)
    }
}

/// The column of the stream, from the neck to the top of the pile, a little narrower at the
/// bottom where the grains have spread apart. Solid under Reduce Motion and in the chips; a
/// faint haze behind the grains otherwise.
struct StreamShape: Shape {
    var landing: Double
    var topWidth: Double
    var bottomWidth: Double

    func path(in rect: CGRect) -> Path {
        let top = HourglassGeometry.streamTop
        let bottom = max(top + 1, landing + 0.5)
        var p = Path()
        p.move(to: CGPoint(x: 60 - topWidth / 2, y: top))
        p.addLine(to: CGPoint(x: 60 + topWidth / 2, y: top))
        p.addLine(to: CGPoint(x: 60 + bottomWidth / 2, y: bottom))
        p.addLine(to: CGPoint(x: 60 - bottomWidth / 2, y: bottom))
        p.closeSubpath()
        return HourglassGeometry.fit(p, in: rect)
    }
}

/// Grains as one path of small ellipses, so a frame of forty grains is one fill.
struct GrainsShape: Shape {
    /// Chips fade as they settle; a fill has one opacity, so they are drawn in a few bands.
    enum Layer: CaseIterable {
        case solid, dimming, faint, gone

        var opacity: Double {
            switch self {
            case .solid: 0.96
            case .dimming: 0.68
            case .faint: 0.38
            case .gone: 0.14
            }
        }

        func holds(_ grain: SandGrain) -> Bool {
            switch self {
            case .solid: grain.alpha > 0.78
            case .dimming: grain.alpha > 0.52 && grain.alpha <= 0.78
            case .faint: grain.alpha > 0.26 && grain.alpha <= 0.52
            case .gone: grain.alpha <= 0.26
            }
        }
    }

    var grains: [SandGrain]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for grain in grains {
            p.addEllipse(in: CGRect(
                x: grain.x - grain.radius, y: grain.y - grain.radius - grain.stretch / 2,
                width: 2 * grain.radius, height: 2 * grain.radius + grain.stretch
            ))
        }
        return HourglassGeometry.fit(p, in: rect)
    }
}

extension HourglassGeometry {
    static func fit(_ path: Path, in rect: CGRect) -> Path {
        let scale = min(rect.width / 120, rect.height / 160)
        let dx = rect.minX + (rect.width - 120 * scale) / 2
        let dy = rect.minY + (rect.height - 160 * scale) / 2
        return path.applying(CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale))
    }

    /// A closed path through the polygon's points.
    static func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for point in points.dropFirst() { p.addLine(to: point) }
        p.closeSubpath()
        return p
    }
}
