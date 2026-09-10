import FamilyControls
import SwiftUI

/// Where one card stands in this run of the flow. Nothing here is written down: skipping is for
/// this run, and the next time the flow is opened every app is offered again. Zach's call,
/// 2026-09-08 — a skip is "not now", and there is no un-skip screen to build.
enum UsageCardState: Equatable {
    case offered
    /// The rule is written. `fresh` is true when the flow added the app itself, which is the
    /// only case it may take straight back; see `AppModel.undoFreshTarget`. `waiting` is true
    /// when the rule loosened what was there and so has to sit out the delay, which is the one
    /// thing the collapsed line says for itself rather than keep behind a tap: it names a time.
    case applied(targetID: UUID, fresh: Bool, message: String, waiting: Bool)
    case skipped
    case failed(String)
}

/// One app, answering three questions in order — what it is and how much of the day it takes,
/// where that time falls, and what Furlough would do about it — and then offering the two
/// buttons. The app draws this itself where iOS 26.4 lets it read the numbers; where it cannot,
/// `UsageReportCard` in the report extension draws the same anatomy and the buttons become a
/// hand-off to the picker.
struct UsageSuggestionCard: View {
    let item: Recommendation
    let entry: UsageEntry
    let days: Int
    let state: UsageCardState
    var isBusy = false
    let apply: () -> Void
    let skip: () -> Void
    let undo: () -> Void
    let collapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 9) {
                UsageHours(histogram: entry.histogram, item: item)
                Text(item.whereLine())
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CardDivider()
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "What Furlough would do", color: Ember.amber)
                RuleDrawing(item: item)
            }
            CardDivider()
            actions
        }
        .padding(16)
        .emberCard()
    }

    // MARK: What it is

    private var header: some View {
        HStack(spacing: 12) {
            if let kind = entry.targetKind {
                TokenTile(kind: kind, size: 42)
            } else {
                PlainTile(isSite: entry.key.hasPrefix("web:"), size: 42)
            }
            VStack(alignment: .leading, spacing: 3) {
                name
                Text(subtitle)
                    .emberBody(11)
                    .foregroundStyle(Ember.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(TimeFormat.budget(Int(item.averageDailyMinutes.rounded())))
                    .emberNumerals(16)
                Text("a day")
                    .emberBody(11)
                    .foregroundStyle(Ember.faint)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    /// Apple's own name for the app, drawn by Apple. With data access `localizedDisplayName` is
    /// nil, so the only name that exists is the one `Label(token)` draws inside this process —
    /// which is why a bundle identifier must never reach the screen.
    @ViewBuilder
    private var name: some View {
        if let kind = entry.targetKind {
            TokenName(kind: kind, size: .xLarge)
                .foregroundStyle(Ember.cream)
        } else {
            Text(entry.plainName)
                .emberDisplaySmall(17)
                .foregroundStyle(Ember.cream)
                .lineLimit(1)
        }
    }

    /// Pickups only when there are enough of them to say something.
    private var subtitle: String {
        let pickups = Int(item.pickupsPerDay.rounded())
        guard pickups >= 1 else { return "Last \(days) days" }
        return "\(pickups) pickups a day · last \(days) days"
    }

    // MARK: What happens next

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .offered:
            HStack(spacing: 12) {
                ProminentButton(title: isBusy ? "Applying…" : "Apply", isBusy: isBusy, action: apply)
                    .disabled(isBusy)
                GhostButton(title: "Skip", color: Ember.muted, action: skip)
                    .frame(width: 78)
            }
        case .applied(let targetID, let fresh, let message, _):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ember.moss)
                    Eyebrow(text: "Applied", color: Ember.moss)
                    Spacer()
                    if fresh { UsageUndoButton(action: undo) }
                }
                Text(message)
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    UsageEditRuleLink(targetID: targetID)
                    Spacer(minLength: 8)
                    UsageFoldButton(title: "Collapse", symbol: "chevron.up", action: collapse)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .emberBody(12)
                    .foregroundStyle(Ember.ember)
                    .fixedSize(horizontal: false, vertical: true)
                ProminentButton(title: "Try again", action: apply)
            }
        case .skipped:
            // The flow collapses a skipped card to `UsageSkippedLine` instead of drawing this.
            EmptyView()
        }
    }
}

