import Foundation

/// How much a device does on its own when something could cross to, or from, another one.
///
/// Three answers and never a fourth: *always* acts without asking, *ask* offers and waits, and
/// *never* stays quiet. Each of the link's settings is one of these, so a person learns the
/// scale once. None of them is a loosening when changed — turning one down blocks nothing that
/// was blocked a moment ago, it only stops adding — so none waits out a delay.
enum LinkChoice: String, Codable, CaseIterable, Sendable {
    case always
    case ask
    case never

    var title: String {
        switch self {
        case .always: "Always"
        case .ask: "Ask"
        case .never: "Never"
        }
    }
}

/// The three settings about what crosses between devices, kept per device in `Config`. Each
/// device answers for itself: one Mac can take everything the phone adds while another asks
/// first, and the phone can send without either of them having any say in how it is received.
///
/// `companionSite` is not really about the link — it is about the website an app is also at,
/// on this device alone — but it is the same kind of question, and the default Zach asked for
/// (2026-09-10) is the reason it is here: adding an app blocks its site unless told otherwise.
struct LinkPreferences: Codable, Equatable, Sendable {
    /// Whether adding an app also blocks the website it is also at, as one row.
    var companionSite: LinkChoice = .always
    /// Whether what this device adds is sent to the other devices on the link.
    var sendAdditions: LinkChoice = .ask
    /// Whether what another device adds is added here.
    var acceptAdditions: LinkChoice = .ask
}

/// What one device says about itself to the others: its name, what it is, and whether it holds
/// a key. Each device writes only its own entry to iCloud, under its own key, so the roster is
/// never one blob two devices fight over — it is the set of entries, and a device that leaves
/// deletes its own.
struct LinkedDevice: Codable, Equatable, Identifiable, Sendable {
    /// `AnchorSync.deviceID`: the same string the anchor record is signed with.
    var id: String
    /// What the person called it. iOS stopped telling third-party apps the device's name in
    /// iOS 16, so on a phone this is typed in the guide; the Mac offers `Host.localizedName`.
    var name: String
    var platform: AnchorRecord.Platform
    /// When it joined. A revocation older than this is spent: the device came back afterwards.
    var enrolledAt: Date
    /// When it last wrote anything here. Refreshed by every enrollment and every addition, so a
    /// device gone quiet for a month reads as one.
    var lastSeen: Date
    /// Whether a tag can be read on it, which is the only thing that releases an anchor. An
    /// iPhone; never an iPad or a Mac, neither of which has a reader.
    var canRelease: Bool

    /// The platform's name where a device has not been given one.
    static func defaultName(for platform: AnchorRecord.Platform) -> String {
        switch platform {
        case .phone: "iPhone"
        case .pad: "iPad"
        case .mac: "Mac"
        }
    }
}

/// One device taking another off the link, written under the revoked device's id so that
/// device finds it on its next read and un-enrolls itself. Any linked device may write one.
struct Revocation: Codable, Equatable, Sendable {
    var by: String
    var at: Date
}

/// The link between a person's devices: who is on it, and the rules for joining and leaving.
///
/// It used to be implicit. Any device signed into the same Apple Account read the one anchor
/// record, so two installs were linked the moment they existed, with nothing to switch on and
/// nothing that said so. Zach's call (2026-09-10) is that a person opts each device in, is told
/// in steps what the link carries, and can take any device off it — which is what this is.
/// Nothing crosses to or from a device that is not enrolled: `AnchorSync.pull` refuses the
/// anchor, and `SharedAdditions` refuses what was added.
///
/// The roster is pure and read from whatever store hands it the entries, so joining, leaving and
/// the refusal to leave under an anchor are all testable without an iCloud account.
enum DeviceLink {
    // MARK: The roster

    /// Every device that has written an entry, and every revocation, as read. Ask `linked` for
    /// who is actually on the link.
    struct Roster: Equatable, Sendable {
        var devices: [LinkedDevice] = []
        var revoked: [String: Revocation] = [:]

        /// The devices on the link: written, and not revoked since they enrolled. A revocation
        /// older than the enrollment is spent — the device was taken off and came back.
        var linked: [LinkedDevice] {
            devices.filter { device in
                guard let revocation = revoked[device.id] else { return true }
                return revocation.at < device.enrolledAt
            }
            .sorted { $0.enrolledAt < $1.enrolledAt }
        }

