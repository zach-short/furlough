import ActivityKit
import SwiftUI
import WidgetKit

/// The Anchor on the Lock Screen and in the Dynamic Island — the other half of what
/// `WindowLiveActivity` does for a window.
///
/// Two shapes, because the Anchor has two: a timed drop has a real end and counts down to it; a
/// tag-only drop has a start and one sentence, and the sentence is the point — the way back is
/// somewhere else, not on this screen.
///
/// **No button.** A Live Activity's buttons run App Intents, and the only intent that could
/// belong here is a release, which lives behind a tag scan in the app and nowhere else.
struct AnchorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AnchorActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 12) {
                HourglassView(state: .anchored)
                    .frame(width: 30, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Furlough", color: Ember.ember)
                    Text(context.state.headline)
                        .emberDisplay(17)
                        .foregroundStyle(Ember.cream)
                        .lineLimit(1)
                    Text(detail(context))
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    clock(context)
                        .emberNumerals(28)
                        .foregroundStyle(Ember.ember)
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
                        mark(size: 18)
                        Text(context.state.headline)
                            .emberDisplay(17)
                            .foregroundStyle(Ember.cream)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        clock(context)
                            .emberNumerals(22)
                            .foregroundStyle(Ember.ember)
                        Text(caption(context))
                            .font(EmberFont.label(9))
                            .tracking(0.06 * 9)
                            .foregroundStyle(Ember.muted)
                    }
                    .frame(minWidth: 84, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(detail(context))
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                }
            } compactLeading: {
                mark(size: 14)
            } compactTrailing: {
                // Nothing to count down for a tag-only hold, so the frozen glass stands in
                // rather than a clock that could be read as a way out.
                if context.state.until != nil {
                    clock(context)
                        .font(EmberFont.numerals(13))
                        .monospacedDigit()
                        .foregroundStyle(Ember.ember)
                        .frame(width: 58, alignment: .trailing)
                } else {
                    HourglassView(state: .anchored)
                        .frame(width: 14, height: 18)
                }
            } minimal: {
                mark(size: 12)
            }
            .keylineTint(Ember.ember)
        }
    }

    /// SF Symbols has no anchor, so this is Furlough's own — the same mark as the tile, the
    /// widget button and the Spotlight shortcut.
    private func mark(size: CGFloat) -> some View {
        AnchorShape()
            .fill(Ember.ember)
            .frame(width: size, height: size)
    }

    /// Counting down to a lift where there is one, otherwise counting up from the drop: the
    /// system's own timer is the only thing that moves in a Live Activity.
    @ViewBuilder
    private func clock(_ context: ActivityViewContext<AnchorActivityAttributes>) -> some View {
        if let until = context.state.until, until > context.state.droppedAt {
            Text(timerInterval: context.state.droppedAt...until, countsDown: true)
        } else {
            // Counting up needs a range all the same, and only its start is read; a week is
            // past any hold a clock on the Lock Screen is still telling the truth about.
            Text(
                timerInterval: context.state.droppedAt...context.state.droppedAt.addingTimeInterval(7 * 24 * 3600),
                countsDown: false
            )
        }
    }

    /// Disambiguates the numerals, the way the window activity's does.
    private func caption(_ context: ActivityViewContext<AnchorActivityAttributes>) -> String {
        context.state.until == nil ? "Held" : "Until it lifts"
    }

    /// The line under the headline: what it holds plus the way back, which for a tag-only hold
    /// is the whole of what there is to say.
    private func detail(_ context: ActivityViewContext<AnchorActivityAttributes>) -> String {
        guard let until = context.state.until else {
            return context.state.anchorsEverything
                ? AnchorText.tagOnly
                : "\(context.state.held) · \(AnchorText.tagOnly)"
        }
        return "\(context.state.held) · lifts \(TimeFormat.clock(until))"
    }
}
