import Foundation

/// How much a target is worth to the person holding the phone.
///
/// One axis, read in two directions. The delay before a loosening lands scales *down* with
/// utility, because needing Messages back is legitimate and needing TikTok back is the thing
/// Furlough exists to sit in front of. The warning before blocking scales *up* with it, for
/// the same reason: blocking Messages is the dangerous act, and Furlough has no emergency
/// unblock, so a bad rule on an essential app is unrecoverable for the whole delay.
enum Utility: Int, Codable, CaseIterable, Sendable {
    /// The phone's own job: reaching people, getting somewhere, proving who you are.
    case essential = 0
    /// Real work or real contact, but nothing breaks if it waits out the usual delay.
    case useful = 1
    /// Passes the time. Not why anyone bought a phone.
    case idle = 2
    /// What Furlough was written for.
    case hazard = 3

    /// What a new target gets until someone says otherwise: the base delay, no warning.
    /// Never `essential`, so forgetting to choose can only ever be the safe way round.
    static let unset = Utility.useful

    /// Multiplies the base delay. Essential is a quarter, hazard four times, so with the
    /// default 24 hours the spread runs 6 hours to 4 days.
    var delayMultiplier: Double {
        switch self {
        case .essential: 0.25
        case .useful: 1
        case .idle: 2
        case .hazard: 4
        }
    }

    var label: String {
        switch self {
        case .essential: "Essential"
        case .useful: "Useful"
        case .idle: "Idle"
        case .hazard: "Hazard"
        }
    }

    /// One line under the chip, in the rule editor.
    var summary: String {
        switch self {
        case .essential: "The phone's own job. Blocking it is the risk."
        case .useful: "Worth having. Nothing breaks if it waits."
        case .idle: "Passes the time."
        case .hazard: "The reason you installed Furlough."
        }
    }

    /// Whether blocking this deserves a word before it happens. Low-utility targets get none:
    /// blocking those is the whole point, and nagging about it would only teach him to swipe
    /// past the banner that matters.
    var warnsBeforeBlocking: Bool { self == .essential || self == .useful }

    /// Anchoring is instant, covers things that are not even targets, and only the paired tag
    /// lifts it — no delay runs out and no rule brings it back. So it warns one tier wider than
    /// blocking does: idle is worth a sentence when the tag might be in another room, even
    /// though it is not worth one for an ordinary rule.
    var warnsBeforeAnchoring: Bool { warnsBeforeBlocking || self == .idle }
}

extension Config {
    /// Hours a loosening waits for this target. Unknown or unconfigured targets get the base.
    ///
    /// Rounded to whole hours so the copy ("waits 6 hours") and the date a change actually
    /// lands cannot disagree, and floored at `Furlough.minimumLoosenDelayHours` so a small
    /// base plus an essential target can never add up to no delay at all.
    /// While the first week runs it is capped instead, so that nothing a beginner does to
    /// themselves out of curiosity costs more than a lunch break. The cap is applied here, at
    /// the one place the number is worked out, so every countdown, every "waits 4 days" line
    /// and every `effectiveAt` agrees with it without being told.
    func delayHours(for utility: Utility) -> Int {
        let hours = fullDelayHours(for: utility)
        return isInTrial ? min(hours, Furlough.trialDelayHours) : hours
    }

    /// What this tier waits once the first week is over. The same number as `delayHours` for
    /// all but those seven days, and the one the editor names while they run, because the
    /// point of saying it early is that the cliff at the end of the week is not a surprise.
    func fullDelayHours(for utility: Utility) -> Int {
        let scaled = Double(loosenDelayHours) * utility.delayMultiplier
        return max(Furlough.minimumLoosenDelayHours, Int(scaled.rounded()))
    }

    func fullDelayHours(for target: Target?) -> Int { fullDelayHours(for: target?.utility ?? .unset) }

    func delayHours(for target: Target?) -> Int { delayHours(for: target?.utility ?? .unset) }

    func delay(for target: Target?) -> TimeInterval { TimeInterval(delayHours(for: target)) * 3600 }

