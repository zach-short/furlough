import Foundation

/// The link's traffic from a model's side: what to do when this device adds something, and
/// what to do with what the others added. The I/O around `SharedAdditions`, which decides, so
/// both apps make the same moves in the same order.
///
/// Sending is two steps because the phone can't always name what it added right away: a target
/// is written down as *awaiting*, `outgoing` asks whether it can be described yet, and `send`
/// writes it. The Mac does both in one breath; the phone's second step may come hours later,
/// once the shield has taught the app the target's name (`SharedAdditions.describe`).
///
/// The rules half tracks awaiting targets by id; the anchor's list is kinds, which can have no
/// id, so it keeps no ledger — `anchorAdditions` just walks the list on every settle. Both end
/// in the same `send`, tagged with the `Half` that tells the receiver where it belongs.
enum LinkFlow {
    private static let awaitingKey = "furlough.link.awaiting"
    private static let sentKey = "furlough.link.sent"
    private static let sendDeclinedKey = "furlough.link.sendDeclined"
    private static let anchorSentKey = "furlough.link.anchorSent"
    private static let anchorDeclinedKey = "furlough.link.anchorDeclined"

    // MARK: Sending

    /// What to do about a target this device added.
    enum Outgoing: Equatable {
        case nothing
        /// Told Always, or already sent once — a rule landing on something already agreed to
        /// isn't a second question.
        case send(SharedAddition)
        case ask(SharedAddition)
    }

    /// Targets added and not yet sent or declined, by id, with the half they were added to.
    static var awaiting: [String: Half] {
        get {
            (SharedStore.defaults.dictionary(forKey: awaitingKey) as? [String: String] ?? [:])
                .compactMapValues(Half.init(rawValue:))
        }
        set { SharedStore.defaults.set(newValue.mapValues(\.rawValue), forKey: awaitingKey) }
    }

