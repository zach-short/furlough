import Foundation

/// What Furlough says when it is asked rather than looked at.
///
/// A Spotlight action, a Siri phrase and a Shortcut all get one line of text and no hourglass,
/// so this is the whole answer: what is open and until when, what is anchored, and what is
/// still waiting out the delay. Everything the home screen says with a hero and a list has to
/// fit here in a sentence or three, which is why it says only the things that would change
/// what you do next — never the full roster.
///
/// Pure, and deliberately kept out of the intents themselves so it can be tested without
/// AppIntents, a running app, or a device.
enum StatusSpeech {
    /// `hasTargets` rather than reading the config again: the caller already has the state,
    /// and an install with nothing in it should say so instead of "nothing is open", which is
    /// true but sounds like Furlough is working.
    static func sentence(
        _ summary: Policy.Summary,
        hasTargets: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard hasTargets || summary.anchoredCount > 0 else { return "Nothing is in Furlough yet." }
        var lines: [String] = []
        if summary.isAnchored, summary.anchoredCount > 0 {
            lines.append("Anchored: \(things(summary.anchoredCount)) locked until you scan your tag.")
        }
        lines.append(open(summary, now: now, calendar: calendar))
        if summary.pendingCount > 0 {
            lines.append("\(changes(summary.pendingCount)) \(verb(summary.pendingCount)) still waiting out the delay.")
        }
        return lines.joined(separator: " ")
    }

    /// What is through the shield right now, or — when nothing is — what opens next. Windowed
    /// and all-day targets are kept apart the way the summary keeps them: only a window has a
    /// closing time, and giving an all-day target one would be a lie.
    private static func open(_ summary: Policy.Summary, now: Date, calendar: Calendar) -> String {
        var clauses: [String] = []
        if !summary.openNames.isEmpty, let until = summary.openUntil {
            clauses.append(
                "\(names(summary.openNames)) \(verb(summary.openNames.count)) open"
                + " until \(TimeFormat.clock(until, calendar: calendar))"
            )
        }
        if !summary.allDayNames.isEmpty {
            clauses.append("\(names(summary.allDayNames)) \(verb(summary.allDayNames.count)) open all day")
        }
        if !clauses.isEmpty { return clauses.joined(separator: ", and ") + "." }
        guard let at = summary.nextOpenAt, !summary.nextOpenNames.isEmpty else {
            return "Nothing is open."
        }
        // Back through `NextOpen` so the phrasing is the one the rows and the shield already
        // use — "at 8:00 PM", "tomorrow at 9:00 AM", "Thursday at 9:00 AM".
        let next = NextOpen(
            minuteOfDay: Policy.minuteOfDay(at, calendar: calendar),
            daysAhead: Policy.daysAhead(of: at, from: now, calendar: calendar)
        )
        let opens = summary.nextOpenNames.count == 1 ? "opens" : "open"
        return "Nothing is open. \(names(summary.nextOpenNames)) \(opens)"
            + " \(TimeFormat.nextOpen(next, from: now, calendar: calendar))."
    }

    /// Names while there are few enough to hear, a count once there are not. Four apps read
    /// aloud is a list; "4 things" is an answer.
    private static func names(_ list: [String]) -> String {
        guard list.count <= 3 else { return things(list.count) }
        switch list.count {
        case 0: return ""
        case 1: return list[0]
        case 2: return "\(list[0]) and \(list[1])"
        default: return "\(list[0]), \(list[1]) and \(list[2])"
        }
    }

    /// "1 thing" / "4 things" — the same word the Mac uses when it refuses to quit.
    private static func things(_ count: Int) -> String {
        "\(count) thing\(count == 1 ? "" : "s")"
    }

    private static func changes(_ count: Int) -> String {
        "\(count) change\(count == 1 ? "" : "s")"
    }

    private static func verb(_ count: Int) -> String { count == 1 ? "is" : "are" }
}
