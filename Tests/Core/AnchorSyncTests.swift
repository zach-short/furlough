import Foundation
import Testing

/// The anchor across devices, added 2026-09-09: what one device does with the record the
/// other wrote. Only `merge` and `macDrop` are here; the iCloud store itself is not touched.
@Suite("Anchor sync: merging the other device's record")
struct AnchorSyncMergeTests {
    let noon = at(8, 12, 0)

    func local(anchored: Bool, until: Date? = nil, sequence: Int = 3) -> AnchorProfile {
        var anchor = AnchorProfile(kinds: [.host("tiktok.com")])
        anchor.isAnchored = anchored
        anchor.anchoredAt = anchored ? at(8, 9, 0) : nil
        anchor.until = until
        anchor.sequence = sequence
        return anchor
    }

    func record(
        sequence: Int,
        anchored: Bool,
        until: Date? = nil,
        platform: AnchorRecord.Platform = .phone,
        origin: AnchorRecord.Origin = .drop
    ) -> AnchorRecord {
        AnchorRecord(
            sequence: sequence, isAnchored: anchored, anchoredAt: anchored ? at(8, 11, 0) : nil, until: until,
            writer: "other", platform: platform, origin: origin, writtenAt: at(8, 11, 0)
        )
    }

    @Test("a stale record changes nothing, whatever it says")
    func stale() {
        let up = local(anchored: false)
        let same = AnchorSync.merge(local: up, remote: record(sequence: 3, anchored: true), now: noon)
        #expect(same.profile == up)
        let older = AnchorSync.merge(local: up, remote: record(sequence: 2, anchored: true), now: noon)
        #expect(older.profile == up)
        let down = local(anchored: true)
        let release = AnchorSync.merge(local: down, remote: record(sequence: 3, anchored: false, origin: .tagScan), now: noon)
        #expect(release.profile == down)
    }

    @Test("a drop from the other device anchors this one, and the sequence moves on")
    func drop() {
        let merged = AnchorSync.merge(local: local(anchored: false), remote: record(sequence: 4, anchored: true), now: noon)
        #expect(merged.profile.isAnchored)
        #expect(merged.profile.anchoredAt == at(8, 11, 0))
        #expect(merged.profile.until == nil)
        #expect(merged.profile.sequence == 4)
        // The list is this device's own and is not touched.
        #expect(merged.profile.kinds == [.host("tiktok.com")])
    }

    @Test("a release is taken only from a phone's tag scan")
    func releaseOnlyFromAPhoneTag() {
        let down = local(anchored: true)
        let fromMac = AnchorSync.merge(local: down, remote: record(sequence: 4, anchored: false, platform: .mac, origin: .tagScan), now: noon)
        #expect(fromMac.profile.isAnchored)
        // The sequence still moves on, so the next local write is past what was refused.
        #expect(fromMac.profile.sequence == 4)
        let lift = AnchorSync.merge(local: down, remote: record(sequence: 5, anchored: false, origin: .lift), now: noon)
        #expect(lift.profile.isAnchored)
        let plainDrop = AnchorSync.merge(local: down, remote: record(sequence: 6, anchored: false, origin: .drop), now: noon)
        #expect(plainDrop.profile.isAnchored)
        let tag = AnchorSync.merge(local: down, remote: record(sequence: 7, anchored: false, origin: .tagScan), now: noon)
        #expect(!tag.profile.isAnchored)
        #expect(tag.profile.anchoredAt == nil)
        #expect(tag.profile.until == nil)
        #expect(tag.profile.sequence == 7)
    }

    @Test("a remote until is judged by this device's own clock")
    func untilByTheLocalClock() {
        // The phone dropped until 6 PM. Furlough's time here is noon: anchored until 6.
        let sixPM = at(8, 18, 0)
        let early = AnchorSync.merge(local: local(anchored: false), remote: record(sequence: 4, anchored: true, until: sixPM), now: noon)
        #expect(early.profile.isAnchored)
        #expect(early.profile.until == sixPM)
        #expect(early.profile.isHolding(at: at(8, 17, 59)))
        #expect(!early.profile.isHolding(at: sixPM))
        // Furlough's time here is 7 PM — the wall clock may say anything, the caller passes the
        // trusted one — so the drop is already over and nothing drops.
        let late = AnchorSync.merge(local: local(anchored: false), remote: record(sequence: 4, anchored: true, until: sixPM), now: at(8, 19, 0))
        #expect(!late.profile.isAnchored)
        #expect(late.profile.sequence == 4)
    }