        func isLinked(_ id: String) -> Bool { linked.contains { $0.id == id } }

        func device(_ id: String) -> LinkedDevice? { linked.first { $0.id == id } }

        /// Everyone on the link but `id`.
        func others(than id: String) -> [LinkedDevice] { linked.filter { $0.id != id } }

        /// Whether some device other than `id` can release an anchor. The Mac's drop reads
        /// this: a Mac with no key-holder on the link would be a lock with no key.
        func hasKey(besides id: String) -> Bool { others(than: id).contains(where: \.canRelease) }

        /// What to call the other devices, for a sentence: "your iPhone", "your Mac and iPad",
        /// "your other devices" when there are many.
        func othersDescription(than id: String) -> String {
            let names = others(than: id).map(\.name)
            switch names.count {
            case 0: return "your other devices"
            case 1: return "your \(names[0])"
            case 2: return "your \(names[0]) and \(names[1])"
            default: return "your \(names.dropLast().joined(separator: ", ")) and \(names.last!)"
            }
        }
    }

    // MARK: Leaving

    /// Why a device cannot come off the link right now.
    enum LeaveRefusal: Equatable, Sendable {
        /// An anchor is holding somewhere on the link. Taking a device off while it holds
        /// would either leave that device locked with no key or release it, and both are the
        /// one thing the Anchor exists to make impossible.
        case anchored

        var message: String {
            switch self {
            case .anchored:
                "The anchor is down. Scan your tag to release it, and then any device can be taken off the link."
            }
        }
    }

    /// Whether a device may leave. Pure: the caller says whether an anchor holds anywhere —
    /// here, by its own profile, or on the link, by the shared record — and that is the whole
    /// question. Leaving is otherwise instant, because with no anchor down the link holds
    /// nothing that leaving would let go of.
    static func leaveRefusal(anchorHoldsHere: Bool, anchorHoldsOnLink: Bool) -> LeaveRefusal? {
        anchorHoldsHere || anchorHoldsOnLink ? .anchored : nil
    }

    /// Whether the shared record says an anchor is holding at `now`, by this device's clock.
    static func recordHolds(_ record: AnchorRecord?, now: Date) -> Bool {
        guard let record, record.isAnchored else { return false }
        guard let until = record.until else { return true }
        return now < until
    }

    // MARK: Joining

    /// Whether an install that predates the roster is put on the link without being asked.
    ///
    /// Zach's call: the two devices he has linked today keep working after the update. What
    /// proves a device was linked is that it has heard the other one — `lastHeard` on either
    /// platform, or the Mac's older `phoneSeen` latch — and a device that has only ever heard
    /// itself, or nothing, starts off the link and is shown the guide like anyone new.
    static func grandfathers(lastHeard: Date?, phoneSeen: Bool) -> Bool {
        lastHeard != nil || phoneSeen
    }

    /// The entry a device writes when it joins, or refreshes when it writes anything else.
    /// `enrolledAt` is kept from the existing entry so a refresh does not spend a revocation
    /// that has not been read yet.
    static func entry(
        id: String,
        name: String,
        platform: AnchorRecord.Platform,
        existing: LinkedDevice?,
        now: Date
    ) -> LinkedDevice {
        LinkedDevice(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? LinkedDevice.defaultName(for: platform)
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            platform: platform,
            enrolledAt: existing?.enrolledAt ?? now,
            lastSeen: now,
            canRelease: platform == .phone
        )
    }

    // MARK: The guide

    /// The steps a person is walked through before a device joins, on both platforms. Prose
    /// rather than a `HalfGuide`: none of these is a thing to do, they are four things to know,
    /// and the one action — Link this device — comes after all of them.
    struct Step: Identifiable, Equatable, Sendable {
        var title: String
        var detail: String
        var id: String { title }
    }

