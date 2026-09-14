import Foundation

/// Whether a launch should ask macOS for the web filter again, and why.
///
/// A system extension belongs to the *bundle* that installed it, so replacing
/// `/Applications/Furlough.app` (any update) leaves macOS holding the old bundle's copy —
/// `systemextensionsctl` reports it activated while a properties request from the new bundle
/// comes back empty. Seen on Zach's Mac 2026-09-10 (HANDOFF 35): the app settled on "Not
/// installed" and filtered nothing until someone pressed Install.
///
/// `WebFilter` records which build's extension macOS accepted (version + code hash), so a
/// launch that finds a different one in its own bundle knows it was replaced rather than never
/// installed, whatever the extension service reports.
enum FilterRepair {
    /// What macOS says about the extension, flattened to the part this decision turns on.
    enum Presence: Sendable, Equatable {
        /// Not in `/Applications`, so nothing can be installed from it.
        case elsewhere
        case notInstalled
        case installing
        case awaitingApproval
        /// Switched off by the person. Their call, not a fault to repair.
        case disabledInSettings
        case running
        /// Enabled, but the filter configuration is off or gone, so it sees nothing.
        case notFiltering
        /// Asked and got no answer — not a refusal, the answering service is stuck (what a
        /// bundle replacement leaves behind).
        case unanswered
        /// Refused without asking the person, usually a configuration left behind by an
        /// earlier attempt.
        case refused
        /// Asked and declined. Told apart from `refused`: re-asking someone who declined is
        /// the one thing a repair must never do.
        case declined
    }

    /// Goes in the activity log.
    enum Reason: Sendable, Equatable {
        case neverInstalled
        case replacedByThisBuild
        case serviceStuck
        case attemptRefused

        var sentence: String {
            switch self {
            case .neverInstalled:
                "asked for but not installed; installing again"
            case .replacedByThisBuild:
                "this copy of Furlough is not the one that installed the filter, so macOS is holding the copy the old bundle staged; installing this build's"
            case .serviceStuck:
                "macOS did not answer about the extension, which is what a replaced bundle leaves behind; submitting a fresh activation, which is what clears it"
            case .attemptRefused:
                "the last attempt was refused without anything being asked of you; trying once more for this build"
            }
        }
    }

    enum Action: Sendable, Equatable {
        case leaveAlone
        case activate(Reason)
    }

    /// - Parameters:
    ///   - wanted: whether the filter was ever asked for. Nothing here installs anything
    ///     somebody did not ask for.
    ///   - presence: what macOS says right now.
    ///   - bundled: the extension identity in this app bundle, or nil (replacement rules are
    ///     skipped rather than guessed at) when it can't be read.
    ///   - activated: the identity macOS last accepted, as far as this app knows.
    ///   - attempted: the identity a launch last asked for without being told it worked.
    static func decide(
        wanted: Bool,
        presence: Presence,
        bundled: String?,
        activated: String?,
        attempted: String?
    ) -> Action {
        guard wanted else { return .leaveAlone }
        switch presence {
        case .elsewhere, .installing, .awaitingApproval:
            return .leaveAlone
        // Deliberate states: switched off by hand, or asked and declined. Re-asking would be
        // Furlough overriding the person's own choice.
        case .disabledInSettings, .declined:
            return .leaveAlone
        // Re-asked on every launch (not once per build): this is the plain "put it back" case.
        case .notInstalled:
            return .activate(bundled != nil && activated != nil && activated != bundled
                ? .replacedByThisBuild
                : .neverInstalled)
        // Running is not necessarily *this* build's copy — an update can land while the old
        // extension keeps enforcing, which macOS reports as healthy.
        case .running, .notFiltering:
            guard let bundled, bundled != activated, attempted != bundled else { return .leaveAlone }
            return .activate(.replacedByThisBuild)
        // Once per build, then stop — repeating a stuck request only buys another dialog.
        case .unanswered:
            guard attempted != bundled else { return .leaveAlone }
            return .activate(.serviceStuck)
        case .refused:
            guard attempted != bundled else { return .leaveAlone }
            return .activate(.attemptRefused)
        }
    }
}
