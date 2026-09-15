import SwiftUI

/// What this Mac measured, at the foot of the sidebar beside The record.
///
/// The two cards are next to each other and must never be read as one number: the record is
/// minutes held **shut**, over sixty days; this is minutes **used**, over a fortnight. Each says
/// which it is, in its own words and its own range line.
struct MacUsageSection: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        MacUsageRows(
            history: model.enforcer.measured,
            order: model.state.config.targets.map(\.id),
            name: { id in model.state.config.target(id: id)?.displayName ?? "Something removed" },
            kind: { id in model.state.config.target(id: id)?.kind },
            now: model.now
        )
    }
}

/// Split out the way `MacRecordRows` is: hand it numbers and it draws, with no app around it.
struct MacUsageRows: View {
    var history: UsageHistory
    /// The ids worth showing, in the config's own order — so something deleted last week does
    /// not come back as a row with no name.
    var order: [UUID]
    var name: (UUID) -> String
    var kind: (UUID) -> TargetKind?
    var now: Date

    var body: some View {
        let totals = history.totals(for: order)
        if !totals.isEmpty {
            SectionLabel(text: "What this Mac counted")
            VStack(spacing: 0) {
                UsageDayStrip(bars: history.bars(upTo: now))
                    .padding(.horizontal, 12)
                    .padding(.top, 11)
                    .padding(.bottom, 9)
                CardDivider()
                ForEach(Array(totals.enumerated()), id: \.element.id) { index, total in
                    if index > 0 { CardDivider() }
                    row(total)
                }
                CardDivider()
                HStack {
                    Text("In all")
                        .emberBody(12, .semibold)
                        .foregroundStyle(Ember.cream)
                    Spacer(minLength: 8)
                    Text(TimeFormat.budget(history.totalMinutes))
                        .emberNumerals(12)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .emberCard()
            Footnote(text: "\(history.rangeLine) Time in front of an app or a site, with the Mac awake — not time held shut, which is the record above.")
                .padding(.top, 6)
        }
    }

    private func row(_ total: UsageHistory.Total) -> some View {
        HStack(spacing: 10) {
            if let kind = kind(total.targetID) {
                KindTile(kind: kind, size: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name(total.targetID))
                    .emberBody(12)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                // A bar against the busiest row rather than a fixed ceiling — the same choice
                // the menu bar's trend makes, for the same lack of a natural maximum.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ember.cream.opacity(0.07))
                        Capsule()
                            .fill(Ember.amber.opacity(0.75))
                            .frame(width: max(2, geometry.size.width * total.fraction))
                    }
                }
                .frame(height: 3)
            }
            Spacer(minLength: 8)
            Text(TimeFormat.budget(total.minutes))
                .emberNumerals(12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The fortnight as one strip: a bar a day, oldest first, today last and amber. No weekday
/// letters — fourteen of them in a 340pt sidebar is a smudge — so the range line under the card
/// is what says how far back it goes. Named apart from the rule editors' `DayStrip`, which is
/// the row of seven weekday toggles.
struct UsageDayStrip: View {
    var bars: [UsageHistory.DayBar]
    var height: CGFloat = 26

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(bars) { bar in
                Capsule(style: .continuous)
                    .fill(Ember.cream.opacity(0.06))
                    .frame(height: height)
                    .overlay(alignment: .bottom) {
                        Capsule(style: .continuous)
                            .fill(bar.isToday ? Ember.amber : Ember.ember.opacity(0.85))
                            .frame(height: max(bar.fraction * height, bar.minutes > 0 ? 2 : 0))
                    }
            }
        }
        .frame(height: height)
    }
}
