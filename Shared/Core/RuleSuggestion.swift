import Foundation

/// The rule Furlough would start something on, before anybody has told it anything.
///
/// `AppUtility` answers what a target *is*: a tier, and the cost of blocking it, from facts that
/// can be checked — a bundle identifier either is Instagram's or it is not. This file answers
/// what to *do* about it, and none of that is checkable the same way. "TikTok gets 30 minutes,
/// not 20" is a judgement, agreed with Zach on 2026-09-09; the tier beside it is a fact. They
/// are separate files for exactly that reason: a figure here can be retuned any afternoon
/// without anyone having to re-verify a table of identifiers.
///
/// The pattern is `AppUtility`'s, one property over. Everything is offered and never applied:
/// the editor shows it only while a target has no rule of its own, one tap takes it into the
/// fields, one ignores it, and nothing is written until Save. `Policy.decide` never reads it,
/// and nothing here can loosen or tighten anything by itself.
///
/// The warm half of this already exists. `UsageAnalysis` builds a whole `Rule` out of what a
/// person actually did — the hours their use piles into, and half of the minutes they spent —
/// but it needs `FamilyActivityData`, which most installs never get. This is the cold half: the
/// same shape of answer for the first app anyone adds, from the tier alone. The numbers below
/// were chosen to sit alongside that engine's, not to argue with it.
enum RuleSuggestion {
    /// A starting rule: a daily budget, and the one window where the tier calls for one.
    ///
    /// A fragment rather than a `Rule` because that is what the editor takes — the budget goes
    /// to the slider and the window becomes a row, both still editable before Save. `rule` is
    /// for the places that want to *show* it whole.
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

    /// An hour a day, and no claim about when. Idle is what passes the time, not what a person
    /// is fighting, so the suggestion limits it and stays out of the question of which hours are
    /// the wrong ones — that answer is different for everybody and the week sheet is where it
    /// belongs. A tick on the budget slider, so what lands under the thumb reads as a decision.
    static let idleBudgetMinutes = 60

    /// Half an hour a day. `UsageAnalysis.budgetKeep` keeps half of what was actually spent, and
    /// half of a typical hazard app's day is about this, so the cold answer and the warm one
    /// land in the same place rather than contradicting each other on the same screen.
    static let hazardBudgetMinutes = 30

    /// 9:00 AM to 10:00 PM, every day: the first and the last hours of the day are not the feed.
    /// 10 PM is already what this codebase calls late (`UsageAnalysis.lateHours`), and the
    /// morning end is the other half of the same idea.
    ///
    /// One window on every day, deliberately, and not a per-weekday shape: it is a starting
    /// draft, and the week sheet is the tool for the rest. It also costs almost nothing to
    /// spread — DeviceActivity dedupes spans, so every hazard target that takes this shares the
    /// one `window:540-1320` activity rather than spending one each against the ceiling of 19.
    static let hazardWindow = TimeWindow(startMinute: 9 * 60, endMinute: 22 * 60)

    /// Two hours for a film or two episodes. An hour-a-day budget on long-form video runs out
    /// somewhere in the second act, and Furlough's answer to "I am halfway through" is to wait
    /// until tomorrow — which is a rule nobody keeps, so it is the rule that gets deleted.
    static let longFormBudgetMinutes = 120

    // MARK: The suggestion

    /// The rule Furlough would start `target` on, or nil when it has nothing worth saying.
    ///
    /// Nil whenever the target already has a rule of its own. A suggestion is for the cold
    /// start; one that could land on top of a rule someone is living under would be a second way
    /// to edit that rule, and this file is not allowed to be that.
    ///
    /// `chosen` is the tier showing in the editor, and only when somebody actually answered:
    /// an untouched picker reads `.useful`, which is the absence of an answer rather than one,
    /// so the table's own guess is what stands in until then.
    static func suggestion(for target: Target, chosen: Utility? = nil) -> Draft? {
        guard target.rule == nil, let tier = tier(for: target, chosen: chosen) else { return nil }
        guard let draft = exception(for: target, at: tier) ?? draft(for: tier) else { return nil }
        // Nothing counts a typed site's minutes, so a budget on one is a number that would never
        // be enforced. Its hours are, which is why the window still stands on its own.
        guard target.isCounted || draft.window != nil else { return nil }
        return draft
    }

    /// The tier a suggestion answers to: what the person said, or failing that the table's guess.
    static func tier(for target: Target, chosen: Utility?) -> Utility? {
        chosen ?? AppUtility.suggestion(for: target)?.utility
    }

