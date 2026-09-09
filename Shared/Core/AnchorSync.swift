import Foundation

/// What one device says about the anchor, as the other receives it. The anchor's *state* and
/// nothing else: rules cannot travel (a Screen Time token means nothing off the phone that
/// minted it, a bundle identifier nothing on it), so each device keeps its own list and this
/// carries only whether the anchor is down, since when, until when, who wrote that, and how.
struct AnchorRecord: Codable, Equatable {
    enum Platform: String, Codable {
        case phone
        case mac
    }

    /// How the write came about. Only a `tagScan` from a phone is a release the other device
    /// will take; everything else is a drop, or a lift each device works out for itself.
    enum Origin: String, Codable {
        /// A drop: by hand, from a widget or Control Center, or by the schedule.
        case drop
        /// The one release: a paired tag read by a phone.
        case tagScan
        /// A timed anchor's `until` passed. Informational — the receiver computes the same
        /// expiry from the `until` it already holds, and refuses this as a release.
        case lift
    }

    /// Monotonic across both devices: every write is one higher than anything either has seen.
    var sequence: Int
    var isAnchored: Bool
    var anchoredAt: Date?
    var until: Date?
    var writer: String
    var platform: Platform
    var origin: Origin
    var writtenAt: Date
}

/// The anchor across devices: dropping on either locks both, and scanning the tag on the
/// phone releases the Mac too. The Mac has no NFC, so a release only ever originates on a
/// phone, and `merge` refuses any other.
///
/// The transport is the iCloud key-value store (`AnchorCloud`): no account of ours, no server
/// of ours, and it works when the devices are apart, which is the case Zach named — anchor at
/// work and the Mac at home locks. A device that cannot reach iCloud keeps its last state.
enum AnchorSync {
    private static let deviceKey = "furlough.device.v1"
    private static let phoneSeenKey = "furlough.sync.phoneSeen"

    /// This device, for the record's `writer`. Made once and kept in the App Group, so every
    /// process on the device signs the same way.
    static var deviceID: String {
        if let id = SharedStore.defaults.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString
        SharedStore.defaults.set(id, forKey: deviceKey)
        return id
    }

    static var platform: AnchorRecord.Platform {
        #if os(iOS)
        .phone
        #else
        .mac
        #endif
    }

    /// Whether a phone has ever written the record this device reads. The Mac's anchor can be
    /// released only by a phone's tag scan arriving through iCloud, so until one has been
    /// heard from, a Mac drop would be a lock with no key, and `macDrop` refuses it.
    static var phoneSeen: Bool { SharedStore.defaults.bool(forKey: phoneSeenKey) }

    #if DEBUG || TESTING_TOOLS
    /// Forgets that a phone has ever written the record, for Settings > Testing > Reset
    /// everything on the Mac. Without it a reset Mac would still take a drop that a fresh
    /// install refuses, and `macDrop`'s lock-with-no-key guard would be untestable after the
    /// first sync.
    static func forgetPhone() {
        SharedStore.defaults.removeObject(forKey: phoneSeenKey)
    }
    #endif

    static func record(_ anchor: AnchorProfile, origin: AnchorRecord.Origin, now: Date) -> AnchorRecord {
        AnchorRecord(
            sequence: anchor.sequence,
            isAnchored: anchor.isAnchored,
            anchoredAt: anchor.anchoredAt,
            until: anchor.until,
            writer: deviceID,
            platform: platform,
            origin: origin,
            writtenAt: now
        )
    }

    /// Writes this device's anchor to iCloud. Called after every anchor write the phone makes,
    /// the monitor's scheduled drops included, and after a local drop on the Mac.
    static func publish(_ anchor: AnchorProfile, origin: AnchorRecord.Origin, now: Date) {
        AnchorCloud.write(record(anchor, origin: origin, now: now))
        SharedStore.log("published the anchor to iCloud (\(origin.rawValue), sequence \(anchor.sequence))")
    }

