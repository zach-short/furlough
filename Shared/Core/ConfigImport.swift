import Foundation

/// A setup file coming back in. An import is a proposal, never a restore — every rule and tier
/// goes through the same gate the editor does, so a hand-edited file can't shortcut the delay.
/// The Anchor, `pending`, and `runtime` are never read: importing them would bypass the delay or
/// un-spend the day. Unknown keys are ignored quietly, which also lets an older file still open.
/// `plan` decides, `apply` performs, so a whole import can be reviewed before anything happens.
enum ConfigImport {
    /// Ceilings for refusing a hand-written file quickly, not shapes Furlough itself writes.
    static let maxFileBytes = 1_000_000
    static let maxTargets = 500
    static let maxWindowsPerRule = 128
    /// Longer than any real identifier; short enough to block padding a file with one giant string.
    static let maxIdentifierLength = 253
    /// Matches the Settings stepper's top; anything outside it was typed by hand.
    static let maxLoosenDelayHours = 168

    enum Refusal: Error, Equatable {
        case couldNotOpen(String)
        case tooBig(bytes: Int)
        case tooMany(targets: Int)
        case unreadable
        /// Written by a Furlough that knows a shape this one does not.
        case fromTheFuture(version: Int)
        /// A phone file on a Mac, or a Mac file on a phone.
        case wrongPlatform(ConfigExport.Platform)

        /// Says what the file is and what to do, not which key failed.
        var message: String {
            switch self {
            case .couldNotOpen(let why):
                return "Furlough could not open that file: \(why)"
            case .tooBig(let bytes):
                return "That file is \(bytes) bytes. A Furlough setup is a few kilobytes, so this is not one."
            case .tooMany(let targets):
                return "That file lists \(targets) apps. Furlough has never written one with more than \(ConfigImport.maxTargets), so this is not a setup it made."
            case .unreadable:
                return "This is not a Furlough setup file, or it has been edited into something Furlough cannot read."
            case .fromTheFuture(let version):
                return "This file was written by a newer Furlough — it is version \(version), and this Furlough reads version \(ConfigExport.currentVersion). Update Furlough and open it again. Reading half of a file is worse than not reading it."
            case .wrongPlatform(.iOS):
                return "This setup came from an iPhone. Screen Time names an app with a token that means nothing off the phone that issued it, so there is nothing in this file for a Mac to look up. Export from the Mac you want to copy."
            case .wrongPlatform(.mac):
                return "This setup came from a Mac. Its apps are bundle identifiers and its websites are hosts, and iOS gives Furlough no way to turn either into something it can shield. Export from the iPhone you want to copy."
            }
        }
    }

    /// Platform is checked before decode so a mismatch gives one clear sentence instead of a
    /// decode error (`TargetKind`'s cases differ between the two builds).
    static func read(_ data: Data) throws(Refusal) -> ConfigExport {
        guard data.count <= maxFileBytes else { throw .tooBig(bytes: data.count) }
        let export: ConfigExport
        do {
            export = try ConfigExport.decode(data)
        } catch {
            // May not decode at all if written by a newer Furlough; report the version instead
            // of a meaningless key.
            if let version = peekVersion(data), version > ConfigExport.currentVersion {
                throw .fromTheFuture(version: version)
            }
            throw .unreadable
        }
        guard export.version <= ConfigExport.currentVersion else {
            throw .fromTheFuture(version: export.version)
        }
        guard export.platform == .current else { throw .wrongPlatform(export.platform) }
        guard export.targets.count <= maxTargets else { throw .tooMany(targets: export.targets.count) }
        return export
    }

    /// On iOS, `.fileImporter`'s URL is security-scoped and must be opened/closed around the
    /// read or it comes back empty. The Mac doesn't need this but does it anyway to keep one path.
    static func read(contentsOf url: URL) throws(Refusal) -> ConfigExport {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .couldNotOpen(error.localizedDescription)
        }
        return try read(data)
    }

    /// Best-effort version read for a file that fails full decode.
    private static func peekVersion(_ data: Data) -> Int? {
        struct Peek: Decodable { var version: Int? }
        return (try? JSONDecoder().decode(Peek.self, from: data))?.version
    }

    /// Why an imported rule is invalid, or nil. Reuses `Rule.validationError` (what the editor
    /// enforces) plus window-count/budget-range checks the editor's own controls can't violate
    /// but a hand-typed file can.
    static func problem(with rule: Rule) -> String? {
        if rule.windows.count > maxWindowsPerRule {
            return "It has \(rule.windows.count) windows. Furlough writes at most \(maxWindowsPerRule)."
        }
        if let error = rule.validationError { return error }
        // budget(on:) falls back to one daily figure if per-day budgets weren't set.
        guard (1...7).allSatisfy({ (0...Furlough.minutesPerDay).contains(rule.budget(on: $0)) }) else {
            return "A daily budget has to be between 0 and \(Furlough.minutesPerDay) minutes."
        }
        return nil
    }
}

