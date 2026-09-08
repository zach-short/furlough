import ActivityKit
import Foundation

// ActivityKit has not adopted Sendable annotations. Activity is documented for use from any
// task, and Furlough only ever touches it inside the detached task below.
extension Activity: @retroactive @unchecked Sendable {}

/// Keeps one Live Activity alive while a window is open. Requested from the app because
/// iOS only lets the foreground app start one. ActivityKit objects are not Sendable, so all
/// of the work happens off the main actor with only value data passed in.
enum LiveActivityManager {
    /// The system draws the activity's timer against its own clock, so the summary is computed
    /// on Furlough's time and then moved onto the device's before ActivityKit sees it.
    @MainActor
    static func sync(state: SharedState) {
        let clock = state.clock()
        let summary = Policy.summary(state: state, now: clock.now).shifted(by: clock.drift)
        let now = clock.device(clock.now)
        Task.detached {
            await apply(summary: summary, now: now)
        }
    }

    nonisolated static func apply(summary: Policy.Summary, now: Date) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Activity<FurloughActivityAttributes>.activities

        guard let openUntil = summary.openUntil, !summary.openNames.isEmpty, openUntil > now else {
            await end(existing)
            return
        }

        let contentState = FurloughActivityAttributes.ContentState(openNames: summary.openNames, note: "Open", warned: summary.openWarned)
        let content = ActivityContent(state: contentState, staleDate: openUntil)

        if let current = existing.first(where: { $0.attributes.windowEnd == openUntil }) {
            await current.update(content)
            await end(existing.filter { $0.id != current.id })
            return
        }

        await end(existing)
        let attributes = FurloughActivityAttributes(windowStart: min(summary.openStart ?? now, now), windowEnd: openUntil)
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            SharedStore.log("live activity request failed: \(error.localizedDescription)")
        }
    }

    private nonisolated static func end(_ activities: [Activity<FurloughActivityAttributes>]) async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
