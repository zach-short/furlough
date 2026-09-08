import FamilyControls
import SwiftUI

/// Where one card stands in this run of the flow. Nothing here is written down: skipping is for
/// this run, and the next time the flow is opened every app is offered again. Zach's call,
/// 2026-09-08 — a skip is "not now", and there is no un-skip screen to build.
enum UsageCardState: Equatable {
    case offered
    /// The rule is written. `fresh` is true when the flow added the app itself, which is the
    /// only case it may take straight back; see `AppModel.undoFreshTarget`.
    case applied(targetID: UUID, fresh: Bool, message: String)
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
        case .applied(let targetID, let fresh, let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ember.moss)
                    Eyebrow(text: "Applied", color: Ember.moss)
                    Spacer()
                    if fresh {
                        Button("Undo", action: undo)
                            .emberBody(13, .semibold)
                            .foregroundStyle(Ember.ember)
                            .buttonStyle(.plain)
                    }
                }
                Text(message)
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink { RuleEditorView(targetID: targetID) } label: {
                    HStack(spacing: 4) {
                        Text("Edit rule").emberBody(13, .semibold)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Ember.amber)
                }
                .buttonStyle(.plain)
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

/// A skipped card, collapsed to a line. Tapping it offers the suggestion again; nothing about
/// the skip is stored, so this run of the flow is the whole of its life.
struct UsageSkippedLine: View {
    let item: Recommendation
    let entry: UsageEntry
    let reopen: () -> Void

    var body: some View {
        Button(action: reopen) {
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
                Text("Skipped").emberBody(11.5).foregroundStyle(Ember.faint)
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ember.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .emberCard()
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
