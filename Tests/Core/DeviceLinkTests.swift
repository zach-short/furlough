import Foundation
import Testing

/// The link between devices, added 2026-09-10: who is on it, joining, leaving and the refusal
/// to leave under an anchor. Only the pure parts are here; the iCloud store is not touched.
@Suite("Device link: the roster")
struct DeviceLinkRosterTests {
    let noon = at(8, 12, 0)

    func device(_ id: String, _ platform: AnchorRecord.Platform, enrolledAt: Date? = nil) -> LinkedDevice {
        DeviceLink.entry(id: id, name: "", platform: platform, existing: nil, now: enrolledAt ?? at(8, 9, 0))
    }

    @Test("a device is linked once it has written an entry, and not after leaving")
    func linkedByEntry() {
        var roster = DeviceLink.Roster()
        #expect(roster.linked.isEmpty)
        #expect(!roster.isLinked("phone"))
        roster.devices = [device("phone", .phone), device("mac", .mac)]
        #expect(roster.isLinked("phone"))
        #expect(roster.isLinked("mac"))
        #expect(roster.others(than: "mac").map(\.id) == ["phone"])
        roster.devices.removeAll { $0.id == "mac" }
        #expect(!roster.isLinked("mac"))
        #expect(roster.others(than: "phone").isEmpty)
    }

    @Test("a revocation takes a device off, and enrolling again afterwards puts it back")
    func revocation() {
        var roster = DeviceLink.Roster()
        roster.devices = [device("phone", .phone), device("pad", .pad, enrolledAt: at(8, 9, 0))]
        roster.revoked["pad"] = Revocation(by: "phone", at: at(8, 10, 0))
        #expect(!roster.isLinked("pad"))
        #expect(roster.others(than: "phone").isEmpty)
        // Came back at 11: the revocation at 10 is spent.
        roster.devices = [device("phone", .phone), device("pad", .pad, enrolledAt: at(8, 11, 0))]
        #expect(roster.isLinked("pad"))
    }

    @Test("only an iPhone holds a key, and the Mac asks for one besides itself")
    func keys() {
        var roster = DeviceLink.Roster()
        roster.devices = [device("mac", .mac), device("pad", .pad)]
        #expect(!roster.hasKey(besides: "mac"))
        #expect(!device("pad", .pad).canRelease)
        #expect(!device("mac", .mac).canRelease)
        roster.devices.append(device("phone", .phone))
        #expect(device("phone", .phone).canRelease)
        #expect(roster.hasKey(besides: "mac"))
        #expect(roster.hasKey(besides: "pad"))
        // A phone alone on the link has no key *besides* itself, which is the right answer for
        // a question only the Mac asks; the phone's own drop never asks it.
        var alone = DeviceLink.Roster()
        alone.devices = [device("phone", .phone)]
        #expect(!alone.hasKey(besides: "phone"))
    }

    @Test("the entry keeps its enrollment date across refreshes, and names itself")
    func entry() {
        let first = DeviceLink.entry(id: "mac", name: "  ", platform: .mac, existing: nil, now: at(8, 9, 0))
        #expect(first.name == "Mac")
        #expect(first.enrolledAt == at(8, 9, 0))
        #expect(first.lastSeen == at(8, 9, 0))
        let again = DeviceLink.entry(id: "mac", name: "Study Mac", platform: .mac, existing: first, now: noon)
        #expect(again.name == "Study Mac")
        #expect(again.enrolledAt == at(8, 9, 0))
        #expect(again.lastSeen == noon)
        #expect(LinkedDevice.defaultName(for: .pad) == "iPad")
        #expect(LinkedDevice.defaultName(for: .phone) == "iPhone")
    }

    @Test("the others are named for a sentence")
    func othersDescription() {
        var roster = DeviceLink.Roster()
        #expect(roster.othersDescription(than: "mac") == "your other devices")
        roster.devices = [device("mac", .mac), device("phone", .phone)]
        roster.devices[1].name = "iPhone"
        #expect(roster.othersDescription(than: "mac") == "your iPhone")
        roster.devices.append(device("pad", .pad, enrolledAt: at(8, 10, 0)))
        roster.devices[2].name = "iPad"
        #expect(roster.othersDescription(than: "mac") == "your iPhone and iPad")
        roster.devices.append(device("mac2", .mac, enrolledAt: at(8, 11, 0)))
        roster.devices[3].name = "Studio"
        #expect(roster.othersDescription(than: "mac") == "your iPhone, iPad and Studio")
    }

