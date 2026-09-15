import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications
import WidgetKit

enum ProposalResult: Equatable {
    case appliedNow
    case scheduled(Date)
    case unchanged

    var message: String {
        switch self {
        case .appliedNow: "Applied immediately."
        case .scheduled(let date): "This loosens your rules, so it takes effect \(date.formatted(date: .abbreviated, time: .shortened))."
        case .unchanged: "Nothing changed."
        }
    }
}

/// Every mutation goes through persisted state then `enforce()`, as on iOS; only enforcement
/// underneath differs.
@MainActor
@Observable
final class MacModel {
    static let shared = MacModel()

    var state = SharedStore.load()
    var lastError: String?
    var notificationsGranted: Bool?
    var isOnboarded = SharedStore.defaults.bool(forKey: MacModel.onboardedKey)
    var launchesAtLogin = SMAppService.mainApp.status == .enabled
    var watchdogIsOn = Watchdog.isOn
    var browserAccess: [BrowserAccess] = []
    let enforcer = Enforcer.shared
    /// A per-view `Timer` never fires here: the detail pane rebuilds every tick and
    /// re-subscribes it first. Views read `now` from the model instead.
    private(set) var now = Date.now

    /// Stored beside `furlough.mac.onboarded`, outside `SharedState`: like the phone's copy,
    /// it records what was asked, not what is blocked, so it must not travel in an exported
    /// setup or wait out a delay.
    private(set) var startHalf = MacModel.storedStartHalf
    /// Not a third half — opens on `startHalf`, but keeps the other half's guide running too.
    private(set) var wantsBothHalves = SharedStore.defaults.bool(forKey: MacModel.bothHalvesKey)
    /// Which half the + button adds to while the Anchor half is on screen. See the phone's
    /// `AppModel.anchorPageAdds`.
    private(set) var anchorHalfAdds = MacModel.storedAnchorHalfAdds
    /// A flag, not derived: the last guide step can't be answered from config alone — the
    /// first two can, see `HalfGuide`.
    private(set) var finishedGuides = MacModel.storedFinishedGuides

    private(set) var hasOfferedWebFilter = SharedStore.defaults.bool(forKey: MacModel.filterOfferedKey)
    /// Which notifications this Mac has switched off; everything absent is on. Per-device,
    /// like the record they are about — these do not sync, unlike most settings. See
    /// `NotificationPreferences`.
    private(set) var mutedNotifications = NotificationPreferences.muted
    /// The weekly digest's own switch, which has a second home in Settings > The record.
    var weeklyDigest: Bool { !mutedNotifications.contains(.weeklyDigest) }

    private static let onboardedKey = "furlough.mac.onboarded"
    private static let filterOfferedKey = "furlough.mac.filterOffered"
    private static let startHalfKey = "furlough.mac.startHalf"
    private static let bothHalvesKey = "furlough.mac.bothHalves"
    private static let anchorHalfAddsKey = "furlough.mac.anchorHalfAdds"
    private static let finishedGuidesKey = "furlough.mac.finishedGuides"
    private static var storedStartHalf: Half {
        SharedStore.defaults.string(forKey: startHalfKey).flatMap(Half.init(rawValue:)) ?? .rules
    }
    private static var storedAnchorHalfAdds: Half {
        SharedStore.defaults.string(forKey: anchorHalfAddsKey).flatMap(Half.init(rawValue:)) ?? .anchor
    }
    private static var storedFinishedGuides: Set<Half> {
        Set((SharedStore.defaults.stringArray(forKey: finishedGuidesKey) ?? []).compactMap(Half.init(rawValue:)))
    }
    @ObservationIgnored private var ticker: Timer?

    // MARK: Lifecycle

