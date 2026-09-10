import Foundation

/// The link's traffic from a model's side: what to do when this device adds something, and
/// what to do with what the others added. The I/O around `SharedAdditions`, which decides, so
/// both apps make the same moves in the same order without each carrying a copy of them.
///
/// Sending is settled in two steps because the phone cannot always say what it added. A target
/// is written down as *awaiting* the moment it is added; `outgoing` asks whether it can be
/// described yet and what the setting says, and `send` is what actually writes. On the Mac the
/// two steps happen in the same breath. On the phone the second may come hours after the first,
/// when the shield has taught the app its name — see `SharedAdditions.describe`.
///
/// The two halves keep that ledger differently, because they hold what they hold differently.
/// A rule is a target with an id, so the rules half writes ids down as awaiting. The anchor's
/// list is kinds, and a kind it holds that no rule covers has no id at all — so the anchor half
/// writes nothing down: `anchorAdditions` walks the list itself on every settle, and what has
/// already gone out is remembered by name. Both end in the same `send`, and both cross as the
/// same `SharedAddition`, tagged with the `Half` that tells the receiver where it belongs.
enum LinkFlow {
    private static let awaitingKey = "furlough.link.awaiting"
    private static let sentKey = "furlough.link.sent"
    private static let sendDeclinedKey = "furlough.link.sendDeclined"
    private static let anchorSentKey = "furlough.link.anchorSent"
    private static let anchorDeclinedKey = "furlough.link.anchorDeclined"

    // MARK: Sending

    /// What to do about a target this device added.
    enum Outgoing: Equatable {
        /// Off the link, told Never, or not nameable yet: nothing, for now or for good.
        case nothing
        /// Send it now: told Always, or already sent once — a rule landing on something the
        /// person has already agreed to send is not a second question.
        case send(SharedAddition)
        /// Told Ask, and not asked yet: offer it.
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

