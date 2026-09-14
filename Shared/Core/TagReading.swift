import Foundation

/// What holding a tag to the phone means, decided after the read: the Anchor screen arms on
/// sight, so the tag itself says which case applies. Kept out of Core NFC so it's testable
/// without a reader.
extension AnchorProfile {
    enum TagReading: Equatable {
        case weigh(PairedTag)
        /// Confirmed before it lands — a tag that can also lock could lock you out by accident.
        case drop(PairedTag)
        case pairFirst(Data)
        case pairAnother(Data)
        case refused(String)
    }

    func reading(of scanned: Data) -> TagReading {
        if let matched = tag(matching: scanned) {
            if isAnchored { return .weigh(matched) }
            // Named this way, not "nothing to anchor," so the tag isn't blamed for what's missing.
            guard hasSomethingToHold else { return .refused("Choose what the anchor holds first.") }
            return .drop(matched)
        }
        if let refusal = pairingRefusal { return .refused(refusal) }
        return isPaired ? .pairAnother(scanned) : .pairFirst(scanned)
    }

    /// Shared by the Pair button and an unknown tag scan — same refusal, opposite paths.
    var pairingRefusal: String? {
        if isAnchored { return "Unanchor first." }
        if !canPairMore { return "\(Furlough.maxAnchorTags) tags is the limit. Forget one to pair another." }
        return nil
    }
}
