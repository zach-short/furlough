import SwiftUI

/// The record of the contract at the foot of the sidebar. The phone's `RecordScreen` in the
/// window's proportions; both say what `Record` says, so neither can word it differently.
struct MacRecordSection: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        MacRecordRows(card: Record.card(model.state, now: model.now))
    }
}

/// The drawing, with the numbers handed to it. Split from the section above so it can be
/// rendered to a PNG on the Mac without an app around it — see the memory note "Verify
/// Shared/UI drawing on the Mac with swiftc" — which is the only way to look at this screen
/// without running Furlough.
struct MacRecordRows: View {
    var card: Record.Card

    var body: some View {
        if !card.isEmpty {
            SectionLabel(text: "The record")
            VStack(spacing: 0) {
                row("No budget spent", Record.streakLine(card))
                CardDivider()
                row("Held shut", Record.shieldedLine(card))
                if let anchored = Record.anchoredLine(card) {
                    CardDivider()
                    row("Anchored", anchored)
                }
                CardDivider()
                row("Loosenings", Record.looseningLine(card))
                CardDivider()
                row("Longest anchor", Record.anchorLine(card))
            }
            .emberCard()
            Footnote(text: Record.rangeLine(card))
                .padding(.top, 6)
        }
    }

    /// As on the phone: a number in Geist Mono, an absence in muted body text.
    private func row(_ title: String, _ value: String) -> some View {
        let isNumber = value.contains { $0.isNumber }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .emberBody(12)
                .foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            Group {
                if isNumber {
                    Text(value).emberNumerals(12)
                } else {
                    Text(value).emberBody(12).foregroundStyle(Ember.muted)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
