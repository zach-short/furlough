import ActivityKit
import SwiftUI
import WidgetKit

/// The window on the Lock Screen and in the Dynamic Island.
///
/// **What the big number counts.** The budget, wherever Furlough honestly knows it, and the
/// window's close otherwise. That order is a constraint, not a preference: Screen Time reports
/// a budget to us at exactly two moments — "about five minutes left" and "spent" — and reports
/// usage itself only to a `DeviceActivityReport` extension that cannot pass a figure back. So
/// for most of a window the minutes remaining are genuinely unknown here, and a ticking number
/// claiming to be them would be invented. The allowance is on the line underneath from the
/// start ("30 min a day"), the countdown becomes the real thing to spend the moment the warning
/// fires (`ContentState.budgetDeadline`), and the caption says which of the two is on screen.
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

    /// The budget's last five minutes when they are running, and the window's close otherwise.
    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<FurloughActivityAttributes>) -> some View {
        if let deadline = context.state.budgetDeadline {
            // Counted from the warning rather than from now, so the system's own timer draws
            // the same five minutes however often the activity is updated.
            Text(
                timerInterval: deadline.addingTimeInterval(-TimeInterval(Furlough.warningMinutes * 60))...deadline,
                countsDown: true
            )
        } else {
            Text(timerInterval: context.attributes.windowStart...context.attributes.windowEnd, countsDown: true)
        }
    }

    /// Which of the two the number is. Worth the two words: "12:04" means something very
    /// different depending on whether it is the day's minutes or the window's hours.
    private func caption(_ context: ActivityViewContext<FurloughActivityAttributes>) -> String {
        context.state.budgetDeadline == nil ? "Until close" : "Left today"
    }

    /// Amber once the number is the budget draining, Cream while it is only the window closing:
    /// the same two colours the glass uses, so they agree at a glance.
    private func numberColor(_ context: ActivityViewContext<FurloughActivityAttributes>) -> Color {
        context.state.budgetDeadline == nil ? Ember.cream : Ember.amber
    }

    /// The day's allowance and when the window shuts, so the figure is on screen from the
    /// start even while the minutes spent against it are unknowable.
    private func allowance(_ context: ActivityViewContext<FurloughActivityAttributes>) -> String {
        let close = context.attributes.windowEnd.formatted(date: .omitted, time: .shortened)
        guard let minutes = context.state.budgetMinutes else { return "Open until \(close)" }
        return "\(TimeFormat.budget(minutes)) a day · until \(close)"
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
