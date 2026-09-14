import ManagedSettings
import ManagedSettingsUI
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
        // Whichever path matched (app/domain or category) is the one iOS just named for us.
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
            let anchoredDirectly = kind.map { config.anchor.blocks($0, at: now) } ?? false
            let anchoredByCategory = category?.token.map { config.anchor.blocks(.category($0), at: now) } ?? false
            if anchoredDirectly || anchoredByCategory { status = .anchored }
            // Only place iOS names something anchored-but-ruleless: write it against the kind
            // so cross-device sync can show what this phone holds. `systemName`, not `learned`,
            // since `learned` may now be the category's name.
            if anchoredDirectly, let kind, let name = systemName, !name.isEmpty {
                if SharedStore.learnAnchorName(name, for: kind) {
                    SharedStore.log("learned the name of something anchored: \(name)")
                }
            }
        }
        let text = ShieldText.text(name: name, status: status, rule: target?.rule)

        // Ember Glass tokens (design/DESIGN.md); the shield's project.yml source list includes
        // Shared/Core plus the hourglass drawing/colours.
        let amber = UIColor(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x4A / 255, alpha: 1)
        let cream = UIColor(red: 0xF5 / 255, green: 0xEF / 255, blue: 0xE6 / 255, alpha: 1)
        let muted = UIColor(red: 0xB8 / 255, green: 0xAF / 255, blue: 0xA3 / 255, alpha: 1)
        // What 14% white used to composite to over the material below. Opaque on purpose: see
        // `primaryButtonBackgroundColor`.
        let pill = UIColor(red: 0x3F / 255, green: 0x3F / 255, blue: 0x3F / 255, alpha: 1)
        var glass: HourglassState?
        if let target, let status {
            glass = HourglassState.of(target, status: status, runtime: state.runtime, now: now)
        } else if status == .anchored {
            // Anchored-but-ruleless: no target for a sand level, but the anchored glass is
            // stopped anyway (anchor across the neck). Without this the shield fell through to
            // the flat SF hourglass (seen 2026-09-09).
            glass = .anchored
        }
        return ShieldConfiguration(
            // Blur only, no tint. iOS masks the blur to the screen's corner radius but fills
            // `backgroundColor` to the square window bounds, so a ground tint left the App
            // Switcher card a black square around a rounded panel (seen 2026-09-14). The tint
            // was near-invisible anyway — ground at 92% over this material lands on #0E0E0B.
            backgroundBlurStyle: .systemChromeMaterialDark,
            backgroundColor: .clear,
            icon: icon(for: glass, fallbackTint: amber),
            title: ShieldConfiguration.Label(text: text.title, color: cream),
            subtitle: ShieldConfiguration.Label(text: text.subtitle, color: muted),
            // A quiet fill, not a shouting cream pill — Close is the only action, no need to
            // fight for the eye. Opaque: iOS ignored `UIColor.white.withAlphaComponent(0.14)`
            // and drew the default system blue instead (seen 2026-09-14), while honouring every
            // opaque colour in this same configuration.
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: cream),
            primaryButtonBackgroundColor: pill,
            secondaryButtonLabel: nil
        )
    }

    /// A still frame of the glass, not the live drawing. Drawn with Core Graphics
    /// (`HourglassStill`), not the SwiftUI view: iOS asks for this off the main thread, and
    /// `ImageRenderer` is main-actor work, so it never rendered and fell back to the symbol
    /// every time (2026-09-08).
    private func icon(for glass: HourglassState?, fallbackTint: UIColor) -> UIImage? {
        // No trait environment here to read a scale from; @3x covers every device and UIKit
        // downscales for @2x.
        if let glass, let still = HourglassStill.uiImage(glass, size: CGSize(width: 132, height: 176), scale: 3) {
            return still
        }
        let symbol = UIImage.SymbolConfiguration(pointSize: 72, weight: .medium)
        return UIImage(systemName: "hourglass", withConfiguration: symbol)?
            .withTintColor(fallbackTint, renderingMode: .alwaysOriginal)
    }

    /// The shield is the only place Screen Time names an app; write it to its own key (never
    /// `state`, which the shield mustn't touch) so other surfaces can use it instead of "This app".
    private func remember(_ name: String, for target: Target) {
        guard target.systemName != name, SharedStore.learnName(name, for: target.id) else { return }
        SharedStore.log("learned a name from the shield: \(name)")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
