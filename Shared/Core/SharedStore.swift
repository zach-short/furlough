import Foundation
import os

/// App Group persistence shared by the app and its extensions.
enum SharedStore {
    private static let stateKey = "furlough.state.v1"
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

    /// The Mac app and its widget share the App Group container. Before the widget existed the
    /// app kept everything in its own defaults, so the first launch that finds the group empty
    /// while the old store has state copies the old store across, once. The old keys are left
    /// where they were. `UserDefaults` is thread-safe but not marked Sendable, hence the unsafe.
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
            return try decoder.decode(SharedState.self, from: data)
        } catch {
            log("Failed to decode state: \(error)")
            return SharedState()
        }
    }

    static func save(_ state: SharedState) {
        do {
            defaults.set(try encoder.encode(state), forKey: stateKey)
        } catch {
            log("Failed to encode state: \(error)")
        }
    }

    /// Forgets every target, rule, pending change, and the Brick. The activity log is kept.
    static func reset() { defaults.removeObject(forKey: stateKey) }

    @discardableResult
    static func mutate(_ body: (inout SharedState) -> Void) -> SharedState {
        var state = load()
        body(&state)
        save(state)
        return state
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
