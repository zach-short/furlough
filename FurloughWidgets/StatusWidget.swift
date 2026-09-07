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
        let summary = entry.summary
        VStack(alignment: .leading, spacing: 4) {
            if family != .accessoryRectangular {
                Label("Furlough", systemImage: "hourglass")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            }
            if let until = summary.openUntil, !summary.openNames.isEmpty, until > entry.date {
                Text(summary.openNames.joined(separator: ", "))
                    .font(.headline)
                    .lineLimit(2)
                Text(timerInterval: entry.date...until, countsDown: true)
                    .font(.title2.monospacedDigit().bold())
                Text("until \(until.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let next = summary.nextOpenAt {
                Text("All blocked")
                    .font(.headline)
                Text(summary.nextOpenNames.joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Text("opens \(nextText(next))")
                    .font(.subheadline.bold())
            } else if summary.isEmpty {
                Text("Nothing managed")
                    .font(.headline)
                Text("Open Furlough to add apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All blocked")
                    .font(.headline)
                Text("\(summary.blockedCount) blocked all day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if summary.pendingCount > 0 {
                Text("\(summary.pendingCount) change\(summary.pendingCount == 1 ? "" : "s") pending")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func nextText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow \(date.formatted(date: .omitted, time: .shortened))"
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
