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
enum LinkFlow {
    private static let awaitingKey = "furlough.link.awaiting"
    private static let sentKey = "furlough.link.sent"
    private static let sendDeclinedKey = "furlough.link.sendDeclined"

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

    /// Writes `targets` down as awaiting, where the setting allows any sending at all. Called
    /// by every add, on both halves.
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
    /// gone out so its first rule follows without asking.
    static func send(_ addition: SharedAddition, now: Date) {
        var stamped = addition
        stamped.sequence = DeviceLink.nextAdditionSequence()
        stamped.addedAt = now
        SharedAdditions.publish(stamped, now: now)
        sent = sent.union([addition.id.uuidString])
        var waiting = awaiting
        waiting[addition.id.uuidString] = nil
        awaiting = waiting
    }

    /// Not this one: it is not asked about again.
    static func decline(_ addition: SharedAddition) {
        sendDeclined = sendDeclined.union([addition.id.uuidString])
        var waiting = awaiting
        waiting[addition.id.uuidString] = nil
        awaiting = waiting
    }

    /// Everything awaiting that can be settled now: sent under Always, or, under Ask, returned
    /// to be offered. Targets that no longer exist are forgotten.
    ///
    /// The order matters on the phone: the caller links the companion site *before* this runs,
    /// so a YouTube that has just learned its name goes out with youtube.com beside it.
    @discardableResult
    static func settleAwaiting(config: Config, now: Date) -> [SharedAddition] {
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
        return offers.sorted { $0.title < $1.title }
    }

    /// A target already sent has changed in a way worth sending again — its first rule. Quiet
    /// when it was never sent: that is `settleAwaiting`'s question.
    static func resendIfSent(_ target: Target, config: Config, now: Date) {
        guard sent.contains(target.id.uuidString) else { return }
        if case .send(let addition) = outgoing(for: target, half: awaiting[target.id.uuidString] ?? .rules, config: config, now: now) {
            send(addition, now: now)
        }
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
                for: addition, in: state.config, installed: installed, companion: state.config.link.companionSite
            )
            if landing.isNothing {
                SharedAdditions.markSeen(addition)
                continue
            }
            switch state.config.link.acceptAdditions {
            case .always:
                let touched = SharedAdditions.land(landing, in: &state.config, now: now)
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
        SharedAdditions.markSeen(landing.addition)
        return touched
    }

    #if DEBUG || TESTING_TOOLS
    static func forget() {
        for key in [awaitingKey, sentKey, sendDeclinedKey] { SharedStore.defaults.removeObject(forKey: key) }
    }
    #endif
}
