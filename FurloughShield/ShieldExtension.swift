import ManagedSettings
import ManagedSettingsUI
import SwiftUI
import UIKit
import WidgetKit

/// Draws the screen iOS shows over a blocked app or site.
final class ShieldExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(kind: application.token.map(TargetKind.application), systemName: application.localizedDisplayName, category: nil)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(kind: application.token.map(TargetKind.application), systemName: application.localizedDisplayName, category: category)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(kind: webDomain.token.map(TargetKind.webDomain), systemName: webDomain.domain, category: nil)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(kind: webDomain.token.map(TargetKind.webDomain), systemName: webDomain.domain, category: category)
    }

    private func make(kind: TargetKind?, systemName: String?, category: ActivityCategory?) -> ShieldConfiguration {
        let state = SharedStore.load()
        let now = state.now
        let config = Policy.effectiveConfig(state, now: now)

        var target = kind.flatMap { config.target(kind: $0) }
        // Whichever of the two matched is the one iOS has just named for us.
        var learned = systemName
        if target == nil, let token = category?.token {
            target = config.target(kind: .category(token))
            learned = category?.localizedDisplayName
        }
        if let target, let learned { remember(learned, for: target) }
        let nickname = target?.nickname ?? ""
        let name = nickname.isEmpty ? (systemName ?? "This app") : nickname
        var status = target.map { Policy.status(of: $0, config: config, runtime: state.runtime, now: now) }
        if status == nil {
            // Things the anchor holds that are not targets, directly or through their category.
            let anchoredDirectly = kind.map(config.anchor.blocks) ?? false
            let anchoredByCategory = category?.token.map { config.anchor.blocks(.category($0)) } ?? false
            if anchoredDirectly || anchoredByCategory { status = .anchored }
        }
        let text = ShieldText.text(name: name, status: status, rule: target?.rule)

        // Ember Glass tokens (design/DESIGN.md). The shield sees Shared/Core, plus the
        // hourglass drawing and its colours, which are on its source list in project.yml.
        let amber = UIColor(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x4A / 255, alpha: 1)
        let cream = UIColor(red: 0xF5 / 255, green: 0xEF / 255, blue: 0xE6 / 255, alpha: 1)
        let muted = UIColor(red: 0xB8 / 255, green: 0xAF / 255, blue: 0xA3 / 255, alpha: 1)
        let ground = UIColor(red: 0x0F / 255, green: 0x0D / 255, blue: 0x0B / 255, alpha: 1)
        var glass: HourglassState?
        if let target, let status {
            glass = HourglassState.of(target, status: status, runtime: state.runtime, now: now)
        }
        return ShieldConfiguration(
            // The app's own ground over the most opaque dark material: the shield reads as a
            // Furlough screen, not as a smear of whatever it is covering.
            backgroundBlurStyle: .systemChromeMaterialDark,
            backgroundColor: ground.withAlphaComponent(0.92),
            icon: icon(for: glass, fallbackTint: amber),
            title: ShieldConfiguration.Label(text: text.title, color: cream),
            subtitle: ShieldConfiguration.Label(text: text.subtitle, color: muted),
            // The card fill from the app, not a shouting cream pill: Close is the only thing
            // here, so it does not have to fight for the eye.
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: cream),
            primaryButtonBackgroundColor: UIColor.white.withAlphaComponent(0.14),
            secondaryButtonLabel: nil
        )
    }

    /// The icon slot takes a UIImage, so the glass is the app's own view rendered to one still
    /// frame: the same drawing, at the sand level this rule has reached, without the timeline.
    /// `ImageRenderer` is main-actor work and iOS calls us on the main thread, but a shield
    /// that throws is a shield the user never sees, so anything else falls back to the symbol.
    private func icon(for glass: HourglassState?, fallbackTint: UIColor) -> UIImage? {
        if let glass, Thread.isMainThread {
            return MainActor.assumeIsolated { Self.still(glass) }
        }
        let symbol = UIImage.SymbolConfiguration(pointSize: 72, weight: .medium)
        return UIImage(systemName: "hourglass", withConfiguration: symbol)?
            .withTintColor(fallbackTint, renderingMode: .alwaysOriginal)
    }

    @MainActor
    private static func still(_ glass: HourglassState) -> UIImage? {
        let renderer = ImageRenderer(
            content: HourglassView(state: glass, phase: 0, motion: false)
                .frame(width: 132, height: 176)
        )
        // No view context out here to read a trait from, and the slot is small: @3x covers
        // every device that draws a shield, and UIKit takes it down on a @2x screen.
        renderer.scale = 3
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// The shield is the one place Screen Time tells us what an app is called; everywhere else
    /// a token is opaque. Write the name down — in its own key, never the state, which the
    /// shield must not touch — so the widget, the notifications and the Live Activity can say
    /// it instead of "This app".
    private func remember(_ name: String, for target: Target) {
        guard target.systemName != name, SharedStore.learnName(name, for: target.id) else { return }
        SharedStore.log("learned a name from the shield: \(name)")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