    /// A later change to a sent target (its first rule) goes out again without asking.
    static var sent: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: sentKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: sentKey) }
    }

    static var sendDeclined: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: sendDeclinedKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: sendDeclinedKey) }
    }

    /// By normalized name, not id — the anchor's list is kinds, which can have no id, and a
    /// name is the only thing that crosses anyway. Taking something off the anchor's list and
    /// back on does not ask again: the person already answered for that name.
    static var anchorSent: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: anchorSentKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: anchorSentKey) }
    }

    static var anchorDeclined: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: anchorDeclinedKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: anchorDeclinedKey) }
    }

    /// Called by every add to the rules half, where the setting allows sending at all. The
    /// anchor half needs no equivalent call: its list is its own ledger, walked by
    /// `anchorAdditions` on every settle.
    static func noteAdded(_ ids: [UUID], half: Half, config: Config) {
        guard DeviceLink.isEnrolled, config.link.sendAdditions != .never else { return }
        var waiting = awaiting
        for id in ids where !sent.contains(id.uuidString) && !sendDeclined.contains(id.uuidString) {
            waiting[id.uuidString] = half
        }
        awaiting = waiting
    }

    /// What to do about `target` right now, under `config`'s setting.
    static func outgoing(for target: Target, half: Half, config: Config, now: Date) -> Outgoing {
        guard DeviceLink.isEnrolled, config.link.sendAdditions != .never else { return .nothing }
        let id = target.id.uuidString
        guard !sendDeclined.contains(id) else { return .nothing }
        guard let addition = SharedAdditions.describe(
            target, half: half, origin: AnchorSync.deviceID, platform: AnchorSync.platform, sequence: 0, now: now
        ) else { return .nothing }
        if config.link.sendAdditions == .always || sent.contains(id) { return .send(addition) }
        return .ask(addition)
    }

    /// Stamps the next sequence, writes the ring, and remembers the target so its first rule
    /// follows without asking. An anchor addition is also remembered by name for the anchor's walk.
    static func send(_ addition: SharedAddition, now: Date) {
        var stamped = addition
        stamped.sequence = DeviceLink.nextAdditionSequence()
        stamped.addedAt = now
        SharedAdditions.publish(stamped, now: now)
        sent = sent.union([addition.id.uuidString])
        if addition.half == .anchor {
            anchorSent = anchorSent.union([Companions.normalize(name: addition.title)])
        }
        var waiting = awaiting
        waiting[addition.id.uuidString] = nil
        awaiting = waiting
    }

    /// Per half, deliberately: declining to share that something is anchored here says nothing
    /// about whether a rule for it should cross later.
    static func decline(_ addition: SharedAddition) {
        if addition.half == .anchor {
            anchorDeclined = anchorDeclined.union([Companions.normalize(name: addition.title)])
        } else {
            sendDeclined = sendDeclined.union([addition.id.uuidString])
        }
        var waiting = awaiting
        waiting[addition.id.uuidString] = nil
        awaiting = waiting
    }

    /// What the anchor's list owes the other devices: everything on it this device can name and
    /// hasn't sent or been told not to send. The list is its own ledger — nothing is written
    /// down when something goes on it, so a nameless app crosses whenever the shield finally
    /// names it, and one never named simply never crosses.
    ///
    /// `names` (e.g. the Mac's Applications-folder walk) is only called when something on the
    /// list still needs it, even though this runs on every settle.
    static func anchorAdditions(config: Config, names: () -> [TargetKind: String], now: Date) -> [SharedAddition] {
        guard DeviceLink.isEnrolled, config.link.sendAdditions != .never else { return [] }
        return SharedAdditions.anchorList(
            in: config,
            names: names,
            settled: anchorSent.union(anchorDeclined),
            origin: AnchorSync.deviceID,
            platform: AnchorSync.platform,
            now: now
        )
    }

    /// Everything either half can settle now: sent under Always, or returned to be offered
    /// under Ask. Targets that no longer exist are forgotten.
    ///
    /// Order matters on the phone: the caller links the companion site *before* this runs, so a
    /// YouTube that just learned its name goes out with youtube.com beside it.
    @discardableResult
    static func settleAwaiting(
        config: Config,
        now: Date,
        anchorNames: () -> [TargetKind: String] = { [:] }
    ) -> [SharedAddition] {
        var offers: [SharedAddition] = []
        var waiting = awaiting
        for (id, half) in awaiting {
            guard let target = config.targets.first(where: { $0.id.uuidString == id }) else {
                waiting[id] = nil
                continue
            }
            switch outgoing(for: target, half: half, config: config, now: now) {
            case .send(let addition):
                send(addition, now: now)
                waiting[id] = nil
            case .ask(let addition):
                offers.append(addition)
            case .nothing:
                // Forgotten if off the link or told Never since added; else still waiting on a name.
                if !DeviceLink.isEnrolled || config.link.sendAdditions == .never { waiting[id] = nil }
            }
        }
        awaiting = waiting

        for addition in anchorAdditions(config: config, names: anchorNames, now: now) {
            // Agreeing to send this thing's *rule* is not agreeing to anchor it elsewhere too —
            // a Mac or iPad with no tag to lift it is a bigger commitment, so it asks separately.
            if config.link.sendAdditions == .always {
                send(addition, now: now)
            } else {
                offers.append(addition)
            }
        }
        return offers.sorted { $0.title < $1.title }
    }

    /// A target already sent has changed in a way worth resending — its first rule. Quiet when
    /// never sent (that's `settleAwaiting`'s question). Keeps the half it last crossed under: the
    /// ring is keyed by id, so resending under the wrong half would strip the anchoring off the
    /// entry for a device that hasn't read it yet. Checked against `anchorSent`, not the anchor's
    /// list, so a rule arriving later can't silently carry an anchoring the person never agreed to send.
    static func resendIfSent(_ target: Target, config: Config, now: Date) {
        guard sent.contains(target.id.uuidString) else { return }
        guard case .send(var addition) = outgoing(for: target, half: .rules, config: config, now: now) else { return }
        if anchorSent.contains(Companions.normalize(name: addition.title)) { addition.half = .anchor }
        send(addition, now: now)
    }

    // MARK: Receiving

    /// What taking the arrivals did: what landed, in words, and what is left to ask about.
    struct Arrivals: Equatable {
        var landed: [String] = []
        var asks: [SharedAdditions.Landing] = []
    }

    /// Everything the other devices have added that this one hasn't dealt with. Always lands it
    /// in `state` for the caller to save; Ask returns it to be offered; Never passes it over.
    /// `installed` is only called when something is actually waiting — on the Mac it walks the
    /// Applications folders, not something to do on every poll.
    static func takeArrivals(_ state: inout SharedState, installed: () -> [String: String]) -> Arrivals {
        var arrivals = Arrivals()
        guard DeviceLink.isEnrolled else { return arrivals }
        let now = state.now
        let pending = SharedAdditions.pending()
        guard !pending.isEmpty else { return arrivals }
        let installed = installed()
        for addition in pending {
            let landing = SharedAdditions.landing(
                for: addition, in: state.config, installed: installed,
                companion: state.config.link.companionSite, now: now
            )
            if landing.isNothing {
                SharedAdditions.markSeen(addition)
                continue
            }
            switch state.config.link.acceptAdditions {
            case .always:
                let touched = SharedAdditions.land(landing, in: &state.config, now: now)
                noteLanded(landing)
                SharedAdditions.markSeen(addition)
                if !touched.isEmpty {
                    let names = touched.compactMap { state.config.target(id: $0)?.displayName }
                    arrivals.landed.append("\(addition.title) from \(LinkedDevice.defaultName(for: addition.platform)): \(names.joined(separator: ", "))")
                }
            case .ask:
                arrivals.asks.append(landing)
            case .never:
                SharedAdditions.markSeen(addition)
            }
        }
        return arrivals
    }

    /// Lands one the person said yes to. The rows it touched.
    @discardableResult
    static func accept(_ landing: SharedAdditions.Landing, in state: inout SharedState) -> [UUID] {
        let touched = SharedAdditions.land(landing, in: &state.config, now: state.now)
        noteLanded(landing)
        SharedAdditions.markSeen(landing.addition)
        return touched
    }

    #if os(iOS)
    private static let anchorOwedKey = "furlough.link.anchorOwed"

    /// Apps another device anchored that this phone agreed to hold but can't add yet — only
    /// Apple's picker mints a Screen Time token, so a bare name can't do it directly (Screen
    /// Time data access can match one later, see `AppModel.anchorArrivalsFromTheTables`). Kept
    /// as a queue since that match needs an async query the landing itself doesn't wait for.
    static var anchorOwed: [String] {
        get { SharedStore.defaults.stringArray(forKey: anchorOwedKey) ?? [] }
        set { SharedStore.defaults.set(SharedAdditions.unique(newValue), forKey: anchorOwedKey) }
    }
    #endif

    /// Marks the name settled on the anchor's half so the walk doesn't offer to send it back to
    /// the device it came from — every device reads every ring, so nothing is lost by not
    /// forwarding. On the phone, an anchored app it can't add itself is also queued for the
    /// tables; nothing to do on the Mac, where an app is just a bundle identifier.
    private static func noteLanded(_ landing: SharedAdditions.Landing) {
        guard landing.addition.half == .anchor else { return }
        if landing.anchors {
            anchorSent = anchorSent.union([Companions.normalize(name: landing.addition.title)])
        }
        #if os(iOS)
        if landing.appNeedsPicker { anchorOwed += landing.addition.bundleIDs }
        #endif
    }

    #if DEBUG || TESTING_TOOLS
    static func forget() {
        var keys = [awaitingKey, sentKey, sendDeclinedKey, anchorSentKey, anchorDeclinedKey]
        #if os(iOS)
        keys.append(anchorOwedKey)
        #endif
        for key in keys { SharedStore.defaults.removeObject(forKey: key) }
    }
    #endif
}
