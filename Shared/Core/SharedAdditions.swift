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

        /// True when everything it names is already here and there is no rule to give.
        var isNothing: Bool { appBundleID == nil && hosts.isEmpty && rule == nil }

        /// What would happen, in a sentence, for the offer under Ask.
        func summary(from device: String) -> String {
            var parts: [String] = []
            if let appName { parts.append("the \(appName) app") }
            if !hosts.isEmpty { parts.append(UtilityText.list(hosts)) }
            let picker = appNeedsPicker ? " The \(addition.title) app itself needs Apple's picker; Furlough will offer it." : ""
            let ruled = rule == nil ? "" : " It brings \(LinkedDevice.defaultName(for: addition.platform) == "Mac" ? "your Mac's" : "your \(LinkedDevice.defaultName(for: addition.platform))'s") rule for it."
            guard !parts.isEmpty else {
                return "\(device) added \(addition.title).\(ruled)\(picker)"
            }
            let onto = existing == nil ? "" : " — beside what already covers it"
            return "\(device) added \(addition.title). Block \(UtilityText.list(parts)) here\(onto)?\(picker)\(ruled)"
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
        companion: LinkChoice
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
        return Landing(
            addition: addition,
            existing: existing?.id,
            appBundleID: appBundleID,
            appName: appName,
            hosts: hosts,
            appNeedsPicker: appNeedsPicker,
            rule: rule
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

        if landing.addition.half == .anchor, !config.anchor.isHolding(at: now), !config.anchor.anchorsEverything {
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
