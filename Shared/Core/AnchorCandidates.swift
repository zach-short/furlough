import Foundation

/// The Anchor's first offer. Its list starts empty, and the things a person most wants held
/// are usually the ones Furlough already blocks — so before Apple's picker, which lists every
/// app on the phone, the Anchor screen offers what has a rule, to take in one tap. Both halves
/// live here rather than in the view because they are the rules engine's business: what
/// "already blocked" means, and what taking a target into the anchor adds.
extension Config {
    /// The targets Furlough blocks that the anchor does not hold yet, in the list's order.
    ///
    /// A target counts once it has a rule: one added and never given windows is not blocked,
    /// and is not offered. A target is left out once every door it covers is in the anchor,
    /// and offered while any is missing — an app whose site was linked on later still has a
    /// door the anchor does not hold.
    var anchorCandidates: [Target] {
        targets.filter { target in
            target.rule != nil && !target.kinds.allSatisfy(anchor.contains)
        }
    }
}

extension AnchorProfile {
    /// Takes in every door of `targets` the anchor does not hold yet, after what it holds, in
    /// the order given. A linked target brings both halves: two doors into one habit should
    /// not need two picks to close. Returns whether anything was added. Nothing here checks
    /// the lock, because `AppModel.addToAnchor` refuses before it gets this far.
    @discardableResult
    mutating func add(_ targets: [Target]) -> Bool {
        var added = false
        for kind in targets.flatMap(\.kinds) where !contains(kind) {
            kinds.append(kind)
            added = true
        }
        return added
    }
}

extension Config {
    /// What the allowlist starts as when the anchor's scope becomes the whole phone: every
    /// door of every target Zach tiered Essential, in the list's order. Those are the apps
    /// whose loss he has already said would hurt — Messages, the authenticator, the way home —
    /// so the anchor that takes everything else starts by keeping them.
    ///
    /// Only a chosen tier counts. `utility` answers useful for a target nobody has tiered, and
    /// the table's guess is a chip the editor offers, never an answer, so neither can put an
    /// app on the list by itself. What the seed does not see, `anchorWarning` still names:
    /// an essential target taken off the list warns before the anchor drops, exactly as
    /// anchoring it singly does.
    var essentialKinds: [TargetKind] {
        targets.filter { $0.utilityLevel == .essential }.flatMap(\.kinds)
    }
}
