import Foundation

/// What one device tells the other about the anchor's *state* only — never rules, since a
/// Screen Time token or bundle identifier means nothing off the device that minted it.
struct AnchorRecord: Codable, Equatable {
    /// iPad is its own case: it runs the phone app but has no tag reader, so — like the Mac —
    /// it can be anchored but never release. `merge` must not accept a release from it.
    enum Platform: String, Codable, Sendable {
        case phone
        case pad
        case mac
    }

    /// Only a `tagScan` from a phone counts as a release the other device will take.
    enum Origin: String, Codable {
        case drop
        case tagScan
        /// A timed anchor's `until` passing. Informational only — the receiver computes this
        /// itself and never treats it as a remote release.
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

/// Syncs the anchor across devices via the iCloud key-value store (`AnchorCloud`) — no server
/// of ours. A release only ever originates from a phone's tag scan; `merge` refuses any other.
/// A device that can't reach iCloud just keeps its last state.
enum AnchorSync {
    private static let deviceKey = "furlough.device.v1"
    private static let phoneSeenKey = "furlough.sync.phoneSeen"
    private static let lastHeardKey = "furlough.sync.lastHeard"

    /// When this device last read a record the *other* device wrote. Nil until it ever has.
    static var lastHeard: Date? { SharedStore.defaults.object(forKey: lastHeardKey) as? Date }

    /// Persisted in the App Group so every process on this device signs the same way.
    static var deviceID: String {
        if let id = SharedStore.defaults.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString
        SharedStore.defaults.set(id, forKey: deviceKey)
        return id
    }

    /// Core has no UIKit to check device idiom, so the app notes iPad-ness at launch
    /// (`notePlatform`) and every process reads it back; defaults to phone.
    static var platform: AnchorRecord.Platform {
        #if os(iOS)
        SharedStore.defaults.string(forKey: platformKey) == AnchorRecord.Platform.pad.rawValue ? .pad : .phone
        #else
        .mac
        #endif
    }

    private static let platformKey = "furlough.link.platform"

    /// Called once at launch by the app — the only process that can actually check.
    static func notePlatform(isPad: Bool) {
        SharedStore.defaults.set((isPad ? AnchorRecord.Platform.pad : .phone).rawValue, forKey: platformKey)
    }

    /// Guards against a Mac dropping a lock with no key — until a phone has been heard from,
    /// `macDrop` refuses.
    static var phoneSeen: Bool { SharedStore.defaults.bool(forKey: phoneSeenKey) }

    /// Kept here for both platforms so the wording can't drift apart. Phrased as a standing
    /// state, not a passing failure — a signed-out account doesn't fix itself.
    static var cutOffWarning: String {
        #if os(iOS)
        """
        Furlough cannot reach iCloud, so the Anchor stops at this iPhone. Dropping it here \
        will not lock your Mac, and scanning your tag will not release one. Turn on iCloud \
        Drive in Settings > your name > iCloud — the Anchor travels on it.
        """
        #else
        """
        Furlough cannot reach iCloud, so the Anchor stops at this Mac. Your iPhone's tag is \
        the only thing that can release an anchor dropped here, and it cannot reach this Mac \
        — so Furlough will not drop one until iCloud is back. Turn on iCloud Drive in System \
        Settings > your name > iCloud — the Anchor travels on it.
        """
        #endif
    }

    #if DEBUG || TESTING_TOOLS
    /// Lets a reset Mac be tested from a clean `phoneSeen` state again — otherwise the
    /// lock-with-no-key guard is untestable after the first sync.
    static func forgetPhone() {
        SharedStore.defaults.removeObject(forKey: phoneSeenKey)
    }
    #endif

    /// Reports the raw shared record rather than a derived verdict — the record (who wrote it,
    /// which device, when) is the only end-to-end proof available without a round-trip ping to
    /// answer. Pure, so both platforms word it identically and edge cases are testable without
    /// an iCloud account.
    struct LinkStatus: Equatable {
        /// Mirrors `AnchorCloud.isAvailable`.
        var cloudAvailable: Bool
        /// Off the link, the record is deliberately not read even if one is present.
        var enrolled = true
        var record: AnchorRecord?
        var thisDevice: String
        var platform: AnchorRecord.Platform
        var lastHeard: Date?

        var otherName: String { platform == .phone ? "Mac" : "iPhone" }

        /// True once proven: the record is the other device's, or we've read theirs before. A
        /// write of our own no longer resets this — it used to, which could show "no proof"
        /// immediately after a link had just been proven.
        var isLinked: Bool {
            guard cloudAvailable, enrolled, let record else { return false }
            return record.writer != thisDevice || lastHeard != nil
        }

        var headline: String {
            guard cloudAvailable else { return "Not linked" }
            guard enrolled else { return "Off the link" }
            guard let record else { return "Nothing shared yet" }
            guard record.writer == thisDevice else { return "Linked" }
            guard let lastHeard else { return "Waiting to hear back" }
            return "Linked · last heard \(TimeFormat.clock(lastHeard))"
        }

