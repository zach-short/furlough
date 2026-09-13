import SwiftUI

/// Where to leave the tag, shown once, straight after the first one pairs.
///
/// The whole mechanism leans on the tag being somewhere else. Pairing teaches how to read one
/// and says nothing about where it then lives, and a key on the same keyring as the phone is
/// not a lock at all — it is a button with an extra step. So this is the one screen that says
/// so, at the only moment a person is holding the tag and has not yet put it down.
///
/// Guidance, not a feature: no checkboxes, nothing tracked, nothing written to `Config`. The
/// only state anywhere is the app-side flag that keeps it to a first pairing
/// (`AppModel.hasSeenTagPlacement`), beside the other "what has been shown" flags.
struct TagPlacementView: View {
    /// The name the tag was just given, when there is one, so the screen speaks about the key
    /// in hand rather than about tags in general. Nil where it is read later, from the Tags
    /// screen, about no tag in particular.
    var tagName: String?

    @Environment(\.dismiss) private var dismiss
    /// The sheet hugs its content, seeded near the real height so it does not resize on open.
    @State private var contentHeight: CGFloat = 560

    /// Four places, each a different kind of distance: a walk, a commute, another person, a
    /// journey. Concrete on purpose — "somewhere inconvenient" is advice nobody acts on.
    private static let places: [(symbol: String, title: String, detail: String)] = [
        (
            "archivebox",
            "A drawer at home",
            "For a phone that should be quiet while you are out. The walk back is the whole of it."
        ),
        (
            "briefcase",
            "At work, or in a locker",
            "For getting your evenings back. The key sits behind a commute until morning."
        ),
        (
            "person.2",
            "With someone you live with",
            "A housemate's bag, a partner's coat pocket. Having to ask out loud is the friction."
        ),
        (
            "bicycle",
            "Somewhere with a journey attached",
            "The bottom of a bike pannier, a jar in the garage, a box you posted to yourself."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AnchorGlyph(isAnchored: false, size: 56)
                Text("Where to leave it")
                    .emberDisplay(26)
                    .foregroundStyle(Ember.cream)
                    .padding(.top, 18)
                Text(lead)
                    .emberBody(14.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(Array(Self.places.enumerated()), id: \.offset) { index, place in
                        if index > 0 { CardDivider() }
                        PlaceRow(symbol: place.symbol, title: place.title, detail: place.detail)
                    }
                }
                .emberCard()
                .padding(.top, 20)
                ProminentButton(title: "Got it") { dismiss() }
                    .padding(.top, 22)
                Footnote(
                    text: "Not your keyring and not your wallet: a tag you carry is a button, not a lock.",
                    alignment: .center
                )
                .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(EmberWall())
        .presentationBackground(Ember.ground)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    /// Why the place matters, in one sentence, which is the site's own reason for a tag over a
    /// code: a code can be photographed and a tag cannot, so the key is one object in one
    /// place — and which place that is decides whether the Anchor is a lock or a formality.
    private var lead: String {
        let paired = tagName.map { "\($0) is paired." } ?? "Your tag is paired."
        return "\(paired) A code could be photographed and kept in your camera roll; a tag cannot be copied that way, "
            + "so the key is one physical object in one place. Which place decides whether the Anchor is a lock or a formality."
    }
}

/// One place: its mark, what it is, and what kind of distance it buys.
private struct PlaceRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HelpTile(symbol: symbol, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .emberDisplaySmall(14)
                    .foregroundStyle(Ember.cream)
                Text(detail)
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}
