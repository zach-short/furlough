import Foundation

/// What Furlough says when asked rather than looked at — Spotlight, Siri, Shortcuts. Fits the
/// home screen's hero-and-list into a sentence or three, saying only what would change what you
/// do next, never the full roster. Kept out of the intents themselves so it's testable without
/// AppIntents, a running app, or a device.
enum StatusSpeech {
    /// `hasTargets` rather than re-reading the config: an empty install should say so, not
    /// "nothing is open" (true, but sounds like Furlough is working).
    static func sentence(
        _ summary: Policy.Summary,
        hasTargets: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard hasTargets || summary.anchoredCount > 0 || summary.anchorsEverything else { return "Nothing is in Furlough yet." }
        var lines: [String] = []
        if summary.anchorsEverything {
            // Said as an exception (what stays open), not a total.
            let kept = summary.anchoredCount > 0 ? " except \(things(summary.anchoredCount))" : ""
            lines.append("Anchored: everything\(kept) is locked until you scan your tag.")
        } else if summary.isAnchored, summary.anchoredCount > 0 {
            lines.append("Anchored: \(things(summary.anchoredCount)) locked until you scan your tag.")
        }
        lines.append(open(summary, now: now, calendar: calendar))
        if summary.pendingCount > 0 {
            lines.append("\(changes(summary.pendingCount)) \(verb(summary.pendingCount)) still waiting out the delay.")
        }
        return lines.joined(separator: " ")
    }

    /// What's through the shield now, or what opens next if nothing is. Windowed and all-day
    /// targets stay separate since only a window has a real closing time.
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
        // Via `NextOpen` so the phrasing matches what the rows and shield already use.
        let next = NextOpen(
            minuteOfDay: Policy.minuteOfDay(at, calendar: calendar),
            daysAhead: Policy.daysAhead(of: at, from: now, calendar: calendar)
        )
        let opens = summary.nextOpenNames.count == 1 ? "opens" : "open"
        return "Nothing is open. \(names(summary.nextOpenNames)) \(opens)"
            + " \(TimeFormat.nextOpen(next, from: now, calendar: calendar))."
    }

    /// Names up to three; a count past that — four apps read aloud is a list, not an answer.
    private static func names(_ list: [String]) -> String {
        guard list.count <= 3 else { return things(list.count) }
        switch list.count {
        case 0: return ""
        case 1: return list[0]
        case 2: return "\(list[0]) and \(list[1])"
        default: return "\(list[0]), \(list[1]) and \(list[2])"
        }
    }

    /// Matches the word the Mac uses when it refuses to quit.
    private static func things(_ count: Int) -> String {
        "\(count) thing\(count == 1 ? "" : "s")"
    }

    private static func changes(_ count: Int) -> String {
        "\(count) change\(count == 1 ? "" : "s")"
    }

    private static func verb(_ count: Int) -> String { count == 1 ? "is" : "are" }
}
