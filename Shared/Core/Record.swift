import Foundation

/// The record of the contract: streaks, time held shut, loosenings cancelled/landed, longest
/// Anchor hold. Pure, like `Policy`; written from the same events that move the shields, read
/// only by the two screens that show it. Never influences `Policy.decide`.
enum Record {
    /// Days kept. Older ones are dropped on the next write.
    static let retainedDays = 60

    // MARK: - Writing

    /// Counts minutes since the last count into the day records, splitting at midnight and at
    /// every status-changing edge, so the status is attributed exactly rather than sampled.
    /// Whole minutes only, so calling this once a second (Mac) or once an hour (phone) totals
    /// the same either way.
    static func accumulate(_ state: inout SharedState, now: Date, calendar: Calendar = .current) {
        guard let stamp = state.runtime.recordedThrough, stamp < now else {
            state.runtime.recordedThrough = now
            return
        }
        // At most a day is ever counted at once — a phone off for a week wasn't holding anything shut.
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

    /// The budget ran out; called where `runtime.exhausted` is first stamped.
    static func markSpent(_ id: UUID, in state: inout SharedState, now: Date, calendar: Calendar = .current) {
        edit(id, in: &state, on: now, calendar: calendar) { $0.spent = true }
    }

    /// The 5-minute warning fired.
    static func markWarned(_ id: UUID, in state: inout SharedState, now: Date, calendar: Calendar = .current) {
        edit(id, in: &state, on: now, calendar: calendar) { $0.warned = true }
    }

    /// Queues a loosening and counts it in one call. Every append meant to be saved must go
    /// through here — a bare `state.pending.append` is only correct on a throwaway state used
    /// to ask "would this fit?" (see `ActivityLimit.projecting`); anywhere else it silently
    /// skips the count.
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

    /// A queued loosening waited out the delay and landed. Counted only via `Policy.applyDuePending`.
    static func noteLanded(
        _ count: Int = 1, in state: inout SharedState, now: Date, calendar: Calendar = .current
    ) {
        guard count > 0 else { return }
        edit(day: now, in: &state, calendar: calendar) { $0.landed += count }
    }

    /// The Anchor was released; call before clearing `anchor.anchoredAt`. Recorded whole on the
    /// day it ended, so a stretch spanning midnight stays one number.
    static func noteAnchorReleased(_ state: inout SharedState, now: Date, calendar: Calendar = .current) {
        guard let since = state.config.anchor.anchoredAt, now > since else { return }
        let minutes = Int(now.timeIntervalSince(since) / 60)
        guard minutes > 0 else { return }
        edit(day: now, in: &state, calendar: calendar) {
            $0.longestAnchorMinutes = max($0.longestAnchorMinutes, minutes)
        }
    }

    /// Drops everything older than `retainedDays`. Day keys (`yyyy-MM-dd`) sort as text exactly
    /// as they sort as dates.
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
        /// Whether the streak just broke (nothing spent today, something yesterday), so the
        /// screen doesn't show a misleading proud "1".
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

    /// Days in a row, ending today, on which no budget was spent. A day with no entry counts as
    /// clean; the run stops at the earliest recorded day, so a fresh install can't claim days
    /// before it existed.
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

    /// The seven whole days before today, most recent first. Unlike `weekKeys` (which could be
    /// one morning long on digest day), this is always a finished span, so its numbers stay true.
    static func lastSevenDayKeys(before now: Date, calendar: Calendar = .current) -> [String] {
        var keys: [String] = []
        var day = calendar.startOfDay(for: now)
        for _ in 0..<7 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            keys.append(Policy.dayKey(day, calendar: calendar))
        }
        return keys
    }

    /// Day keys from the start of this week through today, most recent first; never a future day.
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
    // Both screens say it in the same words, kept here for the same reason as `PendingText`.
    // Nothing here is celebratory; a broken streak says so.

    /// The answer to "no budget spent", so the day a budget did go says "Not today."
    static func streakLine(_ card: Card) -> String {
        if card.streakDays == 0 { return "Not today." }
        if card.brokeYesterday {
            return card.streakDays == 1 ? "Back to day one." : "\(card.streakDays) days, after a break."
        }
        return card.streakDays == 1 ? "1 day, so far." : "\(card.streakDays) days in a row."
    }

