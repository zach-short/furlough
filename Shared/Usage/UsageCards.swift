import SwiftUI

/// The pictures a usage card is made of, drawn the same way wherever the numbers come from.
/// The phone app has them in hand on iOS 26.4 (`UsageReader.hasDataAccess`) and draws these
/// itself; everywhere else only the report extension ever sees a number, and it draws the very
/// same shapes inside its sandbox. Nothing here reaches for Screen Time: give it a histogram
/// and a `Recommendation` and it draws.

/// What the app and the report extension agree a hosted card measures. A report cannot tell
/// its host how tall it wants to be, so the height is settled here instead of guessed twice:
/// room for two rows of bars, two strips, and two lines of prose at each of the two places
/// prose appears. Content is top-aligned, so a shorter card simply leaves space.
enum UsageReportFrame {
    static let height: CGFloat = 380
}

/// Where the time goes: an average day hour by hour, with the hours a rule would close lit in
/// ember and banded behind, so the closure reads as one stretch and not as scattered bars.
/// `tallest` is the minutes the full height stands for; two rows given the same one compare
/// honestly, which is the whole point of showing weekdays beside weekends.
struct HourBars: View {
    let hourly: [Double]
    let closed: Set<Int>
    var tallest: Double
    var height: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 24
            let width = max(2, unit - 2.5)
            let scale = max(tallest, 1)
            ZStack(alignment: .bottomLeading) {
                ForEach(UsageAnalysis.runs(of: closed), id: \.self) { run in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Ember.ember.opacity(0.15))
                        .frame(width: unit * CGFloat(run.count), height: geometry.size.height)
                        .offset(x: unit * CGFloat(run.lowerBound))
                }
                ForEach(0..<24, id: \.self) { hour in
                    Capsule()
                        .fill(closed.contains(hour) ? Ember.ember : Ember.cream.opacity(0.32))
                        .frame(width: width, height: max(2, geometry.size.height * CGFloat(hourly[hour] / scale)))
                        .offset(x: unit * CGFloat(hour) + (unit - width) / 2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
        }
        .frame(height: height)
    }
}

/// Midnight, 6, noon, 6 under a set of bars, so the shape above has a clock to sit on.
struct HourAxis: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(TimeFormat.hour(hour * 60))
                if hour != 18 { Spacer(minLength: 0) }
            }
        }
        .font(EmberFont.label(9))
        .foregroundStyle(Ember.faint)
    }
}

/// The whole "where" picture: one row of bars, or weekdays above weekends when the suggestion
/// tells them apart, both on one scale, with the clock beneath.
struct UsageHours: View {
    let histogram: UsageHistogram
    let item: Recommendation?

    private var rows: [UsageRow] { UsageRow.rows(for: item) }

    /// The busiest hour on any row drawn: the height every row is measured against.
    private var tallest: Double {
        rows.map { histogram.hourlyAverage(on: $0.days).max() ?? 0 }.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(rows) { row in
                if rows.count > 1 {
                    Eyebrow(text: row.label, color: Ember.faint, size: 9)
                }
                HourBars(
                    hourly: histogram.hourlyAverage(on: row.days),
                    closed: row.closed,
                    tallest: tallest,
                    height: rows.count > 1 ? 32 : 44
                )
            }
            HourAxis()
        }
    }
}

/// One day as a 24-hour strip: cream where the rule lets the app open, ember where it closes
/// it. The rule as a picture, which is the only form of it anybody reads at a glance. Named
/// for its hours, not its days: the rule editor's `DayStrip` is the row of seven day toggles.
struct HourStrip: View {
    let closed: Set<Int>
    var height: CGFloat = 13

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 24
            ZStack(alignment: .leading) {
                Rectangle().fill(Ember.cream.opacity(0.18))
                ForEach(UsageAnalysis.runs(of: closed), id: \.self) { run in
                    Rectangle()
                        .fill(Ember.ember)
                        .frame(width: unit * CGFloat(run.count))
                        .offset(x: unit * CGFloat(run.lowerBound))
                }
                ForEach([6, 12, 18], id: \.self) { hour in
                    Rectangle()
                        .fill(Ember.ground.opacity(0.5))
                        .frame(width: 1)
                        .offset(x: unit * CGFloat(hour))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// What Furlough would do, drawn: a strip per group of days with the budget beside it, then
/// the one line that says it in words.
struct RuleDrawing: View {
    let item: Recommendation
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(UsageRow.rows(for: item)) { row in
                HStack(spacing: 10) {
                    Eyebrow(text: row.label, color: Ember.faint, size: 9)
                        .frame(width: 62, alignment: .leading)
                    HourStrip(closed: row.closed)
                }
            }
            HStack(spacing: 8) {
                Text(TimeFormat.budget(item.rule.dailyBudgetMinutes))
                    .emberNumerals(12)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Ember.cream.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Ember.cardBorder, lineWidth: 1))
                Text(item.isBudgetOnly ? "whenever you like" : "across the open hours")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.faint)
            }
            Text(item.consequence(calendar: calendar))
                .emberBody(13)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
