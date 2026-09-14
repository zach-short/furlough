import Foundation

/// One thing a linked device added, as others receive it: its name and every identifier/host it
/// goes by. Never a token — those mean nothing off the phone that minted them — so a receiver
/// blocks whatever it can find under the name instead.
struct SharedAddition: Codable, Equatable, Identifiable, Sendable {
    /// The sender's target id, so a later write about the same thing replaces rather than
    /// duplicates in the ring.
    var id: UUID
    /// One higher on every write from the sending device. What the receiver's watermark counts.
    var sequence: Int
    /// What to call it: "YouTube", or the host when nothing better is known.
    var title: String
    /// Whether the sender's face was an app. A phone can't add the app itself and says so; a Mac looks for it.
    var isApp: Bool
    /// Lowercased bundle identifiers it is known by, on either platform.
    var bundleIDs: [String]
    /// The hosts the sender actually blocks for it.
    var hosts: [String]
    /// The sender's rule, if any — applied only where the receiver has none; never overwrites your own.
    var rule: Rule?
    /// Where it was added: the rules, or the anchor's list.
    var half: Half
    var origin: String
    var platform: AnchorRecord.Platform
    var addedAt: Date
}

/// What crosses when a linked device adds something. Each device publishes to its own ring
/// under `furlough.adds.<id>`; every other device keeps a per-source watermark, so there's
/// nothing shared to fight over and a device off for a week just reads and catches up.
/// Everything that decides is pure; only the iCloud read/write at the bottom touches state.
enum SharedAdditions {
    /// How many of a device's additions the ring keeps. Enough to cover a week away; small
    /// enough that the whole store stays far under iCloud's megabyte.
    static let ringSize = 20

    // MARK: Saying what was added

    /// What `target` can say about itself off this device, or nil when it cannot be named yet.
    /// A typed host or Mac app names itself immediately; a picked app/site on the phone waits
    /// for the shield or Screen Time to teach its name (`Target.systemName`), so the addition
    /// may lag the add by hours. A category can't travel at all.
    static func describe(
        _ target: Target,
        half: Half,
        origin: String,
        platform: AnchorRecord.Platform,
        sequence: Int,
        now: Date
    ) -> SharedAddition? {
        let learned = (target.systemName?.isEmpty ?? true) ? nil : target.systemName
        var title: String
        var bundleIDs: [String] = []
        var hosts = target.hosts
        var isApp = false
        var pair: Companions.Pair?

        switch target.kind {
        #if os(iOS)
        case .application:
            guard let learned else { return nil }
            title = learned
            isApp = true
            pair = Companions.pair(forBundleID: "", name: learned)
        case .webDomain:
            guard let learned else { return nil }
            guard let domain = Hosts.normalize(learned) else { return nil }
            title = domain
            hosts.append(domain)
            pair = Companions.pair(forHost: domain)
        case .category:
            return nil
        #else
        case .macApp(let bundleID):
            isApp = true
            bundleIDs = [Companions.normalize(bundleID: bundleID)]
            pair = Companions.pair(forBundleID: bundleID, name: learned ?? "")
            title = learned ?? pair?.title ?? bundleID
        #endif
        case .host(let host):
            title = host
            pair = Companions.pair(forHost: host)
        }

        if let pair {
            title = isApp ? pair.title : title
            bundleIDs = unique(bundleIDs + pair.bundleIDs)
        }
        // A site whose app the sender also holds is still one thing; the halves are one row.
        hosts = unique(hosts)
        return SharedAddition(
            id: target.id,
            sequence: sequence,
            title: title,
            isApp: isApp,
            bundleIDs: bundleIDs,
            hosts: hosts,
            rule: target.rule,
            half: half,
            origin: origin,
            platform: platform,
            addedAt: now
        )
    }

    /// The anchor's half of `describe`: a kind covered by a rules row is described as that row
    /// (bringing its other doors and rule); a kind held by the anchor alone is described as
    /// itself, with an id derived from its name (`anchorID`) since it has no target id — so
    /// adding a rule to something already anchored changes the ring entry's id, which the
    /// receiver correctly treats as news. `name` is whatever this device has learned the kind
    /// is called; nil for a picked app/site with no name yet, which simply waits.
    static func describe(
        anchorKind kind: TargetKind,
        name: String?,
        in config: Config,
        origin: String,
        platform: AnchorRecord.Platform,
        now: Date
    ) -> SharedAddition? {
        if let target = config.target(kind: kind) {
            return describe(target, half: .anchor, origin: origin, platform: platform, sequence: 0, now: now)
        }
        var standIn = Target(kind: kind)
        standIn.systemName = name
        guard var addition = describe(standIn, half: .anchor, origin: origin, platform: platform, sequence: 0, now: now)
        else { return nil }
        addition.id = anchorID(forTitle: addition.title)
        return addition
    }

