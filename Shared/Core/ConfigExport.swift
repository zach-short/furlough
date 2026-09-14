import Foundation

/// A portable setup file — deliberately not the stored state. `SharedState` carries
/// device-local runtime bookkeeping and, on the phone, Screen Time tokens that are opaque and
/// device-scoped; this carries only what someone actually decided (managed things, names,
/// tiers, rules). A Mac file can fully identify its targets by bundle ID/host; a phone file can
/// only carry names, since a token can't be resolved back on import (see
/// `ExportedTarget.identifier`).
///
/// The Anchor is deliberately excluded — its list is tokens and its key is a physical tag, so
/// none of it would survive the trip.
struct ConfigExport: Codable, Equatable {
    /// Independent of `Config.schemaVersion`, which describes the store instead — don't confuse
    /// the two.
    static let currentVersion = 1

    var version = ConfigExport.currentVersion
    var platform: Platform
    var exportedAt: Date
    var appVersion: String?
    var loosenDelayHours: Int
    var targets: [ExportedTarget]

    enum Platform: String, Codable {
        case iOS = "ios"
        case mac

        static var current: Platform {
            #if os(iOS)
            .iOS
            #else
            .mac
            #endif
        }
    }
}

extension ConfigExport {
    static func current(_ state: SharedState = SharedStore.load()) -> ConfigExport {
        ConfigExport(
            platform: .current,
            exportedAt: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            loosenDelayHours: state.config.loosenDelayHours,
            targets: state.config.targets.map(ExportedTarget.init)
        )
    }

    /// Pretty-printed with sorted keys: this is a file someone may open by hand, and stable
    /// ordering makes two exports diffable.
    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ConfigExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConfigExport.self, from: data)
    }

    /// e.g. "Furlough Setup 2026-09-08" — no extension; the save panel adds it.
    var suggestedFilename: String {
        let day = exportedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Furlough Setup \(day)"
    }
}

/// One managed app, website, or category, in the form that travels.
struct ExportedTarget: Codable, Equatable {
    enum Kind: String, Codable { case app, website, category }

    /// `Utility` is stored as a number internally; this spells it out for a human-readable
    /// file. Exhaustive switches below so adding a tier fails to compile here instead of
    /// silently shifting what the numbers mean.
    enum Tier: String, Codable {
        case essential, useful, idle, hazard

        init(_ utility: Utility) {
            switch utility {
            case .essential: self = .essential
            case .useful: self = .useful
            case .idle: self = .idle
            case .hazard: self = .hazard
            }
        }

        var utility: Utility {
            switch self {
            case .essential: .essential
            case .useful: .useful
            case .idle: .idle
            case .hazard: .hazard
            }
        }
    }

    var kind: Kind
    /// Nil for a Screen Time token (device-scoped, meaningless elsewhere) — import on a phone
    /// must ask which app this was, using `name`.
    var identifier: String?
    var name: String?
    var nickname: String?
    /// Absent (not defaulted) when never explicitly chosen, matching `Target.utilityLevel`.
    var utility: Tier?
    /// Absent for a target added but never given a rule.
    var rule: Rule?
    /// Hosts only — a linked app-picker website token can't travel either, so only a
    /// typed-by-name site survives the round trip.
    var alsoBlocks: [String]?
}

extension ExportedTarget {
    init(_ target: Target) {
        switch target.kind {
        #if os(iOS)
        case .application:
            kind = .app
            identifier = nil
        case .webDomain:
            kind = .website
            identifier = nil
        case .category:
            kind = .category
            identifier = nil
        // A typed host, unlike a token, is a string another device can look up.
        case .host(let host):
            kind = .website
            identifier = host
        #else
        case .macApp(let bundleID):
            kind = .app
            identifier = bundleID
        case .host(let host):
            kind = .website
            identifier = host
        #endif
        }
        name = (target.systemName?.isEmpty ?? true) ? nil : target.systemName
        nickname = target.nickname.isEmpty ? nil : target.nickname
        utility = target.utilityLevel.map(Tier.init)
        rule = target.rule
        // Only host-named linked doors travel; a linked token is dropped rather than guessed.
        let linked = (target.also ?? []).compactMap(\.hostName)
        alsoBlocks = linked.isEmpty ? nil : linked
    }
}