/// What a file's target resolves to on this device. The Mac matches itself
/// (`ConfigImport.matches(for:config:)`); the phone can't (Screen Time tokens are per-device)
/// and walks the person through a picker instead.
enum ImportResolution: Equatable {
    case existing(UUID)
    /// Caller builds the kind, since only it knows the platform's target shape.
    case create(TargetKind)
    /// Left out, with why — e.g. a Mac category, an unreadable website, a declined picker row.
    case skipped(String)
}

struct ImportMatch: Equatable {
    var exported: ExportedTarget
    var resolution: ImportResolution

    /// Nickname, then system name, then identifier — whichever exists first.
    var name: String {
        if let nickname = exported.nickname, !nickname.isEmpty { return nickname }
        if let name = exported.name, !name.isEmpty { return name }
        if let identifier = exported.identifier, !identifier.isEmpty { return identifier }
        return switch exported.kind {
        case .app: "This app"
        case .website: "This website"
        case .category: "This category"
        }
    }
}

/// Everything an import would do, decided but not done — reviewed before it's applied since
/// half of it may be invisible for a day. `items` is what to show; `edits` is what to do.
struct ImportPlan: Equatable {
    /// Which part of a row a line is about.
    enum Subject: Equatable {
        case target
        case rule
        case tier
        case name
        case delay
        /// A website folded into a row rather than added as one of its own.
        case half

        var label: String {
            switch self {
            case .target: "Added"
            case .rule: "Rule"
            case .tier: "Tier"
            case .name: "Name"
            case .delay: "Loosening delay"
            case .half: "Also blocks"
            }
        }

        /// Whether the label adds info beyond the row's own name — true for rule/tier/name/half,
        /// which can share a row with other parts.
        var isWorthNaming: Bool { self == .rule || self == .tier || self == .name || self == .half }
    }

    enum Outcome: Equatable {
        /// In force as soon as the import is applied.
        case now
        /// Waiting out the delay, and when it lands.
        case queued(Date)
        /// In the file, not used, and why.
        case skipped(String)
    }

    struct Item: Equatable {
        var name: String
        var subject: Subject
        var outcome: Outcome
        var delta: PendingText.Delta? = nil
    }

    /// One decided change. Not a state snapshot — between review and apply the enforcer may
    /// have spent budget or landed a queued change, and overwriting that would un-spend the day.
    enum Edit: Equatable {
        /// Name and tier come with it (neither enforces); its rule still goes through the
        /// normal gate.
        case addTarget(Target)
        /// Cosmetic, so it is not gated.
        case setNickname(targetID: UUID, String)
        /// A tightening (more blocked than before), lands at once. Hosts only — a picked
        /// website's token can't travel, see `ExportedTarget.alsoBlocks`.
        case link(targetID: UUID, hosts: [String])
        case applyNow(PendingKind)
        case queue(PendingChange)
    }

    /// When the plan was made; `apply` counts queued waits from here so an open review doesn't
    /// serve time.
    var plannedAt: Date
    var items: [Item] = []
    var edits: [Edit] = []
    /// Targets the file says nothing about. Left alone (dropping would be a loosening) but
    /// named for the confirmation.
    var untouched: [String] = []
    /// When/by which build the file was written. Carried on the plan so the shared review view
    /// needs only the plan.
    var exportedAt: Date? = nil
    var appVersion: String? = nil
    /// Why this import can't be registered. Checked here because `Monitoring.register` (iOS,
    /// 19-span ceiling) runs *after* save — catching it late would leave the import applied but
    /// unmonitored. Always nil on the Mac.
    var limitReason: String? = nil

