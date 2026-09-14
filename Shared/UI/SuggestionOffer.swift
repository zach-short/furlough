import SwiftUI

/// Deliberately the quietest thing on the card — an offer that argues is a default in
/// disguise, and must be as easy to ignore as to take. Distinct from the banners above Save,
/// which state what an edit *will* do.
///
/// Lives here because both rule editors show it and the widget extensions compile it too — no
/// `SectionLabel`/`Footnote`/`CardDivider`.
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
