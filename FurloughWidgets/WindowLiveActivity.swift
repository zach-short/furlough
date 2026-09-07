import ActivityKit
import SwiftUI
import WidgetKit

struct WindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FurloughActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 10) {
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
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Ember.amber)
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
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ember.amber)
            } compactTrailing: {
                countdown(context.attributes)
                    .font(EmberFont.numerals(13))
                    .monospacedDigit()
                    .foregroundStyle(Ember.cream)
                    .frame(width: 58, alignment: .trailing)
            } minimal: {
                Image(systemName: "hourglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.amber)
            }
            .keylineTint(Ember.ember)
        }
    }

    private func countdown(_ attributes: FurloughActivityAttributes) -> some View {
        Text(timerInterval: attributes.windowStart...attributes.windowEnd, countsDown: true)
    }
}
