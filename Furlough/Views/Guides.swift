import SwiftUI

/// `HalfGuide` itself lives in Shared/Core and is reused by the Mac; these are the phone's own
/// three steps per half (not shared), since wording differs by platform capability.
extension HalfGuide {
    // MARK: The two guides

    /// `hasUsageNumbers` only changes step one's wording and button; see
    /// `AppModel.considerUsageStep`.
    static func rules(config: Config, hasUsageNumbers: Bool, finished: Bool) -> HalfGuide {
        HalfGuide(half: .rules, steps: [
            Step(
                title: "Pick the apps that eat your day",
                detail: hasUsageNumbers
                    ? "Furlough has read the last \(UsageReader.days) days. Start from the app you spend the most on."
                    : "Apps and categories, from Apple's picker. Furlough is never told which ones you picked.",
                isDone: !config.targets.isEmpty
            ),
            Step(
                title: "Give the first one a rule",
                detail: "A minute budget, and allowed windows if you want them — the same every day, or different at weekends.",
                footnote: "Adding an app enforces nothing on its own. Saving its first rule is what starts it.",
                // Shows what the usage flow's Apply already added, since that flow lands here right after.
                kinds: config.targets.map(\.kind),
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

    static func anchor(config: Config, finished: Bool) -> HalfGuide {
        let anchor = config.anchor
        return HalfGuide(half: .anchor, steps: [
            Step(
                title: "Pair a tag",
                detail: "Any NTAG sticker, or the tag that came with another blocking product. Hold it to the top of your phone.",
                isDone: anchor.isPaired
            ),
            Step(
                title: "Choose what it holds",
                detail: "A list you lock, or the whole phone with a few apps left open.",
                footnote: "No delay applies to the Anchor. Dropping it only ever takes things away.",
                // Reflects what the usage flow already added to the Anchor's list.
                kinds: anchor.kinds,
                isDone: anchor.hasSomethingToHold
            ),
            Step(
                title: "Drop it",
                // Phrased as "Out of reach: X" rather than "X goes out of reach" to dodge
                // subject-verb agreement between singular/plural forms of heldDescription.
                detail: anchor.hasSomethingToHold
                    ? "One tap, from here or from the widget. Out of reach: \(anchor.heldDescription)."
                    : "One tap, from here or from the widget, and what you chose goes out of reach.",
                footnote: "Only a paired tag lifts it. Furlough has no unblock button, and this is the half that means it.",
                isDone: finished
            ),
        ])
    }
}

/// Caller supplies the button since each step's action differs (picker, push, NFC reader, etc.).
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

private struct GuideStepRow<Action: View>: View {
    let number: Int
    let step: HalfGuide.Step
    let isLive: Bool
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            marker
                .opacity(dimmed)
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .emberDisplaySmall(13.5)
                        .foregroundStyle(Ember.cream)
                    Text(step.detail)
                        .emberBody(11.5)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(dimmed)
                if !step.kinds.isEmpty {
                    GuideStepEvidence(kinds: step.kinds)
                        .padding(.top, 6)
                }
                if isLive {
                    action
                        .padding(.top, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number). \(step.title). \(step.isDone ? "Done" : (isLive ? "Now" : "Not yet"))")
    }

    /// Applied to the marker/text only, not the icon evidence row — icons should stay legible
    /// even when dimmed.
    private var dimmed: Double { isLive ? 1 : 0.55 }

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

/// Icons, not a count — answers "did X go through". Shows up to 6 (matches the Anchor's own
/// grid) then an overflow count.
struct GuideStepEvidence: View {
    let kinds: [TargetKind]
    private static let shown = 6

    private var tiles: [TargetKind] { Array(kinds.prefix(Self.shown)) }
    private var rest: Int { max(0, kinds.count - Self.shown) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, kind in
                TokenTile(kind: kind, size: 26)
            }
            if rest > 0 {
                Text("+\(rest)")
                    .font(EmberFont.numerals(11))
                    .foregroundStyle(Ember.muted)
                    .frame(minWidth: 26, minHeight: 26)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Ember.cardBorder, lineWidth: 1)
                    )
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kinds.count == 1 ? "1 app" : "\(kinds.count) apps")
    }
}

/// Separate from `Button` since some steps use `NavigationLink` instead.
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
    func guideButton() -> some View {
        emberGlassButton(prominent: true, tint: Ember.ember)
    }
}
