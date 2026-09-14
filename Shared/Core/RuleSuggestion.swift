import Foundation

/// The rule Furlough would start something on, before anybody has told it anything. Separate
/// from `AppUtility` (which is fact — a bundle identifier's tier) because these numbers are
/// judgement calls that can be retuned without re-verifying identifiers. Offered, never applied:
/// the editor shows it only while a target has no rule, and nothing writes until Save —
/// `Policy.decide` never reads this. The cold-start counterpart to `UsageAnalysis`, which builds
/// a rule from actual usage data where that's available.
enum RuleSuggestion {
    /// A starting rule: a daily budget, and the one window where the tier calls for one. A
    /// fragment rather than a `Rule` since the editor takes budget and window separately
    /// (still editable before Save); `rule` is for places that want to show it whole.
    struct Draft: Equatable, Sendable {
        var budgetMinutes: Int
        /// The one allowed window, or nil for a rule that is open all day up to its budget.
        var window: TimeWindow?

        /// The fragment as the rule it would become.
        var rule: Rule {
            Rule(windows: window.map { [$0] } ?? [], dailyBudgetMinutes: budgetMinutes)
        }
    }

    // MARK: The numbers, agreed with Zach on 2026-09-09

    /// An hour a day, no window — idle apps are limited on time, not hours, since "wrong hours"
    /// differs per person.
    static let idleBudgetMinutes = 60

    /// Half an hour a day, chosen to roughly agree with what `UsageAnalysis.budgetKeep` derives
    /// from real usage.
    static let hazardBudgetMinutes = 30

    /// 9 AM–10 PM (10 PM matches `UsageAnalysis.lateHours`). One window every day, deliberately,
    /// not per-weekday — it's a starting draft. Also cheap: DeviceActivity dedupes identical
    /// spans, so every hazard target sharing this counts as one activity against the ceiling of 19.
    static let hazardWindow = TimeWindow(startMinute: 9 * 60, endMinute: 22 * 60)

    /// Two hours for a film or two episodes — an hour-a-day budget stops mid-story, which is
    /// the rule that gets deleted.
    static let longFormBudgetMinutes = 120

    // MARK: The suggestion

    /// The rule Furlough would start `target` on, or nil when it has nothing worth saying —
    /// always nil once the target has a rule, since this must never be a second way to edit it.
    /// `chosen` is the tier the editor shows; an untouched picker reads `.useful` (no answer),
    /// so the table's guess stands in until then.
    static func suggestion(for target: Target, chosen: Utility? = nil) -> Draft? {
        guard target.rule == nil, let tier = tier(for: target, chosen: chosen) else { return nil }
        guard let draft = exception(for: target, at: tier) ?? draft(for: tier) else { return nil }
        // A typed site's minutes are never counted, so a budget on one would never be enforced.
        guard target.isCounted || draft.window != nil else { return nil }
        return draft
    }

    /// The tier a suggestion answers to: what the person said, or failing that the table's guess.
    static func tier(for target: Target, chosen: Utility?) -> Utility? {
        chosen ?? AppUtility.suggestion(for: target)?.utility
    }

    /// What a tier alone suggests, before any per-app exception. `.essential`/`.useful` say
    /// nothing on purpose: blocking an essential is already the risk Furlough warns about, and
    /// a work tool has no healthy budget to suggest.
    static func draft(for utility: Utility) -> Draft? {
        switch utility {
        case .essential, .useful: nil
        case .idle: Draft(budgetMinutes: idleBudgetMinutes)
        case .hazard: Draft(budgetMinutes: hazardBudgetMinutes, window: hazardWindow)
        }
    }

    /// The offer in one line: what taking it would put in the fields. `counted` is
    /// `Target.isCounted` — a typed site gets no budget line, since nothing would enforce it.
    static func offer(_ draft: Draft, counted: Bool = true, calendar: Calendar = .current) -> String {
        let budget = counted ? "\(TimeFormat.budget(draft.budgetMinutes)) a day" : nil
        let hours = draft.window.map { TimeFormat.span($0, calendar: calendar) }
        let parts = [budget, hours].compactMap { $0 }
        return "Furlough would start it at \(parts.joined(separator: ", "))"
    }

