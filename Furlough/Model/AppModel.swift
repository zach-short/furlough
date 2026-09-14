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
    /// Shared so App Intents (which can run with no window) mutate the same state the views watch.
    static let shared = AppModel()

    var authorization = AuthorizationCenter.shared.authorizationStatus
    var state = SharedStore.load()
    var lastError: String?
    /// Message for an action with no screen of its own (e.g. an intent run from Spotlight);
    /// shown once by the root, then cleared.
    var notice: String?
    var notificationsGranted: Bool?
    let isAppGroupAvailable = SharedStore.isAppGroupAvailable
    private let scanner = TagScanner()
    /// A Weigh Anchor intent waiting for Furlough to reach the foreground; see below.
    @ObservationIgnored private var wantsWeighAnchor = false
    /// FamilyControls briefly reports "not determined" right after a cold start; this remembers
    /// the last real answer so the launch screen doesn't flash onboarding. In app defaults, not
    /// the App Group, since it tracks what iOS said, not what's blocked.
    let wasAuthorized = UserDefaults.standard.bool(forKey: AppModel.wasAuthorizedKey)
    private static let wasAuthorizedKey = "furlough.wasAuthorized"
    /// Targets whose companion nudge was dismissed. In app defaults, not Config: must not
    /// export with a setup or wait out the loosening delay.
    private var companionDismissed = Set(UserDefaults.standard.stringArray(forKey: AppModel.companionDismissedKey) ?? [])
    private static let companionDismissedKey = "furlough.companionDismissed"
    /// Whether the usage step has been shown. Same reasoning as `wasAuthorized`.
    private(set) var hasSeenUsageStep = UserDefaults.standard.bool(forKey: AppModel.usageStepKey)
    private static let usageStepKey = "furlough.sawUsageStep"
    /// Weekly digest toggle; defaults to on. Lives in the App Group (not app defaults) because
    /// the monitor extension re-plans it while the app is closed — see
    /// `PendingNotifications.digestPreferenceKey`.
    private(set) var weeklyDigest = PendingNotifications.wantsWeeklyDigest
    /// Whether the where-to-leave-it screen has been shown. A flag rather than "anchor has one
    /// tag": forgetting and re-pairing a tag would otherwise look like a first pairing again.
    private(set) var hasSeenTagPlacement = UserDefaults.standard.bool(forKey: AppModel.tagPlacementKey)
    private static let tagPlacementKey = "furlough.sawTagPlacement"
    /// The tag just paired, while its placement screen is up; cleared when the screen dismisses.
    var placingTagID: Data?
    /// What that tag is called now, for the screen's first line.
    var placingTagName: String? {
        placingTagID.flatMap { state.config.anchor.tag(matching: $0)?.name }
    }
    /// Which half Home opens on and which guide runs first. In app defaults, not exported.
    /// Defaults to Rules for upgrades that predate this setting.
    private(set) var startHalf = AppModel.storedStartHalf
    private static let startHalfKey = "furlough.startHalf"
    private static var storedStartHalf: Half {
        UserDefaults.standard.string(forKey: startHalfKey).flatMap(Half.init(rawValue:)) ?? .rules
    }
    /// "Both": opens on `startHalf` but leaves the other half's guide running too.
    private(set) var wantsBothHalves = UserDefaults.standard.bool(forKey: AppModel.bothHalvesKey)
    private static let bothHalvesKey = "furlough.bothHalves"
    /// What the + button adds while on the Anchor page (defaults to anchor; configurable).
    private(set) var anchorPageAdds = AppModel.storedAnchorPageAdds
    private static let anchorPageAddsKey = "furlough.anchorPageAdds"
    private static var storedAnchorPageAdds: Half {
        UserDefaults.standard.string(forKey: anchorPageAddsKey).flatMap(Half.init(rawValue:)) ?? .anchor
    }
    /// Whether arriving on the Anchor page arms the NFC reader automatically. Off by default to
    /// avoid surprising Apple's scan sheet.
    private(set) var autoArmsReader = UserDefaults.standard.bool(forKey: AppModel.autoArmsReaderKey)
    private static let autoArmsReaderKey = "furlough.autoArmsReader"
    /// Halves whose guide has been completed. A stored flag, not derived — completion (e.g.
    /// "read your list") can't be inferred from config state. First two steps of each guide are
    /// derived; see `HalfGuide`.
    private(set) var finishedGuides = AppModel.storedFinishedGuides
    private static let finishedGuidesKey = "furlough.finishedGuides"
    private static var storedFinishedGuides: Set<Half> {
        Set((UserDefaults.standard.stringArray(forKey: finishedGuidesKey) ?? []).compactMap(Half.init(rawValue:)))
    }
    #if DEBUG || TESTING_TOOLS
    /// A testing reset asked for onboarding again — see `resetEverything`.
    private(set) var restartsOnboarding = UserDefaults.standard.bool(forKey: AppModel.restartsOnboardingKey)
    private static let restartsOnboardingKey = "furlough.testing.restartOnboarding"
    #endif

    var isAuthorized: Bool {
        switch authorization {
        case .approved: true
        case .notDetermined, .denied: false
        default: true // approvedWithDataAccess (iOS 26.4+) and any future approved variants
        }
    }

    /// Summarizes access, App Group, notification and registration status; see `Diagnostics`.
    var diagnostics: Diagnostics {
        Diagnostics.summary(
            Diagnostics.Reading(
                screenTimeAllowed: isAuthorized,
                appGroupAvailable: isAppGroupAvailable,
                notificationsAllowed: notificationsGranted,
                registrationError: state.runtime.registrationError
            )
        )
    }

    /// Onboarding shows until Screen Time access is granted, except a testing reset can force
    /// it again — see `resetEverything`.
    var showsOnboarding: Bool {
        #if DEBUG || TESTING_TOOLS
        if restartsOnboarding { return true }
        #endif
        return !isAuthorized
    }

    /// Shown between Screen Time access and the first rule. Stored, not derived from targets:
    /// applying a suggestion inside this step creates the first rule, and a live condition would
    /// pull the screen out from under the user mid-flow. Cleared only by `finishUsageStep`.
    private(set) var showsUsageStep = false

    /// Shown only when data access is available: without it every card would dead-end in a
    /// manual picker trip, which is fine in Settings but a poor first screen.
    private func considerUsageStep() {
        guard !hasSeenUsageStep, isAuthorized, UsageReader.hasDataAccess(authorization) else { return }
        guard state.config.targets.isEmpty else { return }
        showsUsageStep = true
    }

    /// Written on Continue, not on each tap, so backing out of the intro doesn't leave a stray
    /// choice.
    func chooseStart(half: Half, both: Bool) {
        UserDefaults.standard.set(half.rawValue, forKey: Self.startHalfKey)
        UserDefaults.standard.set(both, forKey: Self.bothHalvesKey)
        startHalf = half
        wantsBothHalves = both
    }

    /// Changing just the start half leaves `wantsBothHalves` untouched.
    func setStartHalf(_ half: Half) {
        guard half != startHalf else { return }
        chooseStart(half: half, both: wantsBothHalves)
    }

    /// Which half the + adds to over the Anchor page. See `anchorPageAdds`.
    func setAnchorPageAdds(_ half: Half) {
        guard half != anchorPageAdds else { return }
        UserDefaults.standard.set(half.rawValue, forKey: Self.anchorPageAddsKey)
        anchorPageAdds = half
    }

    /// Turns the Anchor page's arm-on-sight behavior on or off. See `autoArmsReader`.
    func setAutoArmsReader(_ on: Bool) {
        guard on != autoArmsReader else { return }
        UserDefaults.standard.set(on, forKey: Self.autoArmsReaderKey)
        autoArmsReader = on
    }

    /// Where a + press lands, given the page it was pressed over. Rules always adds a rule;
    /// the Anchor page asks the preference.
    func addDestination(on half: Half) -> Half {
        half == .rules ? .rules : anchorPageAdds
    }

    /// One half's guide is done with: its last step was pressed, or the anchor it was walking
    /// towards has been dropped.
    func finishGuide(_ half: Half) {
        guard !finishedGuides.contains(half) else { return }
        write(finishedGuides: finishedGuides.union([half]))
    }

    /// Resets guide completion; the derived first two steps still reflect actual state, so this
    /// only replays the last step.
    func restartGuides() {
        guard !finishedGuides.isEmpty else { return }
        write(finishedGuides: [])
    }

    /// Marks guides as already finished for a phone that's already set up, so an update doesn't
    /// show a checklist to an existing user. Runs once — absence of the key means "never seeded".
    private func seedFinishedGuides() {
        guard UserDefaults.standard.object(forKey: Self.finishedGuidesKey) == nil else { return }
        var seeded: Set<Half> = []
        let config = state.config
        if config.targets.contains(where: { $0.rule != nil }) { seeded.insert(.rules) }
        if config.anchor.isPaired, config.anchor.hasSomethingToHold { seeded.insert(.anchor) }
        write(finishedGuides: seeded)
    }

    private func write(finishedGuides halves: Set<Half>) {
        UserDefaults.standard.set(halves.map(\.rawValue).sorted(), forKey: Self.finishedGuidesKey)
        finishedGuides = halves
    }

    /// The step is done with, whether it was worked through or waved away.
    func finishUsageStep() {
        UserDefaults.standard.set(true, forKey: Self.usageStepKey)
        hasSeenUsageStep = true
        showsUsageStep = false
    }

    // MARK: What a usage card's press writes

    /// What one usage card's Apply did — the rules row, the anchor's doors, or both. The page
    /// keeps it on the card as `UsageCardState.Applied`.
    struct UsageApply: Equatable {
        var targetID: UUID?
        var heldKinds: [TargetKind] = []
        /// True only when the press created the rules row itself — see `undoFreshTarget`.
        var fresh = false
        var message = ""
        /// The rule loosened a row that already had one, so it waits out the delay.
        var waiting = false
    }

    /// Why a press could not be written, in a sentence the card can show.
    struct UsageRefusal: Error {
        var reason: String
    }

    /// Writes one usage card's answer on `kind`. No query or await anywhere in here — every
    /// line is a synchronous write + enforce — which is what makes an instant Apply honest
    /// rather than optimistic. Shared by the page (`UsageView.write`) and the background
    /// finisher below, so a press lands the same way wherever it is finished.
    func applyUsage(
        rule: Rule,
        to kind: TargetKind,
        named name: String,
        writesRule: Bool,
        holds: Bool
    ) -> Result<UsageApply, UsageRefusal> {
        var done = UsageApply()
        if writesRule {
            var fresh = false
            // target(kind:) rather than matching `kind` alone: this app may already be the linked
            // half of a row (YouTube beside youtube.com), and adding it again would split that pair.
            if state.config.target(kind: kind) == nil {
                var picked = pickerSelection
                switch kind {
                case .application(let token): picked.applicationTokens.insert(token)
                case .webDomain(let token): picked.webDomainTokens.insert(token)
                // Screen Time counts neither a whole category nor a hand-typed site.
                case .category, .host: break
                }
                _ = applyPicker(picked)
                reload()
                fresh = true
            }
            guard let target = state.config.targets.first(where: { $0.kind == kind }) else {
                return .failure(UsageRefusal(reason: "Could not add \(name)."))
            }
            let outcome = apply(rule: rule, nickname: target.nickname, for: target.id, andTo: [])
            done.targetID = target.id
            done.fresh = fresh
            done.waiting = outcome.scheduled > 0
            done.message = outcome.message
        }
        if holds {
            // Holds every door of a linked row (app + site) together, so one pick closes both.
            let doors = state.config.target(kind: kind)?.kinds ?? [kind]
            guard hold(doors) else {
                return .failure(UsageRefusal(reason: "The Anchor cannot take anything in while it is down."))
            }
            done.heldKinds = doors
            let held = "On the Anchor's list: out of reach the moment you drop it."
            done.message = done.message.isEmpty ? held : "\(done.message)\n\n\(held)"
        }
        return .success(done)
    }

    /// A press the usage step closed on before Screen Time had named its app: finished here,
    /// off the page, so leaving cannot lose it. `name` is for the alert if it never lands.
    struct UsageOwed {
        var key: String
        var name: String
        var rule: Rule
        var writesRule: Bool
        var holds: Bool
    }

    /// How many times the background finisher asks Screen Time, a second apart — the page's
    /// own `nameApps` count, since it is the same question asked from a different place.
    private static let usageFinishAttempts = 3

    /// Finishes presses the step closed on. Asks for their tokens the way the page did — a few
    /// tries, a second apart, an empty answer meaning a failed query — writes each one it can,
    /// and puts the ones it couldn't in `lastError`, since the page that would have said so is
    /// gone. Nothing is written for a press Screen Time never answers.
    func finishUsageInBackground(_ owed: [UsageOwed]) {
        guard #available(iOS 26.4, *), !owed.isEmpty else { return }
        SharedStore.log("usage: \(owed.count) press(es) still owed when the step closed; finishing in the background")
        Task {
            var found: [String: TargetKind] = [:]
            for attempt in 1...Self.usageFinishAttempts {
                found = (try? await UsageReader.kinds(forKeys: owed.map(\.key), within: UsageReader.patience)) ?? [:]
                if !found.isEmpty || attempt == Self.usageFinishAttempts { break }
                try? await Task.sleep(for: .seconds(1))
            }
            var missed: [String] = []
            for one in owed {
                guard let kind = found[one.key] else {
                    missed.append(one.name)
                    continue
                }
                switch applyUsage(rule: one.rule, to: kind, named: one.name, writesRule: one.writesRule, holds: one.holds) {
                case .success:
                    SharedStore.log("usage: finished \(one.name) in the background")
                case .failure(let refusal):
                    missed.append(one.name)
                    SharedStore.log("usage: could not finish \(one.name) in the background: \(refusal.reason)")
                }
            }
            guard !missed.isEmpty else { return }
            SharedStore.log("usage: \(missed.count) press(es) left to finish in the background never landed")
            let list = missed.formatted(.list(type: .and))
            lastError = missed.count == 1
                ? "Furlough could not finish \(list). Screen Time never handed the app over, so nothing was written for it. You can try again from Settings › Where the time goes."
                : "Furlough could not finish \(list). Screen Time never handed those apps over, so nothing was written for them. You can try again from Settings › Where the time goes."
        }
    }

    // MARK: Lifecycle

    func activate() {
        observeChanges()
        observeCloud()
        AnchorCloud.synchronize()
        // iCloud sign-out happens outside the app; activation is the earliest point to notice
        // the anchor stopped syncing.
        refreshCloudAvailability(reason: "activate")
        // iPad has no tag reader; the signed record must say so or a Mac would treat it as able
        // to release the anchor.
        AnchorSync.notePlatform(isPad: UIDevice.current.userInterfaceIdiom == .pad)
        // Runs once per build upgrade to grandfather existing Mac links.
        DeviceLink.decideGrandfathering(now: state.now)
        note(AuthorizationCenter.shared.authorizationStatus)
        reload()
        applyRemoteAnchor(reason: "activate")
        settleLink(reason: "activate")
        seedFinishedGuides()
        considerUsageStep()
        Task { await refreshNotificationStatus() }
        // Off the critical path: both need a Screen Time query and nothing waits on it.
        Task {
            await nameUnnamedTargets()
            await nameAnchoredKinds()
            await anchorArrivalsFromTheTables()
        }
        // Must run before the authorization guard: lifting the anchor via tag scan must work
        // even before FamilyControls has answered.
        weighAnchorIfInFront()
        guard isAuthorized else { return }
        enforce(reason: "app active")
    }

    /// Darwin notifications carry no payload and the C callback can't capture context, so it
    /// routes through `shared`.
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

    /// Only the app registers DeviceActivity, so any external write (widget drop, monitor)
    /// needs a fresh enforce even though shields may already be applied.
    func changedElsewhere() {
        let before = state
        reload()
        guard state != before, isAuthorized else { return }
        enforce(reason: "changed elsewhere")
        // A name the shield just learned may be what an add was waiting on to link or cross.
        settleLink(reason: "changed elsewhere")
    }

    /// FamilyControls reports "not determined" right after cold start; the real answer arrives
    /// here shortly after — enforce then if `activate()` couldn't.
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
            #if DEBUG || TESTING_TOOLS
            finishOnboardingRestart()
            #endif
            startTrialIfNeeded()
            enforce(reason: "authorized")
        }
    }

    /// Starts the trial only on first grant of Screen Time access; `Forgiveness.startTrial`
    /// refuses subsequent grants.
    private func startTrialIfNeeded() {
        var current = SharedStore.load()
        guard Forgiveness.startTrial(&current.config, now: current.now) else { return }
        SharedStore.save(current)
        SharedStore.log("first week started; loosenings wait \(Furlough.trialDelayHours) h until it ends")
    }

    /// Read on Furlough's own clock so a device clock rolled back can't reopen a closed undo
    /// window.
    func undo(for id: UUID) -> RuleUndo? {
        guard let target = state.config.target(id: id) else { return nil }
        return Forgiveness.undo(for: target, at: clock.now)
    }

    /// Reverts to the prior rule instantly (not a loosening, since it was already in force).
    /// Returns true when applied.
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

    /// `enforce()` re-plans notifications, so turning the digest off also withdraws any already
    /// scheduled.
    func setWeeklyDigest(_ on: Bool) {
        guard on != weeklyDigest else { return }
        PendingNotifications.setWantsWeeklyDigest(on)
        weeklyDigest = on
        SharedStore.log("weekly digest \(on ? "on" : "off")")
        enforce(reason: "weekly digest")
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

    /// Furlough's own time and its drift from the device clock; countdowns read through here.
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
        // Must run before registration or an expired timed anchor's wake gets re-registered.
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
        // Rescheduled on every enforce (not just when queued) so the pre-loosening warning
        // stays accurate.
        PendingNotifications.sync(state: current, now: clock.now, drift: clock.drift, digest: weeklyDigest)
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

        // Each removal waits out its own target's tier. Policy.picker(removes:selected:) decides
        // eligibility — a linked pair isn't broken by unpicking one half (only the editor's
        // "Also blocks" card does that, as a delayed loosening).
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
        // Owed to other devices once named — settled later via settleLink.
        let added = current.config.targets.filter { !existing.contains($0.kind) }.map(\.id)
        LinkFlow.noteAdded(added, half: .rules, config: current.config)
        // A token from the picker has no name yet, and the companion nudge / merge offer both
        // need one. Off the critical path — nothing waits on Screen Time's answer.
        if outcome.added > 0 { Task { await nameUnnamedTargets() } }
        return outcome
    }

    /// How long after adding an app the usage flow may still take it straight back: long enough
    /// to work through a screenful of suggestions, far short of living under one.
    static let undoWindow: TimeInterval = 30 * 60

    /// Undoes a target added moments ago (within `undoWindow`), bypassing the loosening delay
    /// since it never actually shielded anything. False when nothing was undone.
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
            // A single pick joins the row; extra picks become their own rows on the same hours.
            let extras = count > 1 ? " The other \(count - 1) got \(count == 2 ? "a row" : "rows") of \(count == 2 ? "its" : "their") own, on the same hours." : ""
            return inherited
                ? "One row now, on one schedule and one budget.\(extras)"
                : "One row now. Give it hours and both halves follow; nothing is blocked until you do.\(extras)"
        }
    }

    /// Links the app onto the website's existing row rather than using `applyPicker` (which
    /// would treat the empty selection as "remove everything absent"). The app becomes the
    /// row's face; its rule, tier, nickname and delay are unchanged. A tightening, applied
    /// instantly — `unlink` handles removing a half as a delayed loosening.
    @discardableResult
    func addCompanionApps(_ selection: FamilyActivitySelection, for request: AddRequest.Companion) -> CompanionAddOutcome {
        var current = SharedStore.load()
        let existing = Set(current.config.targets.flatMap(\.kinds))
        let tokens = selection.applicationTokens.filter { !existing.contains(.application($0)) }
        guard !tokens.isEmpty,
              let index = current.config.targets.firstIndex(where: { $0.id == request.targetID })
        else { return .none }
        let inherited = current.config.targets[index].rule

        // The first pick becomes the row's face; the site moves in beside it via `also`.
        let site = current.config.targets[index].kinds
        let face = tokens.first!
        current.config.targets[index].kind = .application(face)
        current.config.targets[index].also = site
        if !request.title.isEmpty, tokens.count == 1 {
            current.config.targets[index].systemName = request.title
        }
        // Extra picks aren't part of this pair, so they get their own rows (keeping the
        // inherited rule).
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

    /// Adds a website by name (no token/picker needed — `WebContentSettings.blockedByFilter`
    /// takes a plain string). Deduplicates against existing hosts and subdomains via
    /// `Config.target(host:)`.
    @discardableResult
    func addHost(_ raw: String) -> AddHostOutcome {
        guard let host = Hosts.normalize(raw) else { return .unreadable }
        if let existing = SharedStore.load().config.target(host: host) { return .already(existing.displayName) }
        addHosts([host])
        return .added(host)
    }

    /// Batches several hosts into one save/enforce pass. Mirrors `MacModel.addHosts`.
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
        // A typed host names itself, so it can cross at once.
        LinkFlow.noteAdded(added.map(\.id), half: .rules, config: current.config)
        settleLink(reason: "add sites by name")
        return added
    }

    // MARK: Importing a setup

    /// Opens a file without planning yet: a Screen Time token is opaque and device-scoped, so
    /// the file can't say which app a rule belonged to — `ImportSetupView` asks the user, then
    /// calls `plan`.
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
        // DeviceActivity's activity-count ceiling is iOS-only, so it's checked here rather than
        // in the platform-agnostic ConfigImport.
        plan.limitReason = ActivityLimit.reason(applying: plan, in: current)
        return plan
    }

    /// Applies a whole import plan in one save/enforce pass rather than one per target, and
    /// appends targets directly (not via `applyPicker`, which would schedule removal of
    /// anything absent from a selection).
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

    /// What to offer beside `target` as its companion, or nil. A Screen Time token is opaque
    /// until the shield first names it, so the nudge only appears from the second look on —
    /// except a typed host, which carries its own name immediately. Nil once linked, dismissed,
    /// or unknown to the Companions table.
    func companion(for target: Target) -> Companions.Half? {
        guard !companionDismissed.contains(target.id.uuidString) else { return nil }
        // Checking "does it cover a site" is cheaper than "which site" — a linked site half may
        // be a token whose domain was never learned.
        guard !(target.coversApp && target.coversSite) else { return nil }
        switch target.kind {
        case .application:
            // Under Never no nudge is offered; under Always settleLink has already linked
            // what it could.
            guard state.config.link.companionSite != .never, let name = learnedName(of: target) else { return nil }
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

    /// Links sites onto a target as halves rather than rows. A tightening, applied instantly;
    /// `unlink` handles the delayed loosening of removing a half.
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

    /// Folds `absorbed` into `keeping`, retroactively linking two rows added separately. A
    /// tightening (tighter schedule + shared budget wins), applied instantly. The app half
    /// becomes the face when either side is an app.
    @discardableResult
    func merge(_ absorbed: UUID, into keeping: UUID) -> LinkOutcome {
        var current = SharedStore.load()
        guard absorbed != keeping,
              let a = current.config.target(id: keeping),
              let b = current.config.target(id: absorbed),
              let index = current.config.targets.firstIndex(where: { $0.id == keeping })
        else { return .none }
        let gone = b.displayName
        // The app half becomes the face even if it's the one being absorbed.
        let faceIsApp = a.coversApp || !b.coversApp
        current.config.targets[index].kind = faceIsApp ? a.kind : b.kind
        let face = current.config.targets[index].kind
        // Dedup defensively — the two rows should never share a kind, but a duplicate would
        // show twice and unlink incorrectly.
        var seen: Set<TargetKind> = [face]
        let others = (faceIsApp ? (a.also ?? []) + b.kinds : (b.also ?? []) + a.kinds)
            .filter { seen.insert($0).inserted }
        current.config.targets[index].also = others.isEmpty ? nil : others
        // Tighter rule wins; a target with no rule enforces nothing, so any real rule beats none.
        current.config.targets[index].rule = Self.budgeted(
            Self.tighter(a.rule, b.rule),
            counted: current.config.targets[index].isCounted
        )
        // The name and the tier come from the face, and the face may just have changed.
        if !faceIsApp {
            current.config.targets[index].systemName = b.systemName
            if current.config.targets[index].nickname.isEmpty { current.config.targets[index].nickname = b.nickname }
        }
        // The slower (more cautious) utility tier wins — a merge must not shorten a wait.
        current.config.targets[index].utilityLevel = Self.slower(a.utilityLevel, b.utilityLevel)
        // Must read `name` before removing the absorbed row — removal shifts indices below it,
        // and reading after could hit a stale index or crash (real bug, 2026-09-09).
        let name = current.config.targets[index].displayName
        current.config.targets.removeAll { $0.id == absorbed }
        // Anything queued for the row that is going would land on a target that no longer exists.
        current.pending.removeAll { $0.targetID == absorbed }
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

    /// Replaces the "no limit" sentinel (1440 min, from `RuleEditorView.savedBudget`, used for
    /// uncounted targets) with the default budget when a merge makes the target counted —
    /// otherwise it would show as a maxed-out slider.
    private static func budgeted(_ rule: Rule?, counted: Bool) -> Rule? {
        // All seven days must carry the sentinel for this to apply.
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

    /// Rows that are the other half of `target` and could be merged in. Uses the same
    /// Companions table and learned names as the nudge.
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

    /// Removes a half from a target. A loosening — waits out the delay and can be cancelled
    /// from the pending list.
    func unlink(_ kind: TargetKind, from id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let target = current.config.target(id: id), target.covers(kind), target.kind != kind else { return .unchanged }
        // Queued as a PendingKind like other loosenings so it reuses warning/cancel/display
        // machinery.
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

    /// Names unnamed targets via Screen Time data access (bundle ID matched against
    /// Companions/AppUtility) rather than waiting for the shield to learn them. Data access is
    /// EU-only for customers, dev builds anywhere (`FamilyActivityData`). Written to the
    /// learned-names key, not Config, so it doesn't export or queue.
    func nameUnnamedTargets() async {
        guard #available(iOS 26.4, *), UsageReader.hasDataAccess else { return }
        let unnamed = state.config.targets.filter { learnedName(of: $0) == nil }
        guard !unnamed.isEmpty else { return }
        let identities: [TargetKind: String]
        do {
            identities = try await UsageReader.identities()
        } catch {
            // Screen Time didn't answer; nothing worse off, the shield will still name it
            // eventually.
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
        // A name is what the site and the other devices were waiting on.
        settleLink(reason: "named from the tables")
    }

    /// Same as `nameUnnamedTargets`, but for anchor-held kinds with no target/rule — a token
    /// means nothing to other devices until named. Written to the anchor's names key, not
    /// Config.
    func nameAnchoredKinds() async {
        guard #available(iOS 26.4, *), UsageReader.hasDataAccess else { return }
        let held = state.config.anchor.kinds
        guard !state.config.anchor.anchorsEverything else { return }
        let known = SharedStore.anchorNames()
        let unnamed = held.filter { state.config.target(kind: $0) == nil && known[$0] == nil }
        guard !unnamed.isEmpty else { return }
        let identities: [TargetKind: String]
        do {
            identities = try await UsageReader.identities()
        } catch {
            // Screen Time didn't answer; nothing worse off.
            return
        }
        var learned = 0
        for kind in unnamed {
            guard let key = identities[kind], let name = Self.nameFromTables(key) else { continue }
            if SharedStore.learnAnchorName(name, for: kind) { learned += 1 }
        }
        guard learned > 0 else { return }
        SharedStore.log("named \(learned) anchored item(s) from the tables")
        settleLink(reason: "anchor named from the tables")
    }

    /// Resolves apps another device anchored (arriving as name + bundle ID, no token) into real
    /// tokens via the data-access tables, avoiding a manual picker trip. Without data access,
    /// `LinkFlow.anchorOwed` just stays queued.
    func anchorArrivalsFromTheTables() async {
        guard #available(iOS 26.4, *), UsageReader.hasDataAccess else { return }
        let owed = LinkFlow.anchorOwed
        guard !owed.isEmpty else { return }
        // Refused while anchored or under everything-except scope (adding there would let it
        // through, not hold it); stays queued for later.
        let anchor = state.config.anchor
        guard !anchor.isHolding(at: state.now), !anchor.anchorsEverything else { return }
        // One batched query for the whole queue — asking per bundle ID would re-walk every app
        // on the phone each time.
        let found = (try? await UsageReader.kinds(forKeys: owed, within: UsageReader.patience)) ?? [:]
        guard !found.isEmpty else { return }
        var current = SharedStore.load()
        // Re-check after the await: the anchor may have dropped while the query was in flight.
        guard !current.config.anchor.isHolding(at: current.now), !current.config.anchor.anchorsEverything else { return }
        var added = 0
        for kind in found.values where !current.config.anchor.contains(kind) {
            current.config.anchor.kinds.append(kind)
            added += 1
        }
        LinkFlow.anchorOwed = owed.filter { found[$0] == nil }
        guard added > 0 else { return }
        SharedStore.save(current)
        SharedStore.log("link: the tables found \(added) anchored app(s) another device sent; now holds \(current.config.anchor.count) item(s)")
        enforce(reason: "link arrival, anchor")
    }

    /// Resolves a usage key (bundle ID, or "web:"+domain) to a display name: Companions first,
    /// then AppUtility, else the domain itself.
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
                // systemName belongs to the face only; a linked half has no name of its own.
                case .webDomain: ofHosts && kind == target.kind ? target.systemName : nil
                case .application: !ofHosts && kind == target.kind ? target.systemName : nil
                case .category: nil
                // A typed host is its own name whether it's the face or a linked half.
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
        // A rule landing on something already sent goes out too, so the other devices get
        // the hours as well as the name. The store is re-read: `enforce` folds names in.
        if result == .appliedNow, let target = SharedStore.load().config.target(id: id) {
            LinkFlow.resendIfSent(target, config: state.config, now: state.now)
        }
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

    /// Applies one rule to multiple targets in one save; each is judged individually
    /// (tighten now / loosen delayed) as if saved by hand.
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
        for target in state.config.targets where ([id] + others).contains(target.id) {
            LinkFlow.resendIfSent(target, config: state.config, now: state.now)
        }
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
            // Records the previous rule for undo — only needed here, since undoing a loosening
            // is itself an instant tightening.
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

    /// Furlough's own token, when Screen Time has already named it in `TokenCache` (data access,
    /// iOS 26.4+). `Policy.decide` refuses to shield this token regardless, but keeping it out of
    /// the anchor's list too means the screen never shows Furlough as something it's holding.
    private var ownApplicationToken: ApplicationToken? {
        guard let encoded = UsageReader.cachedKinds()?[Furlough.bundleID],
              let kind = try? JSONDecoder().decode(TargetKind.self, from: encoded),
              case .application(let token) = kind
        else { return nil }
        return token
    }

    /// Replaces the anchor's list: what it holds, or under the everything-except scope what it
    /// lets through. Refused while anchored, so nothing loosens under a lock.
    func setAnchorSelection(_ selection: FamilyActivitySelection) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored else { return }
        var kinds: [TargetKind] = []
        kinds += selection.applicationTokens.map(TargetKind.application)
        kinds += selection.webDomainTokens.map(TargetKind.webDomain)
        // Furlough itself can never become the anchor — anchoring it would take away the one
        // app that could unanchor it. Best-effort: only catches it where the token is already
        // identified (see `ownApplicationToken`); `Policy.decide` is the real backstop.
        if let own = ownApplicationToken {
            kinds.removeAll { $0 == .application(own) }
        }
        // .all(except:) only excepts app/site tokens, never categories — a category token here
        // would sit unread, so it's dropped for the everything-except scope.
        if !current.config.anchor.anchorsEverything {
            kinds += selection.categoryTokens.map(TargetKind.category)
        }
        // The picker only knows tokens, so typed hosts (kept by name) are preserved regardless
        // of selection.
        kinds += current.config.anchor.kinds.filter(\.isHost)
        guard kinds != current.config.anchor.kinds else { return }
        current.config.anchor.kinds = kinds
        SharedStore.save(current)
        SharedStore.log("anchor: now \(current.config.anchor.anchorsEverything ? "lets through" : "holds") \(kinds.count) item(s)")
        enforce(reason: "anchor edit")
        // Newly added tokens usually have no name yet and can't cross today; later settles
        // pick them up once named.
        settleLink(reason: "anchor edit")
        Task { await nameAnchoredKinds() }
    }

    /// Adds existing rule targets to the anchor's list (the Anchor screen's suggested-candidates
    /// flow). Refused while anchored or under everything-except scope.
    func addToAnchor(targetIDs: [UUID]) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored, !current.config.anchor.anchorsEverything else { return }
        let chosen = current.config.targets.filter { targetIDs.contains($0.id) }
        guard current.config.anchor.add(chosen) else { return }
        SharedStore.save(current)
        SharedStore.log("anchor: took in \(chosen.count) of the rules; now holds \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor edit")
        // LinkFlow.anchorAdditions walks the list directly rather than a separate awaiting queue.
        settleLink(reason: "anchor edit")
    }

    /// Removes targets from the anchor's list. No delay — the tag itself is what makes the
    /// anchor hard to undo, not a waiting period.
    func removeFromAnchor(targetIDs: [UUID]) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored, !current.config.anchor.anchorsEverything else { return }
        let going = current.config.targets.filter { targetIDs.contains($0.id) }
        guard current.config.anchor.remove(going) else { return }
        SharedStore.save(current)
        SharedStore.log("anchor: let go of \(going.count); now holds \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor edit")
    }

    /// Adds kinds to the anchor directly (no Target row created) — used by the usage flow. Same
    /// refusals as `addToAnchor`. Returns true if all are held, including already-held ones
    /// (answers "is it held", not "did I change anything").
    @discardableResult
    func hold(_ kinds: [TargetKind]) -> Bool {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored, !current.config.anchor.anchorsEverything else { return false }
        let fresh = kinds.filter { !current.config.anchor.contains($0) }
        guard !fresh.isEmpty else { return true }
        current.config.anchor.kinds += fresh
        SharedStore.save(current)
        SharedStore.log("anchor: took in \(fresh.count) from the usage flow; now holds \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor edit")
        settleLink(reason: "anchor edit")
        // Off the critical path — names are filled in later, not waited on.
        Task { await nameAnchoredKinds() }
        return true
    }

    /// Removes kinds from the anchor (usage flow's Undo). No delay, same reasoning as
    /// `removeFromAnchor`.
    func stopHolding(_ kinds: [TargetKind]) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored, !current.config.anchor.anchorsEverything else { return }
        let going = Set(kinds)
        guard current.config.anchor.kinds.contains(where: going.contains) else { return }
        current.config.anchor.kinds.removeAll(where: going.contains)
        SharedStore.save(current)
        SharedStore.log("anchor: let go of \(going.count) the usage flow put on; now holds \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor edit")
    }

    /// Returns the target id for `kind`, creating a ruleless Target if needed (the anchor
    /// grid's "Give it hours too"). Categories get `.alwaysBlocked` immediately since they have
    /// no hours to configure.
    func targetForRule(_ kind: TargetKind) -> UUID {
        var current = SharedStore.load()
        if let existing = current.config.target(kind: kind) { return existing.id }
        let target = Target(kind: kind, rule: kind.isCategory ? .alwaysBlocked : nil)
        current.config.targets.append(target)
        SharedStore.save(current)
        SharedStore.log("added a target from the anchor's grid")
        enforce(reason: "add target")
        return target.id
    }

    /// Switches anchor scope (its list vs. everything-except). The list can't carry over —
    /// under one scope it's what's blocked, under the other it's what's allowed — so widening
    /// seeds from essential-tier targets and narrowing starts empty.
    func setAnchorScope(_ scope: AnchorProfile.Scope) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored, current.config.anchor.scope != scope else { return }
        current.config.anchor.scope = scope
        current.config.anchor.kinds = scope == .everythingExcept ? current.config.essentialKinds : []
        SharedStore.save(current)
        SharedStore.log("anchor: scope is now \(scope.rawValue); the list starts with \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor scope")
    }

    /// Anchoring needs no tag (a tightening) but requires one paired, or there'd be no way back.
    /// `until` schedules a timed lift. Drop logic is shared with the widget extension via
    /// `AnchorDrop`; only the app can register the wake.
    func anchor(until: Date? = nil) -> AnchorOutcome {
        switch AnchorDrop.drop(until: until, reason: "anchor") {
        case .refused(.alreadyAnchored):
            reload()
            finishGuide(.anchor)
            return .anchored
        case .refused(let why):
            return .failed(why.message)
        case .anchored:
            enforce(reason: "anchor")
            // Guide's last step is dropping the anchor, from any entry point (button, widget, Siri).
            finishGuide(.anchor)
            return .anchored
        }
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

    /// What a tag held up on the Anchor screen turned out to be. The scan itself is one call;
    /// which of the three things it means is `AnchorProfile.reading(of:)`.
    enum TagRead: Equatable {
        case read(AnchorProfile.TagReading)
        /// Cancelled or timed out — a reader armed unprompted is allowed to find nothing.
        case quiet
        case failed(String)
    }

    /// Reads a tag and reports what it would mean, without acting. Reads fresh from the store
    /// (not `state`) since the scan is a long await during which a schedule could change the
    /// anchor.
    func readTag(prompt: String) async -> TagRead {
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: prompt)
        } catch {
            if let scan = error as? TagScanner.ScanError, scan.isQuiet { return .quiet }
            return .failed(error.localizedDescription)
        }
        return .read(SharedStore.load().config.anchor.reading(of: scanned))
    }

    /// Ends an armed read: the Anchor screen going away with its sheet still up.
    func stopReadingTags() { scanner.cancel() }

    /// The only unblock in Furlough: scans a tag and, if paired, lifts the anchor.
    func unanchorWithTag() async -> AnchorOutcome {
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the Furlough tag to weigh anchor.")
        } catch {
            return outcome(for: error)
        }
        return weighAnchor(with: scanned)
    }

    /// Lifts the anchor with a tag already read. Split from the scan so one armed session can
    /// end in either this or a pairing, decided by the tag rather than the button.
    @discardableResult
    func weighAnchor(with scanned: Data) -> AnchorOutcome {
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

    /// Whether iCloud can carry the anchor off this phone. Read once per activation/account
    /// change, not per view rebuild.
    private(set) var cloudAvailable = AnchorCloud.isAvailable

    /// Re-reads whether iCloud is reachable and logs the change. Nothing is enforced — the
    /// phone's own rules never depended on iCloud.
    func refreshCloudAvailability(reason: String) {
        let available = AnchorCloud.isAvailable
        guard available != cloudAvailable else { return }
        cloudAvailable = available
        SharedStore.log("iCloud is \(available ? "reachable again" : "unreachable; the anchor cannot cross") (\(reason))")
    }

    /// iCloud only notifies a running app; the monitor's own pull-on-wake covers the
    /// closed-app case.
    private func observeCloud() {
        guard cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: AnchorCloud.changeNotification, object: nil, queue: .main
        ) { notification in
            let accountChanged = AnchorCloud.isAccountChange(notification)
            Task { @MainActor in
                if accountChanged { AppModel.shared.refreshCloudAvailability(reason: "account changed") }
                AppModel.shared.applyRemoteAnchor(reason: accountChanged ? "iCloud account changed" : "iCloud changed")
            }
        }
    }

    /// The link to the Mac. Re-read on demand (costs a key-value store read).
    private(set) var link = AnchorSync.linkStatus()

    /// Asks iCloud for whatever it has, merges it, and re-reads the link — what Check now does.
    func checkLink() {
        AnchorCloud.synchronize()
        refreshCloudAvailability(reason: "check link")
        applyRemoteAnchor(reason: "check link")
        refreshLink()
        SharedStore.log("link check: \(link.headline) — \(link.detail(now: clock.now))")
    }

    /// Merges what other devices wrote — the anchor via `AnchorSync.merge`, additions via
    /// `LinkFlow.takeArrivals` — and enforces if anything changed.
    func applyRemoteAnchor(reason: String) {
        var current = SharedStore.load()
        let note = AnchorSync.pull(into: &current.config, now: current.now)
        let arrivals = LinkFlow.takeArrivals(&current, installed: { [:] })
        self.arrivals = arrivals.asks
        // An anchored arrival still needs a token; the tables are the one place to get one
        // without the picker.
        if !LinkFlow.anchorOwed.isEmpty { Task { await anchorArrivalsFromTheTables() } }
        guard note != nil || !arrivals.landed.isEmpty else { return }
        SharedStore.save(current)
        if let note { SharedStore.log("iCloud anchor (\(reason)): \(note)") }
        for landed in arrivals.landed { SharedStore.log("link: landed \(landed) (\(reason))") }
        refreshLink()
        if isAuthorized { enforce(reason: "iCloud") } else { reload() }
    }

    // MARK: The link

    /// Whether this device is on the link, as the screens read it.
    private(set) var isEnrolled = DeviceLink.isEnrolled
    /// The other devices on the link, for the Devices screen. Read with the link status: it
    /// costs a scan of the key-value store, and the screen asks when it opens.
    private(set) var devices: [LinkedDevice] = []
    /// What the other devices added and this one is asking about, oldest first. Derived from
    /// the store on every pull, so answering one is what makes it go.
    private(set) var arrivals: [SharedAdditions.Landing] = []
    /// What this device added and is asking whether to send. Settled on every `settleLink`.
    private(set) var outgoing: [SharedAddition] = []

    /// Re-reads everything the Devices screen shows.
    func refreshLink() {
        link = AnchorSync.linkStatus()
        isEnrolled = DeviceLink.isEnrolled
        devices = DeviceLink.others()
    }

    /// The settings the Devices screen changes. Saved and nothing enforced: turning any of them
    /// down blocks nothing that was blocked, and turning the site one up is settled at once.
    func setLinkPreferences(_ preferences: LinkPreferences) {
        guard preferences != state.config.link else { return }
        SharedStore.mutate { $0.config.link = preferences }
        SharedStore.log("link settings: site \(preferences.companionSite.rawValue), send \(preferences.sendAdditions.rawValue), accept \(preferences.acceptAdditions.rawValue)")
        reload()
        settleLink(reason: "link settings")
        applyRemoteAnchor(reason: "link settings")
    }

    /// Puts this device on the link under `name`, or renames it there.
    func enrollDevice(name: String) {
        DeviceLink.enroll(name: name, now: state.now)
        SharedStore.log("link: joined as \(DeviceLink.name)")
        refreshLink()
        applyRemoteAnchor(reason: "joined the link")
        settleLink(reason: "joined the link")
    }

    /// Takes this device off the link. Why not, or nil.
    func leaveLink() -> String? {
        if let refusal = DeviceLink.leave(anchorHoldsHere: state.config.anchor.isHolding(at: state.now), now: state.now) {
            return refusal.message
        }
        outgoing = []
        arrivals = []
        refreshLink()
        return nil
    }

    /// Takes another device off the link from here. Why not, or nil.
    func revokeDevice(_ id: String) -> String? {
        if let refusal = DeviceLink.revoke(id, anchorHoldsHere: state.config.anchor.isHolding(at: state.now), now: state.now) {
            return refusal.message
        }
        refreshLink()
        return nil
    }

    /// Settles what this phone owes: links companion sites (Always mode) first, then
    /// sends/offers pending additions — in that order, so a freshly named app goes out with
    /// its site already linked.
    func settleLink(reason: String) {
        autoLinkCompanions(reason: reason)
        outgoing = LinkFlow.settleAwaiting(config: state.config, now: state.now) {
            // Only what the anchor still holds, so a name learned for something since taken
            // off the list cannot send it.
            SharedStore.pruneAnchorNames(keeping: state.config.anchor.kinds)
            return SharedStore.anchorNames()
        }
        isEnrolled = DeviceLink.isEnrolled
    }

    /// Whether `target` is a picked app told Always that Furlough cannot name yet — so the site
    /// is owed and not here, and the editor should say why.
    func awaitsName(_ target: Target) -> Bool {
        guard state.config.link.companionSite == .always, case .application = target.kind else { return false }
        return learnedName(of: target) == nil && !companionDismissed.contains(target.id.uuidString)
    }

    /// Links sites onto named apps under Always mode. Removing later goes through `unlink`
    /// (free within the undo window, a loosening after).
    private func autoLinkCompanions(reason: String) {
        guard state.config.link.companionSite == .always else { return }
        var current = SharedStore.load()
        var linked: [String] = []
        for target in state.config.targets where !companionDismissed.contains(target.id.uuidString) {
            guard case .sites(let hosts) = companion(for: target),
                  let index = current.config.targets.firstIndex(where: { $0.id == target.id })
            else { continue }
            for host in hosts where current.config.target(host: host) == nil {
                current.config.targets[index].also = (current.config.targets[index].also ?? []) + [.host(host)]
                linked.append(host)
            }
        }
        guard !linked.isEmpty else { return }
        SharedStore.save(current)
        SharedStore.log("linked the site beside the app, as told: \(linked.joined(separator: ", ")) (\(reason))")
        enforce(reason: "companion site")
    }

    /// Sends one the person said yes to.
    func sendOutgoing(_ addition: SharedAddition) {
        LinkFlow.send(addition, now: state.now)
        outgoing.removeAll { $0.id == addition.id }
    }

    /// Not this one, and not asked again.
    func declineOutgoing(_ addition: SharedAddition) {
        LinkFlow.decline(addition)
        outgoing.removeAll { $0.id == addition.id }
    }

    /// Lands one the person said yes to. What it did, for the alert; the phone cannot add the
    /// app half itself, so where one is named the editor's nudge takes over from here.
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
        if landing.appNeedsPicker {
            message += landing.addition.half == .anchor
                ? " Only Apple's picker can add the \(landing.addition.title) app itself: Change apps on this screen. Furlough adds it without asking where Screen Time data access lets it match the name."
                : " The \(landing.addition.title) app needs Apple's picker; its row offers it."
        }
        // Off the critical path — needs a Screen Time query, and the message above is already
        // honest without it.
        if landing.appNeedsPicker, landing.addition.half == .anchor {
            Task { await anchorArrivalsFromTheTables() }
        }
        return message
    }

    /// Not this one, and not asked again.
    func declineArrival(_ landing: SharedAdditions.Landing) {
        SharedAdditions.decline(landing.addition)
        arrivals.removeAll { $0.addition.id == landing.addition.id }
    }

    /// Called by the Weigh Anchor intent. Deferred until foreground: the intent can run before
    /// or after the scene activates, and NFC only works in the foreground, so whichever happens
    /// second triggers the scan.
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

    /// Pairs a new tag. Refused while anchored or past the cap (checked twice — before and
    /// after the scan, since state can move during the long await). No delay: only possible
    /// while unanchored.
    func pairTag() async -> AnchorOutcome {
        if let refusal = state.config.anchor.pairingRefusal { return .failed(refusal) }
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the tag you want to pair.")
        } catch {
            return outcome(for: error)
        }
        return pair(identifier: scanned)
    }

    /// Pairs a tag already read. Cap and lock are re-checked here since the scan is a long
    /// await during which state can move.
    @discardableResult
    func pair(identifier scanned: Data) -> AnchorOutcome {
        var current = SharedStore.load()
        if let refusal = current.config.anchor.pairingRefusal { return .failed(refusal) }
        // Scanning a tag already paired is a mistake worth naming, not a second identical key.
        if let already = current.config.anchor.tag(matching: scanned) {
            return .failed("That tag is already paired, as \(already.name).")
        }
        let isFirst = current.config.anchor.tags.isEmpty
        let tag = PairedTag(id: scanned, name: current.config.anchor.nextTagName)
        current.config.anchor.tags.append(tag)
        SharedStore.save(current)
        SharedStore.log("paired an anchor tag: \(tag.name)")
        reload()
        // Both pairing entry points land here, so the placement screen is raised once from the
        // model rather than from each view. See `TagPlacementView`.
        if isFirst, !hasSeenTagPlacement { noteTagPlacementShown(for: tag) }
        return .paired(tag)
    }

    /// Flag is set immediately (not on dismiss) since a swiped-away sheet still counts as
    /// shown. Delayed by a beat because SwiftUI drops a sheet presented while an alert is still
    /// dismissing — one pairing path is an alert.
    private func noteTagPlacementShown(for tag: PairedTag) {
        UserDefaults.standard.set(true, forKey: Self.tagPlacementKey)
        hasSeenTagPlacement = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            placingTagID = tag.id
        }
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
        if let scan = error as? TagScanner.ScanError, scan.isQuiet { return .cancelled }
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

    /// Changes a target's tier. Toward hazard (longer delay) lands now; toward essential
    /// (shorter delay) queues behind the *current* delay, preventing "reclassify then loosen"
    /// as a bypass. First tier is free, like a first rule.
    func setUtility(_ level: Utility, for id: UUID) -> ProposalResult {
        var current = SharedStore.load()
        guard let target = current.config.target(id: id) else { return .unchanged }
        let queued = current.pending.contains { change in
            if case .setUtility(let targetID, _) = change.kind { return targetID == id }
            return false
        }
        let plan = Policy.plan(utility: level, for: target, queued: queued)
        guard plan != .unchanged else { return .unchanged }
        // A new change replaces any queued one rather than stacking on it.
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

    /// Testing-only: wipes all state and revokes Screen Time access so the phone matches a
    /// fresh install (onboarding, usage step, Home). `restartsOnboarding` — not the async,
    /// possibly-refused revoke — is what the root actually reads, since only a fresh grant
    /// clears it. Notification permission and the activity log are kept. Compiled out of App
    /// Store builds — see `TestingTools`.
    func resetEverything() {
        SharedStore.reset()
        ShieldReconciler.clearEverything()
        // A stale drop left in iCloud would anchor the phone again on its next pull.
        AnchorCloud.clear()
        DeviceLink.forget()
        LinkFlow.forget()
        outgoing = []
        arrivals = []
        refreshLink()
        companionDismissed = []
        UserDefaults.standard.removeObject(forKey: AppModel.companionDismissedKey)
        // Reset everything that tracks "has this been shown" rather than "is this blocked".
        UserDefaults.standard.set(false, forKey: Self.wasAuthorizedKey)
        UserDefaults.standard.removeObject(forKey: Self.usageStepKey)
        hasSeenUsageStep = false
        showsUsageStep = false
        UserDefaults.standard.removeObject(forKey: Self.startHalfKey)
        UserDefaults.standard.removeObject(forKey: Self.bothHalvesKey)
        startHalf = .rules
        wantsBothHalves = false
        UserDefaults.standard.removeObject(forKey: Self.anchorPageAddsKey)
        anchorPageAdds = .anchor
        UserDefaults.standard.removeObject(forKey: Self.autoArmsReaderKey)
        autoArmsReader = false
        // A reset takes the tags with it, so the next pairing is a first pairing again.
        UserDefaults.standard.removeObject(forKey: Self.tagPlacementKey)
        hasSeenTagPlacement = false
        placingTagID = nil
        // Removed rather than set true: absent is what a fresh install has, and a fresh
        // install's answer is yes.
        PendingNotifications.forgetWeeklyDigest()
        weeklyDigest = true
        // Removed rather than emptied: absent is what "never asked" means, so both guides come
        // round again on next launch.
        UserDefaults.standard.removeObject(forKey: Self.finishedGuidesKey)
        finishedGuides = []
        UserDefaults.standard.set(true, forKey: Self.restartsOnboardingKey)
        restartsOnboarding = true
        lastError = nil
        SharedStore.log("reset everything (Debug build)")
        // Before the revoke: this is the last moment the shields can be lifted through an
        // access iOS is still honouring.
        enforce(reason: "reset")
        Task { await revokeAuthorization() }
    }

    /// Hands Screen Time access back to iOS. Quiet when iOS refuses — the onboarding screen and
    /// its re-request button work either way.
    private func revokeAuthorization() async {
        await withCheckedContinuation { continuation in
            AuthorizationCenter.shared.revokeAuthorization { result in
                if case .failure(let error) = result {
                    SharedStore.log("revoking Screen Time access failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
        note(AuthorizationCenter.shared.authorizationStatus)
        SharedStore.log("reset: Screen Time access is \(isAuthorized ? "still granted" : "handed back")")
    }

    /// Clears `restartsOnboarding` on grant only — clearing it in `note()` generally would hide
    /// onboarding even when iOS refused the revoke.
    private func finishOnboardingRestart() {
        guard restartsOnboarding else { return }
        UserDefaults.standard.set(false, forKey: Self.restartsOnboardingKey)
        restartsOnboarding = false
    }
    #endif
}
