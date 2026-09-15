import FamilyControls
import SwiftUI

/// Which half a usage suggestion card offers to act on.
enum UsageOffer {
    case rules
    case anchor
    case both
}

/// Where one card's answer would land, under `UsageOffer.both`.
enum UsageDestination: String, CaseIterable, Identifiable {
    case rules, anchor, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules: "Rules"
        case .anchor: "Anchor"
        case .both: "Both"
        }
    }

    var writesRule: Bool { self != .anchor }
    var holds: Bool { self != .rules }
}

/// Where one card stands in this run of the flow. Skips are never persisted — every time the
/// flow reopens, every app is offered again (Zach's call, 2026-09-08).
enum UsageCardState: Equatable {
    case offered
    case applied(Applied)
    case skipped
    case failed(String)

    /// What a card did when Apply was pressed: a rule, a place on the anchor's list, or both.
    struct Applied: Equatable {
        /// The rules row the rule was written on, or nil when nothing but the anchor happened.
        var targetID: UUID?
        /// The doors the anchor took in, and what Undo takes back off it.
        var heldKinds: [TargetKind] = []
        /// True only when this flow created the rule fresh — the only case Undo may remove it
        /// again; see `AppModel.undoFreshTarget`. The anchor's list has no delay and is always
        /// undoable regardless.
        var fresh = false
        /// What `AppModel.ApplyOutcome` said, plus the anchor's half where there was one.
        var message: String
        /// True when the rule loosened and must sit out the delay; the collapsed line names the
        /// time directly instead of hiding it behind a tap.
        var waiting = false
        /// Where the answer will land once Screen Time hands over the token, or nil once it has
        /// been written. The card says Applied either way (Zach's call, 2026-09-14: the press has
        /// to answer at once, and the Done button is where the double-check waits); `rules` and
        /// `holds` read the intent, so the folded line and the closing count describe the same
        /// thing before and after the write. `UsageView.land` finishes it.
        var owed: UsageDestination?

        var pending: Bool { owed != nil }
        var rules: Bool { targetID != nil || owed?.writesRule == true }
        var holds: Bool { !heldKinds.isEmpty || owed?.holds == true }

        /// Only a freshly-created rule or an anchor-only change can be undone here; a loosened
        /// pre-existing rule belongs in the editor instead. A card still owed has written
        /// nothing, so it is always undoable — `UsageView.undo` just lets the write go.
        var canUndo: Bool { fresh || targetID == nil }

        func line(for item: Recommendation) -> String {
            if waiting { return message }
            let rule = rules ? item.consequence() : nil
            let held = holds ? "Out of reach the moment you drop the anchor." : nil
            return [rule, held].compactMap { $0 }.joined(separator: " ")
        }
    }
}

extension UsageCardState.Applied {
    /// What the model wrote (`AppModel.applyUsage`), as the card keeps it.
    init(_ written: AppModel.UsageApply) {
        self.init(
            targetID: written.targetID,
            heldKinds: written.heldKinds,
            fresh: written.fresh,
            message: written.message,
            waiting: written.waiting
        )
    }
}

/// Mirrors `UsageReportCard` in the report extension, used where iOS can't read Screen Time
/// numbers directly — keep the two in sync.
struct UsageSuggestionCard: View {
    let item: Recommendation
    let entry: UsageEntry
    let days: Int
    let state: UsageCardState
    /// Binding lives on the page, so a chosen destination carries across cards for the run.
    var offer: UsageOffer = .rules
    @Binding var destination: UsageDestination
    let apply: () -> Void
    let skip: () -> Void
    let undo: () -> Void
    let collapse: () -> Void