    func start() {
        SharedStore.log("fonts: \(NSFont(name: "Onest-Regular", size: 12) == nil ? "MISSING, check ATSApplicationFontsPath" : "ok")")
        if SharedStore.defaults.bool(forKey: "furlough.mac.migrated") {
            SharedStore.defaults.removeObject(forKey: "furlough.mac.migrated")
            SharedStore.log("moved the store into the App Group for the widget")
        }
        var stored = SharedStore.load()
        if MacNames.adopt(&stored.config, name: { AppInfo.name(for: $0) }) {
            SharedStore.save(stored)
            SharedStore.log("moved app names out of the nickname field")
        }
        // The enforcer can change state on its own (a budget spent, a pending change landing);
        // refresh the widget on every change.
        enforcer.onChange = { [weak self] in
            self?.reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
        // No midnight callback on Mac; the enforcer's day-boundary tick re-plans the digest
        // here instead — see `Enforcer.onDayRollover`.
        enforcer.onDayRollover = { [weak self] state in
            guard let self else { return }
            let clock = state.clock()
            PendingNotifications.sync(state: state, now: clock.now, drift: clock.drift, muted: self.mutedNotifications)
        }
        enforcer.start()
        startTicking()
        reload()
        seedFinishedGuides()
        Task { await refreshNotificationStatus() }
        refreshBrowserAccess()
        // Force Quit is still the way out, but it should not last until the next login.
        if isOnboarded { Watchdog.enableIfNeeded() }
        observeCloud()
        AnchorCloud.synchronize()
        SharedStore.log("iCloud at launch: \(cloudAvailable ? "reachable" : "unreachable; the anchor cannot cross")")
        // One-time: grandfathers a Mac already talking to its phone onto the link.
        DeviceLink.decideGrandfathering(now: state.now)
        enforce(reason: "launch")
        refreshLink()
        settleLink(reason: "launch")
    }

    // MARK: The two halves

    /// Written on Continue, not per-click, so backing out of the intro doesn't leave a stray
    /// half chosen.
    func chooseStart(half: Half, both: Bool) {
        SharedStore.defaults.set(half.rawValue, forKey: Self.startHalfKey)
        SharedStore.defaults.set(both, forKey: Self.bothHalvesKey)
        startHalf = half
        wantsBothHalves = both
    }

    /// `wantsBothHalves` is untouched: changing the opening half doesn't affect the other guide.
    func setStartHalf(_ half: Half) {
        guard half != startHalf else { return }
        chooseStart(half: half, both: wantsBothHalves)
    }

    func setAnchorHalfAdds(_ half: Half) {
        guard half != anchorHalfAdds else { return }
        SharedStore.defaults.set(half.rawValue, forKey: Self.anchorHalfAddsKey)
        anchorHalfAdds = half
    }

    func addDestination(on half: Half) -> Half {
        half == .rules ? .rules : anchorHalfAdds
    }

    func finishGuide(_ half: Half) {
        guard !finishedGuides.contains(half) else { return }
        write(finishedGuides: finishedGuides.union([half]))
    }

    /// Only the last step is a flag; the first two re-derive live from config, so this is the
    /// whole of what needs resetting.
    func restartGuides() {
        guard !finishedGuides.isEmpty else { return }
        write(finishedGuides: [])
    }

    /// Runs once, keyed by the key's absence (`nil` means "never asked"); writing even an
    /// empty set closes it.
    private func seedFinishedGuides() {
        guard SharedStore.defaults.object(forKey: Self.finishedGuidesKey) == nil else { return }
        var seeded: Set<Half> = []
        let config = state.config
        if config.targets.contains(where: { $0.rule != nil }) { seeded.insert(.rules) }
        if hasKey, config.anchor.hasSomethingToHold { seeded.insert(.anchor) }
        write(finishedGuides: seeded)
    }

    private func write(finishedGuides halves: Set<Half>) {
        SharedStore.defaults.set(halves.map(\.rawValue).sorted(), forKey: Self.finishedGuidesKey)
        finishedGuides = halves
    }

    var diagnostics: Diagnostics {
        Diagnostics.macSummary(
            Diagnostics.MacReading(
                filter: filterReading,
                refusedBrowser: browserAccess.first { $0.status == .denied }?.name,
                appGroupAvailable: SharedStore.isAppGroupAvailable,
                notificationsAllowed: notificationsGranted
            )
        )
    }

    /// `notInApplications` maps to broken, not not-installed: it was asked for but macOS
    /// won't load it from here.
    private var filterReading: Diagnostics.MacReading.Filter {
        switch enforcer.webFilter.status {
        case .notInstalled: .notInstalled
        case .installing, .awaitingApproval: .waiting
        case .on: .on
        case .disabledInSettings, .filterOff, .filterDenied, .failed, .notInApplications: .broken
        }
    }

    // MARK: The anchor across devices

    @ObservationIgnored private var cloudObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var cloudPolls = 0

    /// Cached here, not read in the view: it's a KV-store round trip, and the view rebuilds
    /// every second.
    private(set) var cloudAvailable = AnchorCloud.isAvailable

    /// iCloud's change notification isn't guaranteed; the ticker also polls every 30s as backup.
    private func observeCloud() {
        guard cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: AnchorCloud.changeNotification, object: nil, queue: .main
        ) { notification in
            let accountChanged = AnchorCloud.isAccountChange(notification)
            Task { @MainActor in
                if accountChanged { MacModel.shared.refreshCloudAvailability(reason: "account changed") }
                MacModel.shared.applyRemoteAnchor(reason: accountChanged ? "iCloud account changed" : "iCloud changed")
            }
        }
    }

