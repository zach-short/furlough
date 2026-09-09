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

/// Single source of truth for the Mac UI. Every mutation goes through persisted state and
/// then `enforce()`, exactly as on iOS; only the enforcement underneath is different.
@MainActor
@Observable
final class MacModel {
    static let shared = MacModel()

    var state = SharedStore.load()
    var lastError: String?
    var notificationsGranted: Bool?
    var isOnboarded = SharedStore.defaults.bool(forKey: MacModel.onboardedKey)
    var launchesAtLogin = SMAppService.mainApp.status == .enabled
    /// Whether the launchd agent that reopens Furlough after a Force Quit is registered.
    var watchdogIsOn = Watchdog.isOn
    /// Which browsers are running and whether Furlough may read their address bar.
    var browserAccess: [BrowserAccess] = []
    let enforcer = Enforcer.shared
    /// Furlough's own time, re-read once a second. Every countdown and every used-today line
    /// in the window reads it from here rather than keeping a timer of its own: the detail
    /// pane is rebuilt on every tick of the window's clock, and a timer owned by a view that
    /// is rebuilt that often is re-subscribed before it can ever fire, so anything counting on
    /// it stands still until the view is made again.
    private(set) var now = Date.now

    private static let onboardedKey = "furlough.mac.onboarded"
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
        // The enforcer changes state on its own (a budget spent, a pending change landing),
        // and the widget draws from that state, so every change refreshes it.
        enforcer.onChange = { [weak self] in
            self?.reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
        enforcer.start()
        startTicking()
        reload()
        Task { await refreshNotificationStatus() }
        refreshBrowserAccess()
        // Force Quit is still the way out, but it should not last until the next login.
        if isOnboarded { Watchdog.enableIfNeeded() }
        observeCloud()
        AnchorCloud.synchronize()
        enforce(reason: "launch")
    }

    // MARK: The anchor across devices

    @ObservationIgnored private var cloudObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var cloudPolls = 0

