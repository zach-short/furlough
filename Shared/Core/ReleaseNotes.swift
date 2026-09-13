import Foundation

/// What changed in each version, and which version you are looking at.
///
/// The notes are data rather than code: `release-notes.json` at the root of the repo is the one
/// copy, bundled into both apps and imported by the site's releases page. A second copy would
/// drift the day someone edited one of them, and the thing that makes release notes worth
/// reading is that they are true.
///
/// The rules for the numbers — when a change forces a minor rather than a patch, and what has to
/// be in the file before `scripts/archive.sh` will cut a build — are the Versioning section of
/// README.md. `Tests/Core/ReleaseNotesTests.swift` holds the file to them.
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

        /// The version as numbers, for ordering and for matching a build. `1.1` and `1.1.0` are
        /// the same version — the first two releases were written without the patch component,
        /// and a build of either has to find its own notes.
        var number: Version { Version(version) }

        /// The date as a date, or nil if the file says something that is not one. Only the
        /// formatting uses this; ordering is by version, which cannot be ambiguous.
        var day: Date? { Self.formatter.date(from: date) }

        /// The day as the rest of Furlough writes one: "11 September 2026", the format the
        /// privacy policy's own date already uses. The file's own string if it is not a date.
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

    /// Where a version went. Nothing has reached the App Store yet, so every entry so far says
    /// `testflight`; the site says as much beside them rather than implying a public release.
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

    /// What a change is. Three, deliberately: a longer list turns into a taxonomy nobody agrees
    /// on, and every one of these answers "should I care?" differently.
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

    /// Which app a change happened in. The rules engine is shared, so most changes are `both`;
    /// enforcement is not shared at all, so the ones that are not tend to be whole features.
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

        /// What to put on a change that is not for everyone. Nil where it would be noise: on the
        /// iPhone a change marked `iphone` is simply the news.
        func badge(on platform: Platform) -> String? {
            guard self != .both, self != platform else { return nil }
            return self == .mac ? "Mac" : "iPhone"
        }
    }

    // MARK: - Reading the file

    /// Every release, newest first, exactly as the file has them. Empty if the resource is
    /// missing or will not decode, which is the right failure: a screen with nothing on it is
    /// better than a crash in an app whose whole job is to still be running.
    static var all: [Release] { loaded }

    /// Only the releases with something to say on this platform, each carrying only the changes
    /// that apply here. A release whose every change was for the other device is left out
    /// entirely rather than shown empty.
    static func all(on platform: Platform = .current) -> [Release] {
        loaded.compactMap { release in
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

    /// The notes for the version this build is, or nil when the file has none for it — which a
    /// Debug build off a branch mid-version legitimately is.
    static func current(on platform: Platform = .current) -> Release? {
        guard let version = bundleVersion else { return nil }
        return all(on: platform).first { $0.number == version }
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

    /// Decode a file's bytes. Separate from `loaded` so the tests can hold the real
    /// `release-notes.json` to the same decoder the apps use rather than a copy of it.
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

/// A marketing version as three numbers, so `1.1` and `1.1.0` compare equal and `1.10.0` sorts
/// above `1.9.0` — neither of which a string comparison gets right.
///
/// Anything the string does not supply is zero, and anything that is not a number is zero, so
/// this never fails to parse. A version that cannot be read is 0.0.0, which sorts below every
/// real one and matches none of them.
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

    /// The canonical spelling: always three components, which is what README's Versioning
    /// section asks every new version to be written as.
    var string: String { "\(major).\(minor).\(patch)" }

    var description: String { string }

    static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