    /// The account can be signed out in System Settings with no notification; this is how
    /// it's noticed.
    func refreshCloudAvailability(reason: String) {
        let available = AnchorCloud.isAvailable
        guard available != cloudAvailable else { return }
        cloudAvailable = available
        SharedStore.log("iCloud is \(available ? "reachable again" : "unreachable; the anchor cannot cross") (\(reason))")
    }

    /// Re-read on demand, not observed: it's a KV-store read.
    private(set) var link = AnchorSync.linkStatus()

    /// Does all three deliberately: sync alone leaves stale data shown, re-read alone fetches
    /// nothing new.
    func checkLink() {
        AnchorCloud.synchronize()
        refreshCloudAvailability(reason: "check link")
        applyRemoteAnchor(reason: "check link")
        refreshLink()
        SharedStore.log("link check: \(link.headline) — \(link.detail(now: now))")
    }

    func applyRemoteAnchor(reason: String) {
        var current = SharedStore.load()
        let note = AnchorSync.pull(into: &current.config, now: current.now)
        let arrivals = LinkFlow.takeArrivals(&current, installed: { Self.installedByIdentifier() })
        self.arrivals = arrivals.asks
        guard note != nil || !arrivals.landed.isEmpty else { return }
        SharedStore.save(current)
        if let note { SharedStore.log("iCloud anchor (\(reason)): \(note)") }
        for landed in arrivals.landed { SharedStore.log("link: landed \(landed) (\(reason))") }
        refreshLink()
        enforce(reason: "iCloud")
    }

    // MARK: The link

    private(set) var isEnrolled = DeviceLink.isEnrolled
    private(set) var devices: [LinkedDevice] = []
    /// Cached for display; `dropAnchor` re-reads fresh rather than trusting this.
    private(set) var hasKey = false
    private(set) var arrivals: [SharedAdditions.Landing] = []
    private(set) var outgoing: [SharedAddition] = []

    func refreshLink() {
        link = AnchorSync.linkStatus()
        isEnrolled = DeviceLink.isEnrolled
        let roster = DeviceLink.roster()
        devices = roster.others(than: AnchorSync.deviceID)
        hasKey = isEnrolled && roster.hasKey(besides: AnchorSync.deviceID)
    }

