import Foundation
import Testing

/// `ConfigImport.preresolved`: the rows of a setup file the phone can answer for itself.
///
/// Everything else on a phone import has to be answered by hand, because a Screen Time token
/// is scoped to one device and one install and the file carries no identifier for it. A
/// website row is the exception since the phone gained `.host`: it carries a plain host, which
/// is the same string on every device. This is what lets a Mac's setup arrive on a phone as
/// real enforceable targets rather than as rows nobody can map.
@Suite("Pre-resolving a setup's websites")
struct HostImportTests {
    let unanswered = "not said yet"

    func exported(_ kind: ExportedTarget.Kind, _ identifier: String?, nickname: String? = nil) -> ExportedTarget {
        var one = ExportedTarget(Target(kind: .host("placeholder.example")))
        one.kind = kind
        one.identifier = identifier
        one.nickname = nickname
        one.name = nil
        return one
    }

    func export(_ targets: [ExportedTarget]) -> ConfigExport {
        ConfigExport(
            platform: .mac,
            exportedAt: at(8),
            appVersion: nil,
            loosenDelayHours: 24,
            targets: targets
        )
    }

    @Test("a website row carrying a host resolves to a new target with no picker step")
    func websiteWithHostCreates() {
        let plan = ConfigImport.preresolved(
            for: export([exported(.website, "youtube.com")]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        #expect(plan == [.create(.host("youtube.com"))])
    }

    @Test("a website row lands on a host this device already manages")
    func websiteWithHostMatchesExisting() {
        let existing = Target(kind: .host("youtube.com"))
        let plan = ConfigImport.preresolved(
            for: export([exported(.website, "m.youtube.com")]),
            config: makeConfig([existing]),
            unresolved: unanswered
        )
        #expect(plan == [.existing(existing.id)])
    }

    @Test("an app row is left for the person, because a token cannot be looked up")
    func appRowIsLeftAlone() {
        let plan = ConfigImport.preresolved(
            for: export([exported(.app, "com.google.Chrome"), exported(.app, nil)]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        #expect(plan == [.skipped(unanswered), .skipped(unanswered)])
    }

    @Test("a website row a phone wrote carries no host, so it is left for the person")
    func websiteWithoutAHostIsLeftAlone() {
        let plan = ConfigImport.preresolved(
            for: export([exported(.website, nil), exported(.website, "  ")]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        #expect(plan == [.skipped(unanswered), .skipped(unanswered)])
    }

    @Test("a category row is left for the person rather than invented")
    func categoryRowIsLeftAlone() {
        let plan = ConfigImport.preresolved(
            for: export([exported(.category, nil)]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        #expect(plan == [.skipped(unanswered)])
    }

    @Test("the address is normalised, so a full URL lands on the host")
    func addressIsNormalised() {
        let plan = ConfigImport.preresolved(
            for: export([exported(.website, "https://www.YouTube.com/feed/subscriptions")]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        #expect(plan == [.create(.host("youtube.com"))])
    }

    @Test("a website Furlough cannot read says so rather than being left unanswered")
    func unreadableAddressSaysWhy() {
        let plan = ConfigImport.preresolved(
            for: export([exported(.website, "not a website")]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        guard case .skipped(let why) = plan[0] else { Issue.record("expected a skip"); return }
        #expect(why != unanswered)
        #expect(why.contains("not a website"))
    }

    @Test("a name longer than any host is refused")
    func absurdlyLongAddress() {
        let long = String(repeating: "a", count: ConfigImport.maxIdentifierLength + 1) + ".com"
        let plan = ConfigImport.preresolved(
            for: export([exported(.website, long)]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        guard case .skipped(let why) = plan[0] else { Issue.record("expected a skip"); return }
        #expect(why.contains("characters"))
    }

    @Test("a file listing the same site twice resolves it once")
    func sameSiteTwice() {
        let plan = ConfigImport.preresolved(
            for: export([exported(.website, "youtube.com"), exported(.website, "m.youtube.com")]),
            config: makeConfig([]),
            unresolved: unanswered
        )
        #expect(plan[0] == .create(.host("youtube.com")))
        guard case .skipped(let why) = plan[1] else { Issue.record("expected the second to be skipped"); return }
        #expect(why.contains("more than once"))
    }

    @Test("a Mac setup's websites all arrive, and its apps all wait to be asked about")
    func aWholeMacSetup() {
        let rows = [
            exported(.app, "com.google.Chrome"),
            exported(.website, "youtube.com"),
            exported(.website, "reddit.com"),
            exported(.category, nil),
        ]
        let plan = ConfigImport.preresolved(for: export(rows), config: makeConfig([]), unresolved: unanswered)
        #expect(plan[0] == .skipped(unanswered))
        #expect(plan[1] == .create(.host("youtube.com")))
        #expect(plan[2] == .create(.host("reddit.com")))
        #expect(plan[3] == .skipped(unanswered))
    }
}
