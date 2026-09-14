import Foundation

/// Before Apple's app picker, the Anchor screen offers targets Furlough already blocks, to
/// take in one tap.
extension Config {
    /// Targets Furlough blocks (have a rule) that the anchor doesn't fully hold yet — a
    /// target with only some of its doors (e.g. a linked site) still qualifies.
    var anchorCandidates: [Target] {
        targets.filter { target in
            target.rule != nil && !target.kinds.allSatisfy(anchor.contains)
        }
    }
}

extension AnchorProfile {
    /// Adds every door of `targets` (a linked target brings both halves). Caller
    /// (`AppModel.addToAnchor`) is responsible for checking the lock first.
    @discardableResult
    mutating func add(_ targets: [Target]) -> Bool {
        var added = false
        for kind in targets.flatMap(\.kinds) where !contains(kind) {
            kinds.append(kind)
            added = true
        }
        return added
    }

    /// Mirror of `add`: a linked target comes off as one thing too. Caller checks the lock.
    @discardableResult
    mutating func remove(_ targets: [Target]) -> Bool {
        let going = Set(targets.flatMap(\.kinds))
        guard kinds.contains(where: going.contains) else { return false }
        kinds.removeAll(where: going.contains)
        return true
    }

    /// True only once every door of `target` is held (mirror of `anchorCandidates`).
    func lists(_ target: Target) -> Bool { target.kinds.allSatisfy(contains) }

    func willHold(_ target: Target) -> Bool { target.kinds.contains { holds($0) } }
}

extension Config {
    /// Seeds the whole-phone anchor's allowlist with every door of targets tiered Essential.
    /// Only an explicitly chosen tier counts — `utility`'s guess is a suggestion, not a tier,
    /// and must not silently add an app to the list.
    var essentialKinds: [TargetKind] {
        targets.filter { $0.utilityLevel == .essential }.flatMap(\.kinds)
    }
}
