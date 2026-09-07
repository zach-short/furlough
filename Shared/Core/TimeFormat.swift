import Foundation

enum TimeFormat {
    static func minute(_ minute: Int) -> String {
        if minute >= Furlough.minutesPerDay { return "midnight" }
        return Policy.date(atMinute: minute, of: .now).formatted(date: .omitted, time: .shortened)
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

    static func rule(_ rule: Rule?) -> String {
        guard let rule else { return "Not configured yet" }
        guard rule.isEverAllowed else { return "Blocked all day" }
        let windows = rule.sortedWindows.map(window).joined(separator: ", ")
        return "\(windows) · \(budget(rule.dailyBudgetMinutes))/day"
    }

    static func nextOpen(_ next: NextOpen) -> String {
        next.isTomorrow ? "tomorrow at \(minute(next.minuteOfDay))" : "at \(minute(next.minuteOfDay))"
    }

    static func status(_ status: TargetStatus) -> String {
        switch status {
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
        case .unconfigured:
            return ("Not enforced yet", "Open Furlough and set a schedule for \(name).")
        case .blockedAllDay:
            return ("\(name) is blocked", "It has no allowed windows.")
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
