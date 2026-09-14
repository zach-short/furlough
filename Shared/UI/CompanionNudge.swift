import SwiftUI

/// "You have one half of this." Phone counterpart to the Mac's `CompanionSheet`. A missing
/// site can be added directly (it's just a name); a missing app can't — its Screen Time token
/// only comes from Apple's picker, so this can only nudge toward it. Appears late on a picked
/// target because a token has no name until the shield resolves it; dismissal is permanent
/// per target.
struct CompanionNudge: View {
    let companion: Companions.Half
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 1)
                Text(text)
                    .emberBody(12, .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Ember.amber)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(action: onAdd) {
                    Text(addTitle)
                        .emberBody(12.5, .semibold)
                        .foregroundStyle(Ember.ground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Ember.amber, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onDismiss) {
                    Text("Not now")
                        .emberBody(12.5, .semibold)
                        .foregroundStyle(Ember.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Ember.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ember.amber.opacity(0.35), lineWidth: 1)
        )
    }

    private var symbol: String {
        switch companion {
        case .sites: "globe"
        case .app: "square.grid.2x2.fill"
        }
    }

    private var text: String {
        switch companion {
        case .sites(let hosts) where hosts.count == 1:
            "\(hosts[0]) is the same thing in a browser tab. Blocked together, there is no back door."
        case .sites(let hosts):
            "\(UtilityText.list(hosts)) are the same thing in a browser tab. Blocked together, there is no back door."
        case .app(let name):
            "The \(name) app is the same thing without the browser. Blocked together, there is no back door."
        }
    }

    private var addTitle: String {
        switch companion {
        case .sites(let hosts): hosts.count == 1 ? "Add the website" : "Add the websites"
        case .app: "Add the app"
        }
    }
}