    @Test("a drop over an anchor already down can only lengthen the hold")
    func onlyTightens() {
        let sixPM = at(8, 18, 0)
        let ninePM = at(8, 21, 0)
        // Tag-only here; a timed drop there does not shorten it.
        let tagOnly = AnchorSync.merge(local: local(anchored: true), remote: record(sequence: 4, anchored: true, until: sixPM), now: noon)
        #expect(tagOnly.profile.until == nil)
        #expect(tagOnly.profile.isAnchored)
        // Until 6 here; a tag-only drop there makes it tag-only.
        let widened = AnchorSync.merge(local: local(anchored: true, until: sixPM), remote: record(sequence: 4, anchored: true), now: noon)
        #expect(widened.profile.until == nil)
        // Until 6 here; until 9 there lengthens it, until 6 again changes nothing.
        let later = AnchorSync.merge(local: local(anchored: true, until: sixPM), remote: record(sequence: 4, anchored: true, until: ninePM), now: noon)
        #expect(later.profile.until == ninePM)
        let same = AnchorSync.merge(local: local(anchored: true, until: sixPM), remote: record(sequence: 4, anchored: true, until: sixPM), now: noon)
        #expect(same.profile.until == sixPM)
        #expect(same.profile.anchoredAt == at(8, 9, 0))
    }

    @Test("a timed anchor that has expired here is dropped again by a newer drop")
    func expiredHereDropsAgain() {
        let expired = local(anchored: true, until: at(8, 11, 0))
        #expect(!expired.isHolding(at: noon))
        let merged = AnchorSync.merge(local: expired, remote: record(sequence: 4, anchored: true), now: noon)
        #expect(merged.profile.isHolding(at: noon))
        #expect(merged.profile.until == nil)
        #expect(merged.profile.anchoredAt == at(8, 11, 0))
    }

    @Test("the record round-trips as JSON")
    func roundTrip() throws {
        let record = record(sequence: 9, anchored: true, until: at(8, 18, 0), platform: .mac, origin: .drop)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(AnchorRecord.self, from: try encoder.encode(record))
        #expect(back == record)
    }
}

@Suite("Anchor sync: the Mac's drop")
struct AnchorSyncMacDropTests {
    let noon = at(8, 12, 0)

