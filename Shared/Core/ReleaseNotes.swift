import Foundation

/// What changed in each version. Notes are data, not code: `release-notes.json` at the repo
/// root is the one copy, bundled into both apps and imported by the site — a second copy would
/// drift. Versioning rules live in README.md; `ReleaseNotesTests` holds the file to them.
enum ReleaseNotes {
    /// The resource, in the app bundle. Named without its extension the way `Bundle` wants it.
    private static let resource = "release-notes"

    // MARK: - The shapes the file decodes into

    /// One version, and everything that changed in it.
    struct Release: Codable, Identifiable, Sendable {
        /// MAJOR.MINOR.PATCH, matching `CFBundleShortVersionString` for the build that carried it.
        let version: String
        /// The day the first build of this version went out, as `yyyy-MM-dd`.
        let date: String
        let channel: Channel
        /// One line, the way the version would be described if only one sentence were allowed.
        let headline: String
        /// The paragraph under it.
        let lead: String
        let changes: [Change]

        var id: String { version }

        /// The version as numbers, for ordering/matching; `1.1` and `1.1.0` compare equal since
        /// early releases omitted the patch.
        var number: Version { Version(version) }

        /// The date as a date, or nil if unparsable; only used for formatting — ordering is
        /// always by version.
        var day: Date? { Self.formatter.date(from: date) }

        /// The day formatted as the rest of Furlough writes one ("11 September 2026"); the raw
        /// string if unparsable.
        var dayLabel: String {
            guard let day else { return date }
            return Self.display.string(from: day)
        }

        private static let display: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_GB")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "d MMMM yyyy"
            return formatter
        }()

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()
    }

    /// One thing that changed, and who it changed for.
    struct Change: Codable, Identifiable, Sendable {
        let kind: Kind
        let platform: Platform
        /// A short noun phrase — the thing, not a sentence about it.
        let title: String
        /// What it means, in one or two sentences. The unit every help page is written in.
        let detail: String

        var id: String { title }
    }

    /// Where a version went. Nothing has reached the App Store yet, so every entry so far says `testflight`.
    enum Channel: String, Codable, Sendable {
        case appStore = "appstore"
        case testFlight = "testflight"
        /// Written down, not yet built. Useful while a version is being assembled.
        case unreleased

        var label: String {
            switch self {
            case .appStore: "App Store"
            case .testFlight: "TestFlight"
            case .unreleased: "Unreleased"
            }
        }
    }

    /// What a change is. Deliberately just three — a longer taxonomy nobody agrees on.
    enum Kind: String, Codable, Sendable, CaseIterable {
        /// Something that was not there before.
        case new
        /// Something that was there, done better.
        case better
        /// Something that was wrong.
        case fixed

        var label: String {
            switch self {
            case .new: "New"
            case .better: "Better"
            case .fixed: "Fixed"
            }
        }
    }

    /// Which app a change happened in; most are `both` since the rules engine is shared, but
    /// enforcement isn't.
    enum Platform: String, Codable, Sendable {
        case both
        case iphone
        case mac

        /// The one this build is. The Mac target is the only thing that compiles for macOS.
        static var current: Platform {
            #if os(macOS)
            .mac
            #else
            .iphone
            #endif
        }

        /// Whether a change marked this way is worth showing on `platform`.
        func shows(on platform: Platform) -> Bool { self == .both || self == platform }

        /// A badge for a change not for everyone; nil where it would be noise (e.g. an
        /// iphone-only change on the iPhone).
        func badge(on platform: Platform) -> String? {
            guard self != .both, self != platform else { return nil }
            return self == .mac ? "Mac" : "iPhone"
        }
    }

    // MARK: - Reading the file

    /// Every release, newest first. Empty if the resource is missing or fails to decode — a
    /// blank screen beats a crash.
    static var all: [Release] { loaded }

    /// Only releases with something to say on `platform`; one whose every change was for the
    /// other device is left out entirely (not shown empty).
    static func all(on platform: Platform = .current) -> [Release] { filter(loaded, to: platform) }

    /// The filtering on its own, testable without a bundled resource (which a test bundle lacks).
    static func filter(_ releases: [Release], to platform: Platform) -> [Release] {
        releases.compactMap { release in
            let changes = release.changes.filter { $0.platform.shows(on: platform) }
            guard !changes.isEmpty else { return nil }
            return Release(
                version: release.version,
                date: release.date,
                channel: release.channel,
                headline: release.headline,
                lead: release.lead,
                changes: changes
            )
        }
    }

    /// The notes for this build's version, or nil if the file has none (a mid-version Debug
    /// build, or a version that changed nothing here). `bundleRelease` tells those apart.
    static func current(on platform: Platform = .current) -> Release? {
        guard let version = bundleVersion else { return nil }
        return all(on: platform).first { $0.number == version }
    }

    /// The entry for this build's version regardless of platform — unlike `current(on:)`,
    /// doesn't drop a version that changed nothing here.
    static func bundleRelease() -> Release? {
        guard let version = bundleVersion else { return nil }
        return loaded.first { $0.number == version }
    }

    /// The newest release with something to say here, for the places that want a line about the
    /// app rather than about this exact build.
    static func newest(on platform: Platform = .current) -> Release? { all(on: platform).first }

    /// `CFBundleShortVersionString`, as numbers. Nil only if there is no Info.plist, which
    /// cannot happen in an app and does happen in a test bundle.
    static var bundleVersion: Version? {
        guard let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !string.isEmpty else { return nil }
        return Version(string)
    }

    /// Decode a file's bytes; separated from `loaded` so tests can hold the real JSON to this
    /// same decoder.
    static func decode(_ data: Data) throws -> [Release] {
        try JSONDecoder().decode(File.self, from: data).versions
    }

    /// The file's top level. `$comment` is for whoever opens it and is deliberately not decoded.
    private struct File: Codable {
        let versions: [Release]
    }

    private static let loaded: [Release] = {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            SharedStore.log("release notes: no \(resource).json in the bundle")
            return []
        }
        do {
            return try decode(try Data(contentsOf: url))
        } catch {
            SharedStore.log("release notes: \(error)")
            return []
        }
    }()
}

// MARK: - Version

/// A marketing version as three numbers, so `1.1` == `1.1.0` and `1.10.0` sorts above `1.9.0` —
/// neither of which a string comparison gets right. Never fails to parse: missing/non-numeric
/// components default to zero.
struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        major = parts.count > 0 ? parts[0] : 0
        minor = parts.count > 1 ? parts[1] : 0
        patch = parts.count > 2 ? parts[2] : 0
    }

    /// The canonical spelling: always three components, as README's Versioning section requires.
    var string: String { "\(major).\(minor).\(patch)" }

    var description: String { string }

    static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
