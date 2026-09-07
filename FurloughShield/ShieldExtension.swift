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
        let status = target.map { Policy.status(of: $0, runtime: state.runtime, now: now) }
        let text = ShieldText.text(name: name, status: status, rule: target?.rule)

        let symbol = UIImage.SymbolConfiguration(pointSize: 72, weight: .medium)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.90, green: 0.33, blue: 0.24, alpha: 0.75),
            icon: UIImage(systemName: "hourglass", withConfiguration: symbol),
            title: ShieldConfiguration.Label(text: text.title, color: .white),
            subtitle: ShieldConfiguration.Label(text: text.subtitle, color: UIColor.white.withAlphaComponent(0.85)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .black),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: nil
        )
    }
}
