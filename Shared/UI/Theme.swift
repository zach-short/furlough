import SwiftUI

/// Ember Glass tokens. The spec lives in design/DESIGN.md; keep the two in sync.
enum Ember {
    static let ground = Color(hex: 0x0F0D0B)
    static let ember = Color(hex: 0xE5563D)
    static let amber = Color(hex: 0xF59E4A)
    static let cream = Color(hex: 0xF5EFE6)
    static let muted = Color(hex: 0xB8AFA3)
    static let faint = Color(hex: 0x7E766B)
    static let moss = Color(hex: 0x7BC96F)
    static let pending = Color(hex: 0xF2B544)
    /// Lightest sand grain in the hourglass and the top of the budget slider fill.
    static let sandLight = Color(hex: 0xFFD59A)
    static let cardFill = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.12)
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 9
    static let tileRadiusLarge: CGFloat = 13

    /// Ember to Amber, left to right: the budget slider fill.
    static let sliderFill = LinearGradient(colors: [ember, amber], startPoint: .leading, endPoint: .trailing)
    /// Sand, top to bottom.
    static let sand = LinearGradient(
        stops: [.init(color: sandLight, location: 0), .init(color: amber, location: 0.55), .init(color: ember, location: 1)],
        startPoint: .top, endPoint: .bottom
    )
}

/// Bundled faces, addressed by PostScript name (see Furlough/Fonts).
enum EmberFont {
    /// Bricolage Grotesque Bold at the 72 pt optical size: hero and editor names, widget names.
    static func display(_ size: CGFloat) -> Font { .custom("BricolageGrotesque72pt-Bold", size: size) }
    /// Bricolage Grotesque SemiBold at the 24 pt optical size: names at row sizes.
    static func displaySmall(_ size: CGFloat) -> Font { .custom("BricolageGrotesque24pt-SemiBold", size: size) }
    /// Onest: everything readable.
    static func body(_ size: CGFloat, _ weight: BodyWeight = .regular) -> Font { .custom(weight.postScriptName, size: size) }
    /// Geist Mono Medium: every number that counts. Pair with `.monospacedDigit()`.
    static func numerals(_ size: CGFloat) -> Font { .custom("GeistMono-Medium", size: size) }
    /// Geist Mono Regular: log lines.
    static func mono(_ size: CGFloat) -> Font { .custom("GeistMono-Regular", size: size) }
    /// Onest Bold, meant for uppercase eyebrows with `.tracking(size * 0.14)`.
    static func label(_ size: CGFloat) -> Font { .custom("Onest-Bold", size: size) }

    enum BodyWeight {
        case regular, medium, semibold, bold
        var postScriptName: String {
            switch self {
            case .regular: "Onest-Regular"
            case .medium: "Onest-Medium"
            case .semibold: "Onest-SemiBold"
            case .bold: "Onest-Bold"
            }
        }
    }
}

extension View {
    /// Display face with the spec's -0.025 em tracking.
    func emberDisplay(_ size: CGFloat) -> some View {
        font(EmberFont.display(size)).tracking(-0.025 * size)
    }

    /// Small display face for row names.
    func emberDisplaySmall(_ size: CGFloat) -> some View {
        font(EmberFont.displaySmall(size)).tracking(-0.01 * size)
    }

    /// Geist Mono with tabular figures and -0.02 em tracking, in Cream.
    func emberNumerals(_ size: CGFloat) -> some View {
        font(EmberFont.numerals(size)).monospacedDigit().tracking(-0.02 * size).foregroundStyle(Ember.cream)
    }

    /// Onest body text.
    func emberBody(_ size: CGFloat, _ weight: EmberFont.BodyWeight = .regular) -> some View {
        font(EmberFont.body(size, weight))
    }

    /// The card behind rows and form fields: white 6 % fill, white 12 % 1 pt border, radius 20.
    func emberCard() -> some View {
        background(Ember.cardFill, in: RoundedRectangle(cornerRadius: Ember.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Ember.cardRadius, style: .continuous)
                    .strokeBorder(Ember.cardBorder, lineWidth: 1)
            )
    }
}

/// Uppercase Onest Bold label with wide tracking: section headers, "OPEN NOW · UNTIL 10:00 PM", "NEXT".
struct Eyebrow: View {
    var text: String
    var color: Color = Ember.faint
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(EmberFont.label(size))
            .tracking(0.13 * size)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// The background behind every screen: a warm dark ground, one ember glow that laps the room,
/// a faint amber glow top right, and a light grain to keep the gradients from banding. Reduce
/// Motion parks the ember at its resting place, low on the left.
struct EmberWall: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                Ember.ground
                // Only the ember redraws on the clock; the ground, the amber and the grain hold still.
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                    let center = emberCenter(at: context.date.timeIntervalSinceReferenceDate)
                    glow(color: Ember.ember.opacity(0.6), radiusX: 0.58 * width, radiusY: 0.35 * height, fade: 0.62)
                        .position(x: center.x * width, y: center.y * height)
                }
                glow(color: Ember.amber.opacity(0.14), radiusX: 0.60 * width, radiusY: 0.40 * height, fade: 0.60)
                    .position(x: 0.90 * width, y: -0.04 * height)
                Image("Noise")
                    .resizable(resizingMode: .tile)
                    .opacity(0.07)
                    .blendMode(.overlay)
            }
            .compositingGroup()
        }
        .ignoresSafeArea()
    }

    /// Where the ember sits, as a fraction of the wall. It laps the room in a hundred seconds,
    /// its reach breathing in and out and its pace wobbling, so the path is a long way from
    /// repeating. Because the orbit is polar, `reach` sets a floor the ember never crosses: even
    /// at its tightest it sits a fade radius clear of the middle, where the content is. Keep the
    /// wobble below the period ratio (32/103) or the pace goes negative and the ember backs up.
    private func emberCenter(at phase: TimeInterval) -> CGPoint {
        guard !reduceMotion else { return CGPoint(x: 0.28, y: 1.04) }
        let angle = phase / 103 * 2 * .pi + 0.18 * sin(phase / 32 * 2 * .pi)
        let reach = 0.86 + 0.20 * sin(phase / 41 * 2 * .pi)
        return CGPoint(
            x: 0.5 + 0.70 * reach * cos(angle),
            y: 0.5 + 0.56 * reach * sin(angle)
        )
    }

    /// An elliptical radial glow that fades to clear at `fade` of its radius.
    private func glow(color: Color, radiusX: CGFloat, radiusY: CGFloat, fade: CGFloat) -> some View {
        RadialGradient(
            stops: [.init(color: color, location: 0), .init(color: .clear, location: fade)],
            center: .center, startRadius: 0, endRadius: radiusX
        )
        .frame(width: 2 * radiusX, height: 2 * radiusX)
        .scaleEffect(x: 1, y: radiusX > 0 ? radiusY / radiusX : 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
