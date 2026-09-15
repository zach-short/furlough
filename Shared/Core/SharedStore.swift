import Foundation
import os

/// App Group persistence shared by the app and its extensions.
enum SharedStore {
    private static let stateKey = "furlough.state.v1"
    private static let namesKey = "furlough.names.v1"
    private static let tokensKey = "furlough.tokens.v1"
    private static let anchorNamesKey = "furlough.anchorNames.v1"
    private static let logKey = "furlough.log.v1"
    private static let maxLogEntries = 300
    private static let logger = Logger(subsystem: Furlough.bundleID, category: "shared")

    #if os(iOS)
    static var isAppGroupAvailable: Bool { UserDefaults(suiteName: Furlough.appGroupID) != nil }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: Furlough.appGroupID) ?? .standard
    }
    #else
    static var isAppGroupAvailable: Bool { UserDefaults(suiteName: Furlough.macAppGroupID) != nil }

    /// One-time migration: if the App Group is empty but the old (pre-widget) standalone
    /// defaults has state, copies it across. `UserDefaults` is thread-safe but not Sendable,
    /// hence the unsafe.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard let group = UserDefaults(suiteName: Furlough.macAppGroupID) else { return .standard }
        let old = UserDefaults.standard
        if group.data(forKey: stateKey) == nil, old.data(forKey: stateKey) != nil {
            for key in [stateKey, logKey, "furlough.mac.usage.v1", "furlough.mac.onboarded"] {
                if let value = old.object(forKey: key) { group.set(value, forKey: key) }
            }
            group.set(true, forKey: "furlough.mac.migrated")
        }
        return group
    }()
    #endif

    static func load() -> SharedState {
        guard let data = defaults.data(forKey: stateKey) else { return SharedState() }
        do {
            var state = try decoder.decode(SharedState.self, from: data)
            let names = learnedNames()
            for index in state.config.targets.indices {
                if let name = names[state.config.targets[index].id.uuidString], !name.isEmpty {
                    state.config.targets[index].systemName = name
                }
            }
            return state
        } catch {
            log("Failed to decode state: \(error)")
            return SharedState()
        }
    }

    /// Names Screen Time has told us, by target id. iOS only reveals an app's name via the
    /// shield, which must not write the state directly — so it writes here instead, and `load`
    /// folds these into the targets on every read.
    static func learnedNames() -> [String: String] {
        defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:]
    }

    /// Writes down what iOS called a target; returns true when it's news, so callers can reload
    /// surfaces still showing "This app".
    @discardableResult
    static func learnName(_ name: String, for id: UUID) -> Bool {
        var names = learnedNames()
        guard !name.isEmpty, names[id.uuidString] != name else { return false }
        names[id.uuidString] = name
        defaults.set(names, forKey: namesKey)
        return true
    }

    #if os(iOS)
    /// The anchor's half of `learnedNames`: what it holds outside any rule, by learned name.
    /// Keyed by name rather than kind (a token can't be a defaults key reliably), with the kind
    /// as the value so a stale entry can be dropped when it's no longer on the list. Written by
    /// the shield and by Screen Time's tables where data access exists; never by the state.
    static func anchorNames() -> [TargetKind: String] {
        guard let stored = defaults.dictionary(forKey: anchorNamesKey) as? [String: Data] else { return [:] }
        var names: [TargetKind: String] = [:]
        for (name, encoded) in stored {
            guard let kind = try? decoder.decode(TargetKind.self, from: encoded) else { continue }
            names[kind] = name
        }
        return names
    }

    /// Writes down what `kind` on the anchor's list is called. Returns true when this is news.
    @discardableResult
    static func learnAnchorName(_ name: String, for kind: TargetKind) -> Bool {
        guard !name.isEmpty, let encoded = try? encoder.encode(kind) else { return false }
        var stored = defaults.dictionary(forKey: anchorNamesKey) as? [String: Data] ?? [:]
        guard stored[name] != encoded else { return false }
        stored[name] = encoded
        defaults.set(stored, forKey: anchorNamesKey)
        return true
    }

    /// Forgets names for kinds no longer held, so the map stays the size of the list, not of
    /// everything ever anchored.
    static func pruneAnchorNames(keeping kinds: [TargetKind]) {
        guard let stored = defaults.dictionary(forKey: anchorNamesKey) as? [String: Data] else { return }
        let held = Set(kinds)
        let kept = stored.filter { _, encoded in
            (try? decoder.decode(TargetKind.self, from: encoded)).map(held.contains) ?? false
        }
        guard kept.count != stored.count else { return }
        defaults.set(kept, forKey: anchorNamesKey)
    }
    #endif

    /// What Screen Time last said is installed, so the usage page has icons ready immediately.
    /// Nil before the first answer or after a reset; unreadable bytes are treated as no cache
    /// (costs one slow visit, then gets overwritten).
    static func tokenCache() -> TokenCache? {
        guard let data = defaults.data(forKey: tokensKey) else { return nil }
        do {
            return try decoder.decode(TokenCache.self, from: data)
        } catch {
            log("Failed to decode the token cache: \(error)")
            return nil
        }
    }

    /// Writes down an answer from Screen Time — the whole map, since `UsageReader.identities`
    /// also uses it to name targets no usage card mentioned.
    static func save(_ cache: TokenCache) {
        do {
            let data = try encoder.encode(cache)
            defaults.set(data, forKey: tokensKey)
            log("tokens: cached \(cache.count) entries, \(data.count) bytes")
        } catch {
            log("Failed to encode the token cache: \(error)")
        }
    }

    /// Every save records both clocks, which is what lets Furlough keep its own time. The mark
    /// only advances while the device's clock agrees with it; see `Clock`. The zone mark is
    /// stamped beside it on the same terms: it moves to a new zone only once the old one has
    /// been honoured for the hold.
    @discardableResult
    static func save(_ state: SharedState) -> SharedState {
        var state = state
        let now = state.now
        state.runtime.clock = Clock.stamp(state.runtime.clock)
        let zone = Clock.stampZone(state.runtime.zone, current: TimeZone.current.identifier, now: now, hold: state.zoneHold)
        noteZone(from: state.runtime.zone, to: zone, hold: state.zoneHold)
        state.runtime.zone = zone
        do {
            defaults.set(try encoder.encode(state), forKey: stateKey)
        } catch {
            log("Failed to encode state: \(error)")
        }
        return state
    }

    /// Records a zone move the way a clock change is recorded: once per crossing, from whichever
    /// process saved first, so Diagnostics shows it. A first mark and an unchanged one say nothing.
    private static func noteZone(from old: ZoneMark?, to new: ZoneMark, hold: TimeInterval) {
        guard let old, old != new else { return }
        let current = TimeZone.current.identifier
        if old.movedAt == nil, let movedAt = new.movedAt {
            let until = TimeFormat.clock(movedAt.addingTimeInterval(hold))
            log("time zone is now \(current); keeping \(old.identifier) until \(until)")
        } else if old.identifier != new.identifier {
            log("time zone hold over; now on \(new.identifier)")
        } else {
            log("time zone back to \(new.identifier)")
        }
    }

    /// Forgets every target, rule, pending change, the Anchor, the names iOS gave us and the
    /// tokens it handed over. The activity log is kept.
    static func reset() {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: namesKey)
        defaults.removeObject(forKey: tokensKey)
        defaults.removeObject(forKey: anchorNamesKey)
        // Device-local preferences kept beside the state rather than in it; a reset that left
        // them behind would be a fresh install still muting something.
        NotificationPreferences.forgetAll()
        #if os(macOS)
        // What the Mac measured. Kept outside the state for the same reason the day's ledger
        // is, and forgotten here for the same reason as everything above it.
        defaults.removeObject(forKey: UsageHistory.storeKey)
        #endif
    }

    @discardableResult
    static func mutate(_ body: (inout SharedState) -> Void) -> SharedState {
        var state = load()
        body(&state)
        return save(state)
    }

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        var entries = defaults.stringArray(forKey: logKey) ?? []
        let stamp = Date.now.formatted(date: .numeric, time: .standard)
        entries.append("\(stamp) [\(processTag)] \(message)")
        if entries.count > maxLogEntries {
            entries.removeFirst(entries.count - maxLogEntries)
        }
        defaults.set(entries, forKey: logKey)
    }

    static func logEntries() -> [String] { defaults.stringArray(forKey: logKey) ?? [] }
    static func clearLog() { defaults.removeObject(forKey: logKey) }

    /// Darwin notification posted after a write another process may need to react to (a Control
    /// Center drop, a schedule firing). Carries nothing — the listener just reloads and looks.
    /// Every process hears it, including the poster.
    static let changeNotification = "com.zachshort.furlough.changed"

    static func announceChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(changeNotification as CFString),
            nil,
            nil,
            true
        )
    }

    private static var processTag: String {
        let id = Bundle.main.bundleIdentifier ?? "?"
        return id.hasSuffix(Furlough.bundleID) ? "app" : String(id.split(separator: ".").last ?? "?")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
