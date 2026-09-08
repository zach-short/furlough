import Foundation

/// The other half of `ConfigExport`: a setup file coming back in.
///
/// An import is a *proposal*, never a restore, and that is the whole of the design. Furlough's
/// value is the asymmetry in `Policy`: a tightening applies at once, a loosening waits out the
/// delay. Restoring a file wholesale would be a hole straight through it — export, open the
/// JSON in any text editor, change a 30-minute budget to 1440, import, and the delay is gone
/// in half a minute. So every rule and every tier in a file goes through the very same gate
/// the rule editor goes through, and the file is only ever a source of proposed values.
///
/// What that leaves is narrow on purpose. A file may set targets and the base delay, and
/// nothing else:
///
/// - The Anchor is not in the file, and would not be honoured if it were. Its only key is a
///   physical tag, so a file that could clear it would be exactly the bypass Furlough is built
///   not to have.
/// - `pending` is not read. A queue is delay already served; handing yourself one that is
///   due is the same hole by a quieter door.
/// - `runtime` is not read. `exhausted` and `warned` are today's spent budget, so importing
///   them would un-spend the day, and `clock` is how Furlough notices a wall clock moved
///   forward.
///
/// A file with those keys in it is not an error — extra keys are ignored, quietly rather than
/// fatally, which is also what lets a file from an older Furlough still open. `ConfigExport`
/// has never carried them, so the only way to see them is a hand-edited file, and the answer
/// to a hand-edited file is to read the parts that are allowed to travel and ignore the rest.
///
/// Nothing here does I/O or touches the store. `plan` decides, `apply` performs, and the two
/// are separate so that the whole of an import can be shown to the person before any of it
/// happens — see `ImportPlan`.
enum ConfigImport {
    /// Ceilings on what will even be looked at. None of these are shapes Furlough writes; they
    /// are here because `decode` has to be pointed at whatever arrives, and a hand-written file
    /// should be refused in a sentence rather than spend a minute in `validationError`'s
    /// pairwise window comparison.
    static let maxFileBytes = 1_000_000
    static let maxTargets = 500
    static let maxWindowsPerRule = 128
    /// Longer than any bundle identifier or host, and short enough that a megabyte of them
    /// cannot be smuggled in as one.
    static let maxIdentifierLength = 253
    /// The top of the Settings stepper. A delay outside its range was typed into the file by
    /// hand, so the file is read for everything else and asked about this.
    static let maxLoosenDelayHours = 168

    enum Refusal: Error, Equatable {
        /// The file could not be opened at all — permission withdrawn, or it moved.
        case couldNotOpen(String)
        case tooBig(bytes: Int)
        case tooMany(targets: Int)
        case unreadable
        /// Written by a Furlough that knows a shape this one does not.
        case fromTheFuture(version: Int)
        /// A phone file on a Mac, or a Mac file on a phone.
        case wrongPlatform(ConfigExport.Platform)

        /// Refusals are read by whoever just chose the file, so each says what the file is and
        /// what to do instead, rather than naming the key that failed.
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

