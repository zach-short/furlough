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
    static let cardFill = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.12)
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 9
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
    /// Onest Bold, meant for uppercase eyebrows with `.tracking(1.4)`.
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

/// The background behind every screen: a warm dark ground with one ember glow low on the left.
struct EmberWall: View {
    var body: some View {
        ZStack {
            Ember.ground
            RadialGradient(
                colors: [Ember.ember.opacity(0.6), .clear],
                center: UnitPoint(x: 0.28, y: 1.04), startRadius: 0, endRadius: 340
            )
            RadialGradient(
                colors: [Ember.amber.opacity(0.14), .clear],
                center: UnitPoint(x: 0.9, y: -0.04), startRadius: 0, endRadius: 280
            )
        }
        .ignoresSafeArea()
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
