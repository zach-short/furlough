import SwiftUI

/// "You have one half of this." Shown on a target whose other half — the site an app is also
/// at, or the app a site is also in — is not in Furlough.
///
/// This is the phone's version of the Mac's `CompanionSheet`. Which of the two halves is
/// missing decides how much it can do. A missing **site** is added outright by its Add button,
/// because since 2026-09-08 a site on the phone is a name like it is on the Mac. A missing
/// **app** still has to be a nudge and not an offer: a Screen Time token is minted inside
/// Apple's picker and nowhere else, so all this can do there is say what is missing and open
/// the way to it.
///
/// It arrives late on a picked target — a token says nothing about what it is until the shield
/// learns a name — which is why it lives on the target rather than at the moment of adding. On
/// a typed host it arrives at once, because that one names itself. Dismissed once is dismissed
/// for good on that target: a nudge that comes back is a nag.
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
