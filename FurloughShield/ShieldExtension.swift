import ManagedSettings
import ManagedSettingsUI
import UIKit

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
        let now = Date.now
        let state = SharedStore.load()
        let config = Policy.effectiveConfig(state, now: now)

        var target = kind.flatMap { config.target(kind: $0) }
        if target == nil, let token = category?.token {
            target = config.target(kind: .category(token))
        }
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

        // Ember Glass tokens (design/DESIGN.md): the shield extension cannot see Shared/UI.
        let ember = UIColor(red: 0xE5 / 255, green: 0x56 / 255, blue: 0x3D / 255, alpha: 1)
        let amber = UIColor(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x4A / 255, alpha: 1)
        let cream = UIColor(red: 0xF5 / 255, green: 0xEF / 255, blue: 0xE6 / 255, alpha: 1)
        let muted = UIColor(red: 0xB8 / 255, green: 0xAF / 255, blue: 0xA3 / 255, alpha: 1)
        let ground = UIColor(red: 0x0F / 255, green: 0x0D / 255, blue: 0x0B / 255, alpha: 1)
        let symbol = UIImage.SymbolConfiguration(pointSize: 72, weight: .medium)
        let icon = UIImage(systemName: "hourglass", withConfiguration: symbol)?
            .withTintColor(amber, renderingMode: .alwaysOriginal)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: ember.withAlphaComponent(0.22),
            icon: icon,
            title: ShieldConfiguration.Label(text: text.title, color: cream),
            subtitle: ShieldConfiguration.Label(text: text.subtitle, color: muted),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: ground),
            primaryButtonBackgroundColor: cream,
            secondaryButtonLabel: nil
        )
    }
}
