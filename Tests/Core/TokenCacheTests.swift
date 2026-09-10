import Foundation
import Testing

/// The map from a usage key to the target behind it, kept between visits so the usage page opens
/// on Apple's icons instead of on letters. See `TokenCache`.
@Suite("The token cache")
struct TokenCacheTests {
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Two keys shaped the way `UsageCollector` keys an entry, over bytes standing in for the
    /// encoded `TargetKind`s the real answer carries.
    let answer: [String: Data] = [
        "com.burbn.instagram": Data("instagram-token".utf8),
        "web:youtube.com": Data("youtube-token".utf8),
    ]

    let when = Date(timeIntervalSince1970: 1_770_000_000)

    @Test("it survives the round trip through JSON")
    func roundTrip() throws {
        let cache = try #require(TokenCache.refreshed(with: answer, now: when))
        let read = try decoder.decode(TokenCache.self, from: try encoder.encode(cache))
        #expect(read == cache)
        #expect(read.entries["com.burbn.instagram"] == Data("instagram-token".utf8))
        #expect(read.entries["web:youtube.com"] == Data("youtube-token".utf8))
        #expect(read.savedAt == when)
        #expect(read.count == 2)
        #expect(read.byteCount == "instagram-token".utf8.count + "youtube-token".utf8.count)
    }

    @Test("a fresh answer replaces the cache rather than merging into it")
    func replacesRatherThanMerges() throws {
        // Instagram deleted since the last visit, and a new app in its place.
        let later: [String: Data] = [
            "com.zhiliaoapp.musically": Data("tiktok-token".utf8),
            "web:youtube.com": Data("youtube-token-2".utf8),
        ]
        let refreshed = try #require(TokenCache.refreshed(with: later, now: when.addingTimeInterval(86_400)))
        #expect(refreshed.entries.keys.sorted() == ["com.zhiliaoapp.musically", "web:youtube.com"])
        // A deleted app's token must not outlive the answer that stopped listing it.
        #expect(refreshed.entries["com.burbn.instagram"] == nil)
        #expect(refreshed.entries["web:youtube.com"] == Data("youtube-token-2".utf8))
        #expect(refreshed.savedAt == when.addingTimeInterval(86_400))
    }

    @Test("an empty answer is a failed query, and keeps the cache that is there")
    func emptyAnswerKeepsTheOldCache() throws {
        #expect(TokenCache.refreshed(with: [:], now: when) == nil)
        // Which is what lets a caller write `if let fresh = ... { save(fresh) }` and leave a good
        // cache alone when Screen Time comes back with nothing.
        let good = try #require(TokenCache.refreshed(with: answer, now: when))
        let kept = TokenCache.refreshed(with: [:], now: when.addingTimeInterval(60)) ?? good
        #expect(kept == good)
    }

    @Test("its age reads the way the log line says it")
    func age() throws {
        let cache = try #require(TokenCache.refreshed(with: answer, now: when))
        #expect(cache.age(at: when) == "under a minute")
        #expect(cache.age(at: when.addingTimeInterval(59)) == "under a minute")
        #expect(cache.age(at: when.addingTimeInterval(60)) == "1 minute")
        #expect(cache.age(at: when.addingTimeInterval(4 * 60)) == "4 minutes")
        #expect(cache.age(at: when.addingTimeInterval(3600)) == "1 hour")
        #expect(cache.age(at: when.addingTimeInterval(5 * 3600)) == "5 hours")
        #expect(cache.age(at: when.addingTimeInterval(86_400)) == "1 day")
        #expect(cache.age(at: when.addingTimeInterval(9 * 86_400)) == "9 days")
        // A clock moved backwards is not a cache from the future.
        #expect(cache.age(at: when.addingTimeInterval(-500)) == "under a minute")
        // Nothing to go on, and it says so rather than answering in millennia.
        #expect(TokenCache(entries: answer).age(at: when) == "an unknown time")
    }

    @Test("a cache written before savedAt existed decodes to one that is simply old")
    func olderShapeDecodes() throws {
        let json = #"{"entries":{"com.burbn.instagram":"aW5zdGFncmFt"}}"#
        let cache = try decoder.decode(TokenCache.self, from: Data(json.utf8))
        #expect(cache.entries["com.burbn.instagram"] == Data("instagram".utf8))
        #expect(cache.savedAt == .distantPast)
        #expect(cache.count == 1)
    }

    @Test("a cache written with no entries at all decodes as empty")
    func emptyShapeDecodes() throws {
        let cache = try decoder.decode(TokenCache.self, from: Data(#"{}"#.utf8))
        #expect(cache.entries.isEmpty)
        #expect(cache.count == 0)
        #expect(cache.byteCount == 0)
        #expect(cache.savedAt == .distantPast)
    }
}
