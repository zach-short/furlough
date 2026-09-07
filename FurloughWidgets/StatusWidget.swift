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

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let state = SharedStore.load()
        var entries: [StatusEntry] = []
        var cursor = Date.now
        for _ in 0..<12 {
            entries.append(StatusEntry(date: cursor, summary: Policy.summary(state: state, now: cursor)))
            let config = Policy.effectiveConfig(state, now: cursor)
            let next = Policy.nextTransition(config: config, after: cursor)
            guard next > cursor else { break }
            cursor = next.addingTimeInterval(1)
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

    /// Home-screen sizes: eyebrow, name in Display, countdown or next time in Geist Mono, detail.
    private var home: some View {
        let summary = entry.summary
        return VStack(alignment: .leading, spacing: 0) {
            if let until = summary.openUntil, !summary.openNames.isEmpty, until > entry.date {
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
            if summary.isBricked {
                Text("\(summary.brickedCount) bricked")
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
