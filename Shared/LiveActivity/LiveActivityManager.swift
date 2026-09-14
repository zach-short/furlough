import ActivityKit
import Foundation

// ActivityKit predates Sendable; Furlough only ever touches Activity from the detached task below.
extension Activity: @retroactive @unchecked Sendable {}

/// Keeps the Lock Screen in step with the windows: one Live Activity for the open window, one
/// scheduled ahead for the next.
///
/// `Activity.request(…, start:)` (iOS 26) lets the next window be requested while the app is
/// foreground and have it arrive later on its own, even on a locked/closed phone — before this,
/// only a foreground app could start an activity at all. Requesting is still foreground-only:
/// `canStart` is false in the monitor extension, which updates/ends existing activities but
/// never starts new ones. All work here runs off the main actor since ActivityKit isn't Sendable.
enum LiveActivityManager {
    /// Computed on Furlough's clock, then shifted to the device's before ActivityKit (which
    /// draws its timer against the device clock) ever sees it.
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
                // The one budget deadline Screen Time ever makes knowable: 5 min after a warning fires.
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
        // `nextOpenUntil` is nil for an all-day budget — nothing to count down to.
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

        // A closed window, or a scheduled one a tightening edit removed before it started.
        await end(existing.filter { activity in
            !wanted.contains { same($0.attributes, activity.attributes) }
        })

        for item in wanted {
            if let current = existing.first(where: { same(item.attributes, $0.attributes) }) {
                // Also how a pending activity becomes the open one: identity survives its start.
                await current.update(item.content)
                continue
            }
            guard canStart else { continue }
            do {
                if let start = item.start {
                    // Below iOS 26, Activity.request has no `start:` — an activity can only be
                    // requested for right now, so the next window just waits for a later sync
                    // (when it opens and takes the `else` branch below) instead of staging ahead.
                    guard #available(iOS 26.0, *) else { continue }
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

    /// Compared by minutes covered — the only thing about an activity stable across a sync.
    private nonisolated static func same(
        _ a: FurloughActivityAttributes, _ b: FurloughActivityAttributes
    ) -> Bool {
        a.windowStart == b.windowStart && a.windowEnd == b.windowEnd
    }

    /// Matches the monitor's "Window opened" notification wording, so the two read as one thing.
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
