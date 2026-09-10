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

    @Test("Removing takes every door and leaves the rest alone")
    func removingTakesEveryDoor() {
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        let pair = youtube()
        var anchor = AnchorProfile()
        anchor.kinds = [tiktok.kind, pair.kind, .host("youtube.com"), .host("reddit.com")]
        let removed = anchor.remove([pair])
        #expect(removed)
        #expect(anchor.kinds == [tiktok.kind, .host("reddit.com")])
    }

    @Test("Removing what is not held is no change")
    func removingUnheldIsNoChange() {
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        let pair = youtube()
        var anchor = AnchorProfile()
        anchor.kinds = [tiktok.kind]
        let removedOther = anchor.remove([pair])
        let removedNothing = anchor.remove([])
        #expect(!removedOther)
        #expect(!removedNothing)
        #expect(anchor.kinds == [tiktok.kind])
    }

    /// The rule editor's Anchor row: a target the anchor holds by one door and not the other
    /// reads as off, and turning it on is what closes the second one.
    @Test("A target is listed only once every door is on the list")
    func listedMeansEveryDoor() {
        let pair = youtube()
        var anchor = AnchorProfile()
        anchor.kinds = [pair.kind]
        #expect(!anchor.lists(pair))
        anchor.add([pair])
        #expect(anchor.lists(pair))
    }

    /// The small anchor on a rules row, which has to be right under both scopes: the list is
    /// what is held under one and what is spared under the other.
    @Test("What a drop would hold is read the right way round under either scope")
    func willHoldFollowsTheScope() {
        let tiktok = makeTarget("TikTok", rule: .alwaysBlocked)
        let messages = makeTarget("Messages", rule: .unrestricted)
        var anchor = AnchorProfile()
        anchor.kinds = [tiktok.kind]
        #expect(anchor.willHold(tiktok))
        #expect(!anchor.willHold(messages))
        anchor.scope = .everythingExcept
        #expect(!anchor.willHold(tiktok))
        #expect(anchor.willHold(messages))
    }

    /// A linked target is held when either door is: the halves are one thing, and one of them
    /// shut is the whole of it shut.
    @Test("One held door holds the whole target")
    func oneDoorHoldsTheTarget() {
        let pair = youtube()
        var anchor = AnchorProfile()
        anchor.kinds = [.host("youtube.com")]
        #expect(anchor.willHold(pair))
        #expect(!anchor.lists(pair))
    }
}