    func delayHours(forTargetID id: UUID?) -> Int {
        delayHours(for: id.flatMap { target(id: $0) })
    }

    func delay(forTargetID id: UUID?) -> TimeInterval {
        delay(for: id.flatMap { target(id: $0) })
    }

    /// What the anchor is about to take away that is worth keeping: the highest-utility tier
    /// among the anchored things, and the names in it.
    ///
    /// Only anchored kinds that are also targets can be named — an anchor may hold apps
    /// Furlough has no rule for, and on the phone those are opaque tokens with no name attached.
    /// So this warns about what it can see, which is the part Zach chose deliberately. Read
    /// through `holds`, so an anchor over the whole phone warns about the essential target its
    /// allowlist leaves out, and not about one it keeps.
    var anchorWarning: (utility: Utility, names: [String], detail: String?)? {
        let held = targets
            .filter { target in target.kinds.contains { anchor.holds($0) } && target.utility.warnsBeforeAnchoring }
            .sorted { $0.utility.rawValue < $1.utility.rawValue }
        guard let worst = held.first?.utility else { return nil }
        let named = held.filter { $0.utility == worst }
        let detail = named.compactMap { AppUtility.suggestion(for: $0)?.detail }.first
        // Duplicates collapsed: two targets the shield has never named are both "This app", and
        // "This app and This app" is worse than saying it once. Order kept, so the first name
        // the list found is the first one read.
        var seen = Set<String>()
        let names = named.map(\.displayName).filter { seen.insert($0).inserted }
        return (worst, names, detail)
    }

    /// The longest any single target would wait. Lowering the base delay loosens every target
    /// at once, so it has to wait out the slowest of them rather than the base.
    var longestDelay: TimeInterval {
        let hours = targets.map { delayHours(for: $0) }.max() ?? delayHours(for: nil)
        return TimeInterval(hours) * 3600
    }
}

/// Copy for the tier: what blocking or anchoring a target will actually cost.
enum UtilityText {
    /// Shown in the rule editor when a change would newly restrict a target worth keeping.
    /// Nil when the tier does not warrant interrupting.
    static func blocking(name: String, utility: Utility, detail: String?) -> String? {
        guard utility.warnsBeforeBlocking else { return nil }
        let consequence = detail ?? fallback(name: name, utility: utility)
        switch utility {
        case .essential:
            return "\(consequence) Furlough has no emergency unblock, so undoing this waits out the delay."
        default:
            return consequence
        }
    }

    /// Shown before anchoring. The anchor is instant, covers things that are not even targets,
    /// and only the paired tag lifts it — so if the tag is in another room, this is the whole
    /// story until it is found.
    ///
    /// The only text here that can be about more than one thing, so the only one that has to
    /// agree in number. `detail` is dropped once it can: a detail is written about one app
    /// ("Messages is where the codes texted to you land") and `anchorWarning` hands over the
    /// first it finds among the names, so using it for several would say something true of one
    /// of them as if it were true of all.
    static func anchoring(names: [String], utility: Utility, detail: String?) -> String? {
        guard utility.warnsBeforeAnchoring else { return nil }
        let plural = names.count > 1
        let consequence = (plural ? nil : detail) ?? fallback(name: list(names), utility: utility, plural: plural)
        switch utility {
        case .essential:
            return "\(consequence) Only the paired tag lifts an anchor. If the tag is not with you, nothing here comes back until you find it."
        default:
            return "\(consequence) Only the paired tag lifts an anchor."
        }
    }

    private static func fallback(name: String, utility: Utility, plural: Bool = false) -> String {
        switch utility {
        case .essential: "\(name) \(plural ? "are" : "is") how this phone does its job."
        // Only reachable from `anchoring`: idle is below the line for an ordinary block, and
        // saying it is "worth having around" would be flattery. What is true is that it goes.
        case .idle: "\(name) \(plural ? "go" : "goes") the moment you anchor."
        default: "\(name) \(plural ? "are" : "is") worth having around."
        }
    }

    /// "Messages", "Messages and Phone", "Messages, Phone and Maps".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: "This"
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
    }
}