    private static func installedByIdentifier() -> [String: String] {
        Dictionary(
            AppCatalog.installed().map { (Companions.normalize(bundleID: $0.bundleID), $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Saved only; none of these settings ever block anything themselves.
    func setLinkPreferences(_ preferences: LinkPreferences) {
        guard preferences != state.config.link else { return }
        SharedStore.mutate { $0.config.link = preferences }
        SharedStore.log("link settings: site \(preferences.companionSite.rawValue), send \(preferences.sendAdditions.rawValue), accept \(preferences.acceptAdditions.rawValue)")
        reload()
        settleLink(reason: "link settings")
        applyRemoteAnchor(reason: "link settings")
    }

    func enrollDevice(name: String) {
        DeviceLink.enroll(name: name, now: now)
        SharedStore.log("link: joined as \(DeviceLink.name)")
        refreshLink()
        applyRemoteAnchor(reason: "joined the link")
        settleLink(reason: "joined the link")
    }

    func leaveLink() -> String? {
        if let refusal = DeviceLink.leave(anchorHoldsHere: state.config.anchor.isHolding(at: now), now: now) {
            return refusal.message
        }
        outgoing = []
        arrivals = []
        refreshLink()
        return nil
    }

    func revokeDevice(_ id: String) -> String? {
        if let refusal = DeviceLink.revoke(id, anchorHoldsHere: state.config.anchor.isHolding(at: now), now: now) {
            return refusal.message
        }
        refreshLink()
        return nil
    }

    /// A Mac app names itself, so this settles in the same breath as the add (no extra
    /// confirmation step).
    func settleLink(reason: String) {
        outgoing = LinkFlow.settleAwaiting(config: state.config, now: now) {
            // Only computed when needed: reads the Applications folder, which isn't free.
            var names: [TargetKind: String] = [:]
            let installed = Self.installedByIdentifier()
            for kind in state.config.anchor.kinds {
                guard case .macApp(let bundleID) = kind,
                      let name = installed[Companions.normalize(bundleID: bundleID)] else { continue }
                names[kind] = name
            }
            return names
        }
        isEnrolled = DeviceLink.isEnrolled
    }

    func sendOutgoing(_ addition: SharedAddition) {
        LinkFlow.send(addition, now: now)
        outgoing.removeAll { $0.id == addition.id }
    }

    func declineOutgoing(_ addition: SharedAddition) {
        LinkFlow.decline(addition)
        outgoing.removeAll { $0.id == addition.id }
    }

    @discardableResult
    func acceptArrival(_ landing: SharedAdditions.Landing) -> String {
        var current = SharedStore.load()
        let touched = LinkFlow.accept(landing, in: &current)
        SharedStore.save(current)
        SharedStore.log("link: took \(landing.addition.title) from \(landing.addition.origin.prefix(8))")
        arrivals.removeAll { $0.addition.id == landing.addition.id }
        enforce(reason: "link arrival")
        let names = touched.compactMap { state.config.target(id: $0)?.displayName }
        var message = names.isEmpty ? "Nothing new to block." : "\(UtilityText.list(names)) \(names.count == 1 ? "is" : "are") in Furlough now."
        if landing.anchors { message += " \(names.count == 1 ? "It is" : "They are") on the Anchor's list here too." }
        if landing.rule != nil { message += " The rule came with it, and can be undone for \(Furlough.undoWindowMinutes) minutes." }
        return message
    }

    func declineArrival(_ landing: SharedAdditions.Landing) {
        SharedAdditions.decline(landing.addition)
        arrivals.removeAll { $0.addition.id == landing.addition.id }
    }

    /// No NFC tag on the Mac: only the phone's tag, via iCloud, can release this anchor.
    /// Why a drop would be refused right now, without performing one — for the menu item, which
    /// has to be disabled with a reason rather than enabled and then complaining. Reads the
    /// cached link answers; `dropAnchor` re-reads them fresh before it actually locks anything.
    var dropRefusal: Policy.DropRefusal? {
        var config = state.config
        return AnchorSync.macDrop(&config, now: now, hasKey: hasKey, cloudAvailable: cloudAvailable)
    }

    func dropAnchor() -> String? {
        var current = SharedStore.load()
        let now = current.now
        // Re-read fresh, not cached: a poll-stale iCloud/roster read here could lock the
        // anchor with no key to release it.
        refreshCloudAvailability(reason: "about to drop")
        refreshLink()
        if let refusal = AnchorSync.macDrop(&current.config, now: now, hasKey: hasKey, cloudAvailable: cloudAvailable) {
            return refusal.message
        }
        SharedStore.save(current)
        SharedStore.log("anchored (Mac): \(current.config.anchor.heldDescription)")
        enforce(reason: "anchor")
        AnchorSync.publish(current.config.anchor, origin: .drop, now: now)
        finishGuide(.anchor)
        return nil
    }

    @discardableResult
    func addToAnchor(_ kind: TargetKind) -> String? {
        let current = SharedStore.load()
        let anchor = current.config.anchor
        if anchor.isHolding(at: current.now) {
            return "The anchor is down. Scan your tag on your iPhone to change the list."
        }
        guard !anchor.contains(kind) else {
            return anchor.anchorsEverything ? "That already stays open." : "That is already held."
        }
        setAnchorKinds(anchor.kinds + [kind])
        return nil
    }

    func setAnchorKinds(_ kinds: [TargetKind]) {
        var current = SharedStore.load()
        guard !current.config.anchor.isHolding(at: current.now), kinds != current.config.anchor.kinds else { return }
        current.config.anchor.kinds = kinds
        SharedStore.save(current)
        SharedStore.log("anchor: now \(current.config.anchor.anchorsEverything ? "lets through" : "holds") \(kinds.count) item(s)")
        enforce(reason: "anchor edit")
        // Single entry point for the anchor list, so the link's sync needs no separate
        // awaiting-state.
        settleLink(reason: "anchor edit")
    }

    /// Same behavior as the phone's `setAnchorScope`: the list does not survive the switch.
    func setAnchorScope(_ scope: AnchorProfile.Scope) {
        var current = SharedStore.load()
        guard !current.config.anchor.isHolding(at: current.now), current.config.anchor.scope != scope else { return }
        current.config.anchor.scope = scope
        current.config.anchor.kinds = scope == .everythingExcept ? current.config.essentialKinds : []
        SharedStore.save(current)
        SharedStore.log("anchor: scope is now \(scope.rawValue); the list starts with \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor scope")
    }

    /// Replaces anchor drop schedules. Tightening (more/longer) applies now; loosening queues
    /// behind `anchorDelayHours`. Re-saving the current schedule cancels any queued change.
    func setAnchorSchedules(_ schedules: [AnchorSchedule]) -> ProposalResult {
        var current = SharedStore.load()
        let now = current.now
        Policy.liftExpiredAnchor(&current.config, now: now)
        guard !current.config.anchor.isAnchored else { return .unchanged }
        let before = current.pending.count
        current.pending.removeAll { if case .setAnchorSchedules = $0.kind { return true }; return false }
        let dropped = before - current.pending.count
        guard schedules != current.config.anchor.schedules else {
            guard dropped > 0 else { return .unchanged }
            // True cancellation (vs. replacing a queued value) — counted the same way
            // cancelPending does.
            Record.noteCancelled(dropped, in: &current, now: now)
            SharedStore.save(current)
            SharedStore.log("anchor schedule: cancelled the queued change")
            enforce(reason: "anchor schedule")
            return .unchanged
        }
        let result: ProposalResult
        switch Policy.classify(newSchedules: schedules, against: current.config.anchor.schedules) {
        case .tightening:
            current.config.anchor.schedules = schedules
            result = .appliedNow
        case .loosening:
            let effectiveAt = now.addingTimeInterval(TimeInterval(current.config.anchorDelayHours) * 3600)
            Record.queue(
                PendingChange(kind: .setAnchorSchedules(schedules), effectiveAt: effectiveAt),
                in: &current,
                now: now
            )
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        SharedStore.log("anchor schedule: \(TimeFormat.anchorSchedules(schedules)) (\(result == .appliedNow ? "now" : "queued"))")
        enforce(reason: "anchor schedule")
        return result
    }

    func finishOnboarding() {
        SharedStore.defaults.set(true, forKey: Self.onboardedKey)
        isOnboarded = true
        setLaunchAtLogin(true)
        setWatchdog(true)
    }

    /// Waits for the first host target, matching the threshold `Enforcer` already uses before
    /// reading any browser.
    var shouldOfferWebFilter: Bool {
        guard !hasOfferedWebFilter, isOnboarded else { return false }
        guard !enforcer.webFilter.isWanted, !enforcer.webFilter.status.isOn else { return false }
        return state.config.hasAnyHost
    }

    /// Muting changes nothing about what is shielded, so it applies at once and waits out no
    /// delay. The re-plan is what withdraws one already scheduled; nothing here moves a shield,
    /// so it is a re-plan rather than a whole `enforce`.
    func setNotification(_ kind: NotificationKind, on: Bool) {
        guard NotificationPreferences.isOn(kind) != on else { return }
        NotificationPreferences.set(kind, on: on)
        mutedNotifications = NotificationPreferences.muted
        SharedStore.log("notification \(kind.rawValue) \(on ? "on" : "off")")
        let current = SharedStore.load()
        let clock = current.clock()
        PendingNotifications.sync(
            state: current, now: clock.now, drift: clock.drift, muted: mutedNotifications
        )
    }

    func setWeeklyDigest(_ on: Bool) { setNotification(.weeklyDigest, on: on) }

    func noteWebFilterOffered() {
        guard !hasOfferedWebFilter else { return }
        SharedStore.defaults.set(true, forKey: Self.filterOfferedKey)
        hasOfferedWebFilter = true
    }

    func requestNotifications() async {
        do {
            notificationsGranted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            notificationsGranted = false
        }
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsGranted = settings.authorizationStatus == .authorized
    }

    func refreshBrowserAccess() {
        browserAccess = enforcer.browsers.access()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            SharedStore.log("login item: \(error.localizedDescription)")
            lastError = "Could not change the login item: \(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Not held behind the loosening delay: System Settings can switch this off anyway regardless.
    func setWatchdog(_ on: Bool) {
        if !Watchdog.set(on) { lastError = Self.watchdogRefused }
        watchdogIsOn = Watchdog.isOn
    }

    static let watchdogRefused = "Could not change the watchdog. System Settings > General > Login Items has the final say."

    func reload() {
        state = SharedStore.load()
    }

    var clock: Clock.Reading { state.clock() }

    /// Added to `.common` RunLoop mode so it keeps firing while a menu is open or a window
    /// is dragged.
    private func startTicking() {
        guard ticker == nil else { return }
        now = clock.now
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = self.clock.now
                self.cloudPolls += 1
                if self.cloudPolls % 30 == 0 {
                    AnchorCloud.synchronize()
                    self.refreshCloudAvailability(reason: "poll")
                    self.applyRemoteAnchor(reason: "poll")
                }
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func enforce(reason: String) {
        var current = SharedStore.load()
        let clock = current.clock()
        let now = clock.now
        if Policy.applyDuePending(&current, now: now) {
            SharedStore.log("applied due pending changes (\(reason))")
        }
        if Policy.liftExpiredAnchor(&current.config, now: now) {
            SharedStore.log("a timed anchor's time had passed; lifted it (\(reason))")
        }
        if let note = AnchorSync.pull(into: &current.config, now: now) {
            SharedStore.log("iCloud anchor (\(reason)): \(note)")
        }
        current.runtime.lastRegistration = now
        SharedStore.save(current)
        enforcer.reconcile(reason: reason)
        PendingNotifications.sync(state: current, now: now, drift: clock.drift, muted: mutedNotifications)
        WidgetCenter.shared.reloadAllTimelines()
        reload()
    }

    func usedSeconds(for id: UUID) -> Int {
        enforcer.usedSeconds(for: id)
    }

    // MARK: Targets

    struct AddOutcome: Equatable {
        var added: Target?
        var message: String
    }

    /// Nothing is enforced until its first rule is saved.
    @discardableResult
    func addApp(bundleID: String, name: String) -> AddOutcome {
        var current = SharedStore.load()
        if let existing = current.config.target(bundleID: bundleID) {
            return AddOutcome(added: existing, message: "\(existing.displayName) is already in Furlough.")
        }
        // Goes in `systemName`, not `nickname`: `defaultName` reads `systemName`, so clearing
        // a nickname falls back to this rather than the bundle id.
        let target = Target(kind: .macApp(bundleID: bundleID), systemName: name)
        current.config.targets.append(target)
        SharedStore.save(current)
        SharedStore.log("added app \(bundleID)")
        enforce(reason: "add app")
        // Under Always, add companion host rows directly; under Ask, the sheet still prompts.
        if current.config.link.companionSite == .always {
            let hosts = Companions.hosts(forBundleID: bundleID, name: name).filter { current.config.target(host: $0) == nil }
            if !hosts.isEmpty { addHosts(hosts) }
        }
        LinkFlow.noteAdded([target.id], half: .rules, config: current.config)
        settleLink(reason: "add app")
        return AddOutcome(added: target, message: "Added. Set a schedule; nothing is enforced until you do.")
    }

    /// Anything that looks like a URL is reduced to its host.
    @discardableResult
    func addHost(_ raw: String) -> AddOutcome {
        guard let host = Hosts.normalize(raw) else {
            return AddOutcome(added: nil, message: "Enter a website like youtube.com.")
        }
        var current = SharedStore.load()
        if let existing = current.config.target(host: host) {
            return AddOutcome(added: existing, message: "\(existing.displayName) is already in Furlough.")
        }
        let target = Target(kind: .host(host))
        current.config.targets.append(target)
        SharedStore.save(current)
        SharedStore.log("added site \(host)")
        enforce(reason: "add site")
        LinkFlow.noteAdded([target.id], half: .rules, config: current.config)
        settleLink(reason: "add site")
        return AddOutcome(added: target, message: "Added. Set a schedule; nothing is enforced until you do.")
    }

    /// Skips hosts already present; each lands unconfigured, same as any new target.
    @discardableResult
    func addHosts(_ hosts: [String]) -> [Target] {
        var current = SharedStore.load()
        var added: [Target] = []
        for raw in hosts {
            guard let host = Hosts.normalize(raw), current.config.target(host: host) == nil else { continue }
            let target = Target(kind: .host(host))
            current.config.targets.append(target)
            added.append(target)
        }
        guard !added.isEmpty else { return [] }
        SharedStore.save(current)
        SharedStore.log("added companion site(s) \(added.map(\.displayName).joined(separator: ", "))")
        enforce(reason: "add companion sites")
        LinkFlow.noteAdded(added.map(\.id), half: .rules, config: current.config)
        settleLink(reason: "add companion sites")
        return added
    }

    /// `addHosts`, but for apps offered beside a website just added.
    @discardableResult
    func addApps(_ apps: [(bundleID: String, name: String)]) -> [Target] {
        var current = SharedStore.load()
        var added: [Target] = []
        for app in apps where current.config.target(bundleID: app.bundleID) == nil {
            let target = Target(kind: .macApp(bundleID: app.bundleID), systemName: app.name)
            current.config.targets.append(target)
            added.append(target)
        }
        guard !added.isEmpty else { return [] }
        SharedStore.save(current)
        SharedStore.log("added companion app(s) \(added.map(\.displayName).joined(separator: ", "))")
        enforce(reason: "add companion apps")
        LinkFlow.noteAdded(added.map(\.id), half: .rules, config: current.config)
        settleLink(reason: "add companion apps")
        return added
    }

    // MARK: Importing a setup

    /// Reads the store fresh and writes nothing; the plan is shown before anything happens.
    func review(fileAt url: URL) -> Result<ImportPlan, ConfigImport.Refusal> {
        do {
            let export = try ConfigImport.read(contentsOf: url)
            let current = SharedStore.load()
            return .success(ConfigImport.plan(
                export,
                matches: ConfigImport.matches(for: export, config: current.config),
                state: current,
                now: current.now
            ))
        } catch {
            SharedStore.log("import refused: \(error)")
            return .failure(error)
        }
    }

    /// Batches the whole plan into one save/enforce pass instead of one per target — the way
    /// `propose`/`setUtility` do it would mean N writes and N browser-tab sweeps for an import.
    func applyImport(_ plan: ImportPlan) -> String {
        SharedStore.mutate { state in
            let now = state.now
            ConfigImport.apply(plan, to: &state, now: now)
        }
        SharedStore.log("imported a setup: \(plan.added.count) new, \(plan.immediate.count) now, \(plan.queued.count) queued, \(plan.skipped.count) not used")
        enforce(reason: "import")
        return plan.confirmation
    }

    func classify(rule: Rule, for id: UUID) -> ChangeClass {
        Policy.classify(newRule: rule, against: state.config.target(id: id))
    }

    func propose(rule: Rule, nickname: String, for id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let index = current.config.targets.firstIndex(where: { $0.id == id }) else { return .unchanged }
        Self.rename(index, to: nickname, in: &current)
        let result = Self.assign(rule, to: id, in: &current)
        SharedStore.save(current)
        SharedStore.log("rule edit for \(current.config.targets[index].displayName): \(result)")
        enforce(reason: "rule edit")
        // A rule landing on something already sent goes out too.
        if result == .appliedNow, let target = state.config.target(id: id) {
            LinkFlow.resendIfSent(target, config: state.config, now: now)
        }
        return result
    }

    struct ApplyOutcome: Equatable {
        var appliedNow = 0
        var scheduled = 0
        var effectiveAt: Date?

        var message: String {
            var lines: [String] = []
            if appliedNow > 0 {
                lines.append("Applied to \(appliedNow) now.")
            }
            if scheduled > 0, let effectiveAt {
                let when = effectiveAt.formatted(date: .abbreviated, time: .shortened)
                lines.append(scheduled == 1
                    ? "1 loosens its rules, so it takes effect \(when)."
                    : "\(scheduled) loosen their rules, so they take effect \(when).")
            }
            if lines.isEmpty { return "Nothing changed. They already had these windows." }
            return lines.joined(separator: "\n\n")
        }
    }

    /// Each target is judged independently: tightening applies now, loosening waits the delay
    /// — same as editing one by hand.
    func apply(rule: Rule, nickname: String, for id: UUID, andTo others: [UUID]) -> ApplyOutcome {
        var current = SharedStore.load()
        if let index = current.config.targets.firstIndex(where: { $0.id == id }) {
            Self.rename(index, to: nickname, in: &current)
        }
        var outcome = ApplyOutcome()
        for targetID in [id] + others {
            switch Self.assign(rule, to: targetID, in: &current) {
            case .appliedNow:
                outcome.appliedNow += 1
            case .scheduled(let date):
                outcome.scheduled += 1
                outcome.effectiveAt = date
            case .unchanged:
                break
            }
        }
        SharedStore.save(current)
        SharedStore.log("rule applied to \(1 + others.count) target(s): \(outcome.appliedNow) now, \(outcome.scheduled) scheduled")
        enforce(reason: "rule apply")
        for target in state.config.targets where ([id] + others).contains(target.id) {
            LinkFlow.resendIfSent(target, config: state.config, now: now)
        }
        return outcome
    }

    /// Stored empty, not backfilled: `displayName` already falls back, and this is what
    /// lets a nickname be removed again.
    private static func rename(_ index: Int, to nickname: String, in state: inout SharedState) {
        state.config.targets[index].nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tightening applies immediately; loosening replaces any pending change for this target
    /// and waits out the delay. Caller saves.
    private static func assign(_ rule: Rule, to id: UUID, in state: inout SharedState) -> ProposalResult {
        guard let index = state.config.targets.firstIndex(where: { $0.id == id }) else { return .unchanged }
        let target = state.config.targets[index]
        guard !(target.rule?.isEquivalent(to: rule) ?? false) else { return .unchanged }
        state.pending.removeAll { change in
            if case .setRule(let targetID, _) = change.kind { return targetID == id }
            return false
        }
        if Policy.classify(newRule: rule, against: target) == .tightening {
            state.config.targets[index].rule = rule
            return .appliedNow
        }
        let effectiveAt = state.now.addingTimeInterval(state.config.delay(for: target))
        Record.queue(PendingChange(kind: .setRule(targetID: id, rule: rule), effectiveAt: effectiveAt), in: &state, now: state.now)
        return .scheduled(effectiveAt)
    }

    func removeTarget(id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let target = current.config.target(id: id) else { return .unchanged }
        var result = ProposalResult.unchanged
        if target.rule == nil {
            current.config.targets.removeAll { $0.id == id }
            current.pending.removeAll { $0.targetID == id }
            result = .appliedNow
        } else if !current.pending.contains(where: { $0.kind == .removeTarget(targetID: id) }) {
            let effectiveAt = current.now.addingTimeInterval(current.config.delay(for: target))
            Record.queue(PendingChange(kind: .removeTarget(targetID: id), effectiveAt: effectiveAt), in: &current, now: current.now)
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        enforce(reason: "remove target")
        return result
    }

    /// Queues behind *today's* delay, not the new tier's — closing the "call it essential
    /// first" loophole. A first tier (no rule yet) is free, like a first rule.
    func setUtility(_ level: Utility, for id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let target = current.config.target(id: id) else { return .unchanged }
        let queued = current.pending.contains { change in
            if case .setUtility(let targetID, _) = change.kind { return targetID == id }
            return false
        }
        let plan = Policy.plan(utility: level, for: target, queued: queued)
        guard plan != .unchanged else { return .unchanged }
        // Replaces, not stacks: reselecting the current tier is how a queued change gets cancelled.
        current.pending.removeAll { change in
            if case .setUtility(let targetID, _) = change.kind { return targetID == id }
            return false
        }
        var result = ProposalResult.unchanged
        if plan == .now {
            if let index = current.config.targets.firstIndex(where: { $0.id == id }) {
                current.config.targets[index].utilityLevel = level
            }
            result = .appliedNow
        } else {
            let effectiveAt = current.now.addingTimeInterval(current.config.delay(for: target))
            Record.queue(PendingChange(kind: .setUtility(targetID: id, level: level), effectiveAt: effectiveAt), in: &current, now: current.now)
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        SharedStore.log("utility for \(id): \(level.label), \(result)")
        enforce(reason: "utility edit")
        return result
    }

    func cancelPending(id: UUID) {
        SharedStore.mutate { state in
            let before = state.pending.count
            state.pending.removeAll { $0.id == id }
            Record.noteCancelled(before - state.pending.count, in: &state, now: state.now)
        }
        SharedStore.log("cancelled pending change \(id)")
        enforce(reason: "cancel pending")
    }

    func setDelay(hours: Int) -> ProposalResult {
        var current = SharedStore.load()
        let clamped = max(Furlough.minimumLoosenDelayHours, hours)
        guard clamped != current.config.loosenDelayHours else { return .unchanged }
        current.pending.removeAll { if case .setDelay = $0.kind { return true }; return false }
        var result = ProposalResult.unchanged
        if clamped > current.config.loosenDelayHours {
            current.config.loosenDelayHours = clamped
            result = .appliedNow
        } else {
            // The base multiplies out to every target, so cutting it loosens the slowest one too.
            let effectiveAt = current.now.addingTimeInterval(current.config.longestDelay)
            Record.queue(PendingChange(kind: .setDelay(hours: clamped), effectiveAt: effectiveAt), in: &current, now: current.now)
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        enforce(reason: "delay edit")
        return result
    }

    #if DEBUG || TESTING_TOOLS
    // MARK: Testing

    /// Doesn't touch the web filter or per-browser Automation permissions: both are macOS's
    /// to grant, and the app has no button to re-request them the way iOS re-requests Screen
    /// Time access. Onboarding reads the filter's live status, so it finds the extension in
    /// place regardless.
    func resetEverything() {
        // Cleared first so a login-item/agent refusal further down still has somewhere to report.
        lastError = nil
        SharedStore.reset()
        enforcer.resetUsage()
        AnchorCloud.clear()
        AnchorSync.forgetPhone()
        // Also clears iCloud link entries; a fresh install has never joined.
        DeviceLink.forget()
        LinkFlow.forget()
        outgoing = []
        arrivals = []
        refreshLink()
        // Only unregister if actually registered: `unregister()` throws on a job launchd isn't holding.
        if SMAppService.mainApp.status == .enabled { setLaunchAtLogin(false) }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        // Only overwrite `lastError` if nothing already failed above.
        if !Watchdog.forget(), lastError == nil { lastError = Self.watchdogRefused }
        watchdogIsOn = Watchdog.isOn
        SharedStore.defaults.removeObject(forKey: Self.onboardedKey)
        isOnboarded = false
        // Removed, not set empty: `seedFinishedGuides` treats an absent key as "never asked".
        SharedStore.defaults.removeObject(forKey: Self.startHalfKey)
        SharedStore.defaults.removeObject(forKey: Self.bothHalvesKey)
        SharedStore.defaults.removeObject(forKey: Self.anchorHalfAddsKey)
        SharedStore.defaults.removeObject(forKey: Self.finishedGuidesKey)
        startHalf = .rules
        wantsBothHalves = false
        anchorHalfAdds = .anchor
        finishedGuides = []
        // Removed, not set true: absence is what a fresh install has, and its default is yes
        // to every one of them.
        NotificationPreferences.forgetAll()
        mutedNotifications = []
        SharedStore.log("reset everything (Debug build)")
        enforce(reason: "reset")
    }
    #endif
}
