import Foundation

enum TimeFormat {
    /// Uses the given calendar's own locale/time zone, so output never depends on the machine's.
    private static func style(
        _ calendar: Calendar,
        date: Date.FormatStyle.DateStyle? = nil,
        time: Date.FormatStyle.TimeStyle? = nil
    ) -> Date.FormatStyle {
        Date.FormatStyle(
            date: date,
            time: time,
            locale: calendar.locale ?? .autoupdatingCurrent,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
    }

    static func minute(_ minute: Int, calendar: Calendar = .current) -> String {
        if minute >= Furlough.minutesPerDay { return "midnight" }
        return Policy.date(atMinute: minute, of: .now, calendar: calendar)
            .formatted(style(calendar, date: .omitted, time: .shortened))
    }

    static func shortMinute(_ minute: Int, calendar: Calendar = .current) -> String {
        let wrapped = minute % Furlough.minutesPerDay
        let date = Policy.date(atMinute: wrapped, of: .now, calendar: calendar)
        // Drop minutes on the hour ("8 PM"), but never on a 24-hour clock, where that leaves a
        // bare "09" instead of a time.
        if wrapped % 60 == 0, !isTwentyFourHour(calendar) {
            return date.formatted(style(calendar).hour(.defaultDigits(amPM: .abbreviated)))
        }
        return date.formatted(style(calendar).hour(.defaultDigits(amPM: .abbreviated)).minute())
    }

    private static func isTwentyFourHour(_ calendar: Calendar) -> Bool {
        switch (calendar.locale ?? .autoupdatingCurrent).hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour: true
        default: false
        }
    }

    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(style(calendar, date: .omitted, time: .shortened))
    }

    /// Minutes past 1440 (midnight) are a night's morning, e.g. 1680 == 4:00 AM tomorrow.
    static func until(_ minute: Int, calendar: Calendar = .current) -> String {
        minute > Furlough.minutesPerDay
            ? self.minute(minute - Furlough.minutesPerDay, calendar: calendar)
            : self.minute(minute, calendar: calendar)
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(style(calendar).month(.abbreviated).day())
    }

    static func window(_ window: TimeWindow, calendar: Calendar = .current) -> String {
        "\(minute(window.startMinute, calendar: calendar))–\(minute(window.endMinute, calendar: calendar))"
    }

    /// An hour said out loud: "midnight", "noon", "7 PM" — no minutes, since a suggestion is
    /// always whole hours.
    static func hour(_ minute: Int, calendar: Calendar = .current) -> String {
        let wrapped = ((minute % Furlough.minutesPerDay) + Furlough.minutesPerDay) % Furlough.minutesPerDay
        if wrapped == 0 { return "midnight" }
        if wrapped == Furlough.minutesPerDay / 2 { return "noon" }
        return shortMinute(wrapped, calendar: calendar)
    }

    static func span(_ window: TimeWindow, calendar: Calendar = .current) -> String {
        "\(hour(window.startMinute, calendar: calendar)) to \(hour(window.endMinute, calendar: calendar))"
    }

    /// The three group words ("every day", "on weekdays") stay lowercase mid-sentence; day
    /// names keep their capitals.
    static func onDays(_ group: Weekdays, calendar: Calendar = .current) -> String {
        if group == .all { return "every day" }
        if group == .weekdays { return "on weekdays" }
        if group == .weekend { return "on weekends" }
        return "on \(days(group, calendar: calendar))"
    }

    static func budget(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            return minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
        }
        if minutes > 60 {
            return "\(minutes / 60) h \(minutes % 60) min"
        }
        return "\(minutes) min"
    }

    /// "Weekdays"/"weekends"/"every day" lowercase inline; a name list like "Mon–Thu" keeps its.
    static func daysInline(_ days: Weekdays, calendar: Calendar = .current) -> String {
        let named = self.days(days, calendar: calendar)
        switch days {
        case .all, .weekdays, .weekend: return named.lowercased()
        default: return named
        }
    }

    /// The week's budgets in one phrase, collapsing to "varies by day" past two distinct
    /// figures. Nil when no day has a real limit, so a caller can leave the budget out entirely.
    static func budgets(_ rule: Rule, calendar: Calendar = .current) -> String? {
        var groups: [(days: Weekdays, minutes: Int)] = []
        for weekday in 1...7 {
            let minutes = rule.budget(on: weekday)
            if let index = groups.firstIndex(where: { $0.minutes == minutes }) {
                groups[index].days.insert(Weekdays(weekday: weekday))
            } else {
                groups.append((Weekdays(weekday: weekday), minutes))
            }
        }
        guard groups.contains(where: { $0.minutes < Furlough.minutesPerDay }) else { return nil }
        if groups.count == 1 { return "\(budget(groups[0].minutes))/day" }
        guard groups.count == 2 else { return "varies by day" }
        groups.sort { $0.days.groupOrder(calendar: calendar) < $1.days.groupOrder(calendar: calendar) }
        return groups
            .map { group in
                let amount = group.minutes < Furlough.minutesPerDay ? budget(group.minutes) : "no limit"
                return "\(amount) \(daysInline(group.days, calendar: calendar))"
            }
            .joined(separator: ", ")
    }

    static func anchorSchedules(_ schedules: [AnchorSchedule], calendar: Calendar = .current) -> String {
        guard !schedules.isEmpty else { return "No scheduled drops" }
        return schedules
            .sorted { ($0.minuteOfDay, $0.days.rawValue) < ($1.minuteOfDay, $1.days.rawValue) }
            .map { schedule in
                let when = "\(minute(schedule.minuteOfDay, calendar: calendar)) \(anchorDays(schedule.days, calendar: calendar))"
                let lift = schedule.liftMinuteOfDay.map { "lifts \(minute($0, calendar: calendar))" } ?? "until the tag"
                return "\(when), \(lift)"
            }
            .joined(separator: " · ")
    }

    private static func anchorDays(_ days: Weekdays, calendar: Calendar) -> String {
        switch days {
        case .all: "every day"
        case .weekdays: "weekdays"
        case .weekend: "weekends"
        default: self.days(days, calendar: calendar)
        }
    }

    static func days(_ days: Weekdays, calendar: Calendar = .current) -> String {
        if days == .all { return "Every day" }
        if days == .weekdays { return "Weekdays" }
        if days == .weekend { return "Weekends" }
        if days.isEmpty { return "No days" }
        let symbols = calendar.shortStandaloneWeekdaySymbols
        var runs: [[Int]] = []
        var previousPosition: Int?
        for (position, weekday) in Weekdays.ordered(calendar: calendar).enumerated() where days.contains(weekday: weekday) {
            if let previousPosition, previousPosition == position - 1, !runs.isEmpty {
                runs[runs.count - 1].append(weekday)
            } else {
                runs.append([weekday])
            }
            previousPosition = position
        }
        return runs.map { run in
            let names = run.map { symbols[$0 - 1] }
            guard run.count >= 3, let first = names.first, let last = names.last else {
                return names.joined(separator: ", ")
            }
            return "\(first)–\(last)"
        }.joined(separator: ", ")
    }

    /// A night stored as two halves (`TimeWindow.folded`) is read back as one span, so a rule
    /// reads the way it was written rather than as an evening and a morning apart.
    static func schedule(_ rule: Rule, calendar: Calendar = .current) -> String {
        if rule.isAllDay { return "All day" }
        let listed = TimeWindow.folded(rule.windows)
        if rule.isSameEveryDay {
            return listed.sorted().map { window($0, calendar: calendar) }.joined(separator: ", ")
        }
        var groups: [(days: Weekdays, windows: [TimeWindow])] = []
        for window in TimeWindow.grouped(listed, calendar: calendar) {
            if let index = groups.firstIndex(where: { $0.days == window.days }) {
                groups[index].windows.append(window)
            } else {
                groups.append((window.days, [window]))
            }
        }
        groups.sort { $0.days.groupOrder(calendar: calendar) < $1.days.groupOrder(calendar: calendar) }
        return groups
            .map { group in
                let hours = group.windows.map { window($0, calendar: calendar) }.joined(separator: ", ")
                return "\(days(group.days, calendar: calendar)) \(hours)"
            }
            .joined(separator: " · ")
    }

    static func rule(_ rule: Rule?, calendar: Calendar = .current) -> String {
        guard let rule else { return "Not configured yet" }
        guard rule.isEverAllowed else { return "Blocked all day" }
        let hours = schedule(rule, calendar: calendar)
        guard let limit = budgets(rule, calendar: calendar) else { return hours }
        return "\(hours) · \(limit)"
    }

    static func weekdayName(
        daysAhead: Int,
        abbreviated: Bool = false,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let date = calendar.date(byAdding: .day, value: daysAhead, to: now) ?? now
        return date.formatted(style(calendar).weekday(abbreviated ? .abbreviated : .wide))
    }

    static func nextOpen(_ next: NextOpen, from now: Date = .now, calendar: Calendar = .current) -> String {
        if next.isMidnight { return "at midnight" }
        let at = minute(next.minuteOfDay, calendar: calendar)
        return switch next.daysAhead {
        case 0: "at \(at)"
        case 1: "tomorrow at \(at)"
        case 7: "next \(weekdayName(daysAhead: 7, from: now, calendar: calendar)) at \(at)"
        default: "\(weekdayName(daysAhead: next.daysAhead, from: now, calendar: calendar)) at \(at)"
        }
    }

    static func chip(_ next: NextOpen, from now: Date = .now, calendar: Calendar = .current) -> String {
        if next.isMidnight { return "midnight" }
        if next.daysAhead <= 1 { return minute(next.minuteOfDay, calendar: calendar) }
        return weekdayName(daysAhead: next.daysAhead, abbreviated: true, from: now, calendar: calendar)
    }

    static func status(_ status: TargetStatus, calendar: Calendar = .current) -> String {
        switch status {
        case .anchored: "Anchored"
        case .unconfigured: "Not enforced until you set a schedule"
        case .blockedAllDay: "Blocked all day"
        case .open(let end): "Open until \(until(end, calendar: calendar))"
        case .exhausted(let next):
            if let next {
                "Used up for today · opens \(nextOpen(next, calendar: calendar))"
            } else {
                "Used up for today"
            }
        case .closed(let next): "Opens \(nextOpen(next, calendar: calendar))"
        }
    }

    static func countdown(from now: Date, to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(now).rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func delay(hours: Int) -> String {
        if hours % 24 == 0 {
            let days = hours / 24
            return days == 1 ? "1 day" : "\(days) days"
        }
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

/// Copy for the shield shown over a blocked app or site.
enum ShieldText {
    static func text(
        name: String,
        status: TargetStatus?,
        rule: Rule?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (title: String, subtitle: String) {
        guard let status else {
            return ("Blocked by Furlough", "This is part of a blocked category.")
        }
        // Today's budget, not the rule's general one — the shield is read today.
        let budget = rule.map { TimeFormat.budget($0.budget(on: Policy.weekday(now, calendar: calendar))) } ?? ""
        switch status {
        case .anchored:
            return ("\(name) is anchored", "Unanchor with your tag in Furlough.")
        case .unconfigured:
            return ("Not enforced yet", "Open Furlough and set a schedule for \(name).")
        case .blockedAllDay:
            return ("\(name) is blocked", "It is blocked all day.")
        case .open:
            return ("Opening…", "Furlough is lifting the shield. Try again in a moment.")
        case .exhausted(let next):
            let when = next.map { "Opens \(TimeFormat.nextOpen($0, calendar: calendar))." } ?? ""
            return ("Time's up for today", "You used your \(budget) for \(name). \(when)")
        case .closed(let next):
            // Budget of the day it opens on, not today's — today may be a day the rule shuts out entirely.
            let opens = rule.map {
                TimeFormat.budget($0.budget(on: Policy.weekday(Policy.date(at: next, from: now, calendar: calendar), calendar: calendar)))
            } ?? ""
            return ("\(name) opens \(TimeFormat.nextOpen(next, calendar: calendar))", "You get \(opens) per day.")
        }
    }
}
