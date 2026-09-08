import SwiftUI

/// One slot of the ranking, in a frame the app fixed: the row for that position, or, in the
/// first empty slot, a line saying the list ended. Every text is allowed its lines and the
/// whole thing sits at the top, so nothing is squeezed to fit or centred out of view.
struct RankView: View {
    let slot: RankSlot

    var body: some View {
        Group {
            if let item = slot.item {
                RecommendationRow(item: item)
                    .padding(14)
                    .reportCard()
            } else if slot.position == slot.count + 1 {
                Text(slot.count == 0
                    ? "Nothing on this phone passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day in the last \(slot.days) days."
                    : "Nothing else passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day.")
                    .emberBody(12)
                    .foregroundStyle(Ember.faint)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One line of advice: the name, the daily average, where it piles up, and the rule. Sized
/// for the app's fixed slot: two lines for where, three for the rule.
struct RecommendationRow: View {
    let item: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .emberDisplaySmall(17)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("\(TimeFormat.budget(Int(item.averageDailyMinutes.rounded())))/day")
                    .emberNumerals(13)
                    .lineLimit(1)
            }
            Text(Self.whereItGoes(item))
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Eyebrow(text: "Suggested", color: Ember.amber)
                    if item.lateNightShare >= 0.5 {
                        Eyebrow(text: "Mostly late at night", color: Ember.ember)
                    }
                }
                Text(TimeFormat.rule(item.rule))
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Mostly 10:00 PM–1:00 AM weekdays; 2:00 PM–3:00 PM weekends, 14 pickups a day."
    static func whereItGoes(_ item: Recommendation) -> String {
        let pickups = "\(Int(item.pickupsPerDay.rounded())) pickups a day"
        guard !item.peaks.isEmpty else { return "Spread across the day, \(pickups)." }
        let piles = item.peaks
            .map { "\(TimeFormat.window($0.window)) \(TimeFormat.days($0.days).lowercased())" }
            .joined(separator: "; ")
        return "Mostly \(piles), \(pickups)."
    }
}

/// One thing's average day, hour by hour, with the hours a rule would close lit in ember.
struct FocusView: View {
    let summary: UsageSummary

    private var entry: UsageEntry? {
        summary.entries.max { $0.histogram.totalMinutes < $1.histogram.totalMinutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let entry {
                let advice = UsageAnalysis.recommendation(key: entry.key, name: entry.name, histogram: entry.histogram)
                let closed = Set(advice?.peaks.flatMap { UsageAnalysis.hours(of: $0.window) } ?? [])
                HStack(alignment: .firstTextBaseline) {
                    Text("\(TimeFormat.budget(Int(entry.histogram.averageDailyMinutes.rounded()))) a day")
                        .emberNumerals(13)
                    Spacer()
                    Eyebrow(text: "\(Int(entry.histogram.pickupsPerDay.rounded())) pickups · \(summary.totalDays) days")
                }
                HourBars(hourly: entry.histogram.hourlyAverage(on: .all), closed: closed)
                if let advice {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Eyebrow(text: "Suggested", color: Ember.amber)
                        Text(TimeFormat.rule(advice.rule))
                            .emberBody(12)
                            .foregroundStyle(Ember.cream)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Under \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day. Nothing to cut.")
                        .emberBody(12)
                        .foregroundStyle(Ember.muted)
                }
            } else {
                Text("No use in this stretch.")
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reportCard()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Twenty-four bars, tallest to the busiest hour; the closed ones in ember.
struct HourBars: View {
    let hourly: [Double]
    let closed: Set<Int>

    var body: some View {
        let tallest = max(hourly.max() ?? 0, 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(closed.contains(hour) ? Ember.ember : Ember.cream.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, 48 * (hourly[hour] / tallest)))
                }
            }
            .frame(height: 48, alignment: .bottom)
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(TimeFormat.shortMinute(hour * 60))
                    if hour != 18 { Spacer() }
                }
            }
            .font(EmberFont.label(9))
            .foregroundStyle(Ember.faint)
        }
    }
}

extension View {
    /// Furlough's card over its own ground, so the text reads whatever the host paints behind
    /// the report.
    func reportCard() -> some View {
        background(Ember.ground.opacity(0.92), in: RoundedRectangle(cornerRadius: Ember.cardRadius, style: .continuous))
            .emberCard()
    }
}
