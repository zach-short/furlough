import Foundation

/// The three steps a half is set up in, and which is still owed. Derived from the config rather
/// than stored, so it can't drift: adding a target, pairing a tag, dropping an anchor all move
/// the guide along on their own. The one exception is each half's last step (reading your list,
/// lifting the anchor) which the config can't answer, so those read a flag on the app's model
/// (`AppModel.finishedGuides`, `MacModel.finishedGuides`).
///
/// The steps themselves aren't shared between platforms — the phone's first Rules step changes
/// wording with Screen Time access, and the Mac can't pair a tag at all — so each app writes its
/// own three: the phone's in `Furlough/Views/Guides.swift`, the Mac's below.
struct HalfGuide {
    struct Step: Identifiable {
        var title: String
        var detail: String
        /// Sits under the card while this step is live.
        var footnote: String?
        /// What the step has to show for itself (apps picked, what the anchor holds), drawn as
        /// icons at full strength whether live or long done — a tick says a step happened, this
        /// says what it did.
        var kinds: [TargetKind] = []
        var isDone: Bool
        var id: String { title }
    }

    var half: Half
    var steps: [Step]

    /// The first step not done. Nil once the card folds away.
    var live: Int? { steps.firstIndex { !$0.isDone } }
    var isRunning: Bool { live != nil }
    var footnote: String? { live.flatMap { steps[$0].footnote } }

    /// Names the half rather than "Get started" — the other half is one swipe away and may be
    /// running its own guide.
    var title: String {
        switch half {
        case .rules: "Setting up Rules"
        case .anchor: "Setting up the Anchor"
        }
    }
}

#if os(macOS)
extension HalfGuide {
    /// Pick the apps, give the first one a rule, read the list. The phone's equivalent first
    /// step offers Screen Time data; there's no such API on the Mac, so this step is the picker.
    static func macRules(config: Config, finished: Bool) -> HalfGuide {
        HalfGuide(half: .rules, steps: [
            Step(
                title: "Pick the apps that eat your day",
                detail: "Any app on this Mac, and websites by name. The + button offers both.",
                footnote: "A website is held in Safari and the Chromium browsers straight away, and everywhere else once the web filter is on.",
                isDone: !config.targets.isEmpty
            ),
            Step(
                title: "Give the first one a rule",
                detail: "Allowed windows and a minute budget — the same every day, or different at weekends.",
                footnote: "Adding an app enforces nothing on its own. Saving its first rule is what starts it.",
                isDone: config.targets.contains { $0.rule != nil }
            ),
            Step(
                title: "Read your list",
                detail: "Everything you manage, grouped by when it next opens: open now, later today, tomorrow.",
                footnote: "Tightening a rule applies at once. Anything that hands time back waits, and you can cancel it while it does.",
                isDone: finished
            ),
        ])
    }

    /// Link an iPhone, choose what it holds, drop it. The Mac has no reader to pair a tag, so
    /// its first step is linking an iPhone instead — only an iPhone's tag can release an anchor
    /// dropped here (see `AnchorSync.macDrop`), and `hasKey` is the roster's answer to whether one's linked.
    static func macAnchor(config: Config, finished: Bool, hasKey: Bool) -> HalfGuide {
        let anchor = config.anchor
        return HalfGuide(half: .anchor, steps: [
            Step(
                title: "Link this Mac and your iPhone",
                detail: "This Mac has no tag reader, so an iPhone's tag is the only key. Put both on the link under Settings > Devices, and a drop here locks there too.",
                footnote: "The link rides on your own iCloud. Each device is asked before it joins, and any can be taken off — except while the anchor is down.",
                isDone: hasKey
            ),
            Step(
                title: "Choose what it holds",
                detail: "A list you lock, or every app on this Mac with a few left open.",
                footnote: "No delay applies to the Anchor. Dropping it only ever takes things away.",
                isDone: anchor.hasSomethingToHold
            ),
            Step(
                title: "Drop it",
                // Two separate sentences, not "\(heldDescription) goes out of reach": before
                // anything is chosen that reads "0 items", and a count vs. "Everything except 3"
                // take different verb forms anyway — naming it after a colon sidesteps agreement.
                detail: anchor.hasSomethingToHold
                    ? "One click, and it locks your iPhone too. Out of reach: \(anchor.heldDescription)."
                    : "One click, and it locks your iPhone too. What you chose goes out of reach.",
                footnote: "Only your iPhone's tag lifts it, there and here. Furlough has no unblock button, and this is the half that means it.",
                isDone: finished
            ),
        ])
    }
}
#endif
