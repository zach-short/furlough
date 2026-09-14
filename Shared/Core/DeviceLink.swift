import Foundation

/// How much a device does on its own when something could cross to, or from, another one.
/// Turning one down never blocks anything already blocked, only stops adding — so none of
/// these waits out a delay.
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
/// device answers for itself.
///
/// `companionSite` isn't really about the link — it's whether adding an app also blocks the
/// website it's also at, on this device alone — but it lives here as the same kind of question.
struct LinkPreferences: Codable, Equatable, Sendable {
    /// Whether adding an app also blocks the website it is also at, as one row.
    var companionSite: LinkChoice = .always
    /// Whether what this device adds is sent to the other devices on the link.
    var sendAdditions: LinkChoice = .ask
    /// Whether what another device adds is added here.
    var acceptAdditions: LinkChoice = .ask
}

/// What one device says about itself to the others. Each device writes only its own entry to
/// iCloud under its own key, so the roster is never one blob two devices fight over.
struct LinkedDevice: Codable, Equatable, Identifiable, Sendable {
    /// `AnchorSync.deviceID`: the same string the anchor record is signed with.
    var id: String
    /// iOS stopped telling third-party apps the device name in iOS 16, so on a phone this is
    /// typed in the guide; the Mac offers `Host.localizedName`.
    var name: String
    var platform: AnchorRecord.Platform
    /// A revocation older than this is spent: the device came back afterwards.
    var enrolledAt: Date
    var lastSeen: Date
    /// Whether a tag can be read on it — only an iPhone; never an iPad or Mac.
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
/// device finds it on its next read and un-enrolls itself.
struct Revocation: Codable, Equatable, Sendable {
    var by: String
    var at: Date
}

/// The link between a person's devices: who is on it, and the rules for joining and leaving.
/// A person opts each device in and can take any off it; nothing crosses to or from a device
/// that isn't enrolled (`AnchorSync.pull` refuses the anchor, `SharedAdditions` refuses additions).
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

        /// Written, and not revoked since enrolling. A revocation older than the enrollment is
        /// spent — the device was taken off and came back.
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

        /// The Mac's drop reads this — a Mac with no key-holder on the link would be a lock
        /// with no key.
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
        /// Taking a device off while an anchor holds would either leave it locked with no key
        /// or release it — both are what the Anchor exists to make impossible.
        case anchored

        var message: String {
            switch self {
            case .anchored:
                "The anchor is down. Scan your tag to release it, and then any device can be taken off the link."
            }
        }
    }

    /// Leaving is otherwise instant: with no anchor down, the link holds nothing that leaving
    /// would let go of.
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
    /// Proven by having heard the other device — `lastHeard`, or the Mac's older `phoneSeen`
    /// latch — so an install that never has starts off the link like anyone new.
    static func grandfathers(lastHeard: Date?, phoneSeen: Bool) -> Bool {
        lastHeard != nil || phoneSeen
    }

    /// `enrolledAt` is kept from the existing entry so a refresh doesn't spend a revocation
    /// that hasn't been read yet.
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

    /// The steps a person is walked through before a device joins. Prose rather than a
    /// `HalfGuide`: these are things to know, not do — the one action comes after all of them.
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

    /// Read by every process (the reconciler decides whether to take the anchor by it), so it
    /// lives in the App Group beside `deviceID`.
    static var isEnrolled: Bool { SharedStore.defaults.bool(forKey: enrolledKey) }

    static var name: String {
        SharedStore.defaults.string(forKey: nameKey) ?? LinkedDevice.defaultName(for: AnchorSync.platform)
    }

    /// Called at launch by both apps, once, before anything reads the roster. Returns true
    /// when it enrolled.
    @discardableResult
    static func decideGrandfathering(now: Date) -> Bool {
        guard !SharedStore.defaults.bool(forKey: decidedKey) else { return false }
        SharedStore.defaults.set(true, forKey: decidedKey)
        guard grandfathers(lastHeard: AnchorSync.lastHeard, phoneSeen: AnchorSync.phoneSeen) else { return false }
        enroll(name: name, now: now)
        SharedStore.log("link: this device was already linked, and stays on the link")
        return true
    }

    /// Idempotent, so it doubles as the refresh every write makes.
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

    /// Called beside every other write this device makes, so `lastSeen` means what it says.
    static func touch(now: Date) {
        guard isEnrolled else { return }
        enroll(name: name, now: now)
    }

    /// Refused while an anchor holds — see `leaveRefusal`.
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

    /// The revoked device un-enrolls itself on its next read (`obeyRevocation`); meanwhile
    /// `roster().linked` already leaves it out.
    @discardableResult
    static func revoke(_ id: String, anchorHoldsHere: Bool, now: Date) -> LeaveRefusal? {
        if let refusal = leaveRefusal(anchorHoldsHere: anchorHoldsHere, anchorHoldsOnLink: recordHolds(AnchorCloud.read(), now: now)) {
            return refusal
        }
        AnchorCloud.write(Revocation(by: AnchorSync.deviceID, at: now), key: revokeKey(id))
        SharedStore.log("link: took \(id.prefix(8)) off the link")
        return nil
    }

    /// Leaves if another device has revoked this one since it joined. Called by every read of
    /// the roster, so it happens in whichever process reads first. Returns true when it left.
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

    /// A device whose entry can't be decoded (written by a newer build with an unknown
    /// platform) is left out rather than failing the whole read.
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

    static func others() -> [LinkedDevice] { roster().others(than: AnchorSync.deviceID) }

    // MARK: Additions: this device's sequence and what it has seen

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

    /// Kept separately from the watermark: an addition still awaiting an answer is below the
    /// watermark and not declined, which is what makes it still show.
    static var declined: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: declinedKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: declinedKey) }
    }

    #if DEBUG || TESTING_TOOLS
    /// For Reset everything: off the link, name gone, grandfather question reopened, entry and
    /// additions removed from iCloud.
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
