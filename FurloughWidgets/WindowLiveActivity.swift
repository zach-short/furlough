import ActivityKit
import SwiftUI
import WidgetKit

struct WindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FurloughActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 12) {
                HourglassView(state: glass(context))
                    .frame(width: 30, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Furlough", color: Ember.amber)
                    Text(context.state.openNames.joined(separator: ", "))
                        .emberDisplay(17)
                        .foregroundStyle(Ember.cream)
                        .lineLimit(1)
                    Text("Open until \(context.attributes.windowEnd.formatted(date: .omitted, time: .shortened))")
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                }
                Spacer(minLength: 8)
                countdown(context.attributes)
                    .emberNumerals(28)
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(Ember.ground.opacity(0.6))
            .activitySystemActionForegroundColor(Ember.cream)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        HourglassView(state: glass(context))
                            .frame(width: 18, height: 24)
                        Text(context.state.openNames.first ?? "Open")
                            .emberDisplay(17)
                            .foregroundStyle(Ember.cream)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.attributes)
                        .emberNumerals(22)
                        .frame(minWidth: 84, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Closes at \(context.attributes.windowEnd.formatted(date: .omitted, time: .shortened))")
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                }
            } compactLeading: {
                HourglassView(state: glass(context))
                    .frame(width: 14, height: 18)
            } compactTrailing: {
                countdown(context.attributes)
                    .font(EmberFont.numerals(13))
                    .monospacedDigit()
                    .foregroundStyle(Ember.cream)
                    .frame(width: 58, alignment: .trailing)
            } minimal: {
                HourglassView(state: glass(context))
                    .frame(width: 12, height: 16)
            }
            .keylineTint(Ember.ember)
        }
    }

    private func countdown(_ attributes: FurloughActivityAttributes) -> some View {
        Text(timerInterval: attributes.windowStart...attributes.windowEnd, countsDown: true)
    }

    /// The open glass at the level of the last update. Live Activities cannot animate custom
    /// views, so the sand only moves when the app syncs the activity.
    private func glass(_ context: ActivityViewContext<FurloughActivityAttributes>) -> HourglassState {
        let attributes = context.attributes
        let total = attributes.windowEnd.timeIntervalSince(attributes.windowStart)
        let level = total > 0 ? min(1, max(0, attributes.windowEnd.timeIntervalSince(.now) / total)) : 0
        return .open(level: level, warned: context.state.warned)
    }
}
