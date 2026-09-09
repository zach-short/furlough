import ActivityKit
import Foundation

// ActivityKit has not adopted Sendable annotations. Activity is documented for use from any
// task, and Furlough only ever touches it inside the detached task below.
extension Activity: @retroactive @unchecked Sendable {}

/// Keeps the Lock Screen in step with the windows: one Live Activity for the window that is
/// open, and one scheduled ahead for the window that opens next.
///
/// Until iOS 26 only the foreground app could start an activity, so one appeared only if
/// Furlough happened to be open when a window began. `Activity.request(…, start:)` (iOS 26)
/// takes a start date, so the next window is asked for while the app *is* in front and arrives
/// on its own — on a locked phone, with Furlough closed. Requesting is still foreground-only;
/// `canStart` is false in the monitor extension, which updates and ends but never asks for a
/// new one.
///
/// ActivityKit objects are not Sendable, so all of the work happens off the main actor with
/// only value data passed in.
enum LiveActivityManager {
    /// The system draws the activity's timer against its own clock, so the summary is computed
    /// on Furlough's time and then moved onto the device's before ActivityKit sees it.
    nonisolated static func sync(state: SharedState, canStart: Bool = true) {
        let clock = state.clock()
        let summary = Policy.summary(state: state, now: clock.now).shifted(by: clock.drift)
        let now = clock.device(clock.now)
        Task.detached {
            await apply(summary: summary, now: now, canStart: canStart)
        }
    }

    /// One window the activity should be showing, or waiting to show.
    private struct Wanted {
        var attributes: FurloughActivityAttributes
        var content: ActivityContent<FurloughActivityAttributes.ContentState>
        /// When it should appear, or nil to appear now.
        var start: Date?
        var names: [String]
    }

    nonisolated static func apply(summary: Policy.Summary, now: Date, canStart: Bool = true) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Activity<FurloughActivityAttributes>.activities
        var wanted: [Wanted] = []

        if let openUntil = summary.openUntil, !summary.openNames.isEmpty, openUntil > now {
            let contentState = FurloughActivityAttributes.ContentState(
                openNames: summary.openNames,
                note: "Open",
                warned: summary.openWarned,
                budgetMinutes: summary.openBudgetMinutes,
                // Five minutes from the warning, and only from a warning that really fired:
                // this is the one budget deadline Screen Time ever makes knowable.
                budgetDeadline: summary.openWarnedAt.map {
                    $0.addingTimeInterval(TimeInterval(Furlough.warningMinutes * 60))
                }
            )
            wanted.append(Wanted(
                attributes: FurloughActivityAttributes(
                    windowStart: min(summary.openStart ?? now, now), windowEnd: openUntil
                ),
                content: ActivityContent(state: contentState, staleDate: openUntil),
                start: nil,
                names: summary.openNames
            ))
        }
        // The next window, asked for now and shown then. `nextOpenUntil` is nil for a rule with
        // no windows of its own, which is the same thing that keeps it out of `openNames`: an
        // all-day budget has nothing to count down to.
        if let start = summary.nextOpenAt, let end = summary.nextOpenUntil,
           !summary.nextOpenNames.isEmpty, start > now, end > start {
            let contentState = FurloughActivityAttributes.ContentState(
                openNames: summary.nextOpenNames, note: "Open", warned: false,
                budgetMinutes: summary.nextOpenBudgetMinutes
            )
            wanted.append(Wanted(
                attributes: FurloughActivityAttributes(windowStart: start, windowEnd: end),
                content: ActivityContent(state: contentState, staleDate: end),
                start: start,
                names: summary.nextOpenNames
            ))
        }

        // Anything that is not one of those two windows any more: a window that has closed, and
        // a scheduled one that a tightening edit took away before it ever started.
        await end(existing.filter { activity in
            !wanted.contains { same($0.attributes, activity.attributes) }
        })

        for item in wanted {
            if let current = existing.first(where: { same(item.attributes, $0.attributes) }) {
                // A scheduled activity keeps its identity when its start arrives, so this is
                // also how the pending one becomes the open one.
                await current.update(item.content)
                continue
            }
            guard canStart else { continue }
            do {
                if let start = item.start {
                    _ = try Activity.request(
                        attributes: item.attributes,
                        content: item.content,
                        pushType: nil,
                        style: .standard,
                        alertConfiguration: alert(names: item.names, end: item.attributes.windowEnd),
                        start: start
                    )
                    SharedStore.log("scheduled live activity for \(start.formatted(date: .omitted, time: .shortened))")
                } else {
                    _ = try Activity.request(attributes: item.attributes, content: item.content, pushType: nil)
                }
            } catch {
                SharedStore.log("live activity request failed: \(error.localizedDescription)")
            }
        }
    }

    /// Two activities are the same window when they cover the same minutes. Nothing else about
    /// an activity is stable across a sync, and the attributes cannot be changed once it exists.
    private nonisolated static func same(
        _ a: FurloughActivityAttributes, _ b: FurloughActivityAttributes
    ) -> Bool {
        a.windowStart == b.windowStart && a.windowEnd == b.windowEnd
    }

    /// What the Lock Screen says as a scheduled activity arrives. The same sentence the
    /// monitor's "Window opened" notification uses, so the two read as one thing if the phone
    /// shows both.
    private nonisolated static func alert(names: [String], end: Date) -> AlertConfiguration {
        let list = names.joined(separator: ", ")
        let time = end.formatted(date: .omitted, time: .shortened)
        return AlertConfiguration(
            title: "Window opened",
            body: "\(list) — open until \(time).",
            sound: .default
        )
    }

    private nonisolated static func end(_ activities: [Activity<FurloughActivityAttributes>]) async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