        func detail(now: Date) -> String {
            guard cloudAvailable else {
                return "Furlough cannot reach iCloud, so nothing can cross between this device and your \(otherName)."
            }
            guard enrolled else {
                return "This device is not on the link, so the Anchor stops here. Link it under Settings > Devices."
            }
            guard let record else {
                return "iCloud is reachable, but neither device has written the Anchor yet. Drop the anchor on either one and it will appear here."
            }
            let when = TimeFormat.clock(record.writtenAt)
            let what = record.isAnchored ? "a drop" : "a release"
            if record.writer == thisDevice {
                // Distinct sentences: this used to always say "never heard back", which was
                // false as soon as the other device had ever been read once before.
                guard let lastHeard else {
                    return "The last thing in iCloud is \(what) this device wrote at \(when). Your \(otherName) has not written since, so there is nothing yet to prove it is hearing you."
                }
                return "The last thing in iCloud is \(what) this device wrote at \(when). Your \(otherName) was last read here at \(TimeFormat.clock(lastHeard))."
            }
            let heard = lastHeard.map { " Last read here at \(TimeFormat.clock($0))." } ?? ""
            return "Your \(otherName) wrote \(what) at \(when), and this device has it.\(heard)"
        }
    }

    /// The link as it stands, read from iCloud and this device's own store.
    static func linkStatus() -> LinkStatus {
        LinkStatus(
            cloudAvailable: AnchorCloud.isAvailable,
            enrolled: DeviceLink.isEnrolled,
            record: AnchorCloud.read(),
            thisDevice: deviceID,
            platform: platform,
            lastHeard: lastHeard
        )
    }

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

    /// Called after every anchor write: the phone's (including the monitor's scheduled drops)
    /// and the Mac's local drops.
    static func publish(_ anchor: AnchorProfile, origin: AnchorRecord.Origin, now: Date) {
        AnchorCloud.write(record(anchor, origin: origin, now: now))
        SharedStore.log("published the anchor to iCloud (\(origin.rawValue), sequence \(anchor.sequence))")
    }

    /// Returns a log note only when the anchor actually changed; nil otherwise.
    @discardableResult
    static func pull(into config: inout Config, now: Date) -> String? {
        // Roster read first: another device may have de-linked this one since last check, and
        // that must land before the record does.
        DeviceLink.obeyRevocation()
        guard DeviceLink.isEnrolled, let remote = AnchorCloud.read() else { return nil }
        // Only a still-linked writer can lock this device — a departed device's leftover
        // record has no owner.
        guard remote.writer == deviceID || DeviceLink.roster().isLinked(remote.writer) else { return nil }
        if remote.platform == .phone, !phoneSeen {
            SharedStore.defaults.set(true, forKey: phoneSeenKey)
        }
        // Stamped regardless of what the record says — even a no-op record proves the two
        // devices are talking. Only our own writes are skipped.
        if remote.writer != deviceID {
            SharedStore.defaults.set(now, forKey: lastHeardKey)
        }
        guard remote.writer != deviceID else { return nil }
        let before = config.anchor
        let merged = merge(local: before, remote: remote, now: now)
        config.anchor = merged.profile
        return merged.profile.isHolding(at: now) != before.isHolding(at: now) || merged.profile.until != before.until
            ? merged.note
            : nil
    }

    /// Pure. Rules: highest sequence wins; a release is accepted only from a phone's tagScan
    /// (never the Mac, and `lift` is always computed locally, never accepted remotely); a
    /// remote `until` is judged against Furlough's own trusted clock, not the wall clock.
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

    /// No tag on the Mac, so no `until`. Requires cloud availability (checked first — a
    /// signed-out account makes the roster's answer untrustworthy) and a linked phone
    /// (`hasKey`), since only that phone's tag can ever release it.
    static func macDrop(_ config: inout Config, now: Date, hasKey: Bool, cloudAvailable: Bool) -> Policy.DropRefusal? {
        Policy.liftExpiredAnchor(&config, now: now)
        guard config.anchor.hasSomethingToHold else { return .noList }
        guard cloudAvailable else { return .noCloud }
        guard hasKey else { return .noPhone }
        guard !config.anchor.isAnchored else { return .alreadyAnchored }
        config.anchor.isAnchored = true
        config.anchor.anchoredAt = now
        config.anchor.until = nil
        config.anchor.sequence += 1
        return nil
    }
}

/// One key, one JSON record, under the user's own Apple Account — Furlough has no server of
/// its own.
enum AnchorCloud {
    static let key = "furlough.anchor.v1"

    static var changeNotification: Notification.Name { NSUbiquitousKeyValueStore.didChangeExternallyNotification }

    /// Nil means signed out or iCloud Drive off (the store rides on Drive, so a Mac with Drive
    /// off reads/writes only to itself) — not a network check; an offline device still has a
    /// token. Do NOT swap this for `NSUbiquitousKeyValueStore.synchronize()`: on 2026-09-09 it
    /// returned true on a Drive-off Mac while receiving nothing for 30 minutes — it only
    /// confirms the store is configured, never that anything will actually sync.
    static var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// True when the account itself changed (signed in/out/switched) — `isAvailable` and the
    /// record must be re-read, since what follows belongs to a different account.
    static func isAccountChange(_ notification: Notification) -> Bool {
        guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return false }
        return reason == NSUbiquitousKeyValueStoreAccountChange
    }

    static func read() -> AnchorRecord? { read(key: key) }

    static func write(_ record: AnchorRecord) { write(record, key: key) }

    /// Generic since `DeviceLink`'s roster entries share this same one-key-one-JSON transport.
    static func read<Value: Decodable>(key: String) -> Value? {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: key) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    static func write<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    static func remove(key: String) {
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Lets the roster be enumerated without both devices needing to agree on a shared list.
    static func keys(withPrefix prefix: String) -> [String] {
        NSUbiquitousKeyValueStore.default.dictionaryRepresentation.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// Called at launch and on activation; later changes arrive via `changeNotification`.
    static func synchronize() {
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Debug-only, beside Reset everything — a stale drop left in iCloud would otherwise
    /// re-anchor the phone on its next pull.
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
