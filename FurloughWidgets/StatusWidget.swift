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

    /// One entry per status change over the next 36h, plus every 3 min while draining so the
    /// hourglass animates. Entries are free; only reloads count against the widget budget.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let state = SharedStore.load()
        let clock = state.clock()
        var entries: [StatusEntry] = []
        // Cursor runs on Furlough's own time (what decides transitions); entries are dated on
        // the device clock (what WidgetKit compares against), with the summary shifted to match.
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
    /// False in StandBy, iPad Lock Screen, CarPlay — the only signal for those, since there's
    /// no StandBy widget family or environment value; enlarged layout keys off this instead.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    /// `.vibrant` on iPad Lock Screen / StandBy Night Mode, where the system desaturates and
    /// re-colours the widget; meaning carried in hue elsewhere must carry in contrast instead.
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: StatusEntry

    /// True in StandBy/CarPlay/iPad Lock Screen: read from across a room, so type grows and
    /// secondary lines drop.
    private var enlarged: Bool { !showsBackground }

    var body: some View {
        if family == .accessoryRectangular {
            accessory
                .containerBackground(.clear, for: .widget)
        } else {
            home
                // In StandBy the system drops the wall and puts type on the dark screen beside
                // the other widget.
                .containerBackground(for: .widget) { EmberWall() }
        }
    }

    /// The glass overlays the corner rather than taking its own column — a column left text
    /// only 87pt wide, truncating names and times.
    private var home: some View {
        homeText
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                HourglassView(state: glass)
                    .frame(width: enlarged ? 42 : 30, height: enlarged ? 56 : 40)
            }
            .overlay(alignment: .topTrailing) {
                // Medium widget has room for one action: dropping the anchor (same intent as
                // Control Center) — release stays behind the tag in-app.
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
                Eyebrow(text: "Open now", color: Ember.amber, size: eyebrowSize)
                name(headline(summary.openNames))
                Text(timerInterval: entry.date...until, countsDown: true)
                    .emberNumerals(numeralSize)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                detail("until \(until.formatted(date: .omitted, time: .shortened))")
            } else if let next = summary.nextOpenAt {
                Eyebrow(text: nextEyebrow(next), color: Ember.amber, size: eyebrowSize)
                name(headline(summary.nextOpenNames))
                Text(next.formatted(date: .omitted, time: .shortened))
                    .emberNumerals(numeralSize)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                if let budget = summary.nextOpenBudgetMinutes {
                    detail("\(TimeFormat.budget(budget)) budget")
                } else {
                    detail("\(summary.blockedCount) blocked")
                }
            } else if allDayOnly {
                Eyebrow(text: "Open all day", color: Ember.moss, size: eyebrowSize)
                name(headline(summary.allDayNames))
                detail("budget resets at midnight")
            } else if summary.isEmpty {
                Eyebrow(text: "Furlough", color: Ember.amber, size: eyebrowSize)
                name("Nothing managed")
                detail("Open Furlough to add apps.")
            } else {
                Eyebrow(text: "Blocked", color: Ember.muted, size: eyebrowSize)
                name("All blocked")
                detail("\(summary.blockedCount) blocked all day")
            }
            Spacer(minLength: 0)
            // Enlarged (read from a distance): only the anchor line stays, since it's the one
            // state the glass alone could be mistaken about.
            Group {
                if !summary.allDayNames.isEmpty, !allDayOnly, !enlarged {
                    Text("\(headline(summary.allDayNames)) open all day")
                        .emberBody(10.5, .semibold)
                        .foregroundStyle(Ember.moss)
                        .lineLimit(1)
                }
                if summary.isAnchored {
                    Text(anchoredLine(summary))
                        .emberBody(enlarged ? 13 : 10.5, .semibold)
                        .foregroundStyle(Ember.ember)
                }
                if summary.pendingCount > 0, !enlarged {
                    Text("\(summary.pendingCount) change\(summary.pendingCount == 1 ? "" : "s") pending")
                        .emberBody(10.5, .semibold)
                        .foregroundStyle(Ember.pending)
                }
            }
            .padding(.trailing, enlarged ? 48 : 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Sizes
    //
    // Same lines, just larger when enlarged — a widget saying something different in StandBy
    // would be a second widget to keep true.

    private var eyebrowSize: CGFloat { enlarged ? 12 : 10 }
    private var numeralSize: CGFloat { enlarged ? 36 : 22 }
    private var nameSize: CGFloat { enlarged ? 24 : 15 }
    private var detailSize: CGFloat { enlarged ? 13.5 : 11 }

    /// Under `.vibrant` the dim/grey glasses and the ember halo lose contrast against the
    /// system's desaturating recolour, so this swaps to the brightest existing glass with no
    /// halo rather than introduce a new colour.
    private var glass: HourglassState {
        var state = HourglassState.of(entry.summary, now: entry.date)
        guard renderingMode == .vibrant else { return state }
        state.glass = .cream
        state.glow = nil
        return state
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
            .emberDisplay(nameSize)
            .foregroundStyle(Ember.cream)
            .lineLimit(family == .systemSmall ? 1 : 2)
            .minimumScaleFactor(enlarged ? 0.7 : 1)
            .padding(.top, 3)
    }

    /// "TikTok +2" rather than a name cut off mid-word. Named targets are listed before
    /// unnamed ones, so the names shown are ones the person recognizes.
    private func headline(_ names: [String]) -> String {
        let shown = family == .systemSmall ? 1 : 2
        let lead = names.prefix(shown).joined(separator: ", ")
        let rest = names.count - min(names.count, shown)
        return rest > 0 ? "\(lead) +\(rest)" : lead
    }

    /// The words themselves live in `AnchorText`, shared with the Anchor's Live Activity, so
    /// the Lock Screen and the home screen cannot word the same fact differently.
    private func anchoredLine(_ summary: Policy.Summary) -> String {
        AnchorText.line(
            everything: summary.anchorsEverything,
            count: summary.anchoredCount,
            until: summary.anchorUntil
        )
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .emberBody(detailSize)
            .foregroundStyle(Ember.muted)
            .lineLimit(1)
            .minimumScaleFactor(enlarged ? 0.8 : 1)
            .padding(.top, 2)
    }

    /// What the numerals alone can't carry at widget size: nil for later today, "tomorrow",
    /// else the short weekday.
    private func nextDay(_ date: Date) -> String? {
        if Calendar.current.isDateInToday(date) { return nil }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// Day joins "Next" except for later today, because "1:00 AM" alone reads as tonight.
    private func nextEyebrow(_ date: Date) -> String {
        nextDay(date).map { "Next · \($0)" } ?? "Next"
    }

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
        // No StandBy family exists; StandBy/CarPlay reuse systemSmall scaled up, so that's a
        // layout question inside systemSmall, not a fourth family here.
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
