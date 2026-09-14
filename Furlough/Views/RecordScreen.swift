import SwiftUI

// Text comes from `Record` so the Mac's sidebar reads the same. No minutes-used figures here:
// without Screen Time's data-access entitlement, Furlough only knows whether a budget ran out,
// not how much was used. `SettingsView.recordSummary` hides this row until there's a record.
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
            digestCard
                .padding(.top, 12)
        }
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Monday morning")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer(minLength: 8)
                Toggle(
                    "Monday morning",
                    isOn: Binding(get: { model.weeklyDigest }, set: { model.setWeeklyDigest($0) })
                )
                .labelsHidden()
                .tint(Ember.ember)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Text(digestLine)
                .emberBody(11.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .emberCard()
    }

    private var digestLine: String {
        guard model.weeklyDigest else { return "These numbers stay on this screen." }
        let allowed = model.notificationsGranted == true
        let week = "The last seven days, as a notification on Monday at \(TimeFormat.minute(Furlough.digestHour * 60))."
        return allowed ? week : "\(week) Notifications are off, so nothing will arrive until they are allowed."
    }

    // Numeric values render in Geist Mono; placeholder sentences stay muted body text.
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