    /// Everything on the anchor's list this device can describe and hasn't settled, in list
    /// order. `settled` is normalized names already sent or declined — keyed by name, since two
    /// listed things sharing a name are one question asked once.
    static func anchorList(
        in config: Config,
        names: () -> [TargetKind: String],
        settled: Set<String>,
        origin: String,
        platform: AnchorRecord.Platform,
        now: Date
    ) -> [SharedAddition] {
        // Under everything-except the list is what stays *open*, so sending it would tell the
        // other devices to block exactly what this one keeps reachable.
        guard !config.anchor.anchorsEverything, !config.anchor.kinds.isEmpty else { return [] }
        // Computed once, only if needed — on the Mac this walks the Applications folder, and
        // this runs on every settle.
        var learned: [TargetKind: String]?
        var offers: [SharedAddition] = []
        var seen = settled
        for kind in config.anchor.kinds {
            if learned == nil, config.target(kind: kind) == nil { learned = names() }
            guard let addition = describe(
                anchorKind: kind, name: learned?[kind], in: config,
                origin: origin, platform: platform, now: now
            ) else { continue }
            guard seen.insert(Companions.normalize(name: addition.title)).inserted else { continue }
            offers.append(addition)
        }
        return offers
    }

    /// The stable id for an addition about something the anchor alone holds, so the ring
    /// replaces rather than repeats. Derived, not `hashValue` (which Swift reseeds per process):
    /// FNV-1a twice, salted, for the sixteen bytes, with version/variant nibbles set to form a
    /// valid UUID.
    static func anchorID(forTitle title: String) -> UUID {
        let key = Companions.normalize(name: title)
        var bytes = octets(fnv1a(key, seed: 0xcbf2_9ce4_8422_2325))
            + octets(fnv1a(key, seed: 0x9e37_79b9_7f4a_7c15))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func fnv1a(_ string: String, seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in Array(string.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func octets(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> (56 - $0 * 8)) }
    }

    /// In first-seen order, each once.
    static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// The ring with `addition` in it: replacing an entry about the same thing, or appended,
    /// and the oldest dropped past `ringSize`.
    static func appended(_ ring: [SharedAddition], _ addition: SharedAddition) -> [SharedAddition] {
        var ring = ring.filter { $0.id != addition.id }
        ring.append(addition)
        ring.sort { $0.sequence < $1.sequence }
        return Array(ring.suffix(ringSize))
    }

    // MARK: Hearing what was added

    /// Additions this device hasn't dealt with, from linked devices, oldest first — each
    /// source's ring read past its watermark.
    static func unseen(
        rings: [String: [SharedAddition]],
        watermarks: [String: Int],
        declined: Set<String> = [],
        thisDevice: String,
        roster: DeviceLink.Roster
    ) -> [SharedAddition] {
        rings
            .filter { source, _ in source != thisDevice && roster.isLinked(source) }
            .flatMap { source, ring in
                ring.filter { $0.sequence > (watermarks[source] ?? 0) && !declined.contains($0.id.uuidString) }
            }
            .sorted { $0.addedAt < $1.addedAt }
    }

    /// What landing an addition here would do. Nothing is written; the caller looks, and under
    /// Ask a person does.
    struct Landing: Equatable, Sendable {
        var addition: SharedAddition
        /// A row already covering one of its doors, to link the rest into.
        var existing: UUID?
        /// The app this device can add — a bundle identifier installed on this Mac; never set on a phone.
        var appBundleID: String?
        var appName: String?
        /// The hosts to add, the sender's and the companion table's, minus what is already here.
        var hosts: [String]
        /// A phone receiving an app: the site half lands and the app half is a nudge to the
        /// picker, since nothing here can add it.
        var appNeedsPicker: Bool
        /// The rule to give the row, where it has none.
        var rule: Rule?
        /// Whether landing this would add to *this* device's anchor list — addition was made to
        /// the anchor's half, and this anchor can take one (not down, not everything-except).
        /// Its own field because it's the only thing to do when nothing new needs blocking: a
        /// Mac that already has a YouTube rule still needs to hear "anchor it here too."
        var anchors: Bool

        /// A phone hearing an app was anchored elsewhere: nothing to block by name, but still
        /// owed — Screen Time's tables may match it to a token, and otherwise the offer is how
        /// a person learns the picker is the way in. Dropping it would let the arrival go missing.
        var owesAnchoredApp: Bool { appNeedsPicker && addition.half == .anchor }

        /// True when everything it names is already here, there is no rule to give, the
        /// anchor's list would not change, and no app is owed.
        var isNothing: Bool {
            appBundleID == nil && hosts.isEmpty && rule == nil && !anchors && !owesAnchoredApp
        }

        /// What would happen, in a sentence, for the offer under Ask.
        func summary(from device: String) -> String {
            let act = addition.half == .anchor ? "anchored" : "added"
            var parts: [String] = []
            if let appName { parts.append("the \(appName) app") }
            if !hosts.isEmpty { parts.append(UtilityText.list(hosts)) }
            let picker: String
            switch (appNeedsPicker, addition.half) {
            case (false, _): picker = ""
            case (true, .rules): picker = " The \(addition.title) app itself needs Apple's picker; Furlough will offer it."
            case (true, .anchor): picker = " Furlough adds the \(addition.title) app itself if Screen Time will name it; otherwise Change apps here is the way in."
            }
            let ruled = rule == nil ? "" : " It brings \(LinkedDevice.defaultName(for: addition.platform) == "Mac" ? "your Mac's" : "your \(LinkedDevice.defaultName(for: addition.platform))'s") rule for it."
            guard !parts.isEmpty else {
                // Nothing new to block — the anchor is the whole offer, the only case reaching
                // here with anything to do.
                let held = anchors ? " Hold it here too?" : ""
                return "\(device) \(act) \(addition.title).\(held)\(ruled)\(picker)"
            }
            let onto = existing == nil ? "" : " — beside what already covers it"
            let held = anchors ? " It goes on the Anchor's list here too." : ""
            return "\(device) \(act) \(addition.title). Block \(UtilityText.list(parts)) here\(onto)?\(held)\(picker)\(ruled)"
        }
    }

    /// What `addition` would do in `config`. `installed` is this Mac's bundle-id-to-name map
    /// (empty on a phone). `companion` governs the app's own site: Always adds the table's
    /// hosts alongside the sender's, Ask nudges afterward, Never takes only what the sender blocks.
    static func landing(
        for addition: SharedAddition,
        in config: Config,
        installed: [String: String],
        companion: LinkChoice,
        now: Date
    ) -> Landing {
        // Match by host first (exact on both platforms), then bundle identifier on the Mac,
        // then learned name on the phone.
        var existing: Target? = addition.hosts.lazy.compactMap { config.target(host: $0) }.first
        #if os(macOS)
        if existing == nil {
            existing = addition.bundleIDs.lazy.compactMap { id in
                config.targets.first { target in
                    target.kinds.contains { kind in
                        if case .macApp(let bundleID) = kind { return Companions.normalize(bundleID: bundleID) == id }
                        return false
                    }
                }
            }.first
        }
        #endif
        if existing == nil {
            let key = Companions.normalize(name: addition.title)
            existing = config.targets.first { target in
                guard let name = target.systemName, !name.isEmpty else { return false }
                if Companions.normalize(name: name) == key { return true }
                if let pair = Companions.pair(forBundleID: "", name: name) { return pair.bundleIDs.contains(where: addition.bundleIDs.contains) }
                return false
            }
        }

        var appBundleID: String?
        var appName: String?
        var appNeedsPicker = false
        if addition.isApp, !(existing?.coversApp ?? false) {
            #if os(macOS)
            // Installed here and not yet a row: the Mac keeps an app as a row of its own.
            if let found = addition.bundleIDs.first(where: { id in
                installed[id] != nil && !config.targets.contains { target in
                    target.kinds.contains { kind in
                        if case .macApp(let bundleID) = kind { return Companions.normalize(bundleID: bundleID) == id }
                        return false
                    }
                }
            }) {
                appBundleID = found
                appName = installed[found] ?? addition.title
            }
            #else
            appNeedsPicker = true
            #endif
        }

        var hosts = addition.hosts
        if companion == .always {
            hosts += Companions.hosts(forBundleID: addition.bundleIDs.first ?? "", name: addition.title)
        }
        hosts = unique(hosts).filter { config.target(host: $0) == nil }

        let rule = (existing?.rule == nil) ? addition.rule : nil

        // Anchors it if it was added to the anchor's half and this anchor can take one —
        // new-to-block is always worth holding; an existing row is worth it only if the anchor
        // doesn't already hold every door of it.
        var anchors = false
        if addition.half == .anchor, !config.anchor.isHolding(at: now), !config.anchor.anchorsEverything {
            let arriving = appBundleID != nil || !hosts.isEmpty
            anchors = arriving || !(existing.map(config.anchor.lists) ?? true)
        }
        return Landing(
            addition: addition,
            existing: existing?.id,
            appBundleID: appBundleID,
            appName: appName,
            hosts: hosts,
            appNeedsPicker: appNeedsPicker,
            rule: rule,
            anchors: anchors
        )
    }

    /// Lands it: the rows touched, in order; empty if nothing to do. Always a tightening, so it
    /// lands at once, and any rule it brings gets the undo window like a hand-saved rule would.
    ///
    /// Platform shapes differ deliberately: the phone joins hosts into one row with the app
    /// (as it's held app+site since 2026-09-08); the Mac has never shown a linked half, so each
    /// host and the app are separate rows there, as its companion sheet already adds them.
    @discardableResult
    static func land(_ landing: Landing, in config: inout Config, now: Date) -> [UUID] {
        guard !landing.isNothing else { return [] }
        var touched: [UUID] = []
        var hostKinds = landing.hosts.map(TargetKind.host)

        func ruled(_ target: inout Target) {
            guard let rule = landing.rule, target.rule == nil else { return }
            target.rule = rule
            target.undo = RuleUndo(rule: nil, savedAt: now)
        }

        if let existing = landing.existing, let index = config.targets.firstIndex(where: { $0.id == existing }) {
            touched.append(existing)
            #if os(iOS)
            if !hostKinds.isEmpty {
                config.targets[index].also = (config.targets[index].also ?? []) + hostKinds
                hostKinds = []
            }
            #endif
            ruled(&config.targets[index])
        }

        #if os(macOS)
        if let bundleID = landing.appBundleID {
            var app = Target(kind: .macApp(bundleID: bundleID), systemName: landing.appName)
            app.addedAt = now
            ruled(&app)
            config.targets.append(app)
            touched.append(app.id)
        }
        for kind in hostKinds {
            var site = Target(kind: kind)
            site.addedAt = now
            ruled(&site)
            config.targets.append(site)
            touched.append(site.id)
        }
        #else
        if !hostKinds.isEmpty {
            var site = Target(kind: hostKinds.removeFirst())
            if !hostKinds.isEmpty { site.also = hostKinds }
            site.addedAt = now
            ruled(&site)
            config.targets.append(site)
            touched.append(site.id)
        }
        #endif

        // Re-checked rather than trusted from `landing.anchors`: under Ask, time may pass
        // between the offer and the answer, and the anchor may have dropped meanwhile.
        if landing.anchors, !config.anchor.isHolding(at: now), !config.anchor.anchorsEverything {
            config.anchor.add(touched.compactMap { config.target(id: $0) })
        }
        return touched
    }
}

// MARK: - iCloud

extension SharedAdditions {
    /// Writes `addition` into this device's ring, replacing an earlier write about the same
    /// thing. Refreshes the device's entry too, so `lastSeen` is honest.
    static func publish(_ addition: SharedAddition, now: Date) {
        let key = DeviceLink.addsKey(AnchorSync.deviceID)
        let ring: [SharedAddition] = AnchorCloud.read(key: key) ?? []
        AnchorCloud.write(appended(ring, addition), key: key)
        DeviceLink.touch(now: now)
        SharedStore.log("link: published \(addition.title) (\(addition.half.rawValue), sequence \(addition.sequence))")
    }

