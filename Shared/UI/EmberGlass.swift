import SwiftUI

/// Liquid Glass shim: real glass on iOS/macOS 26+, an Ember Glass material recreation below
/// that (IPHONEOS_DEPLOYMENT_TARGET / MACOSX_DEPLOYMENT_TARGET floor is 18.0 / 15.0) so the
/// two ~7000 unsupported OS versions in between still see something that reads as glass rather
/// than a flat system default. No third-party dependency: the options either reimplement
/// private UIKit internals (App Review risk, and iOS-only — no AppKit story for FurloughMac) or
/// are this same Material-plus-highlight recipe, so it's written in-house once, here.
extension View {
    /// Stand-in for `.glassEffect(.regular, in:)` / `.glassEffect(.regular.interactive(), in:)`.
    @ViewBuilder
    func emberGlass(interactive: Bool = false, in shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(EmberGlassStyle.rim, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
    }

    /// Stand-in for `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`, `.tint(_:)`
    /// folded in: SwiftUI's own tint environment key isn't public, so a custom `ButtonStyle`
    /// can't read an ambient `.tint(_:)` the way the native glass styles do. `.controlSize(_:)`
    /// applied anywhere in the same modifier chain still reaches it, same as the native styles.
    @ViewBuilder
    func emberGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                if let tint { buttonStyle(.glassProminent).tint(tint) } else { buttonStyle(.glassProminent) }
            } else {
                if let tint { buttonStyle(.glass).tint(tint) } else { buttonStyle(.glass) }
            }
        } else {
            buttonStyle(EmberGlassButtonStyle(prominent: prominent, tint: tint ?? .accentColor))
        }
    }
}

/// Stand-in for `GlassEffectContainer`: real union/morph behavior on 26+, a plain pass-through
/// below it since nothing pre-26 can merge separate glass shapes anyway.
struct EmberGlassEffectContainer<Content: View>: View {
    var spacing: CGFloat
    var content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private enum EmberGlassStyle {
    /// Top-left to bottom-right highlight, the way light catches a curved glass edge.
    static let rim = LinearGradient(
        colors: [.white.opacity(0.55), .white.opacity(0.06)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

private struct EmberGlassButtonStyle: ButtonStyle {
    var prominent: Bool
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private var padding: (h: CGFloat, v: CGFloat) {
        switch controlSize {
        case .mini: (8, 4)
        case .small: (10, 6)
        case .large: (18, 10)
        case .extraLarge: (22, 12)
        default: (14, 8)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, padding.h)
            .padding(.vertical, padding.v)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(prominent ? 0.55 : 0.12)))
                    .overlay(Capsule().strokeBorder(EmberGlassStyle.rim, lineWidth: 1))
            )
            .shadow(color: .black.opacity(prominent ? 0.3 : 0.15), radius: prominent ? 6 : 3, y: 2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
