import SwiftUI

/// The heaviest few, each with where its time piles up and the rule that would take it back.
/// Drawn on Furlough's own dark card whatever the host paints behind it.
struct CutbackView: View {
    let summary: UsageSummary

    private var advice: [Recommendation] { summary.recommendations }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(text: "Where the time goes")
                Spacer()
                if summary.totalDays > 0 {
                    Eyebrow(text: "\(summary.totalDays) days · \(TimeFormat.budget(Int(summary.totalMinutesPerDay.rounded())))/day")
                }
            }
            if advice.isEmpty {
                Text(summary.entries.isEmpty
                    ? "Screen Time has nothing for this stretch yet."
                    : "Nothing here passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day. Nothing to cut.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
            } else {
                ForEach(advice) { item in
                    RecommendationRow(item: item)
                    if item.id != advice.last?.id {
                        Divider().overlay(Ember.cardBorder)
                    }
                }
                Text("Only this card sees these numbers; Furlough does not. Open an app's rule below and type its suggestion in.")
                    .emberBody(11)
                    .foregroundStyle(Ember.faint)
            }
        }
        .padding(16)
        .reportCard()
    }
}

/// One line of advice: the name, the daily average, where it piles up, and the rule.
struct RecommendationRow: View {
    let item: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .emberDisplaySmall(17)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Spacer()
                Text("\(TimeFormat.budget(Int(item.averageDailyMinutes.rounded())))/day")
                    .emberNumerals(13)
            }
            Text(Self.whereItGoes(item))
                .emberBody(13)
                .foregroundStyle(Ember.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Eyebrow(text: "Suggested", color: Ember.amber)
                Text(TimeFormat.rule(item.rule))
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
            }
            if item.lateNightShare >= 0.5 {
                Eyebrow(text: "Mostly late at night", color: Ember.ember)
            }
        }
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
        .reportCard()
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
