import ActivityKit
import Foundation

// ActivityKit predates Sendable; Furlough only ever touches Activity from the detached task below.
extension Activity: @retroactive @unchecked Sendable {}

/// Keeps the Lock Screen in step with the windows: one Live Activity for the open window, one
/// scheduled ahead for the next — and since step 48 a second, separate activity for the Anchor.
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
        let anchor = Policy
            .anchorActivity(config: Policy.effectiveConfig(state, now: clock.now), now: clock.now)?
            .shifted(by: clock.drift)
        let now = clock.device(clock.now)
        Task.detached {
            await apply(summary: summary, anchor: anchor, now: now, canStart: canStart)
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

    nonisolated static func apply(
        summary: Policy.Summary,
        anchor: Policy.AnchorActivity? = nil,
        now: Date,
        canStart: Bool = true
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await applyAnchor(anchor, now: now, canStart: canStart)
        let existing = Activity<FurloughActivityAttributes>.activities
        var wanted: [Wanted] = []
        // Zach's call, 2026-09-14: the anchor supersedes the window activity while it holds. A
        // window counting down under a total hold is a countdown to nothing. A *scheduled*
        // anchor doesn't supersede anything — it is a promise, and the window is still open.
        let anchored = anchor.map { !$0.isScheduled } ?? false

        if !anchored, let openUntil = summary.openUntil, !summary.openNames.isEmpty, openUntil > now {
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
        if !anchored, let start = summary.nextOpenAt, let end = summary.nextOpenUntil,
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

    // MARK: The Anchor
    //
    // Its own lifecycle, over its own attributes type. Started on every drop path the app or a
    // schedule can reach, and — the half that matters — ended on every release path, because an
    // activity left running after a release is a phone that says it is locked when it is not.

    nonisolated static func applyAnchor(
        _ plan: Policy.AnchorActivity?, now: Date, canStart: Bool
    ) async {
        let existing = Activity<AnchorActivityAttributes>.activities
        guard let plan else {
            // Released, or the schedule that promised a hold can no longer perform one.
            await end(existing)
            return
        }
        let content = ActivityContent(
            state: AnchorActivityAttributes.ContentState(
                headline: plan.headline,
                held: plan.held,
                droppedAt: plan.droppedAt,
                until: plan.until,
                anchorsEverything: plan.anchorsEverything
            ),
            // A tag-only hold has no end to go stale at; a timed one goes stale when it lifts.
            staleDate: plan.until
        )
        // There is only ever one anchor, so anything past the first is a duplicate.
        let current = existing.first
        await end(Array(existing.dropFirst()))

        if let current {
            // A pending activity's start cannot be moved, and a started one cannot be put back
            // to pending, so those two cases are ended and asked for again; everything else —
            // including a promise becoming the hold it promised — is an update in place.
            let waiting = isWaitingToStart(current)
            let keeps = waiting == plan.isScheduled
                && (!waiting || current.content.state.droppedAt == plan.droppedAt)
            if keeps {
                await current.update(content)
                return
            }
            await end([current])
        }
        guard canStart else { return }
        do {
            if let start = plan.startsAt {
                // Below iOS 26 there is no scheduled start, so a promised hold simply waits for
                // the drop itself to be synced — the same fallback the next window takes.
                guard #available(iOS 26.0, *) else { return }
                _ = try Activity.request(
                    attributes: AnchorActivityAttributes(),
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: AlertConfiguration(
                        title: "Anchor dropped",
                        body: "\(plan.held) locked\(plan.until.map { " until \(TimeFormat.clock($0))" } ?? " until you scan your tag").",
                        sound: .default
                    ),
                    start: start
                )
                SharedStore.log("scheduled anchor live activity for \(TimeFormat.clock(start))")
            } else {
                _ = try Activity.request(attributes: AnchorActivityAttributes(), content: content, pushType: nil)
            }
        } catch {
            SharedStore.log("anchor live activity request failed: \(error.localizedDescription)")
        }
    }

    /// A scheduled activity reads as `.pending` until its start arrives (iOS 26). Below that
    /// nothing can be scheduled at all, so nothing is ever waiting.
    private nonisolated static func isWaitingToStart<Attributes: ActivityAttributes>(
        _ activity: Activity<Attributes>
    ) -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return activity.activityState == .pending
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

    /// Generic over the attributes: the window and the anchor are two types with one way out.
    private nonisolated static func end<Attributes: ActivityAttributes>(
        _ activities: [Activity<Attributes>]
    ) async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
