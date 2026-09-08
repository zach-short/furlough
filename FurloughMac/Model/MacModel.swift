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
    /// Which browsers are running and whether Furlough may read their address bar.
    var browserAccess: [BrowserAccess] = []
    let enforcer = Enforcer.shared

    private static let onboardedKey = "furlough.mac.onboarded"

    // MARK: Lifecycle

    func start() {
        SharedStore.log("fonts: \(NSFont(name: "Onest-Regular", size: 12) == nil ? "MISSING, check ATSApplicationFontsPath" : "ok")")
        if SharedStore.defaults.bool(forKey: "furlough.mac.migrated") {
            SharedStore.defaults.removeObject(forKey: "furlough.mac.migrated")
            SharedStore.log("moved the store into the App Group for the widget")
        }
        // The enforcer changes state on its own (a budget spent, a pending change landing),
        // and the widget draws from that state, so every change refreshes it.
        enforcer.onChange = { [weak self] in
            self?.reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
        enforcer.start()
        reload()
        Task { await refreshNotificationStatus() }
        refreshBrowserAccess()
        enforce(reason: "launch")
    }

    func finishOnboarding() {
        SharedStore.defaults.set(true, forKey: Self.onboardedKey)
        isOnboarded = true
        setLaunchAtLogin(true)
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

    func reload() {
        state = SharedStore.load()
    }

    /// Re-derives everything from persisted state: folds in due pending changes and makes
    /// the Mac match the rules. Safe to call at any time.
    func enforce(reason: String) {
        var current = SharedStore.load()
        if Policy.applyDuePending(&current, now: .now) {
            SharedStore.log("applied due pending changes (\(reason))")
        }
        current.runtime.lastRegistration = .now
        SharedStore.save(current)
        enforcer.reconcile(reason: reason)
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
        let target = Target(kind: .macApp(bundleID: bundleID), nickname: name)
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
        let target = Target(kind: .host(host), nickname: host)
        current.config.targets.append(target)
        SharedStore.save(current)
        SharedStore.log("added site \(host)")
        enforce(reason: "add site")
        return AddOutcome(added: target, message: "Added. Set a schedule; nothing is enforced until you do.")
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

    /// The name shown for the target at `index`: the trimmed nickname, or the app's own name
    /// when that is empty.
    private static func rename(_ index: Int, to nickname: String, in state: inout SharedState) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        state.config.targets[index].nickname = trimmed.isEmpty ? state.config.targets[index].defaultName : trimmed
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
        let effectiveAt = Date.now.addingTimeInterval(state.config.loosenDelay)
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
            let effectiveAt = Date.now.addingTimeInterval(current.config.loosenDelay)
            current.pending.append(PendingChange(kind: .removeTarget(targetID: id), effectiveAt: effectiveAt))
            result = .scheduled(effectiveAt)
        }
        SharedStore.save(current)
        enforce(reason: "remove target")
        return result
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

    #if DEBUG
    // MARK: Testing

    /// Wipes every target, rule and pending change, forgets today's counted usage, and
    /// enforces the empty state so the app matches a fresh install that is still onboarded.
    /// Compiled into Debug builds only: a Release build keeps its promise of no unblock button.
    func resetEverything() {
        SharedStore.reset()
        enforcer.resetUsage()
        SharedStore.log("reset everything (Debug build)")
        lastError = nil
        enforce(reason: "reset")
    }
    #endif
}

// MARK: - Mac lookups on the shared model

extension Config {
    func target(bundleID: String) -> Target? {
        targets.first { $0.kind == .macApp(bundleID: bundleID) }
    }

    /// The target whose host is `host` or a parent domain of it: "m.youtube.com" matches "youtube.com".
    func target(host: String) -> Target? {
        let host = host.lowercased()
        return targets
            .filter { if case .host(let h) = $0.kind { return Hosts.matches(host, rule: h) }; return false }
            .max { a, b in a.host.count < b.host.count }
    }
}

extension TargetKind {
    var isHost: Bool {
        if case .host = self { return true }
        return false
    }
}

extension Target {
    var bundleID: String? {
        if case .macApp(let id) = kind { return id }
        return nil
    }

    var host: String {
        if case .host(let h) = kind { return h }
        return ""
    }
}

enum Hosts {
    /// "https://www.YouTube.com/watch?v=1" becomes "youtube.com"; nil when there is no host in it.
    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), var host = url.host(), host.contains(".") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }

    static func matches(_ host: String, rule: String) -> Bool {
        let host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return host == rule || host.hasSuffix("." + rule)
    }
}
