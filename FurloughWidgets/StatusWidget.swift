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
        var entries: [StatusEntry] = []
        var cursor = Date.now
        let horizon = cursor.addingTimeInterval(36 * 3600)
        while entries.count < 200, cursor < horizon {
            let summary = Policy.summary(state: state, now: cursor)
            entries.append(StatusEntry(date: cursor, summary: summary))
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

extension HourglassState {
    /// The widget's glass: the open target closing soonest, else whatever opens next, else an
    /// all-day app draining towards midnight.
    static func of(_ summary: Policy.Summary, now: Date) -> HourglassState {
        if let until = summary.openUntil, until > now, !summary.openNames.isEmpty {
            let start = summary.openStart ?? now
            let total = until.timeIntervalSince(start)
            let level = total > 0 ? min(1, max(0, until.timeIntervalSince(now) / total)) : 0
            return .open(level: level, warned: summary.openWarned)
        }
        if let next = summary.nextOpenAt {
            if summary.nextOpenIsExhausted { return .usedUp }
            if Calendar.current.isDate(next, inSameDayAs: now) {
                return .comingSoon(inMinutes: next.timeIntervalSince(now) / 60)
            }
            return .doneForToday
        }
        if !summary.allDayNames.isEmpty {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            let total = end.timeIntervalSince(start)
            let level = total > 0 ? min(1, max(0, end.timeIntervalSince(now) / total)) : 0
            return .open(level: level, warned: summary.allDayWarned)
        }
        if summary.isEmpty { return .unconfigured }
        return summary.isAnchored ? .anchored : .alwaysBlocked
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
    private var home: some View {
        HStack(alignment: .bottom, spacing: 6) {
            homeText
            Spacer(minLength: 0)
            HourglassView(state: .of(entry.summary, now: entry.date))
                .frame(width: 30, height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var homeText: some View {
        let summary = entry.summary
        let windowOpen = summary.openUntil.map { $0 > entry.date && !summary.openNames.isEmpty } ?? false
        let allDayOnly = !windowOpen && summary.nextOpenAt == nil && !summary.allDayNames.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            if windowOpen, let until = summary.openUntil {
                Eyebrow(text: "Open now", color: Ember.amber)
                name(summary.openNames.joined(separator: ", "))
                Text(timerInterval: entry.date...until, countsDown: true)
                    .emberNumerals(22)
                    .padding(.top, 4)
                detail("until \(until.formatted(date: .omitted, time: .shortened))")
            } else if let next = summary.nextOpenAt {
                Eyebrow(text: "Next", color: Ember.amber)
                name(summary.nextOpenNames.joined(separator: ", "))
                Text(nextText(next))
                    .emberNumerals(22)
                    .padding(.top, 4)
                if let budget = summary.nextOpenBudgetMinutes {
                    detail("\(TimeFormat.budget(budget)) budget")
                } else {
                    detail("\(summary.blockedCount) blocked")
                }
            } else if allDayOnly {
                Eyebrow(text: "Open all day", color: Ember.moss)
                name(summary.allDayNames.joined(separator: ", "))
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
            if !summary.allDayNames.isEmpty, !allDayOnly {
                Text("\(summary.allDayNames.joined(separator: ", ")) open all day")
                    .emberBody(10.5, .semibold)
                    .foregroundStyle(Ember.moss)
                    .lineLimit(1)
            }
            if summary.isAnchored {
                Text("\(summary.anchoredCount) anchored")
                    .emberBody(10.5, .semibold)
                    .foregroundStyle(Ember.ember)
            }
            if summary.pendingCount > 0 {
                Text("\(summary.pendingCount) change\(summary.pendingCount == 1 ? "" : "s") pending")
                    .emberBody(10.5, .semibold)
                    .foregroundStyle(Ember.pending)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lock-screen rectangle: the system tints it, so only the type carries the look.
    private var accessory: some View {
        let summary = entry.summary
        return VStack(alignment: .leading, spacing: 1) {
            if let until = summary.openUntil, !summary.openNames.isEmpty, until > entry.date {
                Text(summary.openNames.joined(separator: ", "))
                    .font(EmberFont.displaySmall(14))
                    .lineLimit(1)
                Text(timerInterval: entry.date...until, countsDown: true)
                    .font(EmberFont.numerals(16))
                    .monospacedDigit()
                Text("until \(until.formatted(date: .omitted, time: .shortened))")
                    .font(EmberFont.body(11))
            } else if let next = summary.nextOpenAt {
                Text(summary.nextOpenNames.joined(separator: ", "))
                    .font(EmberFont.displaySmall(14))
                    .lineLimit(1)
                Text("opens \(nextText(next))")
                    .font(EmberFont.numerals(14))
                    .monospacedDigit()
            } else if !summary.allDayNames.isEmpty {
                Text(summary.allDayNames.joined(separator: ", "))
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
            .lineLimit(2)
            .padding(.top, 3)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .emberBody(11)
            .foregroundStyle(Ember.muted)
            .lineLimit(1)
            .padding(.top, 2)
    }

    private func nextText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "tmrw \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
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
