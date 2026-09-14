import Foundation

/// The answer to "what is installed on this phone", kept between visits. The real query
/// (`UsageReader.encodedKinds`, enumerating every installed app) can take seconds or never
/// finish, so the page reads this map instead of blocking on it, and the slow query only ever
/// corrects it rather than gating it.
///
/// Generic over `[String: Data]` rather than `TargetKind`: tokens aren't Sendable, so only the
/// encoded form crosses the `@concurrent` lookups; and `TargetKind.application` is iOS-only, so a
/// value keyed on kinds couldn't build from the macOS test bundle.
struct TokenCache: Codable, Equatable, Sendable {
    /// Keyed the way `UsageCollector` keys a usage entry: a bundle identifier, or "web:" + domain.
    var entries: [String: Data] = [:]
    /// Never expires on its own — a token only goes stale when the app is deleted, which only a
    /// fresh answer can tell.
    var savedAt: Date = .distantPast

    /// Replaced whole, never merged: a deleted app must drop out, or its token would linger
    /// forever pointing at nothing. Nil for an empty answer, since that means a failed query
    /// (matching `UsageReader.Naming.answered`), not an empty phone — a failed query must not
    /// wipe a good cache.
    static func refreshed(with answer: [String: Data], now: Date = .now) -> TokenCache? {
        guard !answer.isEmpty else { return nil }
        return TokenCache(entries: answer, savedAt: now)
    }

    var count: Int { entries.count }

    /// Log-line estimate: token bytes only, not keys or JSON overhead.
    var byteCount: Int { entries.values.reduce(0) { $0 + $1.count } }

    /// "4 minutes", "2 days" — rounded down, vague under a minute; precision doesn't matter here.
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

    /// Tolerant decoding: an older or hand-edited cache decodes to what it does say rather than
    /// throwing — worst case, a slow first visit.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([String: Data].self, forKey: .entries) ?? [:]
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .distantPast
    }
}