    var isEmpty: Bool { edits.isEmpty }
    /// Over the ceiling is worse than empty: it would leave rules in force with no monitor
    /// watching them.
    var canApply: Bool { !isEmpty && limitReason == nil }
    var added: [Item] { items.filter { $0.subject == .target && $0.outcome == .now } }
    var immediate: [Item] { items.filter { $0.outcome == .now && $0.subject != .target } }
    var queued: [Item] { items.filter { if case .queued = $0.outcome { return true }; return false } }
    var skipped: [Item] { items.filter { if case .skipped = $0.outcome { return true }; return false } }

    /// The furthest out anything in this plan lands.
    var lastEffectiveAt: Date? {
        items.compactMap { if case .queued(let date) = $0.outcome { return date }; return nil }.max()
    }

    var headline: String {
        guard !isEmpty else { return "There is nothing in this file that is not already set up here." }
        var parts: [String] = []
        if !added.isEmpty {
            parts.append(added.count == 1 ? "1 app or website is new" : "\(added.count) apps and websites are new")
        }
        if !immediate.isEmpty {
            parts.append(immediate.count == 1 ? "1 change applies now" : "\(immediate.count) changes apply now")
        }
        if !queued.isEmpty {
            parts.append(queued.count == 1
                ? "1 loosens your rules, so it waits out the delay"
                : "\(queued.count) loosen your rules, so they wait out the delay")
        }
        let sentence = UtilityText.list(parts)
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
    }

    /// Past-tense version of `headline`, for the post-apply alert — needed because half an
    /// import is invisible until it lands, and a silent close invites a second press. Kept
    /// separate from `headline` (a review, not a result) so the two can't drift apart unnoticed.
    var confirmation: String {
        guard !isEmpty else { return "There was nothing in that file that was not already set up here, so nothing changed." }
        var parts: [String] = []
        if !added.isEmpty {
            parts.append(added.count == 1 ? "1 app or website is now managed" : "\(added.count) apps and websites are now managed")
        }
        if !immediate.isEmpty {
            parts.append(immediate.count == 1 ? "1 change is in force" : "\(immediate.count) changes are in force")
        }
        if !queued.isEmpty {
            parts.append(queued.count == 1
                ? "1 loosening is waiting out the delay"
                : "\(queued.count) loosenings are waiting out the delay")
        }
        let sentence = UtilityText.list(parts)
        var said = sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
        // Include the date — otherwise the only way to find out is the Pending screen.
        if let last = lastEffectiveAt {
            let when = last.formatted(date: .abbreviated, time: .shortened)
            said += queued.count == 1 ? " It takes effect \(when)." : " The last of them takes effect \(when)."
        }
        return said
    }
}

extension ConfigImport {
    /// Judges the file's changes in the same order and by the same rules the editors would use
    /// by hand: base delay, then each target's tier, then its rule (against the tier as it now
    /// stands). `now` is Furlough's own clock, never the device's.
    static func plan(
        _ export: ConfigExport,
        matches: [ImportMatch],
        state: SharedState,
        now: Date
    ) -> ImportPlan {
        var plan = ImportPlan(plannedAt: now)
        plan.exportedAt = export.exportedAt
        plan.appVersion = export.appVersion
        // Scratch copy for classifying later changes in this import against earlier ones; never saved.
        var working = state.config

        planDelay(export, in: &working, plan: &plan, now: now)

        var claimed = Set<UUID>()
        for match in matches {
            let name = match.name
            switch match.resolution {
            case .skipped(let why):
                plan.items.append(.init(name: name, subject: .target, outcome: .skipped(why)))
                continue
            case .existing(let id):
                guard working.target(id: id) != nil else {
                    plan.items.append(.init(
                        name: name,
                        subject: .target,
                        outcome: .skipped("Furlough no longer has it.")
                    ))
                    continue
                }
                guard claimed.insert(id).inserted else {
                    plan.items.append(.init(
                        name: name,
                        subject: .target,
                        outcome: .skipped("The file lists it more than once.")
                    ))
                    continue
                }
                planTarget(match, id: id, isNew: false, in: &working, plan: &plan, state: state, now: now)
            case .create(let kind):
                guard working.target(kind: kind) == nil else {
                    plan.items.append(.init(
                        name: name,
                        subject: .target,
                        outcome: .skipped("The file lists it more than once.")
                    ))
                    continue
                }
                // Named and tiered on the way in: neither enforces anything, and a target
                // nobody has tiered is a different fact from one he called useful, which the
                // file keeps apart and so should this. The rule is not set here — it goes
                // through the gate below like every other rule.
                var target = Target(kind: kind)
                target.systemName = match.exported.name
                target.nickname = match.exported.nickname ?? ""
                target.utilityLevel = match.exported.utility?.utility
                working.targets.append(target)
                claimed.insert(target.id)
                plan.edits.append(.addTarget(target))
                // One line for a new target, not three: what it will be is its rule, and its
                // name and tier are on it already. A rule the file got wrong still gets a line
                // of its own below, which is the only case where the two differ.
                plan.items.append(.init(
                    name: name,
                    subject: .target,
                    outcome: .now,
                    delta: PendingText.Delta(
                        now: "Not managed by Furlough",
                        becomes: TimeFormat.rule(match.exported.rule.flatMap { problem(with: $0) == nil ? $0 : nil })
                    )
                ))
                planTarget(match, id: target.id, isNew: true, in: &working, plan: &plan, state: state, now: now)
            }
        }

        plan.untouched = state.config.targets
            .filter { !claimed.contains($0.id) }
            .map(\.displayName)
        return plan
    }

