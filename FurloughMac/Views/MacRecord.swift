import SwiftUI

struct MacRecordSection: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        MacRecordRows(card: Record.card(model.state, now: model.now))
    }
}

/// Split out so it can render to PNG via swiftc, without the full app.
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