    private var landing: UsageDestination {
        switch offer {
        case .rules: .rules
        case .anchor: .anchor
        case .both: destination
        }
    }

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
            verdict
            CardDivider()
            actions
        }
        .padding(16)
        .emberCard()
    }

    // MARK: What Furlough would do

    @ViewBuilder
    private var verdict: some View {
        switch offer {
        case .rules:
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "What Furlough would do", color: Ember.amber)
                RuleDrawing(item: item)
            }
        case .anchor:
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "What the Anchor would do", color: Ember.amber)
                AnchorHolding()
            }
        case .both:
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "What Furlough would do", color: Ember.amber)
                RuleDrawing(item: item)
                    // Dimmed, not hidden — keeps the schedule visible for comparison even when
                    // leaning toward the Anchor instead.
                    .opacity(landing.writesRule ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.2), value: landing.writesRule)
            }
        }
    }

    // MARK: What it is

    private var header: some View {
        HStack(spacing: 12) {
            if let kind = entry.targetKind {
                TokenTile(kind: kind, size: 42)
            } else {
                MonogramTile(entry: entry, size: 42)
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

    /// Apple's token name once available; otherwise `Brand`'s plain name — `localizedDisplayName`
    /// is nil with data access, and a bundle identifier must never reach the screen.
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

    private var subtitle: String {
        let pickups = Int(item.pickupsPerDay.rounded())
        guard pickups >= 1 else { return "Last \(days) days" }
        return "\(pickups) pickups a day · last \(days) days"
    }

    // MARK: What happens next

    /// Not "Hold it" — nothing goes out of reach until the anchor is actually dropped, so that
    /// wording would be misleading.
    private var applyTitle: String {
        landing == .anchor ? "Add to the Anchor's list" : "Apply"
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .offered:
            VStack(alignment: .leading, spacing: 12) {
                if offer == .both {
                    UsageDestinationPicker(destination: $destination)
                }
                HStack(spacing: 12) {
                    ProminentButton(title: applyTitle, action: apply)
                    GhostButton(title: "Skip", color: Ember.muted, action: skip)
                        .frame(width: 78)
                }
            }
        case .applied(let done):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    UsageAppliedMark()
                    Spacer()
                    if done.canUndo { UsageUndoButton(action: undo) }
                }
                // No outcome to quote until the write lands; until then the line says what was asked.
                Text(done.pending ? done.line(for: item) : done.message)
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    if let targetID = done.targetID { UsageEditRuleLink(targetID: targetID) }
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

/// No schedule to draw — the Anchor has no hours or budget, just hold-or-not.
struct AnchorHolding: View {
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            AnchorGlyph(isAnchored: false, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("Out of reach the moment you drop the anchor.")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No hours and no budget — it is held or it is not, and only a paired tag lifts it.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Lets a `.both` card choose where its answer lands, with the effect spelled out below it.
struct UsageDestinationPicker: View {
    @Binding var destination: UsageDestination

    /// Kept short — repeating the schedule here would pad three answers into a wall of text.
    private var effect: String {
        switch destination {
        case .rules: "The hours above, and nothing on the Anchor's list."
        case .anchor: "The hours above are not written. It goes on the Anchor's list instead."
        case .both: "The hours above, and on the Anchor's list — out of reach when you drop it."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Eyebrow(text: "Apply to", color: Ember.faint)
                Spacer(minLength: 0)
            }
            HStack(spacing: 3) {
                ForEach(UsageDestination.allCases) { value in
                    Button {
                        guard value != destination else { return }
                        withAnimation(.snappy(duration: 0.2)) { destination = value }
                    } label: {
                        Text(value.title)
                            .emberBody(12.5, .bold)
                            .foregroundStyle(value == destination ? Ember.cream : Ember.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(value == destination ? Ember.ember.opacity(0.22) : .clear)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(value.title)
                    .accessibilityAddTraits(value == destination ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Ember.cardBorder, lineWidth: 1))
            Text(effect)
                .emberBody(11.5)
                .foregroundStyle(Ember.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Applying folds the card immediately so cards still waiting to be read aren't pushed down the
/// page by it.
struct UsageAppliedLine: View {
    let item: Recommendation
    let entry: UsageEntry
    let done: UsageCardState.Applied
    let undo: () -> Void
    let expand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                if let kind = entry.targetKind {
                    TokenTile(kind: kind, size: 24)
                } else {
                    MonogramTile(entry: entry, size: 24)
                }
                if let kind = entry.targetKind {
                    TokenName(kind: kind).foregroundStyle(Ember.cream)
                } else {
                    Text(entry.plainName).emberBody(13).foregroundStyle(Ember.cream).lineLimit(1)
                }
                Spacer(minLength: 8)
                // Shows which half this landed on without reopening the card.
                if done.holds { AnchorGlyph(isAnchored: false, size: 20) }
                UsageAppliedMark(size: 12)
            }
            Text(done.line(for: item))
                .emberBody(11.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if done.canUndo { UsageUndoButton(action: undo) }
                if let targetID = done.targetID { UsageEditRuleLink(targetID: targetID) }
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

/// Reopening returns the card to `.offered` — skip state is never stored.
struct UsageSkippedLine: View {
    let item: Recommendation
    let entry: UsageEntry
    var offer: UsageOffer = .rules
    let reopen: () -> Void

    /// Under `.both`, shows the schedule since the destination was never chosen.
    private var passedOn: String {
        offer == .anchor ? "Not on the Anchor's list." : item.consequence()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                if let kind = entry.targetKind {
                    TokenTile(kind: kind, size: 24).opacity(0.55)
                } else {
                    MonogramTile(entry: entry, size: 24).opacity(0.55)
                }
                if let kind = entry.targetKind {
                    TokenName(kind: kind).foregroundStyle(Ember.muted)
                } else {
                    Text(entry.plainName).emberBody(13).foregroundStyle(Ember.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Eyebrow(text: "Skipped", color: Ember.faint)
            }
            Text(passedOn)
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

/// Shared by folded and open cards so "Applied" can't drift between the two. Says Applied
/// even while the write is still owed to Screen Time (`UsageCardState.Applied.owed`): the
/// press answers at once, and a write that never lands is taken back with the toast instead.
struct UsageAppliedMark: View {
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Ember.moss)
            Eyebrow(text: "Applied", color: Ember.moss)
        }
    }
}

/// The onboarding step's Done button. While the last applies are still being confirmed with
/// Screen Time it becomes the wait itself — a running hourglass and a line that changes every
/// couple of seconds — so a slow answer reads as work going on rather than a hang. The lines
/// are deliberately silly (Zach's call, 2026-09-14); the hourglass is the honest part.
struct UsageFinishButton: View {
    let title: String
    let finishing: Bool
    let action: () -> Void

    /// Read in order from the first, so the wait always opens on the same line.
    static let quips = [
        "Accessing the mainframe…",
        "Asking Screen Time nicely…",
        "Reticulating splines…",
        "Counting the hours twice…",
        "Checking every door…",
        "Waiting on Cupertino…",
        "Turning the glass over…",
        "Reading the fine print…",
    ]
    static let quipSeconds: TimeInterval = 2.4

    var body: some View {
        Button(action: action) {
            Group {
                if finishing {
                    UsageFinishingLabel()
                } else {
                    Text(title).emberBody(14.5, .bold)
                }
            }
            .foregroundStyle(Ember.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .emberGlassButton(prominent: true, tint: Ember.ember)
        .controlSize(.large)
        // Not `.disabled` while working: that dims the glass, and a dimmed "Accessing the
        // mainframe…" reads as stuck rather than busy. `UsageView.finish` ignores a second press.
        .animation(.easeInOut(duration: 0.2), value: finishing)
    }
}

/// Under the working Done button once Screen Time has kept it waiting a couple of seconds:
/// the two ways out. Cancel is a real cancel — every press still owed is dropped and its card
/// goes back on offer, nothing written (Zach, 2026-09-14: a cancel that still goes through is
/// worse than none). Finishing in the background leaves now and lets the model land the rest.
struct UsageFinishEscape: View {
    let cancel: () -> Void
    let background: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GhostButton(title: "Cancel", color: Ember.muted, action: cancel)
            GhostButton(title: "Finish in the background", color: Ember.amber, action: background)
        }
    }
}

/// Its own view so `started` is set the moment the wait begins, not when the button first drew.
private struct UsageFinishingLabel: View {
    @State private var started = Date.now

    var body: some View {
        TimelineView(.periodic(from: started, by: UsageFinishButton.quipSeconds)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(started))
            let index = Int(elapsed / UsageFinishButton.quipSeconds) % UsageFinishButton.quips.count
            HStack(spacing: 9) {
                LivingHourglass(state: .open(level: 0.55, warned: false))
                    .frame(width: 14, height: 19)
                Text(UsageFinishButton.quips[index])
                    .emberBody(14.5, .bold)
                    .contentTransition(.opacity)
            }
            .animation(.easeInOut(duration: 0.3), value: index)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finishing up")
    }
}

/// Screen Time confirms writes asynchronously; this names the apps whose write didn't land
/// (rather than a bare count) and lets them be retried.
struct UsageTroubleToast: View {
    let names: [String]
    let retry: () -> Void
    let dismiss: () -> Void

    private var line: String {
        let list = names.formatted(.list(type: .and))
        return names.count == 1
            ? "Furlough could not finish \(list). Screen Time never handed the app over, so nothing was written for it."
            : "Furlough could not finish \(list). Screen Time never handed those apps over, so nothing was written for them."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.ember)
                Eyebrow(text: names.count == 1 ? "1 app did not go through" : "\(names.count) apps did not go through", color: Ember.ember)
                Spacer(minLength: 8)
            }
            Text(line)
                .emberBody(12)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button("Try again", action: retry)
                    .emberBody(13, .semibold)
                    .foregroundStyle(Ember.amber)
                    .buttonStyle(.plain)
                Button("Dismiss", action: dismiss)
                    .emberBody(13, .semibold)
                    .foregroundStyle(Ember.muted)
                    .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .emberCard()
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .accessibilityElement(children: .contain)
    }
}

struct UsageUndoButton: View {
    let action: () -> Void

    var body: some View {
        Button("Undo", action: action)
            .emberBody(13, .semibold)
            .foregroundStyle(Ember.ember)
            .buttonStyle(.plain)
    }
}

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

/// Sized like `TokenTile` so a real icon can later replace it without shifting the row. The
/// dashed-square fallback should never actually render — see `UsageEntry.isNamed`.
struct MonogramTile: View {
    let entry: UsageEntry
    var size: CGFloat = 34

    private var isSite: Bool { UsageAnalysis.domain(inKey: entry.key) != nil }
    private var letter: String? { entry.isNamed ? Brand.monogram(entry.plainName) : nil }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.26, style: .continuous) }

    var body: some View {
        Group {
            if let letter, let color = Brand.color(forKey: entry.key) {
                Text(letter)
                    .emberDisplaySmall(size * 0.5)
                    .foregroundStyle(Brand.isLight(color) ? Color(hex: Brand.ink) : Ember.cream)
                    .frame(minWidth: size, minHeight: size)
                    .background(Color(hex: color), in: shape)
            } else if let letter, !isSite {
                Text(letter)
                    .emberDisplaySmall(size * 0.5)
                    .foregroundStyle(Ember.amber)
                    .frame(minWidth: size, minHeight: size)
                    .background(Color.white.opacity(0.07), in: shape)
            } else {
                Image(systemName: isSite ? TokenTile.hostSymbol : "square.dashed")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Ember.amber)
                    .frame(width: size, height: size)
                    .background(Color.white.opacity(0.07), in: shape)
            }
        }
        .overlay(shape.strokeBorder(Ember.cardBorder, lineWidth: 1))
    }
}
