import Foundation

enum TimeFormat {
    static func minute(_ minute: Int) -> String {
        if minute >= Furlough.minutesPerDay { return "midnight" }
        return Policy.date(atMinute: minute, of: .now).formatted(date: .omitted, time: .shortened)
    }

    /// "8 PM", "8:30 PM", "12 AM" for midnight either end; follows the locale's clock.
    static func shortMinute(_ minute: Int) -> String {
        let wrapped = minute % Furlough.minutesPerDay
        let date = Policy.date(atMinute: wrapped, of: .now)
        if wrapped % 60 == 0 {
            return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
        }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
    }

    static func window(_ window: TimeWindow) -> String {
        "\(minute(window.startMinute))–\(minute(window.endMinute))"
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

    /// "Every day", "Weekdays", "Weekends", or the days compressed into runs: "Mon–Thu, Sat".
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

    /// The whole week's windows: one list when they are the same every day, else one clause
    /// per group of days, broader groups first: "Every day 8:00 PM–midnight · Sat, Sun 12:00 AM–2:00 AM".
    static func schedule(_ rule: Rule, calendar: Calendar = .current) -> String {
        if rule.isAllDay { return "All day" }
        if rule.isSameEveryDay {
            return rule.sortedWindows.map(window).joined(separator: ", ")
        }
        var groups: [(days: Weekdays, windows: [TimeWindow])] = []
        for window in rule.sortedWindows {
            if let index = groups.firstIndex(where: { $0.days == window.days }) {
                groups[index].windows.append(window)
            } else {
                groups.append((window.days, [window]))
            }
        }
        groups.sort { $0.days.groupOrder(calendar: calendar) < $1.days.groupOrder(calendar: calendar) }
        return groups
            .map { "\(days($0.days, calendar: calendar)) \($0.windows.map(window).joined(separator: ", "))" }
            .joined(separator: " · ")
    }

    static func rule(_ rule: Rule?) -> String {
        guard let rule else { return "Not configured yet" }
        guard rule.isEverAllowed else { return "Blocked all day" }
        return "\(schedule(rule)) · \(budget(rule.dailyBudgetMinutes))/day"
    }

    /// The name of the day `daysAhead` days from now.
    static func weekdayName(daysAhead: Int, abbreviated: Bool = false, from now: Date = .now) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        return date.formatted(.dateTime.weekday(abbreviated ? .abbreviated : .wide))
    }

    static func nextOpen(_ next: NextOpen) -> String {
        if next.isMidnight { return "at midnight" }
        return switch next.daysAhead {
        case 0: "at \(minute(next.minuteOfDay))"
        case 1: "tomorrow at \(minute(next.minuteOfDay))"
        case 7: "next \(weekdayName(daysAhead: 7)) at \(minute(next.minuteOfDay))"
        default: "\(weekdayName(daysAhead: next.daysAhead)) at \(minute(next.minuteOfDay))"
        }
    }

    /// The short form for a row's status chip: a time today or tomorrow, else the day.
    static func chip(_ next: NextOpen) -> String {
        if next.isMidnight { return "midnight" }
        return next.daysAhead <= 1 ? minute(next.minuteOfDay) : weekdayName(daysAhead: next.daysAhead, abbreviated: true)
    }

    static func status(_ status: TargetStatus) -> String {
        switch status {
        case .bricked: "Bricked"
        case .unconfigured: "Not enforced until you set a schedule"
        case .blockedAllDay: "Blocked all day"
        case .open(let until): "Open until \(minute(until))"
        case .exhausted(let next):
            if let next { "Used up for today · opens \(nextOpen(next))" } else { "Used up for today" }
        case .closed(let next): "Opens \(nextOpen(next))"
        }
    }

    /// A ticking countdown: "1:12:08" with hours, "12:08" under an hour. Never negative.
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
    static func text(name: String, status: TargetStatus?, rule: Rule?) -> (title: String, subtitle: String) {
        guard let status else {
            return ("Blocked by Furlough", "This is part of a blocked category.")
        }
        let budget = rule.map { TimeFormat.budget($0.dailyBudgetMinutes) } ?? ""
        switch status {
        case .bricked:
            return ("\(name) is bricked", "Unbrick it with your tag in Furlough.")
        case .unconfigured:
            return ("Not enforced yet", "Open Furlough and set a schedule for \(name).")
        case .blockedAllDay:
            return ("\(name) is blocked", "It is blocked all day.")
        case .open:
            return ("Opening…", "Furlough is lifting the shield. Try again in a moment.")
        case .exhausted(let next):
            let when = next.map { "Opens \(TimeFormat.nextOpen($0))." } ?? ""
            return ("Time's up for today", "You used your \(budget) for \(name). \(when)")
        case .closed(let next):
            return ("\(name) opens \(TimeFormat.nextOpen(next))", "You get \(budget) per day.")
        }
    }
}
