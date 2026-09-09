import Foundation
import os

/// App Group persistence shared by the app and its extensions.
enum SharedStore {
    private static let stateKey = "furlough.state.v1"
    private static let namesKey = "furlough.names.v1"
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

    /// The names Screen Time has told us, by target id. iOS says an app's name in one place
    /// only — the shield, as it blocks it — and the shield must not write the state, so it
    /// writes here instead and every `load` folds these into the targets. Everything that has
    /// to render a name as text rather than as `Label(token)` reads them: the widget, the
    /// notifications, the Live Activity.
    static func learnedNames() -> [String: String] {
        defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:]
    }

    /// Writes down what iOS called a target. Returns true when this is news, so the caller can
    /// reload the surfaces that were showing "This app".
    @discardableResult
    static func learnName(_ name: String, for id: UUID) -> Bool {
        var names = learnedNames()
        guard !name.isEmpty, names[id.uuidString] != name else { return false }
        names[id.uuidString] = name
        defaults.set(names, forKey: namesKey)
        return true
    }

    /// Every save records both clocks, which is what lets Furlough keep its own time. The mark
    /// only advances while the device's clock agrees with it; see `Clock`.
    @discardableResult
    static func save(_ state: SharedState) -> SharedState {
        var state = state
        state.runtime.clock = Clock.stamp(state.runtime.clock)
        do {
            defaults.set(try encoder.encode(state), forKey: stateKey)
        } catch {
            log("Failed to encode state: \(error)")
        }
        return state
    }

    /// Forgets every target, rule, pending change, the Anchor, and the names iOS gave us. The
    /// activity log is kept.
    static func reset() {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: namesKey)
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

    /// The Darwin notification posted after a write another process may be showing: a drop
    /// from Control Center, the monitor's schedule firing. The app listens
    /// (`AppModel.changedElsewhere`) so its screen does not say Free over an anchored phone
    /// until the next activation. It carries nothing; the listener reloads and looks. Every
    /// process hears it, the poster included, and the listener finds nothing new in that case.
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
