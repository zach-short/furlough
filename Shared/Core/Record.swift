import Foundation

/// The record of the contract: the numbers only a commitment device can produce. Days in a row
/// with no budget spent, time held shut, loosenings cancelled rather than landed, the longest
/// the Anchor ever held.
///
/// Pure, like `Policy`; every function that touches a day boundary takes a `calendar:`. The
/// activity log is free text and capped, so nothing here parses it — the record is written
/// from the same events that already move the shields, and read only by the two screens that
/// show it. It never influences `Policy.decide`, and `SharedStore.reset` clears it with the
/// rest of the runtime.
enum Record {
    /// Days kept. Older ones are dropped on the next write.
    static let retainedDays = 60

    // MARK: - Writing

    /// Counts the minutes since the last count into the day records, splitting at midnight.
    ///
    /// A status only changes at a window edge, at midnight, or when a threshold callback lands,
    /// and every one of those ends in a reconcile — so between two counts the status held still,
    /// and attributing the whole span to the status at its start is exact rather than a sample.
    /// The exception is an edit that changes a rule mid-span, which is attributed to the rule as
    /// it stands now; it is worth at most the minutes since the last reconcile.
    ///
    /// Only whole minutes are counted and the stamp moves by whole minutes, so calling this
    /// once a second (the Mac) and once an hour (the phone) come to the same total.
    static func accumulate(_ state: inout SharedState, now: Date, calendar: Calendar = .current) {
        guard let stamp = state.runtime.recordedThrough, stamp < now else {
            state.runtime.recordedThrough = now
            return
        }
        // Furlough is not always awake, and a phone that was off for a week was not holding
        // anything shut. At most a day is ever counted at once.
        let earliest = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let from = max(stamp, earliest)
        let minutes = (now.timeIntervalSince(from) / 60).rounded(.down)
        guard minutes >= 1 else { return }
        let to = from.addingTimeInterval(minutes * 60)

        for slice in slices(from: from, to: to, config: state.config, calendar: calendar) {
            let count = Int((slice.end.timeIntervalSince(slice.start) / 60).rounded())
            guard count > 0 else { continue }
            var day = state.runtime.days[Policy.dayKey(slice.start, calendar: calendar)] ?? DayRecord()
            for target in state.config.targets {
                let status = Policy.status(
                    of: target, config: state.config, runtime: state.runtime,
                    now: slice.start, calendar: calendar
                )
                var entry = day.targets[target.id.uuidString] ?? TargetDay()
                switch status {
                case .open:
                    entry.openMinutes += count
                case .anchored:
                    entry.shieldedMinutes += count
                    entry.anchoredMinutes += count
                case .blockedAllDay, .exhausted, .closed:
                    entry.shieldedMinutes += count
                case .unconfigured:
                    // Nothing is being held, so there is nothing to count either way.
                    continue
                }
                day.targets[target.id.uuidString] = entry
            }
            state.runtime.days[Policy.dayKey(slice.start, calendar: calendar)] = day
        }
        state.runtime.recordedThrough = to
        prune(&state.runtime.days, on: now, calendar: calendar)
    }

    /// The budget ran out. Called where `runtime.exhausted` is stamped, which is the one place
    /// that knows it for the first time.
    static func markSpent(_ id: UUID, in state: inout SharedState, now: Date, calendar: Calendar = .current) {
        edit(id, in: &state, on: now, calendar: calendar) { $0.spent = true }
    }

    /// The 5-minute warning fired.
    static func markWarned(_ id: UUID, in state: inout SharedState, now: Date, calendar: Calendar = .current) {
        edit(id, in: &state, on: now, calendar: calendar) { $0.warned = true }
    }

    /// Queues a loosening and counts it, in one call, so a new queueing site cannot forget the
    /// second half. Everything in `state.pending` is a loosening: a tightening lands at once.
    static func queue(
        _ change: PendingChange, in state: inout SharedState, now: Date, calendar: Calendar = .current
    ) {
        state.pending.append(change)
        edit(day: now, in: &state, calendar: calendar) { $0.queued += 1 }
    }

    /// A queued loosening was cancelled: the delay did its job.
    static func noteCancelled(
        _ count: Int = 1, in state: inout SharedState, now: Date, calendar: Calendar = .current
    ) {
        guard count > 0 else { return }
        edit(day: now, in: &state, calendar: calendar) { $0.cancelled += count }
    }

    /// A queued loosening waited out the delay and landed. Counted inside
    /// `Policy.applyDuePending`, which is the one place that folds one in.
    static func noteLanded(
        _ count: Int = 1, in state: inout SharedState, now: Date, calendar: Calendar = .current
    ) {
        guard count > 0 else { return }
        edit(day: now, in: &state, calendar: calendar) { $0.landed += count }
    }