    /// The base delay, judged the way the Settings stepper does it.
    private static func planDelay(
        _ export: ConfigExport,
        in working: inout Config,
        plan: inout ImportPlan,
        now: Date
    ) {
        let hours = export.loosenDelayHours
        // Refused, not clamped — silently rounding would mean reading a file that doesn't exist.
        guard (Furlough.minimumLoosenDelayHours...maxLoosenDelayHours).contains(hours) else {
            plan.items.append(.init(
                name: "Loosening delay",
                subject: .delay,
                outcome: .skipped("The file says \(hours) hours, and the delay runs from \(Furlough.minimumLoosenDelayHours) to \(maxLoosenDelayHours).")
            ))
            return
        }
        guard hours != working.loosenDelayHours else { return }
        let kind = PendingKind.setDelay(hours: hours)
        let delta = PendingText.delta(for: PendingChange(kind: kind, effectiveAt: now), in: working)
        if hours > working.loosenDelayHours {
            Policy.apply(PendingChange(kind: kind, effectiveAt: now), to: &working)
            plan.edits.append(.applyNow(kind))
            plan.items.append(.init(name: "Loosening delay", subject: .delay, outcome: .now, delta: delta))
        } else {
            // Cutting the base loosens every target at once, so it waits out the slowest one.
            let effectiveAt = now.addingTimeInterval(working.longestDelay)
            plan.edits.append(.queue(PendingChange(kind: kind, effectiveAt: effectiveAt)))
            plan.items.append(.init(name: "Loosening delay", subject: .delay, outcome: .queued(effectiveAt), delta: delta))
        }
    }