    @Test("the entry round-trips as JSON, an iPad included")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pad = device("pad", .pad)
        let back = try decoder.decode(LinkedDevice.self, from: try encoder.encode(pad))
        #expect(back == pad)
        let revocation = Revocation(by: "phone", at: noon)
        #expect(try decoder.decode(Revocation.self, from: try encoder.encode(revocation)) == revocation)
    }
}

@Suite("Device link: joining and leaving")
struct DeviceLinkJoinLeaveTests {
    let noon = at(8, 12, 0)

    @Test("an install that has heard the other device is grandfathered; one that has not is not")
    func grandfathering() {
        #expect(DeviceLink.grandfathers(lastHeard: at(8, 9, 0), phoneSeen: false))
        #expect(DeviceLink.grandfathers(lastHeard: nil, phoneSeen: true))
        #expect(!DeviceLink.grandfathers(lastHeard: nil, phoneSeen: false))
    }

    @Test("leaving is refused while an anchor holds, here or on the link, and free otherwise")
    func leaving() {
        #expect(DeviceLink.leaveRefusal(anchorHoldsHere: false, anchorHoldsOnLink: false) == nil)
        #expect(DeviceLink.leaveRefusal(anchorHoldsHere: true, anchorHoldsOnLink: false) == .anchored)
        #expect(DeviceLink.leaveRefusal(anchorHoldsHere: false, anchorHoldsOnLink: true) == .anchored)
        #expect(DeviceLink.LeaveRefusal.anchored.message.contains("tag"))
    }

    @Test("the shared record holds while it says anchored and its until has not passed here")
    func recordHolds() {
        #expect(!DeviceLink.recordHolds(nil, now: noon))
        var record = AnchorRecord(
            sequence: 1, isAnchored: true, anchoredAt: at(8, 9, 0), until: nil,
            writer: "phone", platform: .phone, origin: .drop, writtenAt: at(8, 9, 0)
        )
        #expect(DeviceLink.recordHolds(record, now: noon))
        record.until = at(8, 11, 0)
        #expect(!DeviceLink.recordHolds(record, now: noon))
        record.until = at(8, 18, 0)
        #expect(DeviceLink.recordHolds(record, now: noon))
        record.isAnchored = false
        #expect(!DeviceLink.recordHolds(record, now: noon))
    }

    @Test("the guide has four steps on every platform, and says who can release")
    func steps() {
        for platform in [AnchorRecord.Platform.phone, .pad, .mac] {
            let steps = DeviceLink.steps(platform: platform)
            #expect(steps.count == 4)
            #expect(steps[0].detail.contains("Apple Account"))
            #expect(steps[2].detail.contains("never leave"))
            #expect(steps[3].detail.contains("Always, Ask or Never"))
        }
        #expect(DeviceLink.steps(platform: .phone)[1].detail.contains("releases it everywhere"))
        #expect(DeviceLink.steps(platform: .mac)[1].detail.contains("this Mac has no reader"))
        #expect(DeviceLink.steps(platform: .pad)[1].detail.contains("this iPad has no reader"))
    }

    @Test("the settings default the way Zach asked: the site always, the link asks both ways")
    func defaults() throws {
        let preferences = LinkPreferences()
        #expect(preferences.companionSite == .always)
        #expect(preferences.sendAdditions == .ask)
        #expect(preferences.acceptAdditions == .ask)
        // A state written before the settings existed decodes to the same defaults.
        let json = #"{"targets":[],"loosenDelayHours":24}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.link == LinkPreferences())
        #expect(LinkChoice.allCases.map(\.title) == ["Always", "Ask", "Never"])
    }
}

@Suite("Anchor sync: the link status off the link")
struct DeviceLinkStatusTests {
    let noon = at(8, 12, 0)

    /// The record may well be there, and it is deliberately not read: off the link, the status
    /// says so and stops.
    @Test("off the link is not linked, whatever is in iCloud")
    func offTheLink() {
        let record = AnchorRecord(
            sequence: 1, isAnchored: true, anchoredAt: noon, until: nil,
            writer: "phone-9", platform: .phone, origin: .drop, writtenAt: noon
        )
        let status = AnchorSync.LinkStatus(
            cloudAvailable: true, enrolled: false, record: record, thisDevice: "mac-1", platform: .mac, lastHeard: noon
        )
        #expect(!status.isLinked)
        #expect(status.headline == "Off the link")
        #expect(status.detail(now: noon).contains("Settings > Devices"))
        // iCloud being gone still outranks it: that is the thing to fix first.
        let cutOff = AnchorSync.LinkStatus(
            cloudAvailable: false, enrolled: false, record: record, thisDevice: "mac-1", platform: .mac, lastHeard: noon
        )
        #expect(cutOff.headline == "Not linked")
    }
}
