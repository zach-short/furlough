import SwiftUI

/// The checklist, on the Mac: three steps, the live one carrying the only button, the rest
/// dimmed. `HalfGuide` in Shared/Core is the shape and the Mac's own three steps of each; this
/// is the drawing.
///
/// A copy of the phone's `GuideCard` rather than one file both compile, for the reason
/// `MacComponents.swift` gives about `SectionLabel` and the rest: those live in each app's own
/// views, and Shared/UI is compiled into the iOS widget extension, which has none of them.
/// Unify the two when the components move.
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

/// The one button a live step gets: ember and filled, sized to its words rather than to the
/// card, so a checklist never looks like three things to press.
struct GuideButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title).emberBody(13, .bold)
            }
            .foregroundStyle(Ember.cream)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(Ember.ember)
    }
}