    /// What a tier alone suggests, before any per-app exception.
    ///
    /// The two quiet tiers say nothing on purpose. Blocking an essential is the risk Furlough
    /// interrupts a person about, so recommending a budget for one would be the app arguing with
    /// its own caution banner. And a work tool has no healthy amount: the only generous figure
    /// that could stand for `.useful` is looser than the 30 minutes the slider already sits at,
    /// so taking it would be a suggestion that loosens the screen it is offered on.
    static func draft(for utility: Utility) -> Draft? {
        switch utility {
        case .essential, .useful: nil
        case .idle: Draft(budgetMinutes: idleBudgetMinutes)
        case .hazard: Draft(budgetMinutes: hazardBudgetMinutes, window: hazardWindow)
        }
    }

    /// The offer in one line: what taking it would put in the fields.
    ///
    /// `counted` is `Target.isCounted`: a typed site has no budget to fill, so the line says only
    /// what it can actually do rather than promising minutes nothing will ever count.
    static func offer(_ draft: Draft, counted: Bool = true, calendar: Calendar = .current) -> String {
        let budget = counted ? "\(TimeFormat.budget(draft.budgetMinutes)) a day" : nil
        let hours = draft.window.map { TimeFormat.span($0, calendar: calendar) }
        let parts = [budget, hours].compactMap { $0 }
        return "Furlough would start it at \(parts.joined(separator: ", "))"
    }

    /// The same suggestion as the rule itself, for the card the editor opens on when a target
    /// has no rule yet.
    ///
    /// `offer` is a nudge inside an editor somebody is already reading: it says what tapping
    /// would put in the fields. This is read before there is an editor at all, so it states the
    /// rule rather than the act of taking it — hours first, because that is what a person
    /// pictures, then the budget those hours are spent out of.
    static func statement(_ draft: Draft, counted: Bool = true, calendar: Calendar = .current) -> String {
        let budget = "\(TimeFormat.budget(draft.budgetMinutes)) a day"
        guard let window = draft.window else { return "Open at any hour, \(budget)." }
        let hours = "Open \(TimeFormat.span(window, calendar: calendar))"
        // Nothing counts a typed site's minutes, so on one of those the hours are the whole rule
        // and a figure here would be a promise the phone cannot keep.
        return counted ? "\(hours), \(budget)." : "\(hours)."
    }

    /// Why those numbers, in the word the editor's own chips use for it.
    ///
    /// Conditional on purpose: nothing has been written, and the tier is Furlough's reading of
    /// what this thing is rather than an answer anyone gave. The picker under the editor is
    /// where it is argued with.
    static func because(_ tier: Utility) -> String {
        "Furlough would call this \(tier.label)."
    }

    // MARK: Exceptions

    /// One app's refinement of its tier's default, and the tier it was written against.
    ///
    /// The tier is carried rather than assumed because an exception is an argument about an app
    /// *at* a tier: "an hour cuts a film in half" is a thing to say about Netflix while Netflix
    /// is idle, and says nothing about what to do if it is ever tiered somewhere else. Carrying
    /// it also makes drift loud — `RuleSuggestionTests` checks every entry here still agrees
    /// with `AppUtility`, so retiering an app in that table fails a test here instead of quietly
    /// switching this off.
    struct Exception: Equatable, Sendable {
        var utility: Utility
        var draft: Draft
    }

    /// Long-form video: watched in sittings, not in minutes.
    static let longFormVideo = Exception(
        utility: .idle,
        draft: Draft(budgetMinutes: longFormBudgetMinutes)
    )

    /// A hazard that is also how people are reached. It keeps the budget and loses the window:
    /// closing it from 10 PM to 9 AM would be shutting the door someone is knocked on, which is
    /// the harm `.essential` exists to warn about, arriving through the back of a suggestion.
    static let reachable = Exception(
        utility: .hazard,
        draft: Draft(budgetMinutes: hazardBudgetMinutes)
    )

    /// The exception for `target` at `tier`, or nil to fall through to the tier's own default.
    static func exception(for target: Target, at tier: Utility) -> Draft? {
        guard let found = lookup(target), found.utility == tier else { return nil }
        return found.draft
    }

    /// Keyed off whatever identity the target has, in `AppUtility.suggestion(for:)`'s order and
    /// through `AppUtility`'s own matchers, so an exception is found exactly where a tier is.
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