    /// Every ring in the store but this device's, by source.
    static func rings() -> [String: [SharedAddition]] {
        var rings: [String: [SharedAddition]] = [:]
        for key in AnchorCloud.keys(withPrefix: DeviceLink.addsPrefix) {
            let source = String(key.dropFirst(DeviceLink.addsPrefix.count))
            guard source != AnchorSync.deviceID else { continue }
            if let ring: [SharedAddition] = AnchorCloud.read(key: key) { rings[source] = ring }
        }
        return rings
    }

    /// What is waiting for this device, oldest first. Nothing when this device is off the link.
    static func pending() -> [SharedAddition] {
        guard DeviceLink.isEnrolled else { return [] }
        return unseen(
            rings: rings(),
            watermarks: DeviceLink.watermarks,
            declined: DeviceLink.declined,
            thisDevice: AnchorSync.deviceID,
            roster: DeviceLink.roster()
        )
    }

    /// Done with `addition`, landed or not: the watermark moves past it.
    static func markSeen(_ addition: SharedAddition) {
        var marks = DeviceLink.watermarks
        marks[addition.origin] = max(marks[addition.origin] ?? 0, addition.sequence)
        DeviceLink.watermarks = marks
    }

    /// Declined under Ask: not asked again, and the watermark moves past it.
    static func decline(_ addition: SharedAddition) {
        DeviceLink.declined = DeviceLink.declined.union([addition.id.uuidString])
        markSeen(addition)
    }
}
