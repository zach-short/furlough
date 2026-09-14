import Foundation

/// Whether a launch should ask macOS for the web filter again, and why.
///
/// A system extension belongs to the *bundle* that installed it. Replacing
/// `/Applications/Furlough.app` — which is how every Mac build lands here, and is what an update
/// will be — leaves macOS holding the copy the old bundle staged: `systemextensionsctl` still
/// lists it activated and enabled, while a properties request from the new bundle comes back
/// empty or goes unanswered. Seen on Zach's Mac 2026-09-10 (HANDOFF 35), where the app settled
/// on **Not installed** and waited for somebody to press Install, having filtered nothing in the
/// meantime. The sentence that mattered in that note is "the app cannot tell that from a filter
/// nobody ever installed".
///
/// This is the app being able to tell. `WebFilter` writes down which build's extension macOS
/// accepted — its version and the hash of its code, so two builds of the same version are still
/// two builds — and a launch that finds a different one inside its own bundle knows it was
/// replaced rather than never installed, whatever the extension service says.
///
/// Pure, and here rather than in `WebFilter`, because the rule about when to re-ask macOS is
/// worth testing rather than witnessing once on one Mac. `WebFilter` does the asking.
enum FilterRepair {
    /// What macOS says about the extension, flattened to the part this decision turns on.
    /// `WebFilter.Status` carries the copy and the walkthrough; this carries the facts.
    enum Presence: Sendable, Equatable {
        /// The app is not in `/Applications`, so nothing can be installed from it.
        case elsewhere
        case notInstalled
        case installing
        /// macOS is waiting for the person in System Settings.
        case awaitingApproval
        /// Installed, and switched off by the person. Their call, not a fault to repair.
        case disabledInSettings
        /// Enabled, with its filter configuration on: the filter is doing its job.
        case running
        /// Enabled, but the filter configuration is off or gone, so it sees nothing.
        case notFiltering
        /// macOS was asked about the extension and did not answer. Not a refusal: the service
        /// that answers is stuck, which is the state a bundle replacement leaves it in.
        case unanswered
        /// macOS refused — the activation, or the permission to filter — without putting any
        /// question to the person. A configuration left behind by an earlier attempt is the
        /// usual cause, and a replaced bundle is how one gets left behind.
        case refused
        /// The person was asked and said no. Told apart from `refused` on purpose: this app
        /// already knows the difference (`WebFilter.Status.filterDenied(_:prompted:)`), and
        /// re-asking somebody who declined is the one thing a repair must never do.
        case declined
    }

    /// Why a launch is asking again. It goes in the activity log, which is where the last three
    /// of these arguments were lost the first time.
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
    ///   - wanted: whether the filter was ever asked for (`furlough.mac.filter.wanted`). Nothing
    ///     here installs anything somebody did not ask for.
    ///   - presence: what macOS says right now.
    ///   - bundled: the identity of the extension inside this app bundle, or nil when it cannot
    ///     be read — in which case the replacement rules are skipped rather than guessed at.
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
        // Nothing to do, or somebody is already being asked something.
        case .elsewhere, .installing, .awaitingApproval:
            return .leaveAlone
        // Switched off by hand, or asked for and declined. The app says so and leaves it:
        // re-asking would be Furlough arguing with a decision that is the person's to make, and
        // these are the two states where going without is deliberate.
        case .disabledInSettings, .declined:
            return .leaveAlone
        // Asked for, and macOS says it has none. Re-asked on every launch rather than once per
        // build, deliberately: this is the plain case, it is what somebody asked for, and the
        // request is what puts the extension back.
        case .notInstalled:
            return .activate(bundled != nil && activated != nil && activated != bundled
                ? .replacedByThisBuild
                : .neverInstalled)
        // Running, but not necessarily *this* build's copy. An update that lands while the old
        // extension keeps running is the case worth catching: macOS reports a healthy filter and
        // it is the previous version's code that is enforcing.
        case .running, .notFiltering:
            guard let bundled, bundled != activated, attempted != bundled else { return .leaveAlone }
            return .activate(.replacedByThisBuild)
        // Once per build, then stop. A fresh activation request is what clears a stuck record,
        // and if it does not, submitting it again on every launch only buys another dialog.
        case .unanswered:
            guard attempted != bundled else { return .leaveAlone }
            return .activate(.serviceStuck)
        case .refused:
            guard attempted != bundled else { return .leaveAlone }
            return .activate(.attemptRefused)
        }
    }
}