    @Test("the Mac drops only with something to hold, iCloud, and a phone that has been heard from")
    func refusals() {
        var config = makeConfig([])
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: true, cloudAvailable: true) == .noList)
        config.anchor.kinds = [.macApp(bundleID: "com.google.Chrome")]
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: false, cloudAvailable: true) == .noPhone)
        #expect(!config.anchor.isAnchored)
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: true, cloudAvailable: true) == nil)
        #expect(config.anchor.isAnchored)
        #expect(config.anchor.anchoredAt == noon)
        #expect(config.anchor.until == nil)
        #expect(config.anchor.sequence == 1)
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: true, cloudAvailable: true) == .alreadyAnchored)
        // An empty allowlist is the whole Mac, which is something to hold.
        var everything = makeConfig([])
        everything.anchor.scope = .everythingExcept
        #expect(AnchorSync.macDrop(&everything, now: noon, phoneSeen: true, cloudAvailable: true) == nil)
    }

    /// The lock-with-no-key guard, in the case `phoneSeen` alone cannot see: the latch is set
    /// once and never cleared, so a Mac signed out of iCloud after its first sync would other-
    /// wise still take a drop that nothing on earth could lift.
    @Test("a Mac signed out of iCloud refuses to drop, however many phones it has heard from")
    func refusesWithoutCloud() {
        var config = makeConfig([])
        config.anchor.kinds = [.macApp(bundleID: "com.google.Chrome")]
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: true, cloudAvailable: false) == .noCloud)
        #expect(!config.anchor.isAnchored)
        #expect(config.anchor.sequence == 0)
        // Ahead of the phone: signed out, whether a phone has ever been heard from is moot,
        // and the account is the thing to go and fix.
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: false, cloudAvailable: false) == .noCloud)
        // Behind the list, which is on this screen and fixable without leaving it.
        var empty = makeConfig([])
        #expect(AnchorSync.macDrop(&empty, now: noon, phoneSeen: true, cloudAvailable: false) == .noList)
    }

    /// An anchor already down is not touched by the account going away. Only dropping is
    /// refused; a hold and its release are the phone's business and survive on their own.
    @Test("losing iCloud does not lift an anchor already holding")
    func cutOffLeavesAHoldAlone() {
        var config = makeConfig([])
        config.anchor.kinds = [.macApp(bundleID: "com.google.Chrome")]
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: true, cloudAvailable: true) == nil)
        #expect(config.anchor.isHolding(at: noon))
        #expect(AnchorSync.macDrop(&config, now: noon, phoneSeen: true, cloudAvailable: false) == .noCloud)
        #expect(config.anchor.isHolding(at: noon))
    }

    @Test("every drop moves the sequence on, on the phone too")
    func sequenceMoves() {
        var config = makeConfig([])
        config.anchor.kinds = [.host("tiktok.com")]
        config.anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        config.anchor.sequence = 7
        #expect(Policy.drop(&config, now: noon) == nil)
        #expect(config.anchor.sequence == 8)
        // A scheduled drop that changes something moves it; one that changes nothing does not.
        var scheduled = makeConfig([])
        scheduled.anchor.kinds = [.host("tiktok.com")]
        scheduled.anchor.tags = [PairedTag(id: Data([1]), name: "Home")]
        scheduled.anchor.schedules = [AnchorSchedule(minuteOfDay: 22 * 60)]
        #expect(Policy.scheduledDrop(&scheduled, minute: 22 * 60, now: at(8, 22, 0), calendar: cal) != nil)
        #expect(scheduled.anchor.sequence == 1)
        #expect(Policy.scheduledDrop(&scheduled, minute: 22 * 60, now: at(8, 22, 1), calendar: cal) == nil)
        #expect(scheduled.anchor.sequence == 1)
    }

    @Test("the refusals have words, and the Mac's name the phone")
    func messages() {
        #expect(Policy.DropRefusal.noList.message.contains("Choose"))
        #expect(Policy.DropRefusal.noPhone.message.contains("iPhone"))
        // The instruction that actually clears the refusal. Pairing a tag publishes nothing,
        // so the message must ask for the drop; this pins that it does not go back to asking
        // only for the pairing.
        #expect(Policy.DropRefusal.noPhone.message.contains("Drop anchor"))
        #expect(Policy.DropRefusal.noCloud.message.contains("iCloud"))
        #expect(Policy.DropRefusal.noCloud.message == AnchorSync.cutOffWarning)
    }

    /// The cut-off warning is written as a `\`-continued literal, where a missing space runs two
    /// words together and a kept one doubles up, and neither shows in a diff. It is also the
    /// only string here that a person reads as a paragraph in a banner, so: one paragraph, one
    /// space between words, and it names both the harm and the way out.
    @Test("the cut-off warning reads as one clean paragraph and says what to do")
    func cutOffWarningReads() {
        let warning = AnchorSync.cutOffWarning
        #expect(!warning.contains("  "))
        #expect(!warning.contains("\n"))
        #expect(warning.hasSuffix("."))
        // The harm, said on the device reading it. This bundle is built for macOS.
        #expect(warning.contains("this Mac"))
        #expect(warning.contains("System Settings"))
        // Says iCloud cannot be reached, and stops there. An earlier version of this named a
        // signed-out account as the cause, which the probe behind it cannot actually tell:
        // `isAvailable` reports an unusable store, not an absent account.
        #expect(warning.contains("cannot reach iCloud"))
        #expect(!warning.contains("iCloud Drive"))
    }

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test("an anchor stored before it had a sequence starts at zero")
    func decodesWithoutSequence() throws {
        let json = #"{"targets":[],"loosenDelayHours":24,"anchor":{"kinds":[],"isAnchored":false}}"#
        let config = try decoder.decode(Config.self, from: Data(json.utf8))
        #expect(config.anchor.sequence == 0)
    }
}
