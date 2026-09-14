import ActivityKit
import SwiftUI
import WidgetKit

/// The window on the Lock Screen and in the Dynamic Island.
///
/// The countdown shows the budget only once Screen Time reports it (at the 5-minute warning or
/// exhaustion — it never reports usage directly); otherwise it counts down to the window's
/// close rather than inventing a number.
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
                    Text(allowance(context))
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    countdown(context)
                        .emberNumerals(28)
                        .foregroundStyle(numberColor(context))
                    Text(caption(context))
                        .font(EmberFont.label(9))
                        .tracking(0.06 * 9)
                        .foregroundStyle(Ember.muted)
                }
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
                    VStack(alignment: .trailing, spacing: 1) {
                        countdown(context)
                            .emberNumerals(22)
                            .foregroundStyle(numberColor(context))
                        Text(caption(context))
                            .font(EmberFont.label(9))
                            .tracking(0.06 * 9)
                            .foregroundStyle(Ember.muted)
                    }
                    .frame(minWidth: 84, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(allowance(context))
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                }
            } compactLeading: {
                HourglassView(state: glass(context))
                    .frame(width: 14, height: 18)
            } compactTrailing: {
                countdown(context)
                    .font(EmberFont.numerals(13))
                    .monospacedDigit()
                    .foregroundStyle(numberColor(context))
                    .frame(width: 58, alignment: .trailing)
            } minimal: {
                HourglassView(state: glass(context))
                    .frame(width: 12, height: 16)
            }
            .keylineTint(Ember.ember)
        }
    }

    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<FurloughActivityAttributes>) -> some View {
        if let deadline = context.state.budgetDeadline {
            // Counted from the warning, not from now, so the system's timer draws the same
            // five minutes however often the activity is updated.
            Text(
                timerInterval: deadline.addingTimeInterval(-TimeInterval(Furlough.warningMinutes * 60))...deadline,
                countsDown: true
            )
        } else {
            Text(timerInterval: context.attributes.windowStart...context.attributes.windowEnd, countsDown: true)
        }
    }

    /// Disambiguates the countdown: "12:04" means different things for budget vs window close.
    private func caption(_ context: ActivityViewContext<FurloughActivityAttributes>) -> String {
        context.state.budgetDeadline == nil ? "Until close" : "Left today"
    }

    /// Same two colours the glass uses (amber draining, cream closing), so they agree at a glance.
    private func numberColor(_ context: ActivityViewContext<FurloughActivityAttributes>) -> Color {
        context.state.budgetDeadline == nil ? Ember.cream : Ember.amber
    }

    private func allowance(_ context: ActivityViewContext<FurloughActivityAttributes>) -> String {
        let close = context.attributes.windowEnd.formatted(date: .omitted, time: .shortened)
        guard let minutes = context.state.budgetMinutes else { return "Open until \(close)" }
        return "\(TimeFormat.budget(minutes)) a day · until \(close)"
    }

    /// Live Activities can't animate custom views, so the sand only moves when the app syncs it.
    private func glass(_ context: ActivityViewContext<FurloughActivityAttributes>) -> HourglassState {
        let attributes = context.attributes
        let total = attributes.windowEnd.timeIntervalSince(attributes.windowStart)
        let level = total > 0 ? min(1, max(0, attributes.windowEnd.timeIntervalSince(.now) / total)) : 0
        return .open(level: level, warned: context.state.warned)
    }
}
