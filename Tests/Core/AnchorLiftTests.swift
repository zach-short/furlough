import Foundation
import Testing

/// The lift a Shortcut names as a time of day, resolved the way the Anchor screen resolves its
/// own "Lifts at": the next such time that the monitor can still wake for.
@Suite("Anchor lift from a time of day")
struct AnchorLiftTests {
    let sevenAM = 7 * 60

    @Test("at 11 PM, 7 AM is tomorrow morning")
    func lateEvening() {
        #expect(Policy.liftDate(atMinute: sevenAM, from: at(8, 23, 0), calendar: cal) == at(9, 7, 0))
    }

    @Test("at 6 AM, 7 AM is this morning")
    func earlyMorning() {
        #expect(Policy.liftDate(atMinute: sevenAM, from: at(8, 6, 0), calendar: cal) == at(8, 7, 0))
    }

    @Test("a lift under fifteen minutes away rolls to tomorrow; exactly fifteen does not")
    func minimumWake() {
        #expect(Policy.liftDate(atMinute: sevenAM, from: at(8, 6, 46), calendar: cal) == at(9, 7, 0))
        #expect(Policy.liftDate(atMinute: sevenAM, from: at(8, 6, 45), calendar: cal) == at(8, 7, 0))
        #expect(Policy.liftDate(atMinute: sevenAM, from: at(8, 7, 0), calendar: cal) == at(9, 7, 0))
    }

    @Test("midnight is a time like any other")
    func midnight() {
        #expect(Policy.liftDate(atMinute: 0, from: at(8, 23, 30), calendar: cal) == at(9, 0, 0))
        #expect(Policy.liftDate(atMinute: 0, from: at(8, 0, 10), calendar: cal) == at(9, 0, 0))
    }

    // The resolved date always clears the minimum, so the refusal is reachable only by a caller
    // that hands `Policy.drop` a raw date — which is what the screen and the intent never do.
    @Test("a resolved lift is never refused as too soon, and a raw one under the minimum is")
    func refusal() {
        let tiktok = makeTarget("TikTok", rule: nil)
        var config = makeConfig([tiktok])
        config.anchor.kinds = [tiktok.kind]
        config.anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        let now = at(8, 6, 50)
        var resolved = config
        #expect(Policy.drop(&resolved, now: now, until: Policy.liftDate(atMinute: sevenAM, from: now, calendar: cal)) == nil)
        #expect(resolved.anchor.until == at(9, 7, 0))
        var raw = config
        #expect(Policy.drop(&raw, now: now, until: at(8, 7, 0)) == .tooSoon)
        #expect(!raw.anchor.isAnchored)
    }
}
