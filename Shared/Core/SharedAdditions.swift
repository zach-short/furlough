import Foundation

/// One thing a linked device added, as the others receive it: what it is called and every
/// identifier and host it goes by. Never a token — a Screen Time token means nothing off the
/// phone that minted it — so a phone can only say what it has *learned* a thing is called, and
/// a device receiving one blocks whatever it can find under that name: the Mac an installed
/// app and the site, the phone the site at once and the app by way of Apple's picker.
struct SharedAddition: Codable, Equatable, Identifiable, Sendable {
    /// The sender's target id, so a second write about the same thing — its first rule landing
    /// — replaces the first in the ring rather than sitting beside it.
    var id: UUID
    /// One higher on every write from the sending device. What the receiver's watermark counts.
    var sequence: Int
    /// What to call it: "YouTube", or the host when nothing better is known.
    var title: String
    /// Whether the sender's face was an app. A phone receiving one cannot add the app itself
    /// and says so; a Mac looks for it.
    var isApp: Bool
    /// Lowercased bundle identifiers it is known by, on either platform.
    var bundleIDs: [String]
    /// The hosts the sender actually blocks for it.
    var hosts: [String]
    /// The sender's rule, if it had one yet. Applied on arrival only where the receiver's row
    /// has none — a rule of your own is never overwritten by a device you are not holding.
    var rule: Rule?
    /// Where it was added: the rules, or the anchor's list.
    var half: Half
    var origin: String
    var platform: AnchorRecord.Platform
    var addedAt: Date
}

/// What crosses when a linked device adds something, and what a device does with what crosses.
///
/// Each device publishes to a ring of its own under `furlough.adds.<id>` — the last few things
/// it added — and every other device keeps a watermark per source: the highest sequence it has
/// dealt with. No shared list, so nothing to fight over, and a device that was off for a week
/// reads the ring and catches up. Everything that decides is pure; the two functions at the
/// bottom that touch iCloud are thin.
enum SharedAdditions {
    /// How many of a device's additions the ring keeps. Enough to cover a week away; small
    /// enough that the whole store stays far under iCloud's megabyte.
    static let ringSize = 20

    // MARK: Saying what was added

    /// What `target` can say about itself off this device, or nil when it cannot be named yet.
    ///
    /// A typed host names itself and a Mac app is a bundle identifier, so both answer at once.
    /// A picked app or site answers only once the shield, or Screen Time's own tables, have
    /// taught the phone its name (`Target.systemName`) — so on a phone the addition may follow
    /// the add by hours, and the guide says so. A category cannot travel at all.
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

    /// What one thing on the anchor's list can say about itself, or nil while it cannot be
    /// named. The anchor's half of `describe`, and it goes through the same code: the list is
    /// kinds rather than targets, so a kind covered by a rules row is described as that row —
    /// which brings its other doors and its rule with it — and a kind held by the anchor alone
    /// is described as the one door it is.
    ///
    /// A held thing has no target and so no id, and the ring is keyed by id: an addition about
    /// something already in the ring must replace it rather than pile up beside it. So the id
    /// is derived from the name (`anchorID`), which is also the only thing that crosses. Adding
    /// a rule for something already anchored therefore changes the ring entry's id — from the
    /// derived one to the target's — and the receiver treats it as news, which it is.
    ///
    /// `name` is what this device has learned the kind is called, where it has learned
    /// anything: on the Mac the name off the bundle, on the phone what the shield or Screen
    /// Time's tables taught (`SharedStore.anchorNames`). Nil is not a failure — a Mac app and a
    /// typed host both name themselves — but a picked app or site with no name yet cannot
    /// cross, and waits for one.
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

    /// Everything on the anchor's list this device can describe and has not settled, in the
    /// list's own order. `LinkFlow.anchorAdditions` is this with the link's settings around it.
    ///
    /// `settled` is the normalized names already sent or declined. Names, because a name is
    /// what crosses: two things on the list that go by the same one are one question, asked
    /// once, and the answer to it holds for both.
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
        // Asked for once, and only when the list holds something no rule covers: on the Mac it
        // walks the Applications folders, and this runs on every settle.
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

    /// The id an addition about something the anchor holds and no rule covers goes out under:
    /// the same one every time, on this device and on the next, so the ring replaces rather
    /// than repeats and a receiver's watermark means what it says.
    ///
    /// Derived rather than stored, and derived with a hash written down here rather than with
    /// `hashValue`, which Swift seeds per process and which would therefore give a different
    /// answer on every launch. FNV-1a twice over, once salted, for the sixteen bytes; the
    /// version and variant nibbles are set so what comes out is a well-formed UUID.
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

