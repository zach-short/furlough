import Combine
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import UIKit
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

/// Single source of truth for the UI. Every mutation goes through persisted state and then `enforce()`.
@MainActor
@Observable
final class AppModel {
    /// One model for the app and for the App Intents behind it: an intent can run with no
    /// window on screen, and it has to change the same state the views are watching rather
    /// than a second copy of it. The Mac has done this since it had a menu bar to run from.
    static let shared = AppModel()

    var authorization = AuthorizationCenter.shared.authorizationStatus
    var state = SharedStore.load()
    var lastError: String?
    /// Something to say after an action that had no screen of its own to say it in — an
    /// intent run from Spotlight. The root shows it once and clears it.
    var notice: String?
    var notificationsGranted: Bool?
    let isAppGroupAvailable = SharedStore.isAppGroupAvailable
    private let scanner = TagScanner()
    /// A Weigh Anchor intent waiting for Furlough to reach the foreground; see below.
    @ObservationIgnored private var wantsWeighAnchor = false
    /// Screen Time access stood at the end of an earlier run. FamilyControls reports "not
    /// determined" for a moment after a cold start, so the root trusts this to hold the launch
    /// screen instead of flashing onboarding. Kept in the app's own defaults: a Debug reset
    /// keeps access, so it keeps this too.
    let wasAuthorized = UserDefaults.standard.bool(forKey: AppModel.wasAuthorizedKey)
    private static let wasAuthorizedKey = "furlough.wasAuthorized"
    /// Targets whose "the other half is missing" nudge has been waved away. Beside
    /// `wasAuthorized` in the app's own defaults rather than in `Config`: it records what has
    /// been said, not what is blocked, so it must not be exported with a setup and must not
    /// go through the loosening delay.
    private var companionDismissed = Set(UserDefaults.standard.stringArray(forKey: AppModel.companionDismissedKey) ?? [])
    private static let companionDismissedKey = "furlough.companionDismissed"
    /// The usage step has had its turn. Beside the two above for the same reason: it records
    /// what has been shown, not what is blocked, so it must not travel in an exported setup and
    /// must not wait out a loosening delay.
    private(set) var hasSeenUsageStep = UserDefaults.standard.bool(forKey: AppModel.usageStepKey)
    private static let usageStepKey = "furlough.sawUsageStep"

    var isAuthorized: Bool {
        switch authorization {
        case .approved: true
        case .notDetermined, .denied: false
        default: true // approvedWithDataAccess (iOS 26.4+) and any future approved variants
        }
    }

    /// Whether the usage step is on screen. It sits between Screen Time access and the first
    /// rule, because seeing where a fortnight went is the shortest way from an empty Furlough
    /// to one that is set up — and once there are rules, it has nothing left to say that
    /// Settings cannot say later.
    ///
    /// Stored rather than derived, and only ever turned on by `considerUsageStep`: applying a
    /// suggestion inside the step gives Furlough its first rule, and a condition that read the
    /// targets live would pull the screen out from under the person mid-flow. `finishUsageStep`
    /// is the one way out.
    private(set) var showsUsageStep = false

    /// Turns the step on the first time Furlough has access and nothing to enforce yet.
    private func considerUsageStep() {
        guard !hasSeenUsageStep, isAuthorized, state.config.targets.isEmpty else { return }
        showsUsageStep = true
    }

    /// The step is done with, whether it was worked through or waved away.
    func finishUsageStep() {
        UserDefaults.standard.set(true, forKey: Self.usageStepKey)
        hasSeenUsageStep = true
        showsUsageStep = false
    }

    // MARK: Lifecycle

    func activate() {
        observeChanges()
        observeCloud()
        AnchorCloud.synchronize()
        note(AuthorizationCenter.shared.authorizationStatus)
        reload()
        applyRemoteAnchor(reason: "activate")
        considerUsageStep()
        Task { await refreshNotificationStatus() }
        // Names for anything the shield has not covered yet, where this phone can read them.
        // Off the critical path: it needs a Screen Time query, and nothing waits on the answer.
        Task { await nameUnnamedTargets() }
        // Before the authorization guard: a tag scan is how the anchor is lifted, and it has
        // to work even on a launch where FamilyControls has not answered yet.
        weighAnchorIfInFront()
        guard isAuthorized else { return }
        enforce(reason: "app active")
    }

    /// Listens for a write from another process — a Control Center drop, the monitor's
    /// schedule firing or lifting — and catches up, so the screen does not say Free over a
    /// phone that is anchored. A Darwin notification carries no payload and reaches every
    /// process; the observer is registered once, and its callback can capture nothing, so it
    /// goes through `shared`.
    @ObservationIgnored private var observesChanges = false

    private func observeChanges() {
        guard !observesChanges else { return }
        observesChanges = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in Task { @MainActor in AppModel.shared.changedElsewhere() } },
            SharedStore.changeNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Another process wrote the store. Reload, and if that changed anything, enforce: a drop
    /// from the widget has applied its shields already, but only the app registers
    /// DeviceActivity, and the monitor's own writes are worth a fresh registration too. The
    /// app's own writes come back through here as well and find nothing new.
    func changedElsewhere() {
        let before = state
        reload()
        guard state != before, isAuthorized else { return }
        enforce(reason: "changed elsewhere")
    }

    /// Follows FamilyControls' own updates. After a cold start the first read says "not
    /// determined" and the real answer arrives here a moment later; if the app went active in
    /// between, this enforces now, as `activate()` could not.
    func observeAuthorization() async {
        for await status in AuthorizationCenter.shared.$authorizationStatus.values {
            let hadAccess = isAuthorized
            note(status)
            if isAuthorized, !hadAccess { enforce(reason: "authorized") }
        }
    }

