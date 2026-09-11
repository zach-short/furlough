import FamilyControls
import SwiftUI

/// What a card offers to do about an app: the half the intro was told to start on, or the
/// question when it was told both.
///
/// The page is the same page either way — where a fortnight went, heaviest app first — because
/// that is worth reading whichever half you came for. What changes is the third question a card
/// answers. Rules propose hours and a budget; the Anchor has neither to propose, so its card
/// asks the only question the Anchor has: hold it, or don't. Somebody who asked for both is
/// shown the schedule and then asked where it should land, because they are the one person on
/// this screen for whom that is a real choice.
enum UsageOffer {
    case rules
    case anchor
    case both
}

/// Where one card's answer would land, under `UsageOffer.both`. The default is both, which is
/// what was asked for; the segment is there because "both" is a sensible default and a poor
/// rule, and an app can deserve hours without deserving the tag.
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

/// Where one card stands in this run of the flow. Nothing here is written down: skipping is for
/// this run, and the next time the flow is opened every app is offered again. Zach's call,
/// 2026-09-08 — a skip is "not now", and there is no un-skip screen to build.
enum UsageCardState: Equatable {
    case offered
    /// Something was done. See `Applied`.
    case applied(Applied)
    case skipped
    case failed(String)

    /// What a card did when Apply was pressed, which is no longer one thing: a rule, a place on
    /// the anchor's list, or both at once.
    struct Applied: Equatable {
        /// The rules row the rule was written on, or nil when nothing but the anchor happened.
        var targetID: UUID?
        /// The doors the anchor took in, and what Undo takes back off it.
        var heldKinds: [TargetKind] = []
        /// True when the flow added the app to Rules itself, which is the only case it may take
        /// the rule straight back; see `AppModel.undoFreshTarget`. Says nothing about the
        /// anchor's list, which has no delay and is always takeable back.
        var fresh = false
        /// What `AppModel.ApplyOutcome` said, plus the anchor's half where there was one.
        var message: String
        /// The rule loosened what was there and so has to sit out the delay — the one thing the
        /// collapsed line says for itself rather than keep behind a tap: it names a time.
        var waiting = false

        var holds: Bool { !heldKinds.isEmpty }

        /// Whether Undo can put everything back. A rule written on a row that was already there
        /// is a loosening like any other and belongs in the editor, where the delay is
        /// explained; everything this flow made itself comes straight back off.
        var canUndo: Bool { fresh || targetID == nil }

        /// What was done, in the one line the folded card carries. A waiting rule names its
        /// time and that outranks everything; otherwise the rule as a sentence, the anchor as a
        /// sentence, or both.
        func line(for item: Recommendation) -> String {
            if waiting { return message }
            let rule = targetID != nil ? item.consequence() : nil
            let held = holds ? "Out of reach the moment you drop the anchor." : nil
            return [rule, held].compactMap { $0 }.joined(separator: " ")
        }
    }
}

/// One app, answering three questions in order — what it is and how much of the day it takes,
/// where that time falls, and what Furlough would do about it — and then offering the two
/// buttons. The app draws this itself where iOS 26.4 lets it read the numbers; where it cannot,
/// `UsageReportCard` in the report extension draws the same anatomy and the buttons become a
/// hand-off to the picker.
///
/// The first two questions are the same for everybody. The third is the half the intro was told
/// to start on (`UsageOffer`): a schedule for Rules, one sentence for the Anchor, and for
/// somebody who asked for both, the schedule followed by the question of where it lands.
struct UsageSuggestionCard: View {
    let item: Recommendation
    let entry: UsageEntry
    let days: Int
    let state: UsageCardState
    /// Which half this card is offering, and — under `.both` — where the offer lands. The
    /// binding is the page's, so the answer carries from one card to the next: choosing once is
    /// choosing for the run unless the next app deserves something else.
    var offer: UsageOffer = .rules
    @Binding var destination: UsageDestination
    var isBusy = false
    let apply: () -> Void
    let skip: () -> Void
    let undo: () -> Void
    let collapse: () -> Void

    /// What Apply would do, given the offer and — under `.both` — the segment.
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

    /// The third question, answered in the shape the offer has. Rules draw a schedule; the
    /// Anchor has none to draw and says the one thing it does instead; both draw the schedule
    /// and then ask where it goes.
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
                    // Dimmed rather than hidden when the answer is the Anchor alone: the
                    // schedule is still the proposal on the table, and taking it off the card
                    // the moment somebody leans the other way makes the comparison impossible.
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

