import Foundation
import Testing

/// What the Anchor offers first: the targets Furlough already blocks, before Apple's picker.
/// The phone shows the offer; which targets are in it, and what taking one in adds, is the
/// engine's, so it is pinned here.
@Suite("Anchor candidates")
struct AnchorCandidatesTests {
    /// YouTube the app, with youtube.com linked onto it.
    func youtube() -> Target {
        var target = Target(kind: .macApp(bundleID: "com.google.Chrome"), nickname: "YouTube", rule: .unrestricted)
        target.also = [.host("youtube.com")]
        return target
    }

    @Test("Only targets with a rule are offered, in the list's order")
    func onlyRuledTargetsAreOffered() {
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        let unset = makeTarget("Reddit", rule: nil)
        let evenings = makeTarget("Instagram", rule: Rule(windows: [window(20 * 60, 22 * 60)], dailyBudgetMinutes: 30))
        let config = makeConfig([tiktok, unset, evenings])
        #expect(config.anchorCandidates.map(\.id) == [tiktok.id, evenings.id])
    }

    @Test("What the anchor holds is not offered; what it holds by half still is")
    func heldTargetsAreNotOffered() {
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        let pair = youtube()
        var config = makeConfig([tiktok, pair])
        config.anchor.kinds = [tiktok.kind, pair.kind]
        #expect(config.anchorCandidates.map(\.id) == [pair.id])
        config.anchor.kinds.append(.host("youtube.com"))
        #expect(config.anchorCandidates.isEmpty)
    }

    @Test("Nothing is offered while nothing has a rule")
    func nothingRuledMeansNothingOffered() {
        let config = makeConfig([makeTarget("Reddit", rule: nil)])
        #expect(config.anchorCandidates.isEmpty)
    }

    @Test("Adding keeps what is held, brings every door, and never repeats one")
    func addingIsAdditiveAndExact() {
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        let pair = youtube()
        var anchor = AnchorProfile()
        anchor.kinds = [.host("reddit.com"), pair.kind]
        let added = anchor.add([tiktok, pair])
        #expect(added)
        #expect(anchor.kinds == [.host("reddit.com"), pair.kind, tiktok.kind, .host("youtube.com")])
    }

    @Test("Adding what is already held is no change")
    func addingHeldIsNoChange() {
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        var anchor = AnchorProfile()
        anchor.kinds = [tiktok.kind]
        let addedHeld = anchor.add([tiktok])
        let addedNothing = anchor.add([])
        #expect(!addedHeld)
        #expect(!addedNothing)
        #expect(anchor.kinds == [tiktok.kind])
    }
}
