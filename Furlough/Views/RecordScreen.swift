import SwiftUI

/// The record of the contract, behind Settings' menu: days without a budget spent, time held
/// shut this week, loosenings cancelled against loosenings landed, and the longest the Anchor
/// has held.
///
/// Every sentence comes from `Record`, so the Mac's sidebar says the same words. Nothing here
/// is celebratory: a streak that broke says so, and the numbers the phone cannot see — minutes
/// actually *used* — are not here at all, because without Screen Time's data-access
/// entitlement Furlough only knows whether a budget ran out, not how much of it went.
///
/// How far back the counts go was the footnote under the card; it is the lead now, so it is read
/// before the numbers rather than after them. The menu leaves the row out entirely until there
/// is a record — see `SettingsView.recordSummary` — so a fresh install never opens an empty one.
struct RecordScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let card = Record.card(model.state, now: model.state.now)
        AnchorSettingScreen(title: "The record", lead: Record.rangeLine(card)) {
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
        }
    }

    /// A number is set in Geist Mono, as every number that counts is; a sentence saying there
    /// is no number yet is body text, and muted, so the card does not shout an absence.
    private func row(_ title: String, _ value: String) -> some View {
        let isNumber = value.contains { $0.isNumber }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            Group {
                if isNumber {
                    Text(value).emberNumerals(13)
                } else {
                    Text(value).emberBody(13).foregroundStyle(Ember.muted)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}
