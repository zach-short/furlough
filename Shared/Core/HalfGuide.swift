import Foundation

/// The three steps a half is set up in, and which of them is still owed.
///
/// Derived from the config rather than stored, so it cannot drift from what is actually true:
/// a target added from the widget, a tag paired from the Anchor's own row and an anchor dropped
/// by Siri all move the guide along without anything having to tell it. The one thing the
/// config cannot answer is the last step of each — reading your own list is done when you say
/// it is, and an anchor lifts again without owing the guide a second showing — so that step
/// reads a flag on the app's model (`AppModel.finishedGuides`, `MacModel.finishedGuides`).
///
/// The shape is here rather than beside either app's views because both platforms draw the same
/// card from it. The steps themselves are not shared: the phone's first Rules step changes its
/// words with Screen Time data access, and the Mac cannot pair a tag at all, so each app writes
/// its own three — the phone's in `Furlough/Views/Guides.swift`, the Mac's below, where they are
/// pure enough to be tested.
struct HalfGuide {
    struct Step: Identifiable {
        var title: String
        var detail: String
        /// Sits under the whole card while this step is the live one, so the fact that belongs
        /// to a step arrives with the step rather than three screens earlier.
        var footnote: String?
        var isDone: Bool
        var id: String { title }
    }

    var half: Half
    var steps: [Step]

    /// The step to act on: the first one not done. Nil once the guide has nothing left to say,
    /// which is when the card folds away and the page underneath is the whole page.
    var live: Int? { steps.firstIndex { !$0.isDone } }
    var isRunning: Bool { live != nil }
    var footnote: String? { live.flatMap { steps[$0].footnote } }

    /// What the card is called. Not "Get started": it names the half, because the other half is
    /// one swipe away and may be running a guide of its own.
    var title: String {
        switch half {
        case .rules: "Setting up Rules"
        case .anchor: "Setting up the Anchor"
        }
    }
}

#if os(macOS)
extension HalfGuide {
    /// Pick the apps, give the first one a rule, read the list.
    ///
    /// The phone's first step offers the fortnight Screen Time just read; there is no such API
    /// on the Mac, so the step is the picker and says what this Mac can hold.
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

    /// Hear from the phone, choose what it holds, drop it.
    ///
    /// The phone's first step is *Pair a tag*, and this Mac has no reader to pair one with. What
    /// stands in its place is the same fact from the other end: the only thing that can release
    /// an anchor dropped here is a tag scanned on the phone, arriving through iCloud, so this Mac
    /// will not drop one until a phone has written the shared record once — see
    /// `AnchorSync.macDrop`. `phoneSeen` is that latch.
    static func macAnchor(config: Config, finished: Bool, phoneSeen: Bool) -> HalfGuide {
        let anchor = config.anchor
        return HalfGuide(half: .anchor, steps: [
            Step(
                title: "Drop it once from your iPhone",
                detail: "This Mac has no tag reader, so your iPhone's tag is the only key. Drop the anchor there once and this Mac will have heard from it.",
                footnote: "Both devices signed into the same Apple Account is the whole of the link. There is nothing to pair here and nothing to switch on.",
                isDone: phoneSeen
            ),
            Step(
                title: "Choose what it holds",
                detail: "A list you lock, or every app on this Mac with a few left open.",
                footnote: "No delay applies to the Anchor. Dropping it only ever takes things away.",
                isDone: anchor.hasSomethingToHold
            ),
            Step(
                title: "Drop it",
                // Before anything is chosen `heldDescription` counts an empty list — "0 items" —
                // which is a true sentence about a step that has not happened and a poor one to
                // read two steps ahead of it.
                // "\(heldDescription) goes out of reach" reads wrong half the time — a count
                // takes a plural verb and "Everything except 3" a singular one. Naming the thing
                // after the colon sidesteps the agreement rather than picking a verb per scope.
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
