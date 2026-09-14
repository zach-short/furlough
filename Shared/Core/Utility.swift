import Foundation

/// How much a target is worth to the person holding the phone. One axis, read two ways: the
/// loosening delay scales *down* with utility (needing Messages back is legitimate; needing
/// TikTok back is what Furlough exists to resist), while the blocking warning scales *up* with
/// it, since Furlough has no emergency unblock and a bad rule on an essential app is
/// unrecoverable for the whole delay.
enum Utility: Int, Codable, CaseIterable, Sendable {
    /// The phone's own job: reaching people, getting somewhere, proving who you are.
    case essential = 0
    /// Real work or real contact, but nothing breaks if it waits out the usual delay.
    case useful = 1
    /// Passes the time. Not why anyone bought a phone.
    case idle = 2
    /// What Furlough was written for.
    case hazard = 3

    /// Default for a new target. Never `essential`, so forgetting to set it stays the safe way round.
    static let unset = Utility.useful

    /// With the default 24-hour base, this spreads the delay 6 hours (essential) to 4 days (hazard).
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

    /// Low-utility targets get no warning — blocking those is the point, and nagging would just
    /// train swiping past the banner that matters.
    var warnsBeforeBlocking: Bool { self == .essential || self == .useful }

    /// One tier wider than blocking: anchoring has no delay or rule to undo it, only the tag, so
    /// even idle is worth a word if the tag might be in another room.
    var warnsBeforeAnchoring: Bool { warnsBeforeBlocking || self == .idle }
}

extension Config {
    /// Rounded to whole hours so the copy and the actual landing date agree, and floored at
    /// `Furlough.minimumLoosenDelayHours` so a small base plus essential can't reach zero delay.
    /// Capped during the first week so early curiosity costs at most a lunch break — applied
    /// here, the one place the number is computed, so every caller agrees automatically.
    func delayHours(for utility: Utility) -> Int {
        let hours = fullDelayHours(for: utility)
        return isInTrial ? min(hours, Furlough.trialDelayHours) : hours
    }

    /// What this tier waits after the trial week — also what the editor names during the trial,
    /// so the cliff at week's end isn't a surprise.
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

    /// The highest-utility tier among anchored things, and the names in it. Only anchored kinds
    /// that are also targets can be named — an anchor may hold apps Furlough has no rule for,
    /// which are opaque unnamed tokens. Read through `holds`, so a whole-phone anchor warns about
    /// the essential target its allowlist leaves out, not one it keeps.
    var anchorWarning: (utility: Utility, names: [String], detail: String?)? {
        let held = targets
            .filter { target in target.kinds.contains { anchor.holds($0) } && target.utility.warnsBeforeAnchoring }
            .sorted { $0.utility.rawValue < $1.utility.rawValue }
        guard let worst = held.first?.utility else { return nil }
        let named = held.filter { $0.utility == worst }
        let detail = named.compactMap { AppUtility.suggestion(for: $0)?.detail }.first
        // Collapse duplicates: two unnamed targets are both "This app"; say it once.
        var seen = Set<String>()
        let names = named.map(\.displayName).filter { seen.insert($0).inserted }
        return (worst, names, detail)
    }

    /// Lowering the base delay loosens every target at once, so this waits out the slowest one.
    var longestDelay: TimeInterval {
        let hours = targets.map { delayHours(for: $0) }.max() ?? delayHours(for: nil)
        return TimeInterval(hours) * 3600
    }
}

/// Copy for the tier: what blocking or anchoring a target will actually cost.
enum UtilityText {
    /// Nil when the tier doesn't warrant interrupting.
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

    /// The only copy here that can name more than one thing. `detail` is written about a single
    /// app, so it's dropped once there's more than one name — otherwise it'd state something
    /// true of one app as if true of all of them.
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
        // Only reachable from `anchoring` — idle never warns for an ordinary block.
        case .idle: "\(name) \(plural ? "go" : "goes") the moment you anchor."
        default: "\(name) \(plural ? "are" : "is") worth having around."
        }
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: "This"
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
    }
}
