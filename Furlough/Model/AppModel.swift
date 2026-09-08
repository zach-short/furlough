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

    var isAuthorized: Bool {
        switch authorization {
        case .approved: true
        case .notDetermined, .denied: false
        default: true // approvedWithDataAccess (iOS 26.4+) and any future approved variants
        }
    }

    // MARK: Lifecycle

    func activate() {
        note(AuthorizationCenter.shared.authorizationStatus)
        reload()
        Task { await refreshNotificationStatus() }
        // Before the authorization guard: a tag scan is how the anchor is lifted, and it has
        // to work even on a launch where FamilyControls has not answered yet.
        weighAnchorIfInFront()
        guard isAuthorized else { return }
        enforce(reason: "app active")
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
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access failed: \(error.localizedDescription)"
        }
        note(AuthorizationCenter.shared.authorizationStatus)
        if isAuthorized { enforce(reason: "authorized") }
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
        reload()
        LiveActivityManager.sync(state: state)
    }

    // MARK: Picker

    var pickerSelection: FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        for target in state.config.targets {
            switch target.kind {
            case .application(let token): selection.applicationTokens.insert(token)
            case .webDomain(let token): selection.webDomainTokens.insert(token)
            case .category(let token): selection.categoryTokens.insert(token)
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
        let existing = Set(current.config.targets.map(\.kind))

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
        for target in current.config.targets where !selected.contains(target.kind) {
            if target.rule == nil {
                current.config.targets.removeAll { $0.id == target.id }
                continue
            }
            let alreadyPending = current.pending.contains { $0.kind == .removeTarget(targetID: target.id) }
            guard !alreadyPending else { continue }
            let effectiveAt = current.now.addingTimeInterval(current.config.delay(for: target))
            current.pending.append(PendingChange(kind: .removeTarget(targetID: target.id), effectiveAt: effectiveAt))
            outcome.removalsScheduled += 1
            outcome.effectiveAt = max(effectiveAt, outcome.effectiveAt ?? effectiveAt)
        }

        SharedStore.save(current)
        SharedStore.log("picker: added \(outcome.added), removals scheduled \(outcome.removalsScheduled)")
        enforce(reason: "picker")
        return outcome
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
            state.config.targets[index].rule = rule
            return .appliedNow
        }
        let effectiveAt = state.now.addingTimeInterval(state.config.delay(for: target))
        state.pending.append(PendingChange(kind: .setRule(targetID: id, rule: rule), effectiveAt: effectiveAt))
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
            current.pending.append(PendingChange(kind: .removeTarget(targetID: id), effectiveAt: effectiveAt))
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        enforce(reason: "remove target")
        return result
    }

    // MARK: Anchor

    enum AnchorOutcome: Equatable {
        case anchored, released, paired, wrongTag, cancelled, failed(String)
    }

    var anchorSelection: FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        for kind in state.config.anchor.kinds {
            switch kind {
            case .application(let token): selection.applicationTokens.insert(token)
            case .webDomain(let token): selection.webDomainTokens.insert(token)
            case .category(let token): selection.categoryTokens.insert(token)
            }
        }
        return selection
    }

    /// Replaces what the anchor holds. Refused while anchored, so nothing loosens under a lock.
    func setAnchorSelection(_ selection: FamilyActivitySelection) {
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored else { return }
        var kinds: [TargetKind] = []
        kinds += selection.applicationTokens.map(TargetKind.application)
        kinds += selection.webDomainTokens.map(TargetKind.webDomain)
        kinds += selection.categoryTokens.map(TargetKind.category)
        guard kinds != current.config.anchor.kinds else { return }
        current.config.anchor.kinds = kinds
        SharedStore.save(current)
        SharedStore.log("anchor: now holds \(kinds.count) item(s)")
        enforce(reason: "anchor edit")
    }

    /// Anchoring is tightening, so it needs no tag. It does need a paired tag to exist, or there
    /// would be no way back.
    func anchor() -> AnchorOutcome {
        var current = SharedStore.load()
        guard current.config.anchor.canAnchor else {
            return current.config.anchor.isAnchored ? .anchored : .failed("Choose apps and pair a tag first.")
        }
        current.config.anchor.isAnchored = true
        current.config.anchor.anchoredAt = current.now
        SharedStore.save(current)
        SharedStore.log("anchored \(current.config.anchor.count) item(s)")
        enforce(reason: "anchor")
        return .anchored
    }

    /// The only unblock in Furlough: scans the paired tag and, if it matches, lifts the anchor.
    func unanchorWithTag() async -> AnchorOutcome {
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the Furlough tag to weigh anchor.")
        } catch {
            return outcome(for: error)
        }
        var current = SharedStore.load()
        guard current.config.anchor.isAnchored else { return .released }
        guard let paired = current.config.anchor.tagID, paired == scanned else {
            SharedStore.log("refused to weigh anchor: not the paired tag")
            return .wrongTag
        }
        current.config.anchor.isAnchored = false
        current.config.anchor.anchoredAt = nil
        SharedStore.save(current)
        SharedStore.log("weighed anchor with the paired tag")
        enforce(reason: "weigh anchor")
        return .released
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
            case .wrongTag: notice = "That is not the paired tag. The anchor holds."
            case .failed(let why): notice = why
            // Cancelling the scan is an answer, not a failure: nothing to say.
            case .anchored, .paired, .cancelled: break
            }
        }
    }

    /// Pairs (or replaces) the tag. Refused while anchored, or any tag could become the key.
    func pairTag() async -> AnchorOutcome {
        guard !state.config.anchor.isAnchored else { return .failed("Unanchor first.") }
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the tag you want to pair.")
        } catch {
            return outcome(for: error)
        }
        var current = SharedStore.load()
        guard !current.config.anchor.isAnchored else { return .failed("Unanchor first.") }
        current.config.anchor.tagID = scanned
        SharedStore.save(current)
        SharedStore.log("paired an anchor tag")
        reload()
        return .paired
    }

    func unpairTag() {
        SharedStore.mutate { state in
            guard !state.config.anchor.isAnchored else { return }
            state.config.anchor.tagID = nil
        }
        SharedStore.log("forgot the anchor tag")
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
            current.pending.append(PendingChange(kind: .setUtility(targetID: id, level: level), effectiveAt: effectiveAt))
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        SharedStore.log("utility for \(id): \(level.label), \(result)")
        enforce(reason: "utility edit")
        return result
    }

    func cancelPending(id: UUID) {
        SharedStore.mutate { $0.pending.removeAll { $0.id == id } }
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
            current.pending.append(PendingChange(kind: .setDelay(hours: clamped), effectiveAt: effectiveAt))
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        enforce(reason: "delay edit")
        return result
    }

    #if DEBUG
    // MARK: Testing

    /// Wipes every target, rule, pending change, the Anchor and its tag, lifts every shield, and
    /// enforces the empty state so the app matches a fresh install. Compiled into Debug builds
    /// only: a Release build keeps its promise of no unblock button.
    func resetEverything() {
        SharedStore.reset()
        ShieldReconciler.clearEverything()
        SharedStore.log("reset everything (Debug build)")
        lastError = nil
        enforce(reason: "reset")
    }
    #endif
}
