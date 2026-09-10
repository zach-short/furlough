import Foundation

/// What holding a tag to the phone means, decided after the read rather than before it.
///
/// Every other tag scan in Furlough knows what it is for before the sheet goes up: one button
/// pairs, another weighs anchor. The Anchor screen arms a single session on sight instead, so
/// the only thing left to do is hold the tag up, and the tag itself says which of the three
/// things this is — a key turning the lock one way, the other way, or a new key asking to be
/// cut. Kept here, pure and away from Core NFC, so the branching is tested without a reader:
/// the phone is the only place a tag can be read and the simulator is not one of them.
extension AnchorProfile {
    enum TagReading: Equatable {
        /// A paired tag with the anchor down: the release, which is all a tag has ever done.
        case weigh(PairedTag)
        /// A paired tag with the anchor up: the drop. Confirmed before it lands, because a tag
        /// that can also lock is a tag you can lock yourself out with by walking past a drawer.
        case drop(PairedTag)
        /// A tag this anchor has never seen, and the first key it would have.
        case pairFirst(Data)
        /// A tag this anchor has never seen, with keys already cut for it.
        case pairAnother(Data)
        /// Read, understood, and refused, in the words the alert uses.
        case refused(String)
    }

    /// What a scan of `scanned` means against this anchor as it stands.
    func reading(of scanned: Data) -> TagReading {
        if let matched = tag(matching: scanned) {
            if isAnchored { return .weigh(matched) }
            // A key with nothing to lock. Named rather than refused as "nothing to anchor",
            // which would read as though the tag were the thing missing.
            guard hasSomethingToHold else { return .refused("Choose what the anchor holds first.") }
            return .drop(matched)
        }
        if let refusal = pairingRefusal { return .refused(refusal) }
        return isPaired ? .pairAnother(scanned) : .pairFirst(scanned)
    }

    /// Why this anchor may not take another tag right now, in the words the alert uses. Shared
    /// by the Pair button and by an unknown tag held up, which are the same refusal arrived at
    /// from opposite directions.
    var pairingRefusal: String? {
        // A key cut under the lock is no lock.
        if isAnchored { return "Unanchor first." }
        if !canPairMore { return "\(Furlough.maxAnchorTags) tags is the limit. Forget one to pair another." }
        return nil
    }
}