    /// The total on its own — the anchored share gets its own row so neither number is cut off
    /// in the sidebar's width.
    static func shieldedLine(_ card: Card) -> String {
        card.shieldedMinutes > 0 ? TimeFormat.budget(card.shieldedMinutes) : "Nothing held shut yet."
    }

    /// The Anchor's share of held-shut time; nil (not zero) when it never held anything, so the
    /// row is left out.
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

    // MARK: - The week as bars

    /// One day of the last seven, for a chart: which day it is, what it held shut, and how tall
    /// that is against the tallest day of the seven.
    struct DayBar: Equatable, Identifiable {
        var id: String { key }
        /// The `yyyy-MM-dd` key, which is also the identity.
        var key: String
        /// Calendar weekday, 1…7, for the letter under the bar.
        var weekday: Int
        var shieldedMinutes = 0
        /// 0…1 against the tallest day of the seven, so bars scale to the week rather than a
        /// fixed ceiling.
        var fraction: Double = 0
        var isToday = false
    }

    /// The last seven days, oldest first, ending today. Heights are relative to the week's own
    /// tallest day rather than a fixed ceiling, since there's no natural maximum to scale against.
    static func week(_ days: [String: DayRecord], upTo now: Date, calendar: Calendar = .current) -> [DayBar] {
        var bars: [DayBar] = []
        let today = calendar.startOfDay(for: now)
        for ago in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -ago, to: today) else { continue }
            let key = Policy.dayKey(date, calendar: calendar)
            let minutes = (days[key]?.targets.values).map { $0.reduce(0) { $0 + $1.shieldedMinutes } } ?? 0
            bars.append(DayBar(
                key: key,
                weekday: Policy.weekday(date, calendar: calendar),
                shieldedMinutes: minutes,
                isToday: ago == 0
            ))
        }
        let tallest = bars.map(\.shieldedMinutes).max() ?? 0
        guard tallest > 0 else { return bars }
        for index in bars.indices {
            bars[index].fraction = Double(bars[index].shieldedMinutes) / Double(tallest)
        }
        return bars
    }

    // MARK: - The weekly digest

    /// The week just gone, as a notification: a title and two or three lines.
    struct Digest: Equatable {
        var title: String
        var body: String
    }

    /// What the last seven whole days came to, in the same words the record screens use. Nil
    /// when nothing happened (not worth a notification). Every number, streak included, counts
    /// back from yesterday, not `now` — a digest is scheduled ahead of when it's read, so
    /// counting through today would claim a day that hasn't happened yet.
    static func weeklyDigest(
        _ days: [String: DayRecord], upTo now: Date, calendar: Calendar = .current
    ) -> Digest? {
        let lastWholeDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        var card = Card()
        card.streakDays = streak(days, upTo: lastWholeDay, calendar: calendar)
        card.brokeYesterday = brokeYesterday(days, upTo: lastWholeDay, calendar: calendar)
        for key in lastSevenDayKeys(before: now, calendar: calendar) {
            guard let day = days[key] else { continue }
            for entry in day.targets.values {
                card.shieldedMinutes += entry.shieldedMinutes
                card.anchoredMinutes += entry.anchoredMinutes
            }
            card.cancelled += day.cancelled
            card.landed += day.landed
        }
        guard card.shieldedMinutes > 0 || card.cancelled > 0 || card.landed > 0 else { return nil }
        var lines = ["No budget spent: \(streakLine(card))"]
        if card.shieldedMinutes > 0 {
            let anchored = anchoredLine(card).map { " · \($0) anchored" } ?? ""
            lines.append("Held shut: \(shieldedLine(card))\(anchored)")
        }
        if card.cancelled > 0 || card.landed > 0 {
            lines.append("Loosenings: \(looseningLine(card))")
        }
        return Digest(title: "Last week", body: lines.joined(separator: "\n"))
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

    /// `[from, to)` cut at every status-changing edge (`Policy.nextTransition`), so a stretch
    /// where Furlough was asleep for hours isn't sampled as one status for the whole span.
    private static func slices(
        from: Date, to: Date, config: Config, calendar: Calendar
    ) -> [(start: Date, end: Date)] {
        var slices: [(start: Date, end: Date)] = []
        var cursor = from
        // Cap guards against a transition that fails to advance, not a real limit.
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
