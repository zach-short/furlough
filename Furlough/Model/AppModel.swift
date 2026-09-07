import FamilyControls
import Foundation
import ManagedSettings
import Observation
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
    var authorization = AuthorizationCenter.shared.authorizationStatus
    var state = SharedStore.load()
    var lastError: String?
    var notificationsGranted: Bool?
    let isAppGroupAvailable = SharedStore.isAppGroupAvailable
    private let scanner = TagScanner()

    var isAuthorized: Bool {
        switch authorization {
        case .approved: true
        case .notDetermined, .denied: false
        default: true // approvedWithDataAccess (iOS 26.4+) and any future approved variants
        }
    }

    // MARK: Lifecycle

    func activate() {
        authorization = AuthorizationCenter.shared.authorizationStatus
        reload()
        Task { await refreshNotificationStatus() }
        guard isAuthorized else { return }
        enforce(reason: "app active")
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access failed: \(error.localizedDescription)"
        }
        authorization = AuthorizationCenter.shared.authorizationStatus
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

    /// Re-derives everything from persisted state: folds in due pending changes, re-registers
    /// DeviceActivity schedules, and re-applies shields. Safe to call at any time.
    func enforce(reason: String) {
        var current = SharedStore.load()
        if Policy.applyDuePending(&current, now: .now) {
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
                lines.append("\(removalsScheduled) removal(s) take effect \(effectiveAt.formatted(date: .abbreviated, time: .shortened)). Cancel them from the pending list if you change your mind.")
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

        let effectiveAt = Date.now.addingTimeInterval(current.config.loosenDelay)
        for target in current.config.targets where !selected.contains(target.kind) {
            if target.rule == nil {
                current.config.targets.removeAll { $0.id == target.id }
                continue
            }
            let alreadyPending = current.pending.contains { $0.kind == .removeTarget(targetID: target.id) }
            guard !alreadyPending else { continue }
            current.pending.append(PendingChange(kind: .removeTarget(targetID: target.id), effectiveAt: effectiveAt))
            outcome.removalsScheduled += 1
        }
        if outcome.removalsScheduled > 0 { outcome.effectiveAt = effectiveAt }

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
        let target = current.config.targets[index]

        var result = ProposalResult.unchanged
        if target.rule != rule {
            current.pending.removeAll { change in
                if case .setRule(let targetID, _) = change.kind { return targetID == id }
                return false
            }
            if Policy.classify(newRule: rule, against: target) == .tightening {
                current.config.targets[index].rule = rule
                result = .appliedNow
            } else {
                let effectiveAt = Date.now.addingTimeInterval(current.config.loosenDelay)
                current.pending.append(PendingChange(kind: .setRule(targetID: id, rule: rule), effectiveAt: effectiveAt))
                result = .scheduled(effectiveAt)
            }
        }
        SharedStore.save(current)
        SharedStore.log("rule edit for \(id): \(result)")
        enforce(reason: "rule edit")
        return result
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
            let effectiveAt = Date.now.addingTimeInterval(current.config.loosenDelay)
            current.pending.append(PendingChange(kind: .removeTarget(targetID: id), effectiveAt: effectiveAt))
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        enforce(reason: "remove target")
        return result
    }

    // MARK: Brick

    enum BrickOutcome: Equatable {
        case bricked, unbricked, paired, wrongTag, cancelled, failed(String)
    }

    var brickSelection: FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        for kind in state.config.brick.kinds {
            switch kind {
            case .application(let token): selection.applicationTokens.insert(token)
            case .webDomain(let token): selection.webDomainTokens.insert(token)
            case .category(let token): selection.categoryTokens.insert(token)
            }
        }
        return selection
    }

    /// Replaces what the brick holds. Refused while bricked, so nothing loosens under a lock.
    func setBrickSelection(_ selection: FamilyActivitySelection) {
        var current = SharedStore.load()
        guard !current.config.brick.isBricked else { return }
        var kinds: [TargetKind] = []
        kinds += selection.applicationTokens.map(TargetKind.application)
        kinds += selection.webDomainTokens.map(TargetKind.webDomain)
        kinds += selection.categoryTokens.map(TargetKind.category)
        guard kinds != current.config.brick.kinds else { return }
        current.config.brick.kinds = kinds
        SharedStore.save(current)
        SharedStore.log("brick: now holds \(kinds.count) item(s)")
        enforce(reason: "brick edit")
    }

    /// Bricking is tightening, so it needs no tag. It does need a paired tag to exist, or there
    /// would be no way back.
    func brick() -> BrickOutcome {
        var current = SharedStore.load()
        guard current.config.brick.canBrick else {
            return current.config.brick.isBricked ? .bricked : .failed("Choose apps and pair a tag first.")
        }
        current.config.brick.isBricked = true
        current.config.brick.brickedAt = .now
        SharedStore.save(current)
        SharedStore.log("bricked \(current.config.brick.count) item(s)")
        enforce(reason: "brick")
        return .bricked
    }

    /// The only unblock in Furlough: scans the paired tag and, if it matches, lifts the brick.
    func unbrickWithTag() async -> BrickOutcome {
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the Furlough tag to unbrick.")
        } catch {
            return outcome(for: error)
        }
        var current = SharedStore.load()
        guard current.config.brick.isBricked else { return .unbricked }
        guard let paired = current.config.brick.tagID, paired == scanned else {
            SharedStore.log("unbrick refused: not the paired tag")
            return .wrongTag
        }
        current.config.brick.isBricked = false
        current.config.brick.brickedAt = nil
        SharedStore.save(current)
        SharedStore.log("unbricked with the paired tag")
        enforce(reason: "unbrick")
        return .unbricked
    }

    /// Pairs (or replaces) the tag. Refused while bricked, or any tag could become the key.
    func pairTag() async -> BrickOutcome {
        guard !state.config.brick.isBricked else { return .failed("Unbrick first.") }
        let scanned: Data
        do {
            scanned = try await scanner.scan(prompt: "Hold your iPhone to the tag you want to pair.")
        } catch {
            return outcome(for: error)
        }
        var current = SharedStore.load()
        guard !current.config.brick.isBricked else { return .failed("Unbrick first.") }
        current.config.brick.tagID = scanned
        SharedStore.save(current)
        SharedStore.log("paired a brick tag")
        reload()
        return .paired
    }

    func unpairTag() {
        SharedStore.mutate { state in
            guard !state.config.brick.isBricked else { return }
            state.config.brick.tagID = nil
        }
        SharedStore.log("forgot the brick tag")
        reload()
    }

    private func outcome(for error: any Error) -> BrickOutcome {
        if let scan = error as? TagScanner.ScanError, scan == .cancelled { return .cancelled }
        return .failed(error.localizedDescription)
    }

    func cancelPending(id: UUID) {
        SharedStore.mutate { $0.pending.removeAll { $0.id == id } }
        SharedStore.log("cancelled pending change \(id)")
        enforce(reason: "cancel pending")
    }

    func setDelay(hours: Int) -> ProposalResult {
        var current = SharedStore.load()
        let clamped = max(1, hours)
        guard clamped != current.config.loosenDelayHours else { return .unchanged }
        current.pending.removeAll { if case .setDelay = $0.kind { return true }; return false }
        var result = ProposalResult.unchanged
        if clamped > current.config.loosenDelayHours {
            current.config.loosenDelayHours = clamped
            result = .appliedNow
        } else {
            let effectiveAt = Date.now.addingTimeInterval(current.config.loosenDelay)
            current.pending.append(PendingChange(kind: .setDelay(hours: clamped), effectiveAt: effectiveAt))
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        enforce(reason: "delay edit")
        return result
    }
}