    /// The Anchor was released. Call it while `anchor.anchoredAt` still says when it was set:
    /// the stretch is recorded whole, on the day it ended, so one that ran over midnight stays
    /// one number.
    static func noteAnchorReleased(_ state: inout SharedState, now: Date, calendar: Calendar = .current) {
        guard let since = state.config.anchor.anchoredAt, now > since else { return }
        let minutes = Int(now.timeIntervalSince(since) / 60)
        guard minutes > 0 else { return }
        edit(day: now, in: &state, calendar: calendar) {
            $0.longestAnchorMinutes = max($0.longestAnchorMinutes, minutes)
        }
    }

    /// Drops everything older than `retainedDays`. Day keys are `yyyy-MM-dd`, which sorts as
    /// text exactly as it sorts as a date, so the comparison is the whole of it.
    static func prune(_ days: inout [String: DayRecord], on now: Date, calendar: Calendar = .current) {
        guard let oldest = calendar.date(byAdding: .day, value: -(retainedDays - 1), to: now) else { return }
        let cutoff = Policy.dayKey(oldest, calendar: calendar)
        days = days.filter { $0.key >= cutoff }
    }

    // MARK: - Reading

    /// Everything the two screens show, worked out once.
    struct Card: Equatable {
        /// Days in a row, ending today, on which no budget was spent.
        var streakDays = 0
        /// Whether the streak has just been broken — nothing was spent today, but something was
        /// yesterday — so the screen can say so plainly instead of showing a proud "1".
        var brokeYesterday = false
        /// Minutes held shut this week, added up across every app and site.
        var shieldedMinutes = 0
        /// Minutes the Anchor was what held them, of those.
        var anchoredMinutes = 0
        var cancelled = 0
        var landed = 0
        /// The longest stretch the Anchor has ever held, including one holding right now.
        var longestAnchorMinutes = 0
        /// Days the record covers, so the screen can say how far back the counts go.
        var recordedDays = 0

        /// Nothing has happened yet worth a screen.
        var isEmpty: Bool {
            recordedDays == 0 || (shieldedMinutes == 0 && cancelled == 0 && landed == 0 && longestAnchorMinutes == 0)
        }
    }

    static func card(_ state: SharedState, now: Date, calendar: Calendar = .current) -> Card {
        let days = state.runtime.days
        var card = Card()
        card.streakDays = streak(days, upTo: now, calendar: calendar)
        card.brokeYesterday = brokeYesterday(days, upTo: now, calendar: calendar)
        for key in weekKeys(upTo: now, calendar: calendar) {
            guard let day = days[key] else { continue }
            for entry in day.targets.values {
                card.shieldedMinutes += entry.shieldedMinutes
                card.anchoredMinutes += entry.anchoredMinutes
            }
        }
        for day in days.values {
            card.cancelled += day.cancelled
            card.landed += day.landed
            card.longestAnchorMinutes = max(card.longestAnchorMinutes, day.longestAnchorMinutes)
        }
        if state.config.anchor.isAnchored, let since = state.config.anchor.anchoredAt, now > since {
            card.longestAnchorMinutes = max(card.longestAnchorMinutes, Int(now.timeIntervalSince(since) / 60))
        }
        card.recordedDays = days.count
        return card
    }

