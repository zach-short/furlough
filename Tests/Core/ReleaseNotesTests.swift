import Foundation
import Testing

/// The release notes, and the rules README's Versioning section sets for them.
///
/// These run against the real `release-notes.json` rather than a fixture, found from `#filePath`
/// rather than from a bundle: the file is a resource of the two apps and not of this test
/// bundle, and a fixture would only prove that a copy of the file is well formed. What is worth
/// testing is that the file both apps and the site actually read is — and that it agrees with
/// `project.yml`, which is the thing `scripts/version.sh --check` and `scripts/archive.sh`
/// enforce at the other end.
@Suite("ReleaseNotes")
struct ReleaseNotesTests {
    /// The repo root, from this file's own path: Tests/Core/ReleaseNotesTests.swift.
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let releases: [ReleaseNotes.Release] = {
        let url = root.appending(path: "release-notes.json")
        return (try? ReleaseNotes.decode(try Data(contentsOf: url))) ?? []
    }()

    /// `MARKETING_VERSION: "1.2.0"` out of project.yml's base settings — the one line
    /// `scripts/version.sh` rewrites, matched on its own indentation so a target's
    /// `$(MARKETING_VERSION)` cannot be mistaken for it.
    private static let marketingVersion: String? = {
        let url = root.appending(path: "project.yml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.split(separator: "\n")
            .first { $0.hasPrefix("    MARKETING_VERSION:") }
            .map { $0.split(separator: ":").dropFirst().joined(separator: ":") }
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }()

    @Test("the file decodes, and has every version in it")
    func decodes() {
        #expect(!Self.releases.isEmpty)
        #expect(Self.releases.allSatisfy { !$0.changes.isEmpty })
        #expect(Self.releases.allSatisfy { !$0.headline.isEmpty && !$0.lead.isEmpty })
        #expect(Self.releases.allSatisfy { release in
            release.changes.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty }
        })
    }

    @Test("every version is three numbers, and no version is written twice")
    func spelling() {
        for release in Self.releases {
            // The shape README asks for: 1.2.0, never 1.2, so one version cannot be written
            // down two ways. Padding is what `Version` does; the file does not rely on it.
            #expect(release.version == release.number.string, "\(release.version) is not MAJOR.MINOR.PATCH")
        }
        let numbers = Self.releases.map(\.number)
        #expect(Set(numbers).count == numbers.count, "a version appears more than once")
    }

    @Test("the file is newest first")
    func ordering() {
        let numbers = Self.releases.map(\.number)
        #expect(numbers == numbers.sorted(by: >), "release-notes.json is not in descending version order")
    }

    @Test("every date is a real day, and they fall with the versions")
    func dates() {
        let days = Self.releases.compactMap(\.day)
        #expect(days.count == Self.releases.count, "a date is not yyyy-MM-dd")
        // Not strictly decreasing: two versions can be cut on one day, as 1.0.0 and 1.0.1 were.
        #expect(days == days.sorted(by: >=), "a newer version is dated before an older one")
    }

    @Test("the version being built has notes")
    func marketingVersionIsCovered() throws {
        let version = try #require(Self.marketingVersion, "no MARKETING_VERSION in project.yml")
        #expect(Version(version).string == version, "MARKETING_VERSION \"\(version)\" is not MAJOR.MINOR.PATCH")
        #expect(
            Self.releases.contains { $0.number == Version(version) },
            "release-notes.json has no entry for \(version). Write the notes before the bump — scripts/version.sh."
        )
    }

    @Test("the newest entry is the version being built, not one ahead of it")
    func newestIsCurrent() throws {
        let version = try #require(Self.marketingVersion)
        let newest = try #require(Self.releases.first)
        // An `unreleased` entry is allowed to sit above the build, which is how a version is
        // assembled before it is cut. Anything else means a bump was forgotten.
        #expect(
            newest.number == Version(version) || newest.channel == .unreleased,
            "release-notes.json's newest entry is \(newest.version) but the build is \(version)"
        )
    }

    @Test("a version compares by number, so 1.1 and 1.1.0 are one version")
    func versionComparison() {
        #expect(Version("1.1") == Version("1.1.0"))
        #expect(Version("1.1.0") < Version("1.1.1"))
        #expect(Version("1.9.0") < Version("1.10.0"), "a string comparison gets this one wrong")
        #expect(Version("1.0.1") < Version("1.1"))
        #expect(Version("2.0.0") > Version("1.99.99"))
        // Never fails to parse: anything unreadable is zero, which sorts below every real
        // version and matches none of them.
        #expect(Version("").string == "0.0.0")
        #expect(Version("not a version").string == "0.0.0")
        #expect(Version("1.2.3.4") == Version("1.2.3"))
    }

    @Test("a change is shown on the platform it is for, and badged only on the other one")
    func platforms() {
        #expect(ReleaseNotes.Platform.both.shows(on: .iphone))
        #expect(ReleaseNotes.Platform.both.shows(on: .mac))
        #expect(ReleaseNotes.Platform.mac.shows(on: .mac))
        #expect(!ReleaseNotes.Platform.mac.shows(on: .iphone))
        // A badge on every row is a badge that says nothing.
        #expect(ReleaseNotes.Platform.both.badge(on: .iphone) == nil)
        #expect(ReleaseNotes.Platform.iphone.badge(on: .iphone) == nil)
        #expect(ReleaseNotes.Platform.mac.badge(on: .iphone) == "Mac")
        #expect(ReleaseNotes.Platform.iphone.badge(on: .mac) == "iPhone")
    }

    @Test("filtering to one platform drops the other platform's changes", arguments: [ReleaseNotes.Platform.iphone, .mac])
    func filtering(platform: ReleaseNotes.Platform) {
        let other: ReleaseNotes.Platform = platform == .iphone ? .mac : .iphone
        for release in ReleaseNotes.filter(Self.releases, to: platform) {
            #expect(!release.changes.isEmpty, "\(release.version) survived filtering with nothing in it")
            #expect(release.changes.allSatisfy { $0.platform != other })
        }
    }

    @Test("a version survives filtering exactly when it has something to say there")
    func filteringDropsEmptyVersions() {
        for platform in [ReleaseNotes.Platform.iphone, .mac] {
            let kept = Set(ReleaseNotes.filter(Self.releases, to: platform).map(\.number))
            let expected = Set(
                Self.releases
                    .filter { release in release.changes.contains { $0.platform.shows(on: platform) } }
                    .map(\.number)
            )
            #expect(kept == expected)
        }
        // The case that made this worth testing: 1.2.0 is the phone's Settings menu and the
        // usage step, and changed nothing on the Mac, so it is not in the Mac's list at all.
        // `bundleRelease()` is what stops the Mac's page reading as if it were on 1.1.0.
        let macVersions = ReleaseNotes.filter(Self.releases, to: .mac).map(\.version)
        #expect(!macVersions.contains("1.2.0"))
        #expect(ReleaseNotes.filter(Self.releases, to: .iphone).map(\.version).contains("1.2.0"))
    }

    @Test("a date is written the way the rest of Furlough writes one")
    func dayLabels() {
        // Built rather than looked up: a fixed date in the file is a test that breaks whenever
        // the file is edited, which is what happened when 1.1.0 was re-dated.
        func label(_ date: String) -> String {
            ReleaseNotes.Release(
                version: "9.9.9", date: date, channel: .unreleased,
                headline: "", lead: "", changes: []
            ).dayLabel
        }
        #expect(label("2026-09-11") == "11 September 2026")
        #expect(label("2026-01-01") == "1 January 2026")
        // A date the file could not parse falls back to what it says, rather than to a wrong day.
        #expect(label("soon") == "soon")
        // And every date actually in the file is a real one, formatted rather than echoed.
        #expect(Self.releases.allSatisfy { $0.dayLabel != $0.date })
    }
}