    /// Reads iCloud's record and merges it into `config`. Returns a note for the log when the
    /// anchor changed, nil when there was nothing to read or nothing new in it.
    @discardableResult
    static func pull(into config: inout Config, now: Date) -> String? {
        guard let remote = AnchorCloud.read() else { return nil }
        if remote.platform == .phone, !phoneSeen {
            SharedStore.defaults.set(true, forKey: phoneSeenKey)
        }
        guard remote.writer != deviceID else { return nil }
        let before = config.anchor
        let merged = merge(local: before, remote: remote, now: now)
        config.anchor = merged.profile
        return merged.profile.isHolding(at: now) != before.isHolding(at: now) || merged.profile.until != before.until
            ? merged.note
            : nil
    }

    /// The profile to keep, given what the other device wrote. Pure; the rules:
    ///
    /// - The highest sequence wins, and the sequence moves on whatever is decided, so the next
    ///   local write is one higher than anything either device has seen.
    /// - A release is accepted only when the record says it came from a tag scan on a phone.
    ///   The Mac never writes one, and a `lift` is not one: each device computes a timed
    ///   anchor's expiry from the `until` it already holds.
    /// - A remote `until` is judged by this device's own clock — `now` is Furlough's time, the
    ///   trusted one, never the wall clock — so a drop already over here does not drop here,
    ///   and a drop over an anchor already down can only lengthen the hold.
    static func merge(local: AnchorProfile, remote: AnchorRecord, now: Date) -> (profile: AnchorProfile, note: String) {
        var profile = local
        guard remote.sequence > local.sequence else {
            return (local, "stale record (\(remote.sequence) is not past \(local.sequence))")
        }
        profile.sequence = remote.sequence
        guard remote.isAnchored else {
            guard remote.origin == .tagScan, remote.platform == .phone else {
                return (profile, "refused a release that was not a phone's tag scan")
            }
            guard local.isHolding(at: now) else { return (profile, "released by the phone; already up here") }
            profile.isAnchored = false
            profile.anchoredAt = nil
            profile.until = nil
            return (profile, "released by the phone's tag")
        }
        if let until = remote.until, until <= now {
            return (profile, "a drop already over by this clock")
        }
        if local.isHolding(at: now) {
            let tighter = Policy.tighterUntil(local.until, remote.until)
            guard tighter != local.until else { return (profile, "already anchored here") }
            profile.until = tighter
            return (profile, "hold lengthened by the other device")
        }
        profile.isAnchored = true
        profile.anchoredAt = remote.anchoredAt ?? now
        profile.until = remote.until
        return (profile, "anchored by the other device")
    }

    /// The Mac's drop. No tag here, so no `until` and no `canAnchor`: it needs something to
    /// hold and a phone that has been heard from, since only that phone's tag can ever lift it.
    static func macDrop(_ config: inout Config, now: Date, phoneSeen: Bool) -> Policy.DropRefusal? {
        Policy.liftExpiredAnchor(&config, now: now)
        guard config.anchor.hasSomethingToHold else { return .noList }
        guard phoneSeen else { return .noPhone }
        guard !config.anchor.isAnchored else { return .alreadyAnchored }
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = now
        config.anchor.until = nil
        config.anchor.sequence += 1
        return nil
    }
}

/// The iCloud key-value store, as the anchor's transport. One key, one JSON record. Apple
/// keeps it under the user's own Apple Account; Furlough has no server that could see it, and
/// the privacy page says so in those words.
enum AnchorCloud {
    static let key = "furlough.anchor.v1"

    static var changeNotification: Notification.Name { NSUbiquitousKeyValueStore.didChangeExternallyNotification }

    static func read() -> AnchorRecord? {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: key) else { return nil }
        return try? decoder.decode(AnchorRecord.self, from: data)
    }

    static func write(_ record: AnchorRecord) {
        guard let data = try? encoder.encode(record) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Asks iCloud for whatever it has. Called at launch and on activation; changes that arrive
    /// afterwards come through `changeNotification`.
    static func synchronize() {
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Forgets the record. Debug builds only, beside Reset everything: a reset that left a
    /// stale drop in iCloud would anchor the phone again on its next pull.
    static func clear() {
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