    /// Apple's own name for the app, drawn by Apple, once there is a token to draw it from.
    /// Until then the tables' name (`Brand.name`, via `plainName`): with data access
    /// `localizedDisplayName` is nil, and a bundle identifier must never reach the screen.
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

    /// "Apply" writes something with hours in it; "Hold it" only ever puts a name on a list.
    /// Two words rather than one, because the Anchor's button is not an apply — there is
    /// nothing to apply — and calling it one would be the card's only dishonest word.
    private var applyTitle: String {
        if isBusy { return landing == .anchor ? "Holding…" : "Applying…" }
        return landing == .anchor ? "Hold it" : "Apply"
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
                    ProminentButton(title: applyTitle, isBusy: isBusy, action: apply)
                        .disabled(isBusy)
                    GhostButton(title: "Skip", color: Ember.muted, action: skip)
                        .frame(width: 78)
                }
            }
        case .applied(let done):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ember.moss)
                    Eyebrow(text: "Applied", color: Ember.moss)
                    Spacer()
                    if done.canUndo { UsageUndoButton(action: undo) }
                }
                Text(done.message)
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

/// What the Anchor would do about this app, where Rules would draw a schedule. There is no
/// picture to draw, because there is nothing gradual about it: the Anchor has no hours and no
/// budget, so its whole proposal is one line and the mark beside it.
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

/// The question a card asks somebody who came for both halves: Rules, the Anchor, or both, and
/// one line saying what that means for this app. The segment is the ask and the line is the
/// answer read back — between them they are the whole of "in a clear, simple and concise
/// manner", which is what was asked for and all that was asked for.
struct UsageDestinationPicker: View {
    @Binding var destination: UsageDestination

    /// What Apply would do, in one sentence. Written against the drawing above rather than
    /// repeating it: the schedule has just been read, and saying it a second time under the
    /// segment is how three short answers turn into a wall.
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

/// An applied card, collapsed to its verdict: the app, what the rule now does, and the three
/// things left to do about it — take it back, open the rule, or put the whole card back. Applying
/// folds the card straight away, because a card that has been decided has stopped being a
/// question and the ones still waiting to be read should not be pushed down the page by it.
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
                // The anchor's own mark where the anchor took it in, so a folded list says
                // which half each line landed on without being read.
                if done.holds { AnchorGlyph(isAnchored: false, size: 20) }
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ember.moss)
                    Eyebrow(text: "Applied", color: Ember.moss)
                }
            }
            // What was done, said in one line, so folding does not hide what was agreed to.
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

/// A skipped card, folded the way an applied one is: the app, what the suggestion would have
/// done, and the way back to the card — the whole line, or the word. Dimmer than the applied
/// line throughout, because nothing was decided here.
///
/// Opening it opens the question again, so the card comes back offered rather than marked:
/// nothing about a skip is stored, and this run of the flow is the whole of its life.
struct UsageSkippedLine: View {
    let item: Recommendation
    let entry: UsageEntry
    /// Which half was on offer, so the line says what was actually passed on: a schedule where
    /// one was proposed, and the Anchor's one sentence where none was.
    var offer: UsageOffer = .rules
    let reopen: () -> Void

    /// What was on the table. Under `.both` the schedule, because that is what the card drew
    /// and the destination was never answered.
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
            // What was on offer, so what was passed on is still on the page.
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

/// The tile for something Screen Time has handed no token for yet, so there is no artwork to
/// draw: the first letter of the name on the colour the app is known by (`Brand`), in the shape
/// and proportions `TokenTile` gives a typed host, so the real icon can take its place without
/// the row moving. An app the tables know but have no colour for gets its letter in amber on the
/// plain ground; a site they do not know keeps the globe. An app they do not know is not drawn at
/// all (`UsageEntry.isNamed`), so the dashed square is a fallback that should never be seen.
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
                    .frame(width: size, height: size)
                    .background(Color(hex: color), in: shape)
            } else if let letter, !isSite {
                Text(letter)
                    .emberDisplaySmall(size * 0.5)
                    .foregroundStyle(Ember.amber)
                    .frame(width: size, height: size)
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
