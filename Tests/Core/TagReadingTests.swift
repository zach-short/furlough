import Foundation
import Testing

/// The tag decides what happens (rather than a scan behind each button), so the deciding logic
/// is pure and tested here, without a reader — the simulator can't read a real tag.
@Suite("Tag reading")
struct TagReadingTests {
    private let known = Data([0x04, 0xA2, 0x24, 0x11])
    private let stranger = Data([0x04, 0xFF, 0x00, 0x01])

    /// An anchor with something to hold and one key cut for it.
    private func ready() -> AnchorProfile {
        AnchorProfile(kinds: [.host("tiktok.com")], tags: [PairedTag(id: known, name: "Kitchen")])
    }

    @Test("a paired tag lifts an anchor that is down")
    func pairedTagWeighs() {
        var anchor = ready()
        anchor.isAnchored = true
        #expect(anchor.reading(of: known) == .weigh(PairedTag(id: known, name: "Kitchen")))
    }

    @Test("a paired tag anchors when the anchor is up")
    func pairedTagDrops() {
        #expect(ready().reading(of: known) == .drop(PairedTag(id: known, name: "Kitchen")))
    }

    @Test("a key with nothing to lock is refused, and does not read as nothing to anchor")
    func pairedTagWithEmptyList() {
        var anchor = ready()
        anchor.kinds = []
        #expect(anchor.reading(of: known) == .refused("Choose what the anchor holds first."))
    }

    // An empty list under the wider scope still locks the whole phone (everything but nothing).
    @Test("under everything-except an empty list still has something to hold")
    func pairedTagUnderTheWiderScope() {
        var anchor = ready()
        anchor.kinds = []
        anchor.scope = .everythingExcept
        #expect(anchor.reading(of: known) == .drop(PairedTag(id: known, name: "Kitchen")))
    }

    @Test("the first unknown tag is offered as the first key")
    func firstUnknownTag() {
        var anchor = ready()
        anchor.tags = []
        #expect(anchor.reading(of: stranger) == .pairFirst(stranger))
    }

    @Test("a later unknown tag is offered as another key")
    func laterUnknownTag() {
        #expect(ready().reading(of: stranger) == .pairAnother(stranger))
    }

    // Same refusal as the Pair button, reached from the other direction (a tag, not a tap).
    @Test("an unknown tag is refused while the anchor is down")
    func unknownTagUnderTheLock() {
        var anchor = ready()
        anchor.isAnchored = true
        #expect(anchor.reading(of: stranger) == .refused("Unanchor first."))
    }

    @Test("an unknown tag is refused past the cap")
    func unknownTagPastTheCap() {
        var anchor = ready()
        anchor.tags = (0..<Furlough.maxAnchorTags).map {
            PairedTag(id: Data([UInt8($0)]), name: "Tag \($0)")
        }
        guard case .refused(let why) = anchor.reading(of: stranger) else {
            Issue.record("a tag past the cap should be refused")
            return
        }
        #expect(why.contains("\(Furlough.maxAnchorTags) tags is the limit"))
    }

    // One refusal read from two places, so the Pair button and a held-up tag can't drift apart.
    @Test("the pairing refusal is nil when there is room and no lock")
    func pairingRefusalIsTheSameAnswer() {
        var anchor = ready()
        #expect(anchor.pairingRefusal == nil)
        anchor.isAnchored = true
        #expect(anchor.pairingRefusal == "Unanchor first.")
    }
}
