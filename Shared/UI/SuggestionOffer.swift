import SwiftUI

/// The one shape a suggestion takes on screen: a sparkle, a sentence in the quiet colour, and a
/// tap that takes it.
///
/// Deliberately the smallest thing on the card. Everything Furlough guesses — the tier, a
/// starting rule, a name the tables know — is offered this way and no louder, because an offer
/// that argues is a default in disguise: it has to be as easy to read past as it is to take. The
/// banners above Save are for what an edit *will* do, and this is never that.
///
/// It lives in `Shared/UI` because both rule editors show it, which means the widget extensions
/// compile it too: nothing here may reach for `SectionLabel`, `Footnote` or `CardDivider`.
struct SuggestionOffer: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                Text(text)
                    .emberBody(11, .semibold)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Ember.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