    /// Listens for the phone's writes, once. iCloud posts the change to a running app, which
    /// on the Mac is always, and the ticker asks again every half minute in case it did not.
    private func observeCloud() {
        guard cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: AnchorCloud.changeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in MacModel.shared.applyRemoteAnchor(reason: "iCloud changed") }
        }
    }

    /// Merges what the phone wrote, through `AnchorSync.merge`, and enforces if it changed
    /// anything.
    func applyRemoteAnchor(reason: String) {
        var current = SharedStore.load()
        guard let note = AnchorSync.pull(into: &current.config, now: current.now) else { return }
        SharedStore.save(current)
        SharedStore.log("iCloud anchor (\(reason)): \(note)")
        enforce(reason: "iCloud anchor")
    }

    /// Whether a phone has written the record this Mac reads: the one thing that could ever
    /// release an anchor dropped here.
    var phoneSeen: Bool { AnchorSync.phoneSeen }

    /// Drops the anchor on this Mac and tells the phone. No tag here, so no timed drop and no
    /// release: only the phone's tag, arriving through iCloud, lifts it. Returns why not.
    func dropAnchor() -> String? {
        var current = SharedStore.load()
        let now = current.now
        if let refusal = AnchorSync.macDrop(&current.config, now: now, phoneSeen: phoneSeen) {
            return refusal.message
        }
        SharedStore.save(current)
        SharedStore.log("anchored (Mac): \(current.config.anchor.heldDescription)")
        enforce(reason: "anchor")
        AnchorSync.publish(current.config.anchor, origin: .drop, now: now)
        return nil
    }

    /// Replaces the anchor's list: bundle identifiers and hosts, what it holds or, under the
    /// everything-except scope, what it lets through. Refused while anchored.
    func setAnchorKinds(_ kinds: [TargetKind]) {
        var current = SharedStore.load()
        guard !current.config.anchor.isHolding(at: current.now), kinds != current.config.anchor.kinds else { return }
        current.config.anchor.kinds = kinds
        SharedStore.save(current)
        SharedStore.log("anchor: now \(current.config.anchor.anchorsEverything ? "lets through" : "holds") \(kinds.count) item(s)")
        enforce(reason: "anchor edit")
    }

    /// The phone's `setAnchorScope`, with the same rule: the list does not survive the switch.
    /// Widening starts the allowlist from every target tiered Essential, narrowing empties it.
    func setAnchorScope(_ scope: AnchorProfile.Scope) {
        var current = SharedStore.load()
        guard !current.config.anchor.isHolding(at: current.now), current.config.anchor.scope != scope else { return }
        current.config.anchor.scope = scope
        current.config.anchor.kinds = scope == .everythingExcept ? current.config.essentialKinds : []
        SharedStore.save(current)
        SharedStore.log("anchor: scope is now \(scope.rawValue); the list starts with \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor scope")
    }

    func finishOnboarding() {
        SharedStore.defaults.set(true, forKey: Self.onboardedKey)
        isOnboarded = true
        setLaunchAtLogin(true)
        setWatchdog(true)
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

    /// The watchdog is part of enforcement rather than a convenience, so turning it off is a
    /// loosening — but it is deliberately not held behind the delay: System Settings can
    /// switch the agent off anyway, and a toggle that lied about that would be worse.
    func setWatchdog(_ on: Bool) {
        if !Watchdog.set(on) { lastError = Self.watchdogRefused }
        watchdogIsOn = Watchdog.isOn
    }

    /// Said by the toggle and by the reset, so the two cannot drift apart.
    static let watchdogRefused = "Could not change the watchdog. System Settings > General > Login Items has the final say."

    func reload() {
        state = SharedStore.load()
    }

    /// Furlough's own time and how far this Mac's clock is from it. Every view that shows a
    /// countdown reads it through here; see `Clock`.
    var clock: Clock.Reading { state.clock() }

    /// The window's second hand. The same shape as the enforcer's tick and the menu bar's:
    /// built by hand and added to the common mode, so the countdowns keep moving while a menu
    /// is open or a window is being dragged.
    private func startTicking() {
        guard ticker == nil else { return }
        now = clock.now
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = self.clock.now
                // The key-value store is read locally and cheaply; iCloud is asked to refresh
                // it every half minute, since its own change notification is not a promise.
                self.cloudPolls += 1
                if self.cloudPolls % 30 == 0 {
                    AnchorCloud.synchronize()
                    self.applyRemoteAnchor(reason: "poll")
                }
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Re-derives everything from persisted state: folds in due pending changes and makes
    /// the Mac match the rules. Safe to call at any time.
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
        PendingNotifications.sync(state: current, now: now, drift: clock.drift)
        WidgetCenter.shared.reloadAllTimelines()
        reload()
    }

    /// Seconds of use counted against a target's budget today.
    func usedSeconds(for id: UUID) -> Int {
        enforcer.usedSeconds(for: id)
    }

    // MARK: Targets

    struct AddOutcome: Equatable {
        var added: Target?
        var message: String
    }

    /// Adds a Mac app by bundle identifier. Nothing is enforced until its first rule is saved.
    @discardableResult
    func addApp(bundleID: String, name: String) -> AddOutcome {
        var current = SharedStore.load()
        if let existing = current.config.target(bundleID: bundleID) {
            return AddOutcome(added: existing, message: "\(existing.displayName) is already in Furlough.")
        }
        // The app's own name goes in `systemName`, not `nickname`: that is the field
        // `defaultName` reads, so clearing a nickname later comes back to "Safari" rather
        // than to com.apple.Safari. `nickname` stays what Zach called it, as on the phone.
        let target = Target(kind: .macApp(bundleID: bundleID), systemName: name)
        current.config.targets.append(target)
        SharedStore.save(current)
        SharedStore.log("added app \(bundleID)")
        enforce(reason: "add app")
        return AddOutcome(added: target, message: "Added. Set a schedule; nothing is enforced until you do.")
    }

    /// Adds a website by host. Anything that looks like a URL is reduced to its host.
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
        return AddOutcome(added: target, message: "Added. Set a schedule; nothing is enforced until you do.")
    }

    /// Adds the websites offered beside an app just added, in one save, skipping any already
    /// here. Each lands unconfigured like anything else: nothing is enforced until it has a
    /// schedule. Returns what was added, for the log and the caller's selection.
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
        return added
    }

    /// `addHosts` the other way round: the apps offered beside a website just added.
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
        return added
    }

    // MARK: Importing a setup

    /// What a chosen file would do here. Reads the store rather than the view's copy of it,
    /// and writes nothing: the plan exists to be shown before any of it happens.
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

    /// Applies a whole plan in one save and one enforcement pass.
    ///
    /// `propose`, `setUtility` and the rest each save and re-enforce, which is right for one
    /// edit typed by hand and wrong for twenty arriving together: it would be twenty writes and
    /// twenty passes over every browser tab. So the plan is worked out against `Policy`
    /// directly and applied whole, and the Mac is made to match it once at the end.
    ///
    /// Returns what it did, in the past tense, for the caller to say — the same sentence the
    /// phone says, from `ImportPlan.confirmation`. Every other mutation on this model hands back
    /// a `ProposalResult` that ends up in an alert, and an import is the one worth saying most:
    /// the half of it that waits is invisible until it lands.
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
        return result
    }

    /// What "Apply these windows to other apps" did: how many got the rule now, how many wait
    /// out the delay, and when those land.
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

    /// One rule for several targets in one save: the editor's draft for the app it was written
    /// on (with its name) and for every app chosen in "Apply these windows to other apps".
    /// Each target is judged on its own, so the rule lands now where it tightens and waits out
    /// the delay where it loosens, the same as saving each one by hand.
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
        return outcome
    }

    /// The nickname for the target at `index`. An empty one is stored empty rather than
    /// filled in with the app's own name: `displayName` already falls back to that, and
    /// keeping the two apart is what lets a nickname be taken off again.
    private static func rename(_ index: Int, to nickname: String, in state: inout SharedState) {
        state.config.targets[index].nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Gives `id` the rule, or leaves it alone when it already has it. A tightening lands in
    /// the config; a loosening replaces any rule already pending for that target with one that
    /// waits out the delay. Nothing is saved.
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

    /// Puts `id` in a tier. Moving toward hazard lengthens its delay and lands now; moving
    /// toward essential shortens it, so it queues behind the delay the target has *today* —
    /// which is what keeps "call it essential, then loosen it" from being a way round the wait.
    /// A target with no rule yet is enforcing nothing, so its first tier is free, exactly as
    /// its first rule is. Choosing the tier the target already has cancels a queued change.
    func setUtility(_ level: Utility, for id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let target = current.config.target(id: id) else { return .unchanged }
        let queued = current.pending.contains { change in
            if case .setUtility(let targetID, _) = change.kind { return targetID == id }
            return false
        }
        let plan = Policy.plan(utility: level, for: target, queued: queued)
        guard plan != .unchanged else { return .unchanged }
        // Dropped whatever happens next: choosing the saved tier back is how a queued change
        // is cancelled, and a new one replaces it rather than stacking on it.
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

    /// Wipes every target, rule and pending change, forgets today's counted usage, puts the app
    /// back to its first run, and enforces the empty state, so the Mac matches a fresh install
    /// the way the phone's reset does.
    ///
    /// What it does not touch is the line the phone draws too. There, Screen Time access
    /// survives a reset because the app cannot give it back afterwards and a test pass should
    /// not have to. Here that is the web filter — a system extension that costs two trips
    /// through System Settings to approve — and the per-browser Automation permissions, which
    /// are macOS's to grant and not ours to revoke. Both stay, and the onboarding that follows
    /// reads the filter's live status rather than a stored flag, so it finds the extension in
    /// place and says so. The activity log is kept for the same reason it is on the phone: it
    /// is the record of what just happened, including this.
    ///
    /// The first week is deliberately not started. The phone's reset starts one because a fresh
    /// install there gets one; nothing grants the Mac a week — see `Forgiveness` and the
    /// handoff — so granting one here would make the reset the only way to a Mac state that no
    /// real install can reach.
    ///
    /// Compiled in only when the build asked for the testing tools — see `TestingTools` — so the
    /// shipping build keeps its promise of no unblock button.
    func resetEverything() {
        // Before the work rather than after it, so a login item or an agent that refuses to
        // come off still has something to say when this returns.
        lastError = nil
        SharedStore.reset()
        enforcer.resetUsage()
        AnchorCloud.clear()
        AnchorSync.forgetPhone()
        // Everything `finishOnboarding` switches on, switched back off: a fresh install has
        // neither, and onboarding is about to be run again and will turn them both on. Neither
        // is asked unless it is actually on — the login item here, the watchdog inside
        // `Watchdog.set` — because `unregister()` throws on a job launchd is not holding, and a
        // reset that raised "Could not change the login item" over the onboarding it was
        // opening would be reporting a failure that never happened.
        if SMAppService.mainApp.status == .enabled { setLaunchAtLogin(false) }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        // Only when the login item had nothing to report: one alert stands at a time, and the
        // first thing that refused is the one worth naming.
        if !Watchdog.forget(), lastError == nil { lastError = Self.watchdogRefused }
        watchdogIsOn = Watchdog.isOn
        SharedStore.defaults.removeObject(forKey: Self.onboardedKey)
        isOnboarded = false
        SharedStore.log("reset everything (Debug build)")
        enforce(reason: "reset")
    }
    #endif
}