    /// Records the status, and a definite answer for the next launch (see `wasAuthorized`).
    private func note(_ status: AuthorizationStatus) {
        authorization = status
        if isAuthorized {
            UserDefaults.standard.set(true, forKey: AppModel.wasAuthorizedKey)
        } else if status == .denied {
            UserDefaults.standard.set(false, forKey: AppModel.wasAuthorizedKey)
        }
        considerUsageStep()
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access failed: \(error.localizedDescription)"
        }
        note(AuthorizationCenter.shared.authorizationStatus)
        if isAuthorized {
            startTrialIfNeeded()
            enforce(reason: "authorized")
        }
    }

    /// Begins the first week the first time Screen Time access is granted, and never again on
    /// this install — `Forgiveness.startTrial` is what refuses the second time. This is the
    /// only moment it can start: before access there is nothing to be forgiven for, and after
    /// it every path back here goes through Settings, which is the way out of Furlough and
    /// must not also be the way to a fresh week.
    private func startTrialIfNeeded() {
        var current = SharedStore.load()
        guard Forgiveness.startTrial(&current.config, now: current.now) else { return }
        SharedStore.save(current)
        SharedStore.log("first week started; loosenings wait \(Furlough.trialDelayHours) h until it ends")
    }

    /// The edit on `id` that is still takeable back, or nil. Read on Furlough's own clock, so
    /// a device clock moved back does not reopen a window that has closed.
    func undo(for id: UUID) -> RuleUndo? {
        guard let target = state.config.target(id: id) else { return nil }
        return Forgiveness.undo(for: target, at: clock.now)
    }

    /// Puts `id` back to the rule it had before the last edit. True when it happened.
    ///
    /// Instant, and not an unblock: the rule it restores is the one that was in force a quarter
    /// of an hour ago, so nothing comes open that was not open then. A target whose previous
    /// rule was none goes back to unconfigured, which is where it stood before it was touched.
    @discardableResult
    func undoRule(for id: UUID) -> Bool {
        var current = SharedStore.load()
        let name = current.config.target(id: id)?.displayName ?? "a target"
        guard Forgiveness.revert(targetID: id, in: &current, now: current.now) else { return false }
        SharedStore.save(current)
        SharedStore.log("undid the last rule change for \(name)")
        enforce(reason: "undo")
        return true
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

    func reload() {
        state = SharedStore.load()
    }

    /// Furlough's own time and how far the device's clock is from it. Every view that shows a
    /// countdown reads it through here, so a device clock moved forward changes nothing but the
    /// banner on the Pending screen.
    var clock: Clock.Reading { state.clock() }

    /// Re-derives everything from persisted state: folds in due pending changes, re-registers
    /// DeviceActivity schedules, and re-applies shields. Safe to call at any time.
    func enforce(reason: String) {
        var current = SharedStore.load()
        let clock = current.clock()
        if !clock.isTrusted {
            let direction = clock.drift > 0 ? "ahead" : "behind"
            SharedStore.log("device clock is \(Clock.describe(clock.drift)) \(direction); running on Furlough's own time")
        }
        if Policy.applyDuePending(&current, now: clock.now) {
            SharedStore.log("applied due pending changes (\(reason))")
        }
        // Folded before registration, so a timed anchor whose time has passed does not get its
        // wake registered again; `Policy` has read it as released since the moment it passed.
        if Policy.liftExpiredAnchor(&current.config, now: clock.now) {
            SharedStore.log("a timed anchor's time had passed; lifted it (\(reason))")
        }
        do {
            try Monitoring.register(state: current)
            current.runtime.lastRegistration = .now
            current.runtime.registrationError = nil
        } catch {
            current.runtime.registrationError = error.localizedDescription
            SharedStore.log("registration failed: \(error.localizedDescription)")
            lastError = "Could not schedule monitoring: \(error.localizedDescription)"
        }
        SharedStore.save(current)
        ShieldReconciler.reconcile(reason: reason)
        // The warning before a loosening lands is the last chance to cancel it, so it is
        // rescheduled from the saved state on every enforce rather than only when queued.
        PendingNotifications.sync(state: current, now: clock.now, drift: clock.drift)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: Furlough.anchorControlKind)
        reload()
        LiveActivityManager.sync(state: state)
    }

    // MARK: Picker

    var pickerSelection: FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        // Every door of every target, so the picker shows what Furlough actually covers rather
        // than only the face of each row.
        for kind in state.config.targets.flatMap(\.kinds) {
            switch kind {
            case .application(let token): selection.applicationTokens.insert(token)
            case .webDomain(let token): selection.webDomainTokens.insert(token)
            case .category(let token): selection.categoryTokens.insert(token)
            // A typed host has no token, so there is nothing to preselect. `applyPicker`
            // leaves those targets alone for the same reason.
            case .host: break
            }
        }
        return selection
    }

    struct PickerOutcome: Equatable {
        var added = 0
        var removalsScheduled = 0
        var effectiveAt: Date?

        var message: String {
            var lines: [String] = []
            if added > 0 {
                lines.append("\(added) added. Set a schedule for each one; nothing is enforced until you do.")
            }
            if removalsScheduled > 0, let effectiveAt {
                lines.append("\(removalsScheduled) removal(s) take effect by \(effectiveAt.formatted(date: .abbreviated, time: .shortened)). Cancel them from the pending list if you change your mind.")
            }
            return lines.joined(separator: "\n\n")
        }
    }

    func applyPicker(_ selection: FamilyActivitySelection) -> PickerOutcome {
        var current = SharedStore.load()
        var outcome = PickerOutcome()
        // Every door, not every face: a token already covered as the linked half of some other
        // row must not be added again as a row of its own.
        let existing = Set(current.config.targets.flatMap(\.kinds))

        for token in selection.applicationTokens where !existing.contains(.application(token)) {
            current.config.targets.append(Target(kind: .application(token)))
            outcome.added += 1
        }
        for token in selection.webDomainTokens where !existing.contains(.webDomain(token)) {
            current.config.targets.append(Target(kind: .webDomain(token)))
            outcome.added += 1
        }
        for token in selection.categoryTokens where !existing.contains(.category(token)) {
            current.config.targets.append(Target(kind: .category(token), rule: .alwaysBlocked))
            outcome.added += 1
        }

        var selected = Set<TargetKind>()
        selected.formUnion(selection.applicationTokens.map(TargetKind.application))
        selected.formUnion(selection.webDomainTokens.map(TargetKind.webDomain))
        selected.formUnion(selection.categoryTokens.map(TargetKind.category))

        // Each removal waits out its own target's tier, so unpicking Messages and TikTok
        // together does not make Messages wait for TikTok.
        //
        // Which targets the picker may remove at all is `Policy.picker(removes:selected:)`, which
        // is pure and tested: a typed host is in no selection, and a linked pair is not broken by
        // unpicking one half of it. The editor's "Also blocks" card is the one place a half comes
        // off, because that is a loosening and has to wait out the delay.
        for target in current.config.targets where Policy.picker(removes: target, selected: selected) {
            if target.rule == nil {
                current.config.targets.removeAll { $0.id == target.id }
                continue
            }
            let alreadyPending = current.pending.contains { $0.kind == .removeTarget(targetID: target.id) }
            guard !alreadyPending else { continue }
            let effectiveAt = current.now.addingTimeInterval(current.config.delay(for: target))
            Record.queue(PendingChange(kind: .removeTarget(targetID: target.id), effectiveAt: effectiveAt), in: &current, now: current.now)
            outcome.removalsScheduled += 1
            outcome.effectiveAt = max(effectiveAt, outcome.effectiveAt ?? effectiveAt)
        }

        SharedStore.save(current)
        SharedStore.log("picker: added \(outcome.added), removals scheduled \(outcome.removalsScheduled)")
        enforce(reason: "picker")
        return outcome
    }

    /// How long after adding an app the usage flow may still take it straight back: long enough
    /// to work through a screenful of suggestions, far short of living under one.
    static let undoWindow: TimeInterval = 30 * 60

    /// Takes back an app the usage flow has just added, and the rule it wrote on it. Not a
    /// loosening waiting out the delay: the delay is there so a rule you have been living under
    /// cannot be dropped on a whim, and this one was written and taken back inside one screen,
    /// minutes old, before it ever shielded anything — the same judgement `applyPicker` makes
    /// about a target that has no rule yet. Refuses anything older than `undoWindow`, which is
    /// why the flow offers Undo only on what it added itself. False when nothing was undone.
    func undoFreshTarget(_ id: UUID) -> Bool {
        var current = SharedStore.load()
        guard let target = current.config.targets.first(where: { $0.id == id }),
              current.now.timeIntervalSince(target.addedAt) <= Self.undoWindow
        else { return false }
        current.config.targets.removeAll { $0.id == id }
        current.pending.removeAll { $0.targetID == id }
        SharedStore.save(current)
        SharedStore.log("usage flow took back \(target.displayName), added \(Int(current.now.timeIntervalSince(target.addedAt))) s ago")
        enforce(reason: "usage undo")
        return true
    }

    // MARK: The app half, beside a website

    /// What adding the companion app did, in the words the editor says back.
    enum CompanionAddOutcome: Equatable {
        case none
        /// How many were added, and whether they inherited the website's hours.
        case added(count: Int, inheritedRule: Bool)

        var message: String? {
            guard case .added(let count, let inherited) = self else { return nil }
            // One pick is the pair itself and shares the row. More than one means the rest are
            // separate things that were picked at the same time, and they get rows of their own.
            let extras = count > 1 ? " The other \(count - 1) got \(count == 2 ? "a row" : "rows") of \(count == 2 ? "its" : "their") own, on the same hours." : ""
            return inherited
                ? "One row now, on one schedule and one budget.\(extras)"
                : "One row now. Give it hours and both halves follow; nothing is blocked until you do.\(extras)"
        }
    }

    /// Puts the app half onto the website's own row, so the two are one thing.
    ///
    /// Not `applyPicker`: that one reads a selection as the whole truth and schedules a removal
    /// for every target absent from it, which is right for the + button and catastrophic here,
    /// where the picker was deliberately opened empty to ask one question. Nothing is removed.
    ///
    /// Linking rather than appending, since 2026-09-08: one habit is one row. The app becomes the
    /// **face** of that row and the site moves in beside it, because the app is the half with
    /// Apple's own artwork and name. The rule, the tier, the nickname and the removal delay were
    /// already the row's and stay the row's, so nothing is copied and nothing can drift.
    ///
    /// A tightening, and instant: more is blocked than a moment ago. Taking a half back off is
    /// the loosening, and `unlink` queues that behind the delay.
    ///
    /// One pick is the app the nudge named, so it is named from the companions table at once —
    /// the widget, the notifications and the Live Activity can say "YouTube" rather than "This
    /// app" before the shield has ever covered it. Several picks means the name fits none of
    /// them, so the extras become rows of their own wearing the same rule, exactly as before.
    @discardableResult
    func addCompanionApps(_ selection: FamilyActivitySelection, for request: AddRequest.Companion) -> CompanionAddOutcome {
        var current = SharedStore.load()
        let existing = Set(current.config.targets.flatMap(\.kinds))
        let tokens = selection.applicationTokens.filter { !existing.contains(.application($0)) }
        guard !tokens.isEmpty,
              let index = current.config.targets.firstIndex(where: { $0.id == request.targetID })
        else { return .none }
        let inherited = current.config.targets[index].rule

        // The first pick joins the row and becomes its face; the site it was offered beside moves
        // in beside it. `also` keeps the order it was built in, so the face comes off the front.
        let site = current.config.targets[index].kinds
        let face = tokens.first!
        current.config.targets[index].kind = .application(face)
        current.config.targets[index].also = site
        if !request.title.isEmpty, tokens.count == 1 {
            current.config.targets[index].systemName = request.title
        }
        // Anything else picked is not this thing, so it gets its own row rather than being folded
        // into a pair it does not belong to. It still wears the rule, as it did before linking.
        for token in tokens.dropFirst() {
            current.config.targets.append(Target(kind: .application(token), rule: inherited))
        }
        SharedStore.save(current)
        SharedStore.log("linked an app onto \(current.config.targets[index].displayName), plus \(tokens.count - 1) other(s)")
        enforce(reason: "add companion app")
        return .added(count: tokens.count, inheritedRule: inherited != nil)
    }

    // MARK: Sites by name

    /// What adding a typed host did, in the words the sheet says back.
    enum AddHostOutcome: Equatable {
        case added(String)
        case already(String)
        case unreadable
    }

    /// Adds a website by name, the way the Mac has always done it.
    ///
    /// No token and no picker: `WebContentSettings.blockedByFilter` takes a plain string, so
    /// the host is the whole target. Nothing is enforced until it has a rule, as ever. A host
    /// that is already managed — or a subdomain of one, which `Config.target(host:)` matches —
    /// is not added twice; the sheet says which one it landed on.
    @discardableResult
    func addHost(_ raw: String) -> AddHostOutcome {
        guard let host = Hosts.normalize(raw) else { return .unreadable }
        if let existing = SharedStore.load().config.target(host: host) { return .already(existing.displayName) }
        addHosts([host])
        return .added(host)
    }

    /// Several at once, in one save and one enforcement pass: the companion nudge offers every
    /// site an app is also at, and adding four of them should not be four rounds of the whole
    /// reconcile. Mirrors `MacModel.addHosts`, which the Mac's companion sheet has always used.
    @discardableResult
    func addHosts(_ raw: [String]) -> [Target] {
        var current = SharedStore.load()
        var added: [Target] = []
        for one in raw {
            guard let host = Hosts.normalize(one), current.config.target(host: host) == nil else { continue }
            let target = Target(kind: .host(host))
            current.config.targets.append(target)
            added.append(target)
        }
        guard !added.isEmpty else { return [] }
        SharedStore.save(current)
        SharedStore.log("added site(s) by name: \(added.map(\.host).joined(separator: ", "))")
        enforce(reason: "add sites by name")
        return added
    }

    // MARK: Importing a setup

    /// Opens a chosen file, or says why it will not be read. Writes nothing.
    ///
    /// The phone stops here rather than going straight to a plan: a Screen Time target is an
    /// opaque token scoped to this device and this install, so the file cannot say which app
    /// each of its rules belonged to and the person has to. `ImportSetupView` asks, and hands
    /// the answers back to `plan`.
    func openSetup(fileAt url: URL) -> Result<ConfigExport, ConfigImport.Refusal> {
        do {
            return .success(try ConfigImport.read(contentsOf: url))
        } catch {
            SharedStore.log("import refused: \(error)")
            return .failure(error)
        }
    }

    func plan(_ export: ConfigExport, matches: [ImportMatch]) -> ImportPlan {
        let current = SharedStore.load()
        var plan = ConfigImport.plan(export, matches: matches, state: current, now: current.now)
        // iOS's ceiling on monitored activities, asked before the button rather than after the
        // save. `ConfigImport` cannot ask it: the limit is DeviceActivity's and the Mac has no
        // such thing, so the platform that has the ceiling is the one that counts against it.
        plan.limitReason = ActivityLimit.reason(applying: plan, in: current)
        return plan
    }

    /// Applies a whole plan in one save and one enforcement pass.
    ///
    /// `propose`, `setUtility` and the rest each save and then re-register every DeviceActivity
    /// schedule, which is right for one edit typed by hand and wrong for twenty arriving
    /// together. The targets a file adds are appended by the plan rather than through
    /// `applyPicker`: that method reads a selection as the whole truth and schedules a removal
    /// for everything absent from it, which is exactly wrong for a file that only ever adds.
    ///
    /// Returns what it did, in the past tense, for the caller to say. Every other mutation here
    /// hands back a `ProposalResult` and every screen puts it in an alert; an import that
    /// silently closed the sheet would be the one change in the app that says nothing, and it is
    /// the largest one — see `ImportPlan.confirmation`.
    func applyImport(_ plan: ImportPlan) -> String {
        SharedStore.mutate { state in
            let now = state.now
            ConfigImport.apply(plan, to: &state, now: now)
        }
        SharedStore.log("imported a setup: \(plan.added.count) new, \(plan.immediate.count) now, \(plan.queued.count) queued, \(plan.skipped.count) not used")
        enforce(reason: "import")
        return plan.confirmation
    }

    // MARK: The other half

    /// What to offer beside `target`, or nil when there is nothing to say.
    ///
    /// A picked target cannot be offered anything as it is added: a Screen Time token is
    /// opaque. The shield learns the name the first time it covers something, and from that
    /// name `Companions` still answers — so for those the offer arrives on the second look
    /// rather than the first, which is the best the phone can do. Nil once the other half is
    /// in, once the nudge has been waved away, and for anything the table does not know.
    ///
    /// A typed host is the exception, and the reason this reads the way it does. It was
    /// written down rather than minted, so it carries its name from the moment it is added and
    /// needs no learned one: its nudge fires on the first look, the way the Mac's sheet does.
    ///
    /// "Already in" can only be judged by the names Furlough knows, so a picked half that has
    /// never been blocked is invisible here and can be offered once. Dismissing it settles
    /// that for good, which is why the nudge is dismissible rather than merely closable.
    func companion(for target: Target) -> Companions.Half? {
        guard !companionDismissed.contains(target.id.uuidString) else { return nil }
        // A target that already covers both halves has nothing left to be offered, and this is
        // the cheapest way to know it: a linked row's site half may be a token whose domain
        // Furlough was never told, so asking "does it cover a site?" beats asking "which site?"
        guard !(target.coversApp && target.coversSite) else { return nil }
        switch target.kind {
        case .application:
            guard let name = learnedName(of: target) else { return nil }
            let hosts = Companions.missingHosts(forAppNamed: name, knownHosts: learnedNames(ofHosts: true))
            return hosts.isEmpty ? nil : .sites(hosts)
        case .webDomain:
            // A website target's learned name is its domain, so the lookup goes the other way.
            guard let name = learnedName(of: target) else { return nil }
            return Companions.missingApp(forHost: name, knownAppNames: learnedNames(ofHosts: false)).map(Companions.Half.app)
        case .category:
            return nil
        case .host(let host):
            return Companions.missingApp(forHost: host, knownAppNames: learnedNames(ofHosts: false)).map(Companions.Half.app)
        }
    }

    // MARK: Linking the two halves

    /// What linking did, in the words the editor says back.
    enum LinkOutcome: Equatable {
        case none
        /// `name` is the row the halves now live on, and `added` what joined it.
        case linked(name: String, added: [String])
        /// The two were already separate rows and have been made one.
        case merged(name: String, gone: String)

        var message: String? {
            switch self {
            case .none:
                nil
            case .linked(let name, let added):
                "\(UtilityText.list(added)) \(added.count == 1 ? "is" : "are") part of \(name) now. One row, one schedule, one budget."
            case .merged(let name, let gone):
                "\(gone) is part of \(name) now. Its own row is gone, and the two share one schedule and one budget."
            }
        }
    }

    /// Adds sites to a target as linked halves rather than as rows of their own.
    ///
    /// A tightening, and applied at once: more is blocked than a moment ago, and the pair being
    /// shut together from the moment it is offered is the whole point. Removing a half is the
    /// loosening, and that waits — see `unlink`.
    @discardableResult
    func linkHosts(_ raw: [String], to id: UUID) -> LinkOutcome {
        var current = SharedStore.load()
        guard let index = current.config.targets.firstIndex(where: { $0.id == id }) else { return .none }
        var added: [String] = []
        for one in raw {
            guard let host = Hosts.normalize(one), current.config.target(host: host) == nil else { continue }
            current.config.targets[index].also = (current.config.targets[index].also ?? []) + [.host(host)]
            added.append(host)
        }
        guard !added.isEmpty else { return .none }
        let name = current.config.targets[index].displayName
        SharedStore.save(current)
        SharedStore.log("linked \(added.joined(separator: ", ")) to \(name)")
        enforce(reason: "link site")
        return .linked(name: name, added: added)
    }

    /// Folds `absorbed` into `keeping` as a linked half, and takes its row away.
    ///
    /// This is the retroactive case: YouTube and youtube.com were added separately, before there
    /// was any such thing as linking. Merging is a **tightening** — two 45-minute budgets become
    /// one 45 across both halves, and the tighter of the two schedules wins — so it lands now,
    /// with no delay. The face is the app wherever one of the two is an app: it is the half with
    /// Apple's own artwork and name.
    @discardableResult
    func merge(_ absorbed: UUID, into keeping: UUID) -> LinkOutcome {
        var current = SharedStore.load()
        guard absorbed != keeping,
              let a = current.config.target(id: keeping),
              let b = current.config.target(id: absorbed),
              let index = current.config.targets.firstIndex(where: { $0.id == keeping })
        else { return .none }
        let gone = b.displayName
        // The app is the face. When the row being kept is the website and the one being absorbed
        // is the app, the halves swap places so the row shows the app.
        let faceIsApp = a.coversApp || !b.coversApp
        current.config.targets[index].kind = faceIsApp ? a.kind : b.kind
        let face = current.config.targets[index].kind
        // Order kept and duplicates dropped: the two rows should never have shared a door — the
        // lookups refuse to add one twice — but a half listed twice would show twice and unlink
        // half-way, and the guard costs one line.
        var seen: Set<TargetKind> = [face]
        let others = (faceIsApp ? (a.also ?? []) + b.kinds : (b.also ?? []) + a.kinds)
            .filter { seen.insert($0).inserted }
        current.config.targets[index].also = others.isEmpty ? nil : others
        // The tighter of the two rules, so a merge can only ever take away. A target with no rule
        // enforces nothing, so the one that has a rule wins outright.
        current.config.targets[index].rule = Self.budgeted(
            Self.tighter(a.rule, b.rule),
            counted: current.config.targets[index].isCounted
        )
        // The name and the tier come from the face, and the face may just have changed.
        if !faceIsApp {
            current.config.targets[index].systemName = b.systemName
            if current.config.targets[index].nickname.isEmpty { current.config.targets[index].nickname = b.nickname }
        }
        // The more cautious tier of the two: a longer wait is the safe direction, and a merge
        // must not be a way to shorten one.
        current.config.targets[index].utilityLevel = Self.slower(a.utilityLevel, b.utilityLevel)
        current.config.targets.removeAll { $0.id == absorbed }
        // Anything queued for the row that is going would land on a target that no longer exists.
        current.pending.removeAll { $0.targetID == absorbed }
        let name = current.config.targets[index].displayName
        SharedStore.save(current)
        SharedStore.log("merged \(gone) into \(name)")
        enforce(reason: "merge halves")
        return .merged(name: name, gone: gone)
    }

    /// The rule that allows no more than the other. Nil means "no rule yet", which enforces
    /// nothing, so any real rule beats it.
    private static func tighter(_ a: Rule?, _ b: Rule?) -> Rule? {
        guard let a else { return b }
        guard let b else { return a }
        return a.isTighterOrEqual(to: b) ? a : b
    }

    /// The surviving rule, with the no-limit budget replaced where a limit now means something.
    ///
    /// A whole day of budget is not a budget. It is the sentinel `RuleEditorView.savedBudget`
    /// forces onto a target nothing counts, precisely because a limit there would be a number no
    /// part of iOS would enforce. Merge a site like that into an app and the pair *is* counted, so
    /// the sentinel stops being true — and left alone it would show as "1440 MIN" beside a slider
    /// pinned at its maximum. The default takes its place, which is what any new rule gets, and it
    /// is a tightening, so it lands with the rest of the merge.
    private static func budgeted(_ rule: Rule?, counted: Bool) -> Rule? {
        // No real limit on any day of the week, however the week is written: seven days of the
        // sentinel is the same sentinel, and the default replaces the lot of them.
        guard counted, var rule, (1...7).allSatisfy({ rule.limit(on: $0) == nil }), rule.isEverAllowed
        else { return rule }
        rule.dailyBudgetMinutes = Furlough.defaultBudgetMinutes
        rule.budgetByWeekday = nil
        return rule
    }

    /// The tier that waits longest, so merging can only lengthen a delay. Nil on both sides stays
    /// nil: nobody has said, and a merge is not the moment to decide for them.
    private static func slower(_ a: Utility?, _ b: Utility?) -> Utility? {
        guard let a else { return b }
        guard let b else { return a }
        return a.delayMultiplier >= b.delayMultiplier ? a : b
    }

    /// The rows that are the other half of `target` and could be folded into it.
    ///
    /// Only ever the halves of one thing: an app row beside the site it is also at, or the other
    /// way round. Judged by the same table and the same learned names the nudge uses, so a row
    /// the shield has never covered is invisible here, exactly as it is there.
    func mergeable(with target: Target) -> [Target] {
        guard !(target.coversApp && target.coversSite) else { return [] }
        guard let pair = pairOf(target) else { return [] }
        return state.config.targets.filter { other in
            guard other.id != target.id, !(other.coversApp && other.coversSite) else { return false }
            // One of the two must bring the half the other lacks.
            guard (target.coversApp && other.coversSite) || (target.coversSite && other.coversApp) else { return false }
            return pairOf(other) == pair
        }
    }

    /// Which thing in the companions table this row is, by whatever identity it has.
    private func pairOf(_ target: Target) -> Companions.Pair? {
        for host in target.hosts {
            if let pair = Companions.pair(forHost: host) { return pair }
        }
        guard let name = learnedName(of: target) ?? (target.nickname.isEmpty ? nil : target.nickname) else { return nil }
        return Companions.pair(forHost: name) ?? Companions.pair(forBundleID: "", name: name)
    }

    /// Takes a half back off a target. A **loosening** — something blocked a moment ago stops
    /// being — so it waits out the delay like every other loosening, and the pending list can
    /// cancel it. Returns nil when there is nothing to take off.
    func unlink(_ kind: TargetKind, from id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let target = current.config.target(id: id), target.covers(kind), target.kind != kind else { return .unchanged }
        // Queued as a `PendingKind` like every other loosening, so it warns an hour ahead, reads
        // as a delta on the pending card and cancels from the same list — rather than getting a
        // mechanism of its own that all three would have to learn about.
        let already = current.pending.contains { $0.kind == .unlink(targetID: id, kind: kind) }
        guard !already else { return .unchanged }
        let effectiveAt = current.now.addingTimeInterval(current.config.delay(for: target))
        Record.queue(PendingChange(kind: .unlink(targetID: id, kind: kind), effectiveAt: effectiveAt), in: &current, now: current.now)
        SharedStore.save(current)
        SharedStore.log("queued unlinking a half of \(target.displayName)")
        enforce(reason: "unlink")
        return .scheduled(effectiveAt)
    }

    /// The name Screen Time taught for a picked target, or nil while it has never been blocked.
    private func learnedName(of target: Target) -> String? {
        guard let name = target.systemName, !name.isEmpty else { return nil }
        return name
    }

    // MARK: Naming what the shield has not covered yet

    /// Gives a name to every target that has none, from the tables rather than from the shield.
    ///
    /// A Screen Time token is opaque, so until the shield first covers something the only thing
    /// Furlough can call it is "This app" — which is what put "This app and This app is worth
    /// having around" on the Anchor screen. With data access the token can be matched against
    /// what is installed, which yields a bundle identifier, and `Companions` and `AppUtility`
    /// both key on those. So an app in either table gets its real name before it is ever blocked.
    ///
    /// Two limits, both deliberate and neither hidden. It needs `FamilyActivityData`, which Apple
    /// gives a development build in any region and a customer only in the EU, so most installs
    /// fall through to the shield exactly as before — Zach chose this route on 2026-09-08 knowing
    /// that. And it can only name what the tables know: something in neither is still "This app"
    /// until the shield says otherwise.
    ///
    /// Written to the learned-names key rather than into the config, so it travels the same road
    /// the shield's own names travel: no rule changes, nothing queues, an export does not carry
    /// it, and a name Screen Time teaches later still wins on the next load.
    func nameUnnamedTargets() async {
        guard #available(iOS 26.4, *), UsageReader.hasDataAccess else { return }
        let unnamed = state.config.targets.filter { learnedName(of: $0) == nil }
        guard !unnamed.isEmpty else { return }
        let identities: [TargetKind: String]
        do {
            identities = try await UsageReader.identities()
        } catch {
            // Screen Time simply did not answer. Nothing is worse off than before, and the shield
            // is still coming; there is nothing here worth telling anyone about.
            return
        }
        var learned = 0
        for target in unnamed {
            guard let key = identities[target.kind], let name = Self.nameFromTables(key) else { continue }
            if SharedStore.learnName(name, for: target.id) { learned += 1 }
        }
        guard learned > 0 else { return }
        SharedStore.log("named \(learned) target(s) from the tables")
        reload()
    }

    /// What the tables call the thing behind a usage key: a bundle identifier, or "web:" and a
    /// domain. `Companions` first, because its names are the ones written to be shown; then
    /// `AppUtility`, which knows many more apps than are also websites. A domain is its own name.
    static func nameFromTables(_ key: String) -> String? {
        if key.hasPrefix("web:") { return String(key.dropFirst(4)) }
        if let pair = Companions.pair(forBundleID: key, name: "") { return pair.title }
        return AppUtility.name(forBundleID: key)
    }

    /// Said once is enough: a nudge that comes back is a nag.
    func dismissCompanion(for id: UUID) {
        companionDismissed.insert(id.uuidString)
        UserDefaults.standard.set(Array(companionDismissed), forKey: AppModel.companionDismissedKey)
    }

    /// The names the shield has taught, from one side of the list or the other.
    private func learnedNames(ofHosts: Bool) -> [String] {
        state.config.targets.flatMap { target -> [String] in
            target.kinds.compactMap { kind in
                switch kind {
                // `systemName` belongs to the face, so it only names this door when this door
                // *is* the face. A linked website token has no name of its own; `companion(for:)`
                // does not need one, because a target covering both halves is asked nothing.
                case .webDomain: ofHosts && kind == target.kind ? target.systemName : nil
                case .application: !ofHosts && kind == target.kind ? target.systemName : nil
                case .category: nil
                // A typed host is its own name, learned or not, so it counts as a known site
                // whether it is the face of its row or a half linked onto one.
                case .host(let host): ofHosts ? host : nil
                }
            }
        }
    }

    // MARK: Rules

    func classify(rule: Rule, for id: UUID) -> ChangeClass {
        Policy.classify(newRule: rule, against: state.config.target(id: id))
    }

    func propose(rule: Rule, nickname: String, for id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let index = current.config.targets.firstIndex(where: { $0.id == id }) else { return .unchanged }
        current.config.targets[index].nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = Self.assign(rule, to: id, in: &current)
        SharedStore.save(current)
        SharedStore.log("rule edit for \(id): \(result)")
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
    /// on (with its nickname) and for every app chosen in "Apply these windows to other apps".
    /// Each target is judged on its own, so the rule lands now where it tightens and waits out
    /// the delay where it loosens, the same as saving each one by hand.
    func apply(rule: Rule, nickname: String, for id: UUID, andTo others: [UUID]) -> ApplyOutcome {
        var current = SharedStore.load()
        if let index = current.config.targets.firstIndex(where: { $0.id == id }) {
            current.config.targets[index].nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
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
            // What it replaced, so the next quarter of an hour can put it back. Only here,
            // where a rule lands *now*: a loosening arriving after its delay needs no undo,
            // because undoing a loosening is a tightening and those are instant anyway.
            Forgiveness.record(previous: target.rule, on: &state.config.targets[index], at: state.now)
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

    // MARK: Anchor

    enum AnchorOutcome: Equatable {
        case anchored, released, paired(PairedTag), wrongTag, cancelled, failed(String)
    }

    var anchorSelection: FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        for kind in state.config.anchor.kinds {
            switch kind {
            case .application(let token): selection.applicationTokens.insert(token)
            case .webDomain(let token): selection.webDomainTokens.insert(token)
            case .category(let token): selection.categoryTokens.insert(token)
            case .host: break
            }
        }
        return selection
    }

    /// Replaces the anchor's list: what it holds, or under the everything-except scope what it
    /// lets through. Refused while anchored, so nothing loosens under a lock.
    func setAnchorSelection(_ selection: FamilyActivitySelection) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored else { return }
        var kinds: [TargetKind] = []
        kinds += selection.applicationTokens.map(TargetKind.application)
        kinds += selection.webDomainTokens.map(TargetKind.webDomain)
        // A category can be held, but it cannot be let through: `.all(except:)` excepts app
        // and site tokens and nothing else. The picker expands a picked category into its apps
        // (`includeEntireCategory`), so those are on the allowlist as apps, and the category
        // token itself would only sit in the list unread. Dropped here rather than ignored
        // downstream, so the list a person sees is the list that is enforced.
        if !current.config.anchor.anchorsEverything {
            kinds += selection.categoryTokens.map(TargetKind.category)
        }
        // The picker speaks only about tokens, so it may only replace tokens. Anything the
        // anchor holds by name is kept: a selection that has never heard of a typed host is
        // not evidence that the host should be let go, and `Policy.decide` shields `.host`
        // kinds in the anchor exactly like the rest.
        kinds += current.config.anchor.kinds.filter(\.isHost)
        guard kinds != current.config.anchor.kinds else { return }
        current.config.anchor.kinds = kinds
        SharedStore.save(current)
        SharedStore.log("anchor: now \(current.config.anchor.anchorsEverything ? "lets through" : "holds") \(kinds.count) item(s)")
        enforce(reason: "anchor edit")
    }

    /// Takes what `targetIDs` cover into the anchor, on top of what it holds. This is the
    /// Anchor screen's first offer — the targets Furlough already blocks, chosen from
    /// `Config.anchorCandidates` — landing; Apple's picker is the other way in, through
    /// `setAnchorSelection`. Refused while anchored, like every other change to the list, and
    /// refused under the everything-except scope, where "what you already block" is already
    /// held and taking it in would mean letting it through.
    func addToAnchor(targetIDs: [UUID]) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored, !current.config.anchor.anchorsEverything else { return }
        let chosen = current.config.targets.filter { targetIDs.contains($0.id) }
        guard current.config.anchor.add(chosen) else { return }
        SharedStore.save(current)
        SharedStore.log("anchor: took in \(chosen.count) of the rules; now holds \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor edit")
    }

    /// Chooses how far the anchor reaches: its list, or the whole phone except its list.
    /// Refused while anchored, like every other change to it.
    ///
    /// The list does not survive the switch, because it cannot: under one scope it is what
    /// goes and under the other it is what stays, so a list carried across would turn TikTok
    /// into the one app left open. Widening to the whole phone starts the allowlist from every
    /// target tiered Essential (`Config.essentialKinds`); narrowing back starts the list empty,
    /// where the rules sheet offers everything already blocked again in one tap. The Anchor
    /// screen says both before asking.
    func setAnchorScope(_ scope: AnchorProfile.Scope) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored, current.config.anchor.scope != scope else { return }
        current.config.anchor.scope = scope
        current.config.anchor.kinds = scope == .everythingExcept ? current.config.essentialKinds : []
        SharedStore.save(current)
        SharedStore.log("anchor: scope is now \(scope.rawValue); the list starts with \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor scope")
    }

    /// Anchoring is tightening, so it needs no tag. It does need a paired tag to exist, or there
    /// would be no way back. `until` makes it a timed drop: it lifts by itself then, or sooner
    /// with the tag. The drop itself is `AnchorDrop`, shared with the intent that runs in the
    /// widget extension; the app adds only what it alone can do, which is register the wake at
    /// `until` through `enforce`.
    func anchor(until: Date? = nil) -> AnchorOutcome {
        switch AnchorDrop.drop(until: until, reason: "anchor") {
        case .refused(.alreadyAnchored):
            reload()
            return .anchored
        case .refused(let why):
            return .failed(why.message)
        case .anchored:
            enforce(reason: "anchor")
            return .anchored
        }
    }

    /// Replaces the anchor's drop times. Refused while anchored, like every other change to it.
    /// More drops or longer holds land at once; fewer or shorter ones queue behind the delay the
    /// anchor's contents earn (`Config.anchorDelayHours`) as `PendingKind.setAnchorSchedules`,
    /// so the pending list shows and cancels them like any other loosening. Saving the schedule
    /// the anchor already has drops any queued change to it, the way choosing a saved tier back
    /// cancels a queued tier.
    func setAnchorSchedules(_ schedules: [AnchorSchedule]) -> ProposalResult {
        var current = SharedStore.load()
        let now = current.now
        Policy.liftExpiredAnchor(&current.config, now: now)
        guard !current.config.anchor.isAnchored else { return .unchanged }
        let hadQueued = current.pending.contains { if case .setAnchorSchedules = $0.kind { return true }; return false }
        current.pending.removeAll { if case .setAnchorSchedules = $0.kind { return true }; return false }
        guard schedules != current.config.anchor.schedules else {
            guard hadQueued else { return .unchanged }
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
            current.pending.append(PendingChange(kind: .setAnchorSchedules(schedules), effectiveAt: effectiveAt))
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        SharedStore.log("anchor schedule: \(TimeFormat.anchorSchedules(schedules)) (\(result == .appliedNow ? "now" : "queued"))")
        enforce(reason: "anchor schedule")
        return result
    }

    /// The only unblock in Furlough: scans a tag and, if it is one of the paired ones, lifts the
    /// anchor. Every paired tag is equal here — they are keys to one lock.
    func unanchorWithTag() async -> AnchorOutcome {
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the Furlough tag to weigh anchor.")
        } catch {
            return outcome(for: error)
        }
        var current = SharedStore.load()
        guard current.config.anchor.isAnchored else { return .released }
        guard let matched = current.config.anchor.tag(matching: scanned) else {
            SharedStore.log("refused to weigh anchor: not a paired tag")
            return .wrongTag
        }
        Record.noteAnchorReleased(&current, now: current.now)
        current.config.anchor.isAnchored = false
        current.config.anchor.anchoredAt = nil
        current.config.anchor.until = nil
        current.config.anchor.sequence += 1
        SharedStore.save(current)
        SharedStore.log("weighed anchor with \(matched.name)")
        enforce(reason: "weigh anchor")
        // The one release the other device will take: a tag scan, on a phone.
        AnchorSync.publish(current.config.anchor, origin: .tagScan, now: current.now)
        return .released
    }

    // MARK: The anchor across devices

    /// A notification from iCloud that the other device wrote the anchor's record.
    @ObservationIgnored private var cloudObserver: (any NSObjectProtocol)?

    /// Listens for the other device's writes, once. iCloud posts the change to a running app
    /// only, so the reconciler pulls on every wake besides — the monitor's callbacks reach the
    /// record while the app is closed.
    private func observeCloud() {
        guard cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: AnchorCloud.changeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.applyRemoteAnchor(reason: "iCloud changed") }
        }
    }

    /// Merges what the other device wrote, through `AnchorSync.merge`, and enforces if it
    /// changed anything. Called on activation, when iCloud says the record changed, and by
    /// every reconcile besides.
    func applyRemoteAnchor(reason: String) {
        var current = SharedStore.load()
        guard let note = AnchorSync.pull(into: &current.config, now: current.now) else { return }
        SharedStore.save(current)
        SharedStore.log("iCloud anchor (\(reason)): \(note)")
        if isAuthorized { enforce(reason: "iCloud anchor") } else { reload() }
    }

    /// Asked for by the Weigh Anchor intent, which opens the app to get here.
    ///
    /// Held rather than run on the spot when Furlough is not yet in front: an intent that
    /// opens the app can perform before or after the scene goes active, and NFC only reads
    /// for a foreground app. Whichever of the two happens second is the one that scans.
    func requestWeighAnchor() {
        wantsWeighAnchor = true
        weighAnchorIfInFront()
    }

    /// Runs a held request, once there is a foreground app to run it in.
    func weighAnchorIfInFront() {
        guard wantsWeighAnchor, UIApplication.shared.applicationState == .active else { return }
        wantsWeighAnchor = false
        guard state.config.anchor.isAnchored else {
            notice = "Nothing is anchored."
            return
        }
        Task {
            switch await unanchorWithTag() {
            case .released: notice = "Anchor weighed. Everything it held is back on its own rules."
            case .wrongTag: notice = "That is not a paired tag. The anchor holds."
            case .failed(let why): notice = why
            // Cancelling the scan is an answer, not a failure: nothing to say.
            case .anchored, .paired, .cancelled: break
            }
        }
    }

    /// Pairs another tag. Refused while anchored — a key cut under the lock is no lock — and
    /// refused past the cap, which is checked twice because the scan is a long await and the
    /// state can move under it. Adding a key does not queue behind the loosen delay: it can only
    /// be done with the anchor already off, where nothing is being held to wait for.
    func pairTag() async -> AnchorOutcome {
        if let refusal = pairingRefusal(state.config.anchor) { return .failed(refusal) }
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the tag you want to pair.")
        } catch {
            return outcome(for: error)
        }
        var current = SharedStore.load()
        if let refusal = pairingRefusal(current.config.anchor) { return .failed(refusal) }
        // Scanning a tag already paired is a mistake worth naming, not a second identical key.
        if let already = current.config.anchor.tag(matching: scanned) {
            return .failed("That tag is already paired, as \(already.name).")
        }
        let tag = PairedTag(id: scanned, name: current.config.anchor.nextTagName)
        current.config.anchor.tags.append(tag)
        SharedStore.save(current)
        SharedStore.log("paired an anchor tag: \(tag.name)")
        reload()
        return .paired(tag)
    }

    /// Why this anchor may not take another tag right now, in the words the alert uses.
    private func pairingRefusal(_ anchor: AnchorProfile) -> String? {
        if anchor.isAnchored { return "Unanchor first." }
        if !anchor.canPairMore {
            return "\(Furlough.maxAnchorTags) tags is the limit. Forget one to pair another."
        }
        return nil
    }

    /// Names a paired tag. The name is the whole reason more than one is usable, so an empty one
    /// is ignored rather than stored, and it is locked with everything else while anchored.
    func renameTag(id: Data, to name: String) {
        let trimmed = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(PairedTag.maxNameLength)
        )
        guard !trimmed.isEmpty else { return }
        SharedStore.mutate { state in
            guard !state.config.anchor.isAnchored,
                  let index = state.config.anchor.tags.firstIndex(where: { $0.id == id })
            else { return }
            state.config.anchor.tags[index].name = trimmed
        }
        reload()
    }

    /// Forgets one key. Taking a key away is a tightening, so it lands at once — but only while
    /// the anchor is off, like every other change to it.
    func unpairTag(id: Data) {
        SharedStore.mutate { state in
            guard !state.config.anchor.isAnchored else { return }
            state.config.anchor.tags.removeAll { $0.id == id }
        }
        SharedStore.log("forgot an anchor tag")
        reload()
    }

    private func outcome(for error: any Error) -> AnchorOutcome {
        if let scan = error as? TagScanner.ScanError, scan == .cancelled { return .cancelled }
        return .failed(error.localizedDescription)
    }

    /// What anchoring would take away that is worth keeping, in the words both the Anchor
    /// screen and the Anchor button use. Nil when the anchor holds nothing worth a warning.
    var anchorCaution: (text: String, isSevere: Bool)? {
        guard let warning = state.config.anchorWarning,
              let text = UtilityText.anchoring(
                names: warning.names,
                utility: warning.utility,
                detail: warning.detail
              )
        else { return nil }
        return (text, warning.utility == .essential)
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

    /// Wipes every target, rule, pending change, the Anchor and its tag, lifts every shield, and
    /// enforces the empty state so the app matches a fresh install. Compiled in only when the
    /// build asked for the testing tools — see `TestingTools` — so the App Store build keeps its
    /// promise of no unblock button.
    func resetEverything() {
        SharedStore.reset()
        ShieldReconciler.clearEverything()
        // A stale drop left in iCloud would anchor the phone again on its next pull.
        AnchorCloud.clear()
        companionDismissed = []
        UserDefaults.standard.removeObject(forKey: AppModel.companionDismissedKey)
        SharedStore.log("reset everything (Debug build)")
        // A reset leaves Screen Time access granted, so `requestAuthorization` never runs
        // again and the first week would never start. A fresh install gets one; this is meant
        // to look like a fresh install.
        var current = SharedStore.load()
        if Forgiveness.startTrial(&current.config, now: current.now) { SharedStore.save(current) }
        lastError = nil
        enforce(reason: "reset")
    }
    #endif
}
