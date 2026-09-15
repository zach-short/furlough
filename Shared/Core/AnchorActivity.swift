import Foundation

/// What the Anchor is called on a screen that is not the Anchor screen: the widget's line, the
/// Lock Screen's headline, the sentence a tag-only hold has instead of a countdown.
///
/// One place, because a second wording of the same fact is a bug waiting to be reported —
/// `StatusWidget` and the Live Activity both read this.
enum AnchorText {
    /// "Everything anchored", or "3 anchored". Under `.everythingExcept` the count is the
    /// allowlist, which is not what is held, so it is left out there.
    static func headline(everything: Bool, count: Int) -> String {
        everything ? "Everything anchored" : "\(count) anchored"
    }

    /// The headline plus when it lifts, where there is one — the widget's one line.
    static func line(everything: Bool, count: Int, until: Date?, calendar: Calendar = .current) -> String {
        let what = headline(everything: everything, count: count)
        guard let until else { return what }
        return "\(what) · lifts \(TimeFormat.clock(until, calendar: calendar))"
    }

    /// The one sentence a tag-only hold has. There is nothing to count down to, and that is
    /// the point of it: the way back is somewhere else, not on this screen.
    static let tagOnly = "Only your tag lifts it."
}

extension Policy {
    /// The Anchor's Live Activity: the hold that is on now, or the one a schedule promises
    /// next. Pure, so what the Lock Screen should be showing is decided here and tested here;
    /// `LiveActivityManager` only does the I/O.
    ///
    /// A promised hold is here because only a foreground app may *request* an activity, and a
    /// scheduled drop is performed by `MonitorExtension`, which may not. So the app asks for it
    /// ahead with `Activity.request(start:)` the way step 10 does for a window, and the drop
    /// simply updates the activity that is already waiting.
    struct AnchorActivity: Equatable {
        /// When the hold began, or is promised to begin.
        var droppedAt: Date
        /// When it lifts by itself; nil when the tag is the only way back.
        var until: Date?
        /// `AnchorText.headline`'s words for what it holds.
        var headline: String
        /// `AnchorProfile.heldDescription`: "3 items", "Everything except 2".
        var held: String
        var anchorsEverything: Bool
        /// Nil when the hold is on now; otherwise when it starts, for `Activity.request(start:)`.
        var startsAt: Date?

        /// True while this is a promise rather than a hold.
        var isScheduled: Bool { startsAt != nil }

        /// The same plan on the device's own clock, which is what ActivityKit draws against.
        func shifted(by drift: TimeInterval) -> AnchorActivity {
            guard drift != 0 else { return self }
            var copy = self
            copy.droppedAt = droppedAt.addingTimeInterval(drift)
            copy.until = until?.addingTimeInterval(drift)
            copy.startsAt = startsAt?.addingTimeInterval(drift)
            return copy
        }
    }

    static func anchorActivity(config: Config, now: Date, calendar: Calendar = .current) -> AnchorActivity? {
        let anchor = config.anchor
        if anchor.isHolding(at: now) {
            return AnchorActivity(
                // A hold with no stamp is one being read mid-drop; `now` is as true as it gets.
                droppedAt: anchor.anchoredAt ?? now,
                until: anchor.until,
                headline: AnchorText.headline(everything: anchor.anchorsEverything, count: anchor.count),
                held: anchor.heldDescription,
                anchorsEverything: anchor.anchorsEverything,
                startsAt: nil
            )
        }
        // The same two conditions `scheduledDrop` checks before it drops anything: promising a
        // hold the schedule could not perform would put a lie on the Lock Screen at 11 PM.
        guard anchor.hasSomethingToHold, anchor.isPaired,
              let next = nextScheduledDrop(anchor.schedules, after: now, calendar: calendar)
        else { return nil }
        return AnchorActivity(
            droppedAt: next.at,
            until: next.schedule.liftDate(afterDropAt: next.at, calendar: calendar),
            headline: AnchorText.headline(everything: anchor.anchorsEverything, count: anchor.count),
            held: anchor.heldDescription,
            anchorsEverything: anchor.anchorsEverything,
            startsAt: next.at
        )
    }

    /// The soonest drop any schedule asks for, with the schedule that asked — `[AnchorSchedule]
    /// .nextDrop` answers only the date, and the lift belongs to the schedule that owns it.
    static func nextScheduledDrop(
        _ schedules: [AnchorSchedule], after now: Date, calendar: Calendar = .current
    ) -> (schedule: AnchorSchedule, at: Date)? {
        schedules
            .compactMap { schedule in schedule.nextDrop(after: now, calendar: calendar).map { (schedule, $0) } }
            .min { $0.1 < $1.1 }
    }
}
