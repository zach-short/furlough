import SwiftUI

/// The phone's two guides: the steps themselves, and the card that draws them.
///
/// The shape they are built in — three steps, one live, the rest dimmed — is `HalfGuide` in
/// Shared/Core, because the Mac draws the same card from the same struct. What is here is the
/// phone's own three of each, which are not shared: the first Rules step changes its words with
/// Screen Time data access, and the Anchor's first step is a tag this Mac has no reader for.
extension HalfGuide {
    // MARK: The two guides

    /// Pick the apps, give the first one a rule, read the list.
    ///
    /// `hasUsageNumbers` only changes the first step's words and its button: where Furlough can
    /// read Screen Time itself, the shortest way to a good first rule is the fortnight it just
    /// read, and where it cannot, that tour is a thing to find in Settings rather than the first
    /// wall a new person meets. See `AppModel.considerUsageStep`.
    static func rules(config: Config, hasUsageNumbers: Bool, finished: Bool) -> HalfGuide {
        HalfGuide(half: .rules, steps: [
            Step(
                title: "Pick the apps that eat your day",
                detail: hasUsageNumbers
                    ? "Furlough has read the last \(UsageReader.days) days. Start from the app you spend the most on."
                    : "Apps and categories, from Apple's picker. Furlough is never told which ones you picked.",
                footnote: "Websites work too, typed by name. The + button offers both.",
                isDone: !config.targets.isEmpty
            ),
            Step(
                title: "Give the first one a rule",
                detail: "A minute budget, and allowed windows if you want them — the same every day, or different at weekends.",
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

    /// Pair a tag, choose what it holds, drop it.
    ///
    /// The tag comes first because nothing can drop without a key, because the reader only works
    /// with the app in front of you, and because someone arriving from another blocking product
    /// already has one in their hand.
    static func anchor(config: Config, finished: Bool) -> HalfGuide {
        let anchor = config.anchor
        return HalfGuide(half: .anchor, steps: [
            Step(
                title: "Pair a tag",
                detail: "Any NTAG sticker, or the tag that came with another blocking product. Hold it to the top of your phone.",
                footnote: "Leave it somewhere that makes you think — a drawer at home, a desk you have to walk to.",
                isDone: anchor.isPaired
            ),
            Step(
                title: "Choose what it holds",
                detail: "A list you lock, or the whole phone with a few apps left open.",
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
                    ? "One tap, from here or from the widget. Out of reach: \(anchor.heldDescription)."
                    : "One tap, from here or from the widget, and what you chose goes out of reach.",
                footnote: "Only a paired tag lifts it. Furlough has no unblock button, and this is the half that means it.",
                isDone: finished
            ),
        ])
    }
}

/// The checklist: three steps, the live one carrying the only button, the rest dimmed.
///
/// The caller supplies the button, because each step's is a different thing — Apple's picker, a
/// push into the editor, an NFC reader, the Anchor button itself — and a card that owned them
/// all would have to know about every one of those.
struct GuideCard<Action: View>: View {
    let guide: HalfGuide
    @ViewBuilder var action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: guide.title)
            VStack(spacing: 0) {
                ForEach(Array(guide.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { CardDivider() }
                    GuideStepRow(
                        number: index + 1,
                        step: step,
                        isLive: guide.live == index
                    ) {
                        if guide.live == index { action }
                    }
                }
            }
            .emberCard()
            if let footnote = guide.footnote {
                Footnote(text: footnote)
                    .padding(.top, 8)
            }
        }
        .animation(.snappy(duration: 0.3), value: guide.live)
    }
}

/// One row of the checklist: its number or its tick, its words, and — on the live one — the
/// button and nothing else on the card.
private struct GuideStepRow<Action: View>: View {
    let number: Int
    let step: HalfGuide.Step
    let isLive: Bool
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            marker
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .emberDisplaySmall(13.5)
                    .foregroundStyle(Ember.cream)
                Text(step.detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if isLive {
                    action
                        .padding(.top, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        // Done and not-yet look different from live in the same way: they are not what you are
        // being asked to do. A tick is still legible at this opacity; a dim number is the point.
        .opacity(isLive ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number). \(step.title). \(step.isDone ? "Done" : (isLive ? "Now" : "Not yet"))")
    }

    private var marker: some View {
        ZStack {
            Circle()
                .fill(step.isDone ? Ember.moss : (isLive ? Ember.amber : Color.white.opacity(0.07)))
            Circle()
                .strokeBorder(Ember.cardBorder, lineWidth: step.isDone || isLive ? 0 : 1)
            if step.isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ember.ground)
            } else {
                Text("\(number)")
                    .font(EmberFont.numerals(11))
                    .foregroundStyle(isLive ? Ember.ground : Ember.faint)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// The words inside a live step's button. Its own view because half of these buttons are
/// `NavigationLink`s — a step whose action is a push should not have to be a second kind of
/// button to say so.
struct GuideButtonLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title).emberBody(13, .bold)
        }
        .foregroundStyle(Ember.cream)
    }
}

/// The one button a live step gets: ember and filled, sized to its words rather than to the
/// card, so a checklist never looks like three things to press.
struct GuideButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GuideButtonLabel(title: title, systemImage: systemImage)
        }
        .guideButton()
    }
}

extension View {
    /// The live step's button, however it is spelled — a `Button` or a `NavigationLink`.
    func guideButton() -> some View {
        buttonStyle(.glassProminent).tint(Ember.ember)
    }
}
