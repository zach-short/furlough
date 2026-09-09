import AppIntents
import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let summary: Policy.Summary
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(
            date: .now,
            summary: Policy.Summary(openNames: ["Instagram"], openUntil: .now.addingTimeInterval(3600), blockedCount: 3)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, summary: Policy.summary(state: SharedStore.load(), now: .now)))
    }

    /// One entry per status change over the next day and a half, plus one every three
    /// minutes while a window or an all-day app is open so the hourglass keeps draining.
    /// Entries are free; only reloads count against the widget budget.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let state = SharedStore.load()
        let clock = state.clock()
        var entries: [StatusEntry] = []
        // The cursor runs on Furlough's own time, because that is what decides the timeline;
        // each entry is then dated on the device's clock, because that is what WidgetKit
        // compares against, and its summary moved with it so the countdowns read right.
        var cursor = clock.now
        let horizon = cursor.addingTimeInterval(36 * 3600)
        while entries.count < 200, cursor < horizon {
            let summary = Policy.summary(state: state, now: cursor)
            entries.append(StatusEntry(date: clock.device(cursor), summary: summary.shifted(by: clock.drift)))
            let config = Policy.effectiveConfig(state, now: cursor)
            let next = Policy.nextTransition(config: config, after: cursor)
            guard next > cursor else { break }
            let draining = summary.openUntil != nil || !summary.allDayNames.isEmpty
            let step = draining ? min(next, cursor.addingTimeInterval(180)) : next
            cursor = step == next ? next.addingTimeInterval(1) : step
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}


struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        if family == .accessoryRectangular {
            accessory
                .containerBackground(.clear, for: .widget)
        } else {
            home
                .containerBackground(for: .widget) { EmberWall() }
        }
    }

    /// Home-screen sizes: eyebrow, name in Display, countdown or next time in Geist Mono, detail,
    /// and the status hourglass in the bottom corner.
    ///
    /// The glass is laid over the corner rather than given a column of its own: in the small
    /// widget a column left the text 87 points, which cut "tmrw 1:00 AM" to "tmrw 1…" and
    /// three names to "YouT…". Only the status lines at the bottom share a row with it, and
    /// they keep clear of it with trailing padding.
    private var home: some View {
        homeText
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                HourglassView(state: .of(entry.summary, now: entry.date))
                    .frame(width: 30, height: 40)
            }
            .overlay(alignment: .topTrailing) {
                // The medium widget has room for one action, and there is only one Furlough
                // allows from a widget: dropping the anchor, which can only tighten. It runs
                // the same intent Control Center does, in this extension; release stays in the
                // app behind the tag.
                if family == .systemMedium, entry.summary.canDropAnchor {
                    Button(intent: DropAnchorIntent()) {
                        HStack(spacing: 5) {
                            Image("anchor")
                                .font(.system(size: 10, weight: .bold))
                            Text("Anchor")
                                .emberBody(11, .bold)
                        }
                        .foregroundStyle(Ember.cream)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Ember.ember.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
    }

    private var homeText: some View {
        let summary = entry.summary
        let windowOpen = summary.openUntil.map { $0 > entry.date && !summary.openNames.isEmpty } ?? false
        let allDayOnly = !windowOpen && summary.nextOpenAt == nil && !summary.allDayNames.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            if windowOpen, let until = summary.openUntil {
                Eyebrow(text: "Open now", color: Ember.amber)
                name(headline(summary.openNames))
                Text(timerInterval: entry.date...until, countsDown: true)
                    .emberNumerals(22)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                detail("until \(until.formatted(date: .omitted, time: .shortened))")
            } else if let next = summary.nextOpenAt {
                Eyebrow(text: nextEyebrow(next), color: Ember.amber)
                name(headline(summary.nextOpenNames))
                Text(next.formatted(date: .omitted, time: .shortened))
                    .emberNumerals(22)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                if let budget = summary.nextOpenBudgetMinutes {
                    detail("\(TimeFormat.budget(budget)) budget")
                } else {
                    detail("\(summary.blockedCount) blocked")
                }
            } else if allDayOnly {
                Eyebrow(text: "Open all day", color: Ember.moss)
                name(headline(summary.allDayNames))
                detail("budget resets at midnight")
            } else if summary.isEmpty {
                Eyebrow(text: "Furlough", color: Ember.amber)
                name("Nothing managed")
                detail("Open Furlough to add apps.")
            } else {
                Eyebrow(text: "Blocked", color: Ember.muted)
                name("All blocked")
                detail("\(summary.blockedCount) blocked all day")
            }
            Spacer(minLength: 0)
            Group {
                if !summary.allDayNames.isEmpty, !allDayOnly {
                    Text("\(headline(summary.allDayNames)) open all day")
                        .emberBody(10.5, .semibold)
                        .foregroundStyle(Ember.moss)
                        .lineLimit(1)
                }
                if summary.isAnchored {
                    Text(anchoredLine(summary))
                        .emberBody(10.5, .semibold)
                        .foregroundStyle(Ember.ember)
                }
                if summary.pendingCount > 0 {
                    Text("\(summary.pendingCount) change\(summary.pendingCount == 1 ? "" : "s") pending")
                        .emberBody(10.5, .semibold)
                        .foregroundStyle(Ember.pending)
                }
            }
            .padding(.trailing, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock-screen rectangle: the system tints it, so only the type carries the look.
    private var accessory: some View {
        let summary = entry.summary
        return VStack(alignment: .leading, spacing: 1) {
            if let until = summary.openUntil, !summary.openNames.isEmpty, until > entry.date {
                Text(headline(summary.openNames))
                    .font(EmberFont.displaySmall(14))
                    .lineLimit(1)
                Text(timerInterval: entry.date...until, countsDown: true)
                    .font(EmberFont.numerals(16))
                    .monospacedDigit()
                Text("until \(until.formatted(date: .omitted, time: .shortened))")
                    .font(EmberFont.body(11))
            } else if let next = summary.nextOpenAt {
                Text(headline(summary.nextOpenNames))
                    .font(EmberFont.displaySmall(14))
                    .lineLimit(1)
                Text(accessoryNext(next))
                    .font(EmberFont.numerals(14))
                    .monospacedDigit()
            } else if !summary.allDayNames.isEmpty {
                Text(headline(summary.allDayNames))
                    .font(EmberFont.displaySmall(14))
                    .lineLimit(1)
                Text("open all day")
                    .font(EmberFont.body(11))
            } else {
                Text("Furlough")
                    .font(EmberFont.displaySmall(14))
                Text(summary.isEmpty ? "Nothing managed" : "All blocked")
                    .font(EmberFont.body(11))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .emberDisplay(15)
            .foregroundStyle(Ember.cream)
            .lineLimit(family == .systemSmall ? 1 : 2)
            .padding(.top, 3)
    }

    /// One name and a count rather than a list cut off mid-word: "TikTok +2" in the small
    /// widget, "TikTok, YouTube +1" in the medium. The summary lists named targets before
    /// the ones still called "This app", so the names shown are the ones a person knows.
    private func headline(_ names: [String]) -> String {
        let shown = family == .systemSmall ? 1 : 2
        let lead = names.prefix(shown).joined(separator: ", ")
        let rest = names.count - min(names.count, shown)
        return rest > 0 ? "\(lead) +\(rest)" : lead
    }

    /// "3 anchored", "Everything anchored", and the lift when the anchor has one.
    private func anchoredLine(_ summary: Policy.Summary) -> String {
        let what = summary.anchorsEverything ? "Everything anchored" : "\(summary.anchoredCount) anchored"
        guard let until = summary.anchorUntil else { return what }
        return "\(what) · lifts \(until.formatted(date: .omitted, time: .shortened))"
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .emberBody(11)
            .foregroundStyle(Ember.muted)
            .lineLimit(1)
            .padding(.top, 2)
    }

    /// The part of a next-open time the numerals cannot carry at widget size: nil for later
    /// today, "tomorrow", else the short weekday.
    private func nextDay(_ date: Date) -> String? {
        if Calendar.current.isDateInToday(date) { return nil }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// "Next" for later today. The day joins it otherwise, because "1:00 AM" on its own
    /// reads as tonight.
    private func nextEyebrow(_ date: Date) -> String {
        nextDay(date).map { "Next · \($0)" } ?? "Next"
    }

    /// The lock-screen line under the name: "opens 1:00 AM" today, else the day first.
    private func accessoryNext(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return nextDay(date).map { "\($0) \(time)" } ?? "opens \(time)"
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FurloughStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Furlough")
        .description("What is open now and when the next window starts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