    /// One row of the file, judged name then tier then rule. `isNew` means the caller's own
    /// line already said what this target will be, so nothing here repeats it except a dropped
    /// rule.
    private static func planTarget(
        _ match: ImportMatch,
        id: UUID,
        isNew: Bool,
        in working: inout Config,
        plan: inout ImportPlan,
        state: SharedState,
        now: Date
    ) {
        let name = match.name

        // Not gated (cosmetic). Only ever set, never cleared — a missing nickname isn't a
        // request to forget one.
        if let nickname = match.exported.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nickname.isEmpty,
           let index = working.targets.firstIndex(where: { $0.id == id }),
           nickname != working.targets[index].nickname {
            let before = working.targets[index].nickname
            working.targets[index].nickname = nickname
            plan.edits.append(.setNickname(targetID: id, nickname))
            if !before.isEmpty {
                plan.items.append(.init(
                    name: name,
                    subject: .name,
                    outcome: .now,
                    delta: PendingText.Delta(now: before, becomes: nickname)
                ))
            }
        }

        // A tightening, lands at once. Anything already covered or already its own row is skipped.
        if let index = working.targets.firstIndex(where: { $0.id == id }) {
            let wanted = (match.exported.alsoBlocks ?? [])
                .compactMap(Hosts.normalize)
                .filter { working.target(host: $0) == nil }
            if !wanted.isEmpty {
                for host in wanted {
                    working.targets[index].also = (working.targets[index].also ?? []) + [.host(host)]
                }
                plan.edits.append(.link(targetID: id, hosts: wanted))
                // No separate line when the target is new — its halves are already part of "added".
                if !isNew {
                    plan.items.append(.init(
                        name: name,
                        subject: .half,
                        outcome: .now,
                        delta: PendingText.Delta(now: "Not blocked", becomes: UtilityText.list(wanted))
                    ))
                }
            }
        }

        if let tier = match.exported.utility?.utility, let target = working.target(id: id) {
            let queued = state.pending.contains { change in
                if case .setUtility(let targetID, _) = change.kind { return targetID == id }
                return false
            }
            let kind = PendingKind.setUtility(targetID: id, level: tier)
            let delta = PendingText.delta(for: PendingChange(kind: kind, effectiveAt: now), in: working)
            switch Policy.plan(utility: tier, for: target, queued: queued) {
            case .unchanged:
                break
            case .now:
                Policy.apply(PendingChange(kind: kind, effectiveAt: now), to: &working)
                plan.edits.append(.applyNow(kind))
                plan.items.append(.init(name: name, subject: .tier, outcome: .now, delta: delta))
            case .queue:
                let effectiveAt = now.addingTimeInterval(working.delay(for: target))
                plan.edits.append(.queue(PendingChange(kind: kind, effectiveAt: effectiveAt)))
                plan.items.append(.init(name: name, subject: .tier, outcome: .queued(effectiveAt), delta: delta))
            }
        }

        guard let rule = match.exported.rule else { return }
        if let problem = problem(with: rule) {
            // Dropped, not repaired — guessing at a hand-typed rule is what a commitment
            // device must never do.
            plan.items.append(.init(name: name, subject: .rule, outcome: .skipped(problem)))
            return
        }
        // Read again: the tier above may have landed, and a target's delay is its tier's.
        guard let target = working.target(id: id) else { return }
        guard !(target.rule?.isEquivalent(to: rule) ?? false) else { return }
        let kind = PendingKind.setRule(targetID: id, rule: rule)
        let delta = PendingText.delta(for: PendingChange(kind: kind, effectiveAt: now), in: working)
        if Policy.classify(newRule: rule, against: target) == .tightening {
            Policy.apply(PendingChange(kind: kind, effectiveAt: now), to: &working)
            plan.edits.append(.applyNow(kind))
            guard !isNew else { return }
            plan.items.append(.init(name: name, subject: .rule, outcome: .now, delta: delta))
        } else {
            let effectiveAt = now.addingTimeInterval(working.delay(for: target))
            plan.edits.append(.queue(PendingChange(kind: kind, effectiveAt: effectiveAt)))
            plan.items.append(.init(name: name, subject: .rule, outcome: .queued(effectiveAt), delta: delta))
        }
    }

    /// Applies edits (not a config snapshot) against live state — a snapshot would silently
    /// undo whatever the enforcer did while the review was open. Queued waits count from
    /// `plan.plannedAt`, not now.
    static func apply(_ plan: ImportPlan, to state: inout SharedState, now: Date) {
        let read = max(0, now.timeIntervalSince(plan.plannedAt))
        for edit in plan.edits {
            switch edit {
            case .addTarget(let target):
                guard state.config.target(kind: target.kind) == nil else { continue }
                state.config.targets.append(target)
            case .setNickname(let id, let nickname):
                guard let index = state.config.targets.firstIndex(where: { $0.id == id }) else { continue }
                state.config.targets[index].nickname = nickname
            case .link(let id, let hosts):
                guard let index = state.config.targets.firstIndex(where: { $0.id == id }) else { continue }
                // Re-checked against live state so a site added by hand meanwhile isn't blocked twice.
                for host in hosts where state.config.target(host: host) == nil {
                    state.config.targets[index].also = (state.config.targets[index].also ?? []) + [.host(host)]
                }
            case .applyNow(let kind):
                state.pending.removeAll { supersedes(kind, $0.kind) }
                Policy.apply(PendingChange(kind: kind, effectiveAt: now), to: &state.config)
            case .queue(let change):
                // Diverges from `assign` deliberately: an identical pending change already
                // queued is left alone rather than restarted, because a file (unlike a hand
                // edit) is easy to apply twice and each press would push the loosening further
                // out. Anything that differs at all still supersedes and restarts, below.
                guard !state.pending.contains(where: { $0.kind == change.kind }) else { continue }
                state.pending.removeAll { supersedes(change.kind, $0.kind) }
                var change = change
                change.effectiveAt = change.effectiveAt.addingTimeInterval(read)
                Record.queue(change, in: &state, now: now)
            }
        }
    }