    /// The same suggestion stated as a rule (not a nudge to tap), for the card shown before an
    /// editor exists at all — hours first, then the budget.
    static func statement(_ draft: Draft, counted: Bool = true, calendar: Calendar = .current) -> String {
        let budget = "\(TimeFormat.budget(draft.budgetMinutes)) a day"
        guard let window = draft.window else { return "Open at any hour, \(budget)." }
        let hours = "Open \(TimeFormat.span(window, calendar: calendar))"
        // A typed site's minutes are never counted, so the hours are the whole rule.
        return counted ? "\(hours), \(budget)." : "\(hours)."
    }

    /// Why those numbers, phrased conditionally since the tier is Furlough's guess, not a saved answer.
    static func because(_ tier: Utility) -> String {
        "Furlough would call this \(tier.label)."
    }

    // MARK: Exceptions

    /// One app's refinement of its tier's default, with the tier it was written against carried
    /// along — an exception is an argument about an app *at* a tier, and carrying the tier lets
    /// `RuleSuggestionTests` catch drift if `AppUtility` retiers the app later.
    struct Exception: Equatable, Sendable {
        var utility: Utility
        var draft: Draft
    }

    /// Long-form video: watched in sittings, not in minutes.
    static let longFormVideo = Exception(
        utility: .idle,
        draft: Draft(budgetMinutes: longFormBudgetMinutes)
    )

    /// A hazard that's also how people are reached: keeps the budget, drops the window (closing
    /// overnight would shut off a way to be reached).
    static let reachable = Exception(
        utility: .hazard,
        draft: Draft(budgetMinutes: hazardBudgetMinutes)
    )

    /// The exception for `target` at `tier`, or nil to fall through to the tier's own default.
    static func exception(for target: Target, at tier: Utility) -> Draft? {
        guard let found = lookup(target), found.utility == tier else { return nil }
        return found.draft
    }

    /// Keyed the same way `AppUtility.suggestion(for:)` looks up a tier, so an exception is
    /// found wherever a tier is.
    private static func lookup(_ target: Target) -> Exception? {
        switch target.kind {
        #if os(iOS)
        case .application:
            return AppUtility.match(name: target.systemName, in: names)
                ?? AppUtility.match(name: target.nickname, in: names)
        case .webDomain:
            return AppUtility.match(host: target.systemName, in: hosts)
                ?? AppUtility.match(host: target.nickname, in: hosts)
                ?? AppUtility.match(name: target.systemName, in: names)
        case .category:
            return nil
        case .host(let host):
            return AppUtility.match(host: host, in: hosts)
        #else
        case .macApp(let bundleID):
            return AppUtility.match(bundleID: bundleID, in: bundleIDs)
                ?? AppUtility.match(name: target.nickname, in: names)
        case .host(let host):
            return AppUtility.match(host: host, in: hosts)
        #endif
        }
    }

    // MARK: The table

    /// Names as the shield reports them on iOS, lowercased.
    static let names: [String: Exception] = [
        "netflix": longFormVideo,
        "hulu": longFormVideo,
        "disney+": longFormVideo,
        "max": longFormVideo,
        "hbo max": longFormVideo,
        "prime video": longFormVideo,
        "peacock": longFormVideo,
        "paramount+": longFormVideo,
        "apple tv": longFormVideo,
        "crunchyroll": longFormVideo,

        "snapchat": reachable,
    ]

    static let bundleIDs: [String: Exception] = [
        "com.netflix.netflix": longFormVideo,
        "com.hulu.plus": longFormVideo,
        "com.disney.disneyplus": longFormVideo,
        "com.wbd.stream": longFormVideo,
        "com.amazon.aiv.aivapp": longFormVideo,
        "com.peacocktv.peacock": longFormVideo,
        "com.cbsvideo.app": longFormVideo,
        "com.apple.tv": longFormVideo,
        "com.crunchyroll.iphone": longFormVideo,

        "com.toyopagroup.picaboo": reachable,
    ]

    static let hosts: [(host: String, value: Exception)] = [
        ("netflix.com", longFormVideo),
        ("hulu.com", longFormVideo),
        ("disneyplus.com", longFormVideo),
        ("max.com", longFormVideo),
        ("primevideo.com", longFormVideo),
        ("peacocktv.com", longFormVideo),
        ("paramountplus.com", longFormVideo),
        ("crunchyroll.com", longFormVideo),

        ("snapchat.com", reachable),
    ]
}
