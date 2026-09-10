import Foundation

/// The answer to "what is installed on this phone", kept between visits.
///
/// With data access Screen Time names an app in the usage data by its bundle identifier alone.
/// Apple's own name and icon, and the token a rule is written on, come from a second query —
/// `FamilyActivityData.shared.installedApplications` and `visitedWebDomains`, wrapped by
/// `UsageReader.encodedKinds` — which enumerates every app on the device, takes seconds when it
/// answers and sometimes never does. The usage page no longer waits on it (`Brand`, and the
/// letters `MonogramTile` draws), but every visit still paid for it before a real icon appeared.
///
/// The answer barely changes between visits: a token is stable for as long as the app is
/// installed, and Furlough persists tokens inside every target already. So the map is written
/// down and the page opens on it, and the slow query becomes the thing that corrects it rather
/// than the thing that gates it.
///
/// Generic over `[String: Data]` rather than over `TargetKind` on purpose. Tokens are not
/// Sendable, so what crosses out of the `@concurrent` lookups is the encoded form anyway; and
/// `TargetKind.application` exists only under `#if os(iOS)`, so a value keyed on kinds could not
/// be built at all from the macOS test bundle.
struct TokenCache: Codable, Equatable, Sendable {
    /// Encoded `TargetKind`s, keyed the way `UsageCollector` keys a usage entry: a bundle
    /// identifier, or "web:" and a domain.
    var entries: [String: Data] = [:]
    /// When the query that produced `entries` answered. Read for the log line and for judging
    /// how old a card's icon may be; nothing expires on it, because an installed app's token
    /// does not go stale with time — it goes stale when the app is deleted, which only a fresh
    /// answer can say.
    var savedAt: Date = .distantPast

    /// The cache a fresh answer makes, or nil when there is nothing worth keeping.
    ///
    /// Replaced whole rather than merged: an app deleted since the last visit is absent from the
    /// new answer, and merging would keep its token for ever — a card for an app that is not
    /// there, drawn on a token `Label` cannot render and Apply would write a rule on.
    ///
    /// Nil for an empty answer, because an empty answer is a failed query and not a phone with
    /// no apps on it — the same judgement `UsageReader.Naming.answered` makes, and the reason
    /// `UsageView` asks again. A failed query must not be allowed to wipe a good cache.
    static func refreshed(with answer: [String: Data], now: Date = .now) -> TokenCache? {
        guard !answer.isEmpty else { return nil }
        return TokenCache(entries: answer, savedAt: now)
    }

    /// How many keys are in it.
    var count: Int { entries.count }

    /// Roughly what it costs to keep, for the log line: the tokens themselves, without the keys
    /// or the JSON around them.
    var byteCount: Int { entries.values.reduce(0) { $0 + $1.count } }

    /// How old it is, in the words the log line uses: "4 minutes", "2 days". Rounded down, and
    /// vague under a minute, because nothing here turns on the precision — it is there so that a
    /// reader looking at a page full of the wrong icons can see whether the cache is from this
    /// morning or from last month.
    func age(at now: Date = .now) -> String {
        guard savedAt > .distantPast else { return "an unknown time" }
        let seconds = Int(now.timeIntervalSince(savedAt).rounded(.down))
        guard seconds >= 60 else { return "under a minute" }
        let minutes = seconds / 60
        if minutes < 60 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        let days = hours / 24
        return days == 1 ? "1 day" : "\(days) days"
    }

    private enum CodingKeys: String, CodingKey { case entries, savedAt }

    init(entries: [String: Data] = [:], savedAt: Date = .distantPast) {
        self.entries = entries
        self.savedAt = savedAt
    }

    /// Tolerant, like every other stored shape here: a cache written by an older build, or one
    /// hand-edited into the defaults, decodes to what it does say rather than throwing. A cache
    /// that cannot be read at all is only a slow first visit.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([String: Data].self, forKey: .entries) ?? [:]
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
    }
}