    /// Reads a file, or refuses it whole.
    ///
    /// The platform is checked here rather than left to fail at decode: `TargetKind`'s cases
    /// differ between the two builds, so a mismatched file would otherwise come back as some
    /// unreadable key error instead of the one sentence that explains it.
    static func read(_ data: Data) throws(Refusal) -> ConfigExport {
        guard data.count <= maxFileBytes else { throw .tooBig(bytes: data.count) }
        let export: ConfigExport
        do {
            export = try ConfigExport.decode(data)
        } catch {
            // A file from a newer Furlough may not decode at all. Say which version wrote it,
            // which is the useful half, rather than naming a key that means nothing to anyone.
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

    /// Reads a file the person chose.
    ///
    /// `.fileImporter` hands back a URL rather than a document, and on iOS that URL is
    /// security-scoped: it has to be opened and closed around the read or the read comes back
    /// empty. The Mac does not need it, and does it anyway rather than keep two paths.
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

    /// The `version` alone, from a file the full decode could not read.
    private static func peekVersion(_ data: Data) -> Int? {
        struct Peek: Decodable { var version: Int? }
        return (try? JSONDecoder().decode(Peek.self, from: data))?.version
    }

    /// Why an imported rule cannot be used, or nil.
    ///
    /// `Rule.validationError` is the check the rule editor runs, so a rule Furlough could not
    /// have written is refused for the reason the editor would have given. The window count and
    /// the budget range are checked on top of it: the editor's own controls cannot leave either,
    /// so nothing needs to say so there, but a file is typed by hand.
    static func problem(with rule: Rule) -> String? {
        if rule.windows.count > maxWindowsPerRule {
            return "It has \(rule.windows.count) windows. Furlough writes at most \(maxWindowsPerRule)."
        }
        if let error = rule.validationError { return error }
        guard (0...Furlough.minutesPerDay).contains(rule.dailyBudgetMinutes) else {
            return "A daily budget has to be between 0 and \(Furlough.minutesPerDay) minutes."
        }
        return nil
    }
}

/// What the file's targets turned out to be on this device.
///
/// The Mac works this out for itself — a Mac target is a bundle identifier or a host, both of
/// which another Mac can look up — and `ConfigImport.matches(for:config:)` does it. The phone
/// cannot: a Screen Time token is scoped to one device and one install and cannot be turned
/// back into an app, so the file carries no identifier and the person is walked through the
/// picker to say which app each row was. Either way the answer arrives here.
enum ImportResolution: Equatable {
    /// Something Furlough already manages on this device.
    case existing(UUID)
    /// Nothing here is it yet, so it is added. The kind is the caller's to build: it is the
    /// only side that knows what a target is made of on this platform.
    case create(TargetKind)
    /// Left out, with a sentence saying why — a category on a Mac, a website the file writes
    /// in a way Furlough cannot read, an app the person chose not to pick.
    case skipped(String)
}

struct ImportMatch: Equatable {
    var exported: ExportedTarget
    var resolution: ImportResolution

    /// What to call this row: what he named it if he named it, else what the system called it.
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

/// Everything an import would do, decided but not yet done.
///
/// An import is the largest single change Furlough can make to itself, and half of it may be
/// invisible for a day — so it is shown before it happens, in the same words the pending cards
/// use, and only then applied. `items` is what to show; `edits` is what to do.
struct ImportPlan: Equatable {
    /// Which part of a row a line is about.
    enum Subject: Equatable {
        case target
        case rule
        case tier
        case name
        case delay

        var label: String {
            switch self {
            case .target: "Added"
            case .rule: "Rule"
            case .tier: "Tier"
            case .name: "Name"
            case .delay: "Loosening delay"
            }
        }

        /// Whether the label says anything the row's name has not already said. A target and
        /// the delay each carry their own name; a rule, a tier and a nickname are one part of
        /// a row that can have three, so those say which part they are.
        var isWorthNaming: Bool { self == .rule || self == .tier || self == .name }
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
        /// What is enforced now and what replaces it, exactly as a pending card says it.
        var delta: PendingText.Delta? = nil
    }

    /// One decided change, in the form the store can take. Deliberately not a copy of the
    /// whole state: an import is reviewed before it is applied, and in between the enforcer
    /// may have spent a budget or landed a queued change. Writing back a state captured
    /// before that would un-spend the day, which is the thing an import must never do.
    enum Edit: Equatable {
        /// A target the file has and this device does not, added bare. What it should be
        /// called and what tier it is in come with it — neither enforces anything — but its
        /// rule goes through the gate like any other, which is why the first rule on a fresh
        /// install lands at once without needing a path of its own.
        case addTarget(Target)
        /// The name he gave it. Cosmetic, so it is not gated.
        case setNickname(targetID: UUID, String)
        case applyNow(PendingKind)
        case queue(PendingChange)
    }

    /// When the plan was worked out. `apply` counts a queued change's wait from here, so that
    /// leaving the review open does not serve any of it.
    var plannedAt: Date
    var items: [Item] = []
    var edits: [Edit] = []
    /// Targets this device manages that the file says nothing about. Left alone — an import is
    /// additive, and dropping them would be a loosening — but named, because "my old setup is
    /// back" and "my old setup is back and this is also still here" are different facts.
    var untouched: [String] = []
    /// When the file was written, and by which build. Carried onto the plan rather than read
    /// off the export by the review, so that the one view both platforms share needs only the
    /// plan. This is the largest single change Furlough can make to itself, and whether the
    /// file is from yesterday or from March is the first thing worth knowing about it.
    var exportedAt: Date? = nil
    var appVersion: String? = nil
    /// Why this import cannot be registered, or nil. Set by the phone's model, because the
    /// ceiling is iOS's: `Monitoring.register` refuses past 19 distinct window spans, and it
    /// runs *after* the import is saved — so an oversized file would land, registration would
    /// throw, and nothing at all would be monitored. Counted here while it is still a proposal.
    /// Always nil on the Mac, which has no DeviceActivity; see `ActivityLimit`.
    var limitReason: String? = nil

    var isEmpty: Bool { edits.isEmpty }
    /// Whether the button should do anything. Empty is nothing to do; over the ceiling is worse
    /// than nothing to do, because an import that cannot be registered leaves the rules in force
    /// and no monitor watching them.
    var canApply: Bool { !isEmpty && limitReason == nil }
    var added: [Item] { items.filter { $0.subject == .target && $0.outcome == .now } }
    var immediate: [Item] { items.filter { $0.outcome == .now && $0.subject != .target } }
    var queued: [Item] { items.filter { if case .queued = $0.outcome { return true }; return false } }
    var skipped: [Item] { items.filter { if case .skipped = $0.outcome { return true }; return false } }

    /// The furthest out anything in this plan lands.
    var lastEffectiveAt: Date? {
        items.compactMap { if case .queued(let date) = $0.outcome { return date }; return nil }.max()
    }

    /// The sentence at the top of the review. The shape of the whole thing — how much is new,
    /// how much lands now, how much waits — before any of the detail under it.
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

    /// The same shape in the past tense, for the alert after the button.
    ///
    /// Every other mutation in the app ends in a sentence saying what it did — `ProposalResult`
    /// is that sentence for one edit, and this is it for a whole file. It matters more here than
    /// anywhere else: half of an import is invisible until it lands, so a screen that simply
    /// closed would leave the queued half looking like nothing happened, and pressing the button
    /// again is the natural response to that.
    ///
    /// `headline` cannot be reused. It is written for a review — what this *would* do — and the
    /// two must not drift, which is why they are next to each other.
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
        // When it lands, not just that it waits. Without the date the only way to find out is
        // the Pending screen, and the sentence would be telling someone to go and look.
        if let last = lastEffectiveAt {
            let when = last.formatted(date: .abbreviated, time: .shortened)
            said += queued.count == 1 ? " It takes effect \(when)." : " The last of them takes effect \(when)."
        }
        return said
    }
}

extension ConfigImport {
    /// What this file would do here, decided against the state as it stands.
    ///
    /// Every change is judged the way the editor judges the same change by hand, in the order
    /// the editors would have been used, so that an import can never be a shorter road than
    /// the screens are:
    ///
    /// 1. The base delay. Raising it lands now and lengthens every wait worked out below it;
    ///    lowering it waits out the slowest target, because the base multiplies out to all of
    ///    them. This is `AppModel.setDelay(hours:)`, not a second opinion on it.
    /// 2. Each target's tier, before its rule. A tier that moves toward hazard lands now and
    ///    makes that target's own delay longer, so the rule underneath it waits the longer
    ///    time — which is what saving the two by hand does, and is the stricter of the two
    ///    readings. A tier that moves toward essential shortens the wait, so it queues, and
    ///    the rule under it is judged against the tier the target still has today.
    /// 3. Each target's rule, through `Policy.classify(newRule:against:)`.
    ///
    /// `now` is Furlough's own time — `state.now` — and never the device's.
    static func plan(
        _ export: ConfigExport,
        matches: [ImportMatch],
        state: SharedState,
        now: Date
    ) -> ImportPlan {
        var plan = ImportPlan(plannedAt: now)
        plan.exportedAt = export.exportedAt
        plan.appVersion = export.appVersion
        // The config as the import would leave it, for classifying what comes after against
        // what came before. Only ever a scratch copy: nothing here is saved.
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

    /// The base delay, the way the Settings stepper does it.
    private static func planDelay(
        _ export: ConfigExport,
        in working: inout Config,
        plan: inout ImportPlan,
        now: Date
    ) {
        let hours = export.loosenDelayHours
        // Refused rather than clamped: a number the stepper cannot reach was typed into the
        // file by hand, and quietly rounding it to something Furlough likes would be reading
        // a file that does not exist.
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

    /// One row of the file against the target it turned out to be: name, then tier, then rule.
    /// `isNew` says the target was added a moment ago by the caller, whose line already says
    /// what it will be — so nothing here repeats it except a rule that had to be dropped.
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

        // A nickname changes nothing about what is allowed, so it is not gated — the rule
        // editor saves one alongside a rule without asking either. Only ever set, never
        // cleared: an import is additive, and a file that simply has no nickname for a target
        // is not a request to forget the one this device has.
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
            // Named and dropped rather than repaired. A rule Furlough would not have written
            // is one somebody typed, and guessing what they meant is the one thing a
            // commitment device must not do with a hand-edited file.
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

    /// Performs a plan against the state as it stands right now.
    ///
    /// Applied as a set of changes rather than as a saved copy of the config, and deliberately:
    /// between working the plan out and pressing the button, the enforcer may have spent a
    /// budget, landed a queued change or learned a name, and writing back a config captured
    /// before that would quietly undo it.
    ///
    /// Anything queued has its wait counted from `plan.plannedAt`, so reading the review for an
    /// hour does not serve an hour of the delay.
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
            case .applyNow(let kind):
                state.pending.removeAll { supersedes(kind, $0.kind) }
                Policy.apply(PendingChange(kind: kind, effectiveAt: now), to: &state.config)
            case .queue(let change):
                // The very same change, already waiting, is left exactly where it is.
                //
                // This is the one place import diverges from `assign`, and deliberately. Saving
                // the same pending edit twice by hand restarts its clock, which is right: it was
                // typed twice, and a hand edit is not something anyone does by accident. A file
                // is applied as a whole and is easy to press twice — a second look at the review,
                // a double tap, a Mac and a phone both restored from the same file — and every
                // press would push every loosening in it further out than the last. Superseding
                // it with an identical copy is not a decision, so it does not restart anything.
                //
                // Anything that differs in the least — one window moved, one minute of budget —
                // is a different decision and supersedes the old one on the new clock, below.
                guard !state.pending.contains(where: { $0.kind == change.kind }) else { continue }
                state.pending.removeAll { supersedes(change.kind, $0.kind) }
                var change = change
                change.effectiveAt = change.effectiveAt.addingTimeInterval(read)
                state.pending.append(change)
            }
        }
    }

    /// Whether making the first change replaces a second one already waiting.
    ///
    /// The rule editor, the tier picker and the delay stepper each drop what was queued for
    /// the thing they are changing rather than stacking a second change on it, so that at most
    /// one change per target is ever in flight — which is the assumption `PendingText` reads
    /// the saved rule under. An import is not allowed to be the one edit that stacks.
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

#if os(iOS)
extension ConfigImport {
    /// What the phone can work out for itself, before anybody is asked.
    ///
    /// Most of a phone import cannot be: a Screen Time token is scoped to one device and one
    /// install, so the file writes no identifier for it and `ImportSetupView` walks the person
    /// through the picker row by row. A website row is the exception since 2026-09-08. The
    /// phone has `.host` targets now, and a `.website` row carrying an identifier is a plain
    /// string this phone can look up exactly as a Mac would — so those rows need no picker
    /// step at all, which is what lets a Mac's websites arrive here as real enforceable
    /// targets rather than as rows nobody can answer.
    ///
    /// Everything else comes back `.skipped(unresolved)`, which is what an unanswered row says
    /// until the person answers it: "not yet" and "leave it out" are the same state on that
    /// screen until Import is pressed.
    ///
    /// Read against a config that grows as the file is read, the way the Mac's does, so a file
    /// listing both "youtube.com" and "m.youtube.com" lands on one target rather than two: the
    /// second is a subdomain of the first, and `Config.target(host:)` is the thing that knows it.
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
                // Matched something this file asked for a moment ago rather than anything on
                // this phone, which makes it the same row twice.
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
#endif

#if !os(iOS)
extension ConfigImport {
    /// How a Mac file lines up with what this Mac already manages.
    ///
    /// A Mac target is a bundle identifier or a host — both plain strings another Mac can look
    /// up — so unlike the phone, the Mac needs nobody's help to work this out. Websites match
    /// through `Config.target(host:)`, which matches parent domains too, so a file listing
    /// "m.youtube.com" lands on the "youtube.com" already here rather than beside it.
    /// Read against a config that grows as the file is read, so a file listing both
    /// "youtube.com" and "m.youtube.com" resolves to one target and not two: the second is a
    /// subdomain of the first, and `Config.target(host:)` is the thing that knows it.
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
            // Matched something this file asked for a moment ago rather than anything on
            // this Mac, which makes it the same row twice.
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
