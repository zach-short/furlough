import ActivityKit
import SwiftUI
import WidgetKit

struct WindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FurloughActivityAttributes.self) { context in
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Furlough", systemImage: "hourglass")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                    Text(context.state.openNames.joined(separator: ", "))
                        .font(.headline)
                        .lineLimit(1)
                    Text("Open until \(context.attributes.windowEnd.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                countdown(context.attributes)
                    .font(.title2.monospacedDigit().bold())
                    .frame(width: 84, alignment: .trailing)
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.openNames.first ?? "Open", systemImage: "hourglass")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.attributes)
                        .font(.title3.monospacedDigit().bold())
                        .frame(width: 76, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Closes at \(context.attributes.windowEnd.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "hourglass")
            } compactTrailing: {
                countdown(context.attributes)
                    .monospacedDigit()
                    .frame(width: 52)
            } minimal: {
                Image(systemName: "hourglass")
            }
        }
    }

    private func countdown(_ attributes: FurloughActivityAttributes) -> some View {
        Text(timerInterval: attributes.windowStart...attributes.windowEnd, countsDown: true)
    }
}
