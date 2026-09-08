import Foundation

/// A setup as a file: what Furlough hands to another Mac, or to the same person's next phone.
///
/// Deliberately not the stored state. `SharedState` is written for the device holding it —
/// half of it is runtime bookkeeping that means nothing anywhere else, and on the phone a
/// target *is* a Screen Time token, an opaque blob Apple scopes to one device and one install
/// of one app. What travels is the part someone actually decided: which things are managed,
/// what they are called, how much each is worth, and when it is allowed.
///
/// So a Mac file is a whole setup — a Mac target is a bundle identifier or a host, and the
/// other Mac can look those up for itself — while a phone file carries every rule but can only
/// say what the apps they belonged to were called. That is a fact about Screen Time rather
/// than a gap here; see `ExportedTarget.identifier`.
///
/// The Anchor is left out on purpose. Its list is tokens and its key is a physical tag, so
/// none of it would survive the trip, and a file that looked like it carried the Anchor would
/// be worse than one that plainly does not.
struct ConfigExport: Codable, Equatable {
    /// This file's own shape. It changes on its own schedule: `Config.schemaVersion` describes
    /// the store, which is nobody's business but Furlough's, and the two must not be confused.
    static let currentVersion = 1

    var version = ConfigExport.currentVersion
    var platform: Platform
    var exportedAt: Date
    /// The build that wrote the file, for reading a bug report six months from now.
    var appVersion: String?
    var loosenDelayHours: Int
    var targets: [ExportedTarget]

    enum Platform: String, Codable {
        case iOS = "ios"
        case mac

        /// What this build is. Stamped on every export so that an import can tell a phone
        /// file from a Mac one and say so, rather than failing on an unknown target kind.
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
    /// The setup as it stands. Reads the store rather than a view's copy of it, the way
    /// everything else that touches state does.
    static func current(_ state: SharedState = SharedStore.load()) -> ConfigExport {
        ConfigExport(
            platform: .current,
            exportedAt: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            loosenDelayHours: state.config.loosenDelayHours,
            targets: state.config.targets.map(ExportedTarget.init)
        )
    }

    /// Pretty-printed, keys in order, slashes left alone: this is a file someone may well open
    /// and read, and a stable key order makes two of them worth diffing.
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

    /// "Furlough Setup 2026-09-08". No extension: the save panel adds it from the content type.
    var suggestedFilename: String {
        let day = exportedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Furlough Setup \(day)"
    }
}

/// One managed app, website, or category, in the form that travels.
struct ExportedTarget: Codable, Equatable {
    enum Kind: String, Codable { case app, website, category }

    /// The tier as a word. `Utility` is stored as a number, which is right for a blob the
    /// engine reads and wrong for a file a person might open. Exhaustive on purpose: adding
    /// a tier should stop the compiler here rather than silently shift what the numbers mean.
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
    /// What another device can look this up by: a bundle identifier for a Mac app
    /// ("com.google.Chrome"), a host for a website ("youtube.com"). Nil for anything the phone
    /// knows only as a Screen Time token — that token is meaningless off the device that
    /// issued it and cannot be turned back into a bundle identifier, so an import on a phone
    /// has to ask which app this was, with `name` to ask about.
    var identifier: String?
    /// The name the system gave it, where Furlough has been told one. On the phone that is
    /// what the shield learned; on the Mac, what the bundle says.
    var name: String?
    /// Zach's own word for it, when he gave one.
    var nickname: String?
    /// Absent when the tier was never chosen, so that "he said useful" and "nobody said"
    /// stay apart in the file exactly as `Target.utilityLevel` keeps them apart in the store.
    var utility: Tier?
    /// Absent for a target added but never given a rule. Nothing is enforced for those, and
    /// the file should say so rather than invent an open rule for them.
    var rule: Rule?
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
    }
}