    static func steps(platform: AnchorRecord.Platform) -> [Step] {
        let here = platform == .mac ? "this Mac" : (platform == .pad ? "this iPad" : "this iPhone")
        let release: String = switch platform {
        case .phone: "Scanning your tag on this iPhone releases it everywhere."
        case .pad, .mac: "Only an iPhone's tag releases it — \(here) has no reader, so the link needs an iPhone on it before \(here) will drop."
        }
        return [
            Step(
                title: "It rides on your iCloud",
                detail: "Furlough keeps a few small records in the key-value store under your own Apple Account. There is no Furlough server and no account of ours; Apple carries it, and it works with the devices apart."
            ),
            Step(
                title: "The Anchor crosses",
                detail: "Drop the anchor on any linked device and every linked device locks. \(release)"
            ),
            Step(
                title: "Names cross, never rules",
                detail: "When you add something here, the other devices can be told its name — YouTube, youtube.com — and each one blocks what it can find. Your rules, your list and Apple's Screen Time tokens never leave \(here)."
            ),
            Step(
                title: "You choose what travels",
                detail: "Whether \(here) sends what you add, and whether it takes what the others add, are each Always, Ask or Never — and any device can be taken off the link, except while the anchor is down."
            ),
        ]
    }
}

// MARK: - This device's side of it

extension DeviceLink {
    private static let enrolledKey = "furlough.link.enrolled"
    private static let decidedKey = "furlough.link.decided"
    private static let nameKey = "furlough.link.name"
    private static let platformKey = "furlough.link.platform"
    private static let watermarksKey = "furlough.link.watermarks"
    private static let sequenceKey = "furlough.link.sequence"
    private static let declinedKey = "furlough.link.declined"

    /// Whether this device is on the link. Read by every process — the reconciler decides
    /// whether to take the anchor by it — so it lives in the App Group beside `deviceID`.
    static var isEnrolled: Bool { SharedStore.defaults.bool(forKey: enrolledKey) }

    /// The name this device joined under, or the platform's until it has one.
    static var name: String {
        SharedStore.defaults.string(forKey: nameKey) ?? LinkedDevice.defaultName(for: AnchorSync.platform)
    }

    /// Settles, once, whether an install that predates the roster is already linked. Called at
    /// launch by both apps before anything reads the roster. Returns true when it enrolled.
    @discardableResult
    static func decideGrandfathering(now: Date) -> Bool {
        guard !SharedStore.defaults.bool(forKey: decidedKey) else { return false }
        SharedStore.defaults.set(true, forKey: decidedKey)
        guard grandfathers(lastHeard: AnchorSync.lastHeard, phoneSeen: AnchorSync.phoneSeen) else { return false }
        enroll(name: name, now: now)
        SharedStore.log("link: this device was already linked, and stays on the link")
        return true
    }

    /// Puts this device on the link: writes its entry, clears any revocation of it, and
    /// remembers the name. Idempotent, so it doubles as the refresh every write makes.
    static func enroll(name: String, now: Date) {
        let id = AnchorSync.deviceID
        let entry = DeviceLink.entry(
            id: id, name: name, platform: AnchorSync.platform, existing: roster().device(id), now: now
        )
        AnchorCloud.write(entry, key: deviceKey(id))
        AnchorCloud.remove(key: revokeKey(id))
        SharedStore.defaults.set(entry.name, forKey: nameKey)
        SharedStore.defaults.set(true, forKey: enrolledKey)
    }

    /// Refreshes this device's entry, if it is on the link. Called beside every other write
    /// this device makes, so `lastSeen` means what it says.
    static func touch(now: Date) {
        guard isEnrolled else { return }
        enroll(name: name, now: now)
    }

    /// Takes this device off the link. Refused while an anchor holds — see `leaveRefusal` —
    /// and the caller passes what it knows about that, since the phone's profile and the
    /// shared record are both a `now` away from being wrong.
    @discardableResult
    static func leave(anchorHoldsHere: Bool, now: Date) -> LeaveRefusal? {
        if let refusal = leaveRefusal(anchorHoldsHere: anchorHoldsHere, anchorHoldsOnLink: recordHolds(AnchorCloud.read(), now: now)) {
            return refusal
        }
        let id = AnchorSync.deviceID
        AnchorCloud.remove(key: deviceKey(id))
        AnchorCloud.remove(key: addsKey(id))
        SharedStore.defaults.set(false, forKey: enrolledKey)
        SharedStore.log("link: this device left the link")
        return nil
    }