    /// Whether one change should drop another already queued for the same thing — keeps to the
    /// app-wide invariant of at most one pending change per target, which `PendingText` assumes.
    private static func supersedes(_ made: PendingKind, _ queued: PendingKind) -> Bool {
        switch (made, queued) {
        case (.setRule(let a, _), .setRule(let b, _)): a == b
        case (.setUtility(let a, _), .setUtility(let b, _)): a == b
        case (.removeTarget(let a), .removeTarget(let b)): a == b
        case (.setDelay, .setDelay): true
        default: false
        }
    }
}

extension ConfigImport {
    /// What the phone can resolve on its own, before asking. Most rows can't (a Screen Time
    /// token is per-device, per-install, so `ImportSetupView` walks the picker) — except a
    /// `.website` row, which is a plain host string this phone can look up exactly like a Mac
    /// (since 2026-09-08). Everything else comes back `.skipped(unresolved)`, matching the
    /// "not answered yet" state on that screen.
    ///
    /// Grows `config` as it reads so "youtube.com" and "m.youtube.com" in the same file resolve
    /// to one target.
    ///
    /// Not `#if os(iOS)`-gated: nothing here is iOS-only, and the test bundle is macOS.
    static func preresolved(for export: ConfigExport, config: Config, unresolved: String) -> [ImportResolution] {
        var growing = config
        var invented = Set<UUID>()
        return export.targets.map { exported in
            guard exported.kind == .website,
                  let identifier = exported.identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !identifier.isEmpty
            else { return .skipped(unresolved) }
            guard identifier.count <= maxIdentifierLength else {
                return .skipped("The file names it with \(identifier.count) characters, which is not a name anything has.")
            }
            guard let host = Hosts.normalize(identifier) else {
                return .skipped("\"\(identifier)\" is not a website Furlough can read.")
            }
            if let existing = growing.target(host: host) {
                // Matched an earlier row in this same file, not anything already on the phone — a duplicate.
                if invented.contains(existing.id) { return .skipped("The file lists it more than once.") }
                return .existing(existing.id)
            }
            let stub = Target(kind: .host(host))
            growing.targets.append(stub)
            invented.insert(stub.id)
            return .create(.host(host))
        }
    }
}

#if !os(iOS)
extension ConfigImport {
    /// How a Mac file lines up with what's already here. A Mac target (bundle id or host) is a
    /// plain string this Mac can look up itself. Grows `config` as it reads so "youtube.com" and
    /// "m.youtube.com" in the same file resolve to one target rather than two.
    static func matches(for export: ConfigExport, config: Config) -> [ImportMatch] {
        var growing = config
        var invented = Set<UUID>()
        return export.targets.map { exported in
            var resolution = resolve(exported, config: growing)
            switch resolution {
            case .create(let kind):
                let stub = Target(kind: kind)
                growing.targets.append(stub)
                invented.insert(stub.id)
            // Matched an earlier row in this file, not anything already here — a duplicate.
            case .existing(let id) where invented.contains(id):
                resolution = .skipped("The file lists it more than once.")
            case .existing, .skipped:
                break
            }
            return ImportMatch(exported: exported, resolution: resolution)
        }
    }

    private static func resolve(_ exported: ExportedTarget, config: Config) -> ImportResolution {
        guard exported.kind != .category else {
            return .skipped("Categories are a Screen Time idea; the Mac has no such thing.")
        }
        guard let identifier = exported.identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty
        else {
            return .skipped("The file does not say which one this is.")
        }
        guard identifier.count <= maxIdentifierLength else {
            return .skipped("The file names it with \(identifier.count) characters, which is not a name anything has.")
        }
        switch exported.kind {
        case .app:
            if let existing = config.target(bundleID: identifier) { return .existing(existing.id) }
            return .create(.macApp(bundleID: identifier))
        case .website:
            guard let host = Hosts.normalize(identifier) else {
                return .skipped("\"\(identifier)\" is not a website Furlough can read.")
            }
            if let existing = config.target(host: host) { return .existing(existing.id) }
            return .create(.host(host))
        case .category:
            return .skipped("Categories are a Screen Time idea; the Mac has no such thing.")
        }
    }
}
#endif