/// An applied card, collapsed to its verdict: the app, what the rule now does, and the three
/// things left to do about it — take it back, open the rule, or put the whole card back. Applying
/// folds the card straight away, because a card that has been decided has stopped being a
/// question and the ones still waiting to be read should not be pushed down the page by it.
struct UsageAppliedLine: View {
    let item: Recommendation
    let entry: UsageEntry
    let targetID: UUID
    let fresh: Bool
    /// What `AppModel.ApplyOutcome` said, which is only worth the line when it names a time.
    let message: String
    let waiting: Bool
    let undo: () -> Void
    let expand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                if let kind = entry.targetKind {
                    TokenTile(kind: kind, size: 24)
                } else {
                    PlainTile(isSite: entry.key.hasPrefix("web:"), size: 24)
                }
                if let kind = entry.targetKind {
                    TokenName(kind: kind).foregroundStyle(Ember.cream)
                } else {
                    Text(entry.plainName).emberBody(13).foregroundStyle(Ember.cream).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ember.moss)
                    Eyebrow(text: "Applied", color: Ember.moss)
                }
            }
            // The rule, said in one line, so folding the card does not hide what was agreed to.
            Text(waiting ? message : item.consequence())
                .emberBody(11.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if fresh { UsageUndoButton(action: undo) }
                UsageEditRuleLink(targetID: targetID)
                Spacer(minLength: 8)
                UsageFoldButton(title: "Expand", symbol: "chevron.down", action: expand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        // Anywhere the three buttons are not. They are inside this, and a button takes its own
        // tap first, so Undo and Edit rule still do their own thing; the rest of the line opens
        // the card, the way the skipped line reopens from anywhere on it.
        .onTapGesture(perform: expand)
        .emberCard()
    }
}

/// A skipped card, folded the way an applied one is: the app, what the suggestion would have
/// done, and the way back to the card — the whole line, or the word. Dimmer than the applied
/// line throughout, because nothing was decided here.
///
/// Opening it opens the question again, so the card comes back offered rather than marked:
/// nothing about a skip is stored, and this run of the flow is the whole of its life.
struct UsageSkippedLine: View {
    let item: Recommendation
    let entry: UsageEntry
    let reopen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                if let kind = entry.targetKind {
                    TokenTile(kind: kind, size: 24).opacity(0.55)
                } else {
                    PlainTile(isSite: entry.key.hasPrefix("web:"), size: 24).opacity(0.55)
                }
                if let kind = entry.targetKind {
                    TokenName(kind: kind).foregroundStyle(Ember.muted)
                } else {
                    Text(entry.plainName).emberBody(13).foregroundStyle(Ember.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Eyebrow(text: "Skipped", color: Ember.faint)
            }
            // The rule that was on offer, so what was passed on is still on the page.
            Text(item.consequence())
                .emberBody(11.5)
                .foregroundStyle(Ember.faint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Spacer(minLength: 8)
                UsageFoldButton(title: "Expand", symbol: "chevron.down", action: reopen)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        // Anywhere at all: there is no other button on this line to take a tap first.
        .onTapGesture(perform: reopen)
        .emberCard()
    }
}

/// Takes the rule straight back off an app this run added. Ember, because it undoes rather
/// than does; the same words whether the card is folded or open.
struct UsageUndoButton: View {
    let action: () -> Void

    var body: some View {
        Button("Undo", action: action)
            .emberBody(13, .semibold)
            .foregroundStyle(Ember.ember)
            .buttonStyle(.plain)
    }
}

/// The way from an applied card into the rule it wrote.
struct UsageEditRuleLink: View {
    let targetID: UUID

    var body: some View {
        NavigationLink { RuleEditorView(targetID: targetID) } label: {
            HStack(spacing: 4) {
                Text("Edit rule").emberBody(13, .semibold)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Ember.amber)
        }
        .buttonStyle(.plain)
    }
}

/// Expand and Collapse: the quietest thing on the card, because it changes nothing but the view.
struct UsageFoldButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).emberBody(13, .semibold)
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Ember.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The tile for something Screen Time counted but handed no token for, so there is no artwork
/// to draw. The same shape `TokenTile` gives a typed host, in the same proportions.
struct PlainTile: View {
    let isSite: Bool
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: isSite ? TokenTile.hostSymbol : "square.dashed")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Ember.amber)
            .frame(width: size, height: size)
            .background(
                Color.white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Ember.cardBorder, lineWidth: 1)
            )
    }
}