    /// Days in a row, ending today, on which no budget was spent.
    ///
    /// A day with no entry at all counts: a spend is only ever written down when it happens, so
    /// silence is not a spend. The run stops at the earliest day the record has, which is what
    /// keeps a fresh install from claiming sixty clean days it was not there for.
    static func streak(_ days: [String: DayRecord], upTo now: Date, calendar: Calendar = .current) -> Int {
        guard let earliest = days.keys.min() else { return 0 }
        var count = 0
        var day = calendar.startOfDay(for: now)
        while Policy.dayKey(day, calendar: calendar) >= earliest {
            if spentAnything(days[Policy.dayKey(day, calendar: calendar)]) { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Nothing spent today, something spent yesterday: a streak that has just gone.
    static func brokeYesterday(_ days: [String: DayRecord], upTo now: Date, calendar: Calendar = .current) -> Bool {
        guard !spentAnything(days[Policy.dayKey(now, calendar: calendar)]),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        else { return false }
        return spentAnything(days[Policy.dayKey(yesterday, calendar: calendar)])
    }

    /// The day keys from the start of this week through today, most recent first. Never a day
    /// in the future: a week is what has happened, not what is scheduled.
    static func weekKeys(upTo now: Date, calendar: Calendar = .current) -> [String] {
        var day = calendar.startOfDay(for: now)
        var keys: [String] = []
        while keys.count < 7 {
            keys.append(Policy.dayKey(day, calendar: calendar))
            if calendar.component(.weekday, from: day) == calendar.firstWeekday { break }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return keys
    }

    // MARK: - Copy
    //
    // Both screens say it in the same words, and the words are here rather than in either view,
    // for the same reason `PendingText` is: the phone and the Mac must not be able to word the
    // record differently. Nothing here is celebratory, and a streak that broke says so.

    /// The answer to "no budget spent", so the day a budget did go says "Not today."
    static func streakLine(_ card: Card) -> String {
        if card.streakDays == 0 { return "Not today." }
        if card.brokeYesterday {
            return card.streakDays == 1 ? "Back to day one." : "\(card.streakDays) days, after a break."
        }
        return card.streakDays == 1 ? "1 day, so far." : "\(card.streakDays) days in a row."
    }

    /// The total, on its own: the anchored share is a row of its own rather than a clause, so
    /// neither number is cut off in the sidebar's width.
    static func shieldedLine(_ card: Card) -> String {
        card.shieldedMinutes > 0 ? TimeFormat.budget(card.shieldedMinutes) : "Nothing held shut yet."
    }

    /// How much of the week's held-shut time was the Anchor holding it. Nil when it never was,
    /// so the row is left out rather than showing a zero.
    static func anchoredLine(_ card: Card) -> String? {
        card.anchoredMinutes > 0 ? TimeFormat.budget(card.anchoredMinutes) : nil
    }

    static func looseningLine(_ card: Card) -> String {
        if card.cancelled == 0 && card.landed == 0 { return "Nothing has waited yet." }
        let cancelled = card.cancelled == 1 ? "1 cancelled" : "\(card.cancelled) cancelled"
        let landed = card.landed == 1 ? "1 landed" : "\(card.landed) landed"
        return "\(cancelled), \(landed)"
    }

    static func anchorLine(_ card: Card) -> String {
        card.longestAnchorMinutes > 0 ? TimeFormat.budget(card.longestAnchorMinutes) : "Never anchored."
    }

    /// How far back the numbers go, for the line under the card.
    static func rangeLine(_ card: Card) -> String {
        let days = min(card.recordedDays, retainedDays)
        let counted = days == 1 ? "1 day" : "\(days) days"
        return "Held shut counts this week. Loosenings and the anchor are the \(counted) on "
            + "record; Furlough keeps \(retainedDays) days and forgets the rest."
    }

    // MARK: - Private

    private static func spentAnything(_ day: DayRecord?) -> Bool {
        day?.targets.values.contains { $0.spent } ?? false
    }

    private static func edit(
        _ id: UUID, in state: inout SharedState, on now: Date, calendar: Calendar,
        _ body: (inout TargetDay) -> Void
    ) {
        edit(day: now, in: &state, calendar: calendar) { day in
            var entry = day.targets[id.uuidString] ?? TargetDay()
            body(&entry)
            day.targets[id.uuidString] = entry
        }
    }

    private static func edit(
        day now: Date, in state: inout SharedState, calendar: Calendar, _ body: (inout DayRecord) -> Void
    ) {
        let key = Policy.dayKey(now, calendar: calendar)
        var day = state.runtime.days[key] ?? DayRecord()
        body(&day)
        state.runtime.days[key] = day
        prune(&state.runtime.days, on: now, calendar: calendar)
    }

    /// `[from, to)` cut at every midnight and every window edge in it, so that each piece has
    /// one status for the whole of it. In the ordinary case — a count a minute or two after the
    /// last one — that is a single piece; it matters when Furlough has been asleep and is
    /// catching up over hours, where sampling the status once would call a whole evening open
    /// because the window happened to be open when the phone went quiet.
    ///
    /// `Policy.nextTransition` already answers "when can a status next change", and its
    /// fallback is the next midnight, so the two cuts are one call.
    private static func slices(
        from: Date, to: Date, config: Config, calendar: Calendar
    ) -> [(start: Date, end: Date)] {
        var slices: [(start: Date, end: Date)] = []
        var cursor = from
        // A day of minutes cut at every edge of at most 19 spans; the cap is a stop against a
        // transition that fails to move rather than a real limit.
        while cursor < to, slices.count < 128 {
            let next = Policy.nextTransition(config: config, after: cursor, calendar: calendar)
            let end = min(next, to)
            guard end > cursor else { break }
            slices.append((cursor, end))
            cursor = end
        }
        return slices
    }
}