    /// The additions this device has not dealt with, from devices on the link, oldest first.
    /// A source's ring is read past that source's watermark; this device's own ring and any
    /// device not on the link are ignored.
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
        /// The app this device can add — a bundle identifier installed on this Mac. Never set
        /// on a phone, where only Apple's picker can mint one.
        var appBundleID: String?
        var appName: String?
        /// The hosts to add, the sender's and the companion table's, minus what is already here.
        var hosts: [String]
        /// A phone receiving an app: the site half lands and the app half is a nudge to the
        /// picker, since nothing here can add it.
        var appNeedsPicker: Bool
        /// The rule to give the row, where it has none.
        var rule: Rule?
        /// Whether landing this would put something on *this* device's anchor list: the
        /// addition was made to the anchor's half, and this anchor can take one — it is not
        /// down, and its scope is not everything-except, where the list is what stays open.
        ///
        /// Its own field because it is the one thing an addition can do when it brings nothing
        /// new to block. A Mac that already has a YouTube rule hears that the phone anchored
        /// YouTube: no app to add, no host to add, no rule to take, and yet the whole point of
        /// the message is that YouTube should be held here too. Without this the landing read
        /// as nothing and was thrown away.
        var anchors: Bool

        /// A phone hearing that another device anchored an app. There is nothing it can block
        /// by name — only Apple's picker mints a token — and the app may go by no website at
        /// all, so by every other measure this says nothing. It is still owed: Screen Time's
        /// tables can match the name to a token where data access exists
        /// (`AppModel.anchorArrivalsFromTheTables`), and where it does not, the offer is how a
        /// person hears that the picker is the way in. Dropping it would be the one arrival the
        /// anchor half exists for going quietly missing.
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
                // Nothing new to block, so the anchor is the whole of the offer — and it is the
                // only case that reaches here with something to do at all.
                let held = anchors ? " Hold it here too?" : ""
                return "\(device) \(act) \(addition.title).\(held)\(ruled)\(picker)"
            }
            let onto = existing == nil ? "" : " — beside what already covers it"
            let held = anchors ? " It goes on the Anchor's list here too." : ""
            return "\(device) \(act) \(addition.title). Block \(UtilityText.list(parts)) here\(onto)?\(held)\(picker)\(ruled)"
        }
    }

    /// What `addition` would do in `config`.
    ///
    /// `installed` is what this Mac has, normalized bundle identifier to name — empty on a
    /// phone. `companion` is this device's own setting for the site an app is also at: under
    /// Always the table's hosts land beside the sender's, under Ask the row's own nudge offers
    /// them afterwards, under Never only what the sender blocks is taken. So a Mac with no
    /// YouTube app installed still lands youtube.com, which is the least Zach asked for.
    static func landing(
        for addition: SharedAddition,
        in config: Config,
        installed: [String: String],
        companion: LinkChoice,
        now: Date
    ) -> Landing {
        // The row already covering any door of it. By host first, which both platforms can
        // answer exactly; then by identifier on the Mac; then by learned name on the phone,
        // where an app's row knows nothing but what the shield called it.
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

        // The anchor takes it in when that is where it was added and this anchor can take one.
        // Something new to block is always something new to hold; a row already here is only
        // worth landing for the anchor's sake while the anchor does not hold every door of it
        // already, which is the same question `Config.anchorCandidates` asks.
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

    /// Lands it. The rows it touched, in the order it touched them; empty when there was
    /// nothing to do.
    ///
    /// A tightening, every part of it: more is blocked than a moment ago, so it lands at once,
    /// and a rule it brings is given the undo window so a wrong one can be taken straight back
    /// — exactly what a rule saved by hand gets. Taken into the anchor's list too when that is
    /// where it was added, unless the anchor is down, since nothing changes the list under a
    /// lock, or the scope is everything-except, where the list is what stays open.
    ///
    /// The shape differs by platform, and deliberately. On the phone the halves are one row —
    /// hosts join the row that already covers the thing, or the first host becomes a row and
    /// the rest join it — because that is how the phone has held an app and its site since
    /// 2026-09-08. The Mac shows a row per door and has never drawn a linked half, so there
    /// each host is a row of its own and the app is another, exactly as its companion sheet
    /// adds them; a linked half the editor could not show would be a block with no handle.
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

        // Asked again here rather than trusted from `landing.anchors`: under Ask the landing is
        // worked out when the addition arrives and answered whenever the person gets to the
        // card, and the anchor may have dropped in between. Nothing changes the list under a
        // lock, however long ago the offer was made.
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