    /// Takes another device off the link from here. The same refusal as leaving: the anchor
    /// holding anywhere makes every device a party to it. The revoked device un-enrolls itself
    /// on its next read (`obeyRevocation`); meanwhile `roster().linked` already leaves it out.
    @discardableResult
    static func revoke(_ id: String, anchorHoldsHere: Bool, now: Date) -> LeaveRefusal? {
        if let refusal = leaveRefusal(anchorHoldsHere: anchorHoldsHere, anchorHoldsOnLink: recordHolds(AnchorCloud.read(), now: now)) {
            return refusal
        }
        AnchorCloud.write(Revocation(by: AnchorSync.deviceID, at: now), key: revokeKey(id))
        SharedStore.log("link: took \(id.prefix(8)) off the link")
        return nil
    }

    /// Whether another device has taken this one off the link since it joined, and if so,
    /// leaves. Called by every read of the roster, so it happens in whichever process reads
    /// first. Returns true when it left.
    @discardableResult
    static func obeyRevocation() -> Bool {
        guard isEnrolled else { return false }
        let id = AnchorSync.deviceID
        let read = roster()
        guard !read.isLinked(id), read.devices.contains(where: { $0.id == id }) || read.revoked[id] != nil else { return false }
        AnchorCloud.remove(key: deviceKey(id))
        AnchorCloud.remove(key: addsKey(id))
        SharedStore.defaults.set(false, forKey: enrolledKey)
        SharedStore.log("link: another device took this one off the link")
        return true
    }

    /// The roster as iCloud has it. A device that never wrote an entry, or removed it, is not
    /// in `devices`; a device whose entry cannot be decoded — written by a newer build with a
    /// platform this one does not know — is left out rather than failing the whole read.
    static func roster() -> Roster {
        var roster = Roster()
        for key in AnchorCloud.keys(withPrefix: devicePrefix) {
            if let device: LinkedDevice = AnchorCloud.read(key: key) { roster.devices.append(device) }
        }
        for key in AnchorCloud.keys(withPrefix: revokePrefix) {
            if let revocation: Revocation = AnchorCloud.read(key: key) {
                roster.revoked[String(key.dropFirst(revokePrefix.count))] = revocation
            }
        }
        return roster
    }

    /// The other devices on the link, from here. The list a Devices screen shows.
    static func others() -> [LinkedDevice] { roster().others(than: AnchorSync.deviceID) }

    // MARK: Additions: this device's sequence and what it has seen

    /// The next sequence number for an addition this device publishes. One higher every call.
    static func nextAdditionSequence() -> Int {
        let next = SharedStore.defaults.integer(forKey: sequenceKey) + 1
        SharedStore.defaults.set(next, forKey: sequenceKey)
        return next
    }

    /// The last addition sequence this device has dealt with, per source device.
    static var watermarks: [String: Int] {
        get { SharedStore.defaults.dictionary(forKey: watermarksKey) as? [String: Int] ?? [:] }
        set { SharedStore.defaults.set(newValue, forKey: watermarksKey) }
    }

    /// Additions declined under Ask, by id, so a "Not this time" is not asked again on the
    /// next read. Kept separately from the watermark: an addition still waiting for an answer
    /// is below the watermark and not declined, which is what makes it still show.
    static var declined: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: declinedKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: declinedKey) }
    }

    #if DEBUG || TESTING_TOOLS
    /// Forgets the link, for Reset everything: off the link, the name gone, the grandfather
    /// question open again, and this device's entry and additions out of iCloud.
    static func forget() {
        let id = AnchorSync.deviceID
        AnchorCloud.remove(key: deviceKey(id))
        AnchorCloud.remove(key: addsKey(id))
        AnchorCloud.remove(key: revokeKey(id))
        for key in [enrolledKey, decidedKey, nameKey, platformKey, watermarksKey, sequenceKey, declinedKey] {
            SharedStore.defaults.removeObject(forKey: key)
        }
    }
    #endif

    // MARK: Keys

    static let devicePrefix = "furlough.device."
    static let revokePrefix = "furlough.revoke."
    static let addsPrefix = "furlough.adds."

    static func deviceKey(_ id: String) -> String { devicePrefix + id }
    static func revokeKey(_ id: String) -> String { revokePrefix + id }
    static func addsKey(_ id: String) -> String { addsPrefix + id }
}