    /// Targets this device has sent at least once, by id. A later change to one — its first
    /// rule — goes out again without asking.
    static var sent: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: sentKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: sentKey) }
    }

    /// Targets the person said not to send, by id. Not asked again.
    static var sendDeclined: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: sendDeclinedKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: sendDeclinedKey) }
    }

    /// What has gone out from the anchor's list, by normalized name, and what the person said
    /// not to send from it. Names rather than ids, because the anchor's list is kinds and a
    /// kind held by the anchor alone has no id — and a name is the only thing that crosses
    /// anyway, so two things called the same thing are one question, asked once.
    ///
    /// The consequence, stated because it is a choice and not an oversight: taking something
    /// off the anchor's list and putting it back does not ask again. The person has already
    /// answered about that name, and a nudge that comes back is a nag.
    static var anchorSent: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: anchorSentKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: anchorSentKey) }
    }

    static var anchorDeclined: Set<String> {
        get { Set(SharedStore.defaults.stringArray(forKey: anchorDeclinedKey) ?? []) }
        set { SharedStore.defaults.set(Array(newValue).sorted(), forKey: anchorDeclinedKey) }
    }

    /// Writes `targets` down as awaiting, where the setting allows any sending at all. Called
    /// by every add to the rules half.
    ///
    /// The anchor's half keeps no ledger of its own: its list is the ledger. `anchorAdditions`
    /// walks it on every settle and offers whatever it can name and has not sent, so a picked
    /// app that is nameless when it goes on the list is offered whenever the name arrives,
    /// without anything having had to write down that it was waiting.
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

    /// Sends it: stamps the next sequence, writes the ring, and remembers that this target has
    /// gone out so its first rule follows without asking. An anchor addition is remembered by
    /// name as well, which is what the anchor's walk reads.
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

    /// Not this one: it is not asked about again.
    ///
    /// Per half, and deliberately. Declining to tell the others that something is anchored here
    /// says nothing about whether a rule for it should cross later; they are two questions, and
    /// answering the one is not answering the other.
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
    /// has neither sent nor been told not to send, described as it would go out.
    ///
    /// The list is the ledger. Nothing is written down when something goes on it; this walks it
    /// whenever a settle runs and offers what it can describe, so a picked app that is nameless
    /// on Monday crosses on Thursday when the shield finally names it, and one that is never
    /// named simply never crosses. `Half` is what tells the receiving device to put it on its
    /// own anchor's list rather than only among its rules.
    ///
    /// `names` is what this device calls the things the anchor holds that no rule covers, asked
    /// for once and only when something on the list still needs it: on the Mac it walks the
    /// Applications folders, and this runs on every settle.
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

    /// Everything either half can settle now: sent under Always, or, under Ask, returned to be
    /// offered. Targets that no longer exist are forgotten.
    ///
    /// The order matters on the phone: the caller links the companion site *before* this runs,
    /// so a YouTube that has just learned its name goes out with youtube.com beside it.
    ///
    /// `anchorNames` is passed through to `anchorAdditions`, which is the anchor's whole side
    /// of this — it has no `awaiting` of its own to walk.
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
                // Off the link or told Never since it was added: forgotten. Not nameable yet:
                // still waiting.
                if !DeviceLink.isEnrolled || config.link.sendAdditions == .never { waiting[id] = nil }
            }
        }
        awaiting = waiting

        for addition in anchorAdditions(config: config, names: anchorNames, now: now) {
            // Always, or ask — and having agreed to send this thing's *rule* is not agreeing to
            // this. Telling the other devices that something is anchored here anchors it there,
            // and the Mac and the iPad have no tag to lift it with; that is a bigger thing than
            // a set of hours, and it gets its own question.
            if config.link.sendAdditions == .always {
                send(addition, now: now)
            } else {
                offers.append(addition)
            }
        }
        return offers.sorted { $0.title < $1.title }
    }

    /// A target already sent has changed in a way worth sending again — its first rule. Quiet
    /// when it was never sent: that is `settleAwaiting`'s question.
    ///
    /// It keeps the half it last crossed under, which for something already sent from the
    /// anchor's list is the anchor's. The ring is keyed by id, so a second write about the same
    /// target replaces the first: sending an anchored target's new rule under the rules half
    /// would take the anchoring back off the entry for any device that had not read it yet.
    ///
    /// Read off `anchorSent` rather than off the anchor's list, and that is the point. Being on
    /// the list is this device's business; having been sent from it is the person's answer, and
    /// a rule arriving later must not be the thing that quietly carries the anchoring across.
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

    /// Everything the other devices have added that this one has not dealt with. Under Always
    /// it lands in `state` here and the caller saves and enforces; under Ask it comes back to
    /// be offered, and stays pending until it is answered; under Never it is passed over. What
    /// is already here is passed over whatever the setting says.
    ///
    /// `installed` is asked once, and only when something is actually waiting: on the Mac it
    /// walks the Applications folders, which is not a thing to do on every half-minute poll.
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

    /// Apps another device anchored that this phone has agreed to hold and cannot add yet, by
    /// bundle identifier. Only Apple's picker mints a Screen Time token, so a name alone can
    /// never put an app on this phone's anchor list — except where Screen Time data access
    /// exists, which can match a bundle identifier to the token for it
    /// (`AppModel.anchorArrivalsFromTheTables`). This is the queue that waits for that.
    ///
    /// Kept rather than acted on at once because the answer needs an async query and the
    /// landing does not: the arrival lands what it can now, and the app follows.
    static var anchorOwed: [String] {
        get { SharedStore.defaults.stringArray(forKey: anchorOwedKey) ?? [] }
        set { SharedStore.defaults.set(SharedAdditions.unique(newValue), forKey: anchorOwedKey) }
    }
    #endif

    /// What taking one in leaves behind.
    ///
    /// The name is settled on the anchor's half: it has crossed, and the walk must not turn
    /// round and offer to send it back to the device it came from. Every device reads every
    /// ring, so nothing is lost by not forwarding — the third device on the link hears it from
    /// the origin, not from here.
    ///
    /// And, on the phone, an anchored app it cannot add itself is queued for the tables. Nothing
    /// on the Mac, where an app is a bundle identifier and there is nothing to wait for.
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
