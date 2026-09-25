import FamilyControls
import SwiftUI

/// Renders the system icon and name for an opaque Screen Time token. A typed host has no
/// token or artwork, so it draws its own text and a globe instead.
struct TokenLabel: View {
    let kind: TargetKind

    var body: some View {
        switch kind {
        case .application(let token): Label(token)
        case .webDomain(let token): Label(token)
        case .category(let token): Label(token)
        case .host(let host): Label(host, systemImage: TokenTile.hostSymbol)
        }
    }
}

/// Apple renders the token's text and ignores fonts/weights/colors, following only Dynamic
/// Type — `size` maps to that: xSmall (rows), xLarge (editor header), xxxLarge (hero).
struct TokenName: View {
    let kind: TargetKind
    var size: DynamicTypeSize = .xSmall

    var body: some View {
        if case .host(let host) = kind {
            // Drawn at the size/font Apple's view would use, so a row mixing both kinds matches.
            Text(host)
                .font(.system(size: Self.points(for: size), weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            TokenLabel(kind: kind)
                .labelStyle(.titleOnly)
                .lineLimit(1)
                .dynamicTypeSize(size)
                .environment(\.legibilityWeight, .bold)
        }
    }

    /// What `Label(token)` measures at each size, from an on-device measurement.
    static func points(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 14
        case .xLarge: 19
        case .xxxLarge: 23
        default: 16
        }
    }
}

/// The real app icon, scaled to fill `size`. Apple's system view is always 32pt but the artwork
/// inside it covers a varying fraction, so this measures the view and scales past that padding.
struct TokenTile: View {
    let kind: TargetKind
    var size: CGFloat = 34
    @State private var natural = CGSize.zero
    /// Matches the glyph the + button uses for Website.
    static let hostSymbol = "globe"

    var body: some View {
        if case .host = kind {
            Image(systemName: Self.hostSymbol)
                .font(.system(size: size * 0.48, weight: .semibold))
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
        } else {
            let longest = max(natural.width, natural.height)
            let scale = longest > 0 ? size / (longest * Self.artworkFraction(of: kind)) : 1
            TokenLabel(kind: kind)
                .labelStyle(.iconOnly)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
                .scaleEffect(scale)
                .frame(width: size, height: size)
        }
    }

    /// How much of Apple's 32pt icon view the artwork of `kind` covers: an app icon is a
    /// squircle filling 0.655 of the view (measured on-device); everything else runs edge to
    /// edge already. Scaling an edge-to-edge glyph as if it had this padding overflowed its
    /// frame in the Anchor grid — only scale past padding you've actually measured.
    private static func artworkFraction(of kind: TargetKind) -> CGFloat {
        if case .application = kind { return 0.655 }
        return 1
    }
}

/// Marks a rules row as also being on the anchor's list.
struct HeldMark: View {
    var size: CGFloat = 9

    var body: some View {
        AnchorShape()
            .fill(Ember.faint)
            .frame(width: size * 0.8, height: size)
            .accessibilityLabel("Held by the anchor")
    }
}

/// The mirror of `HeldMark`, in the anchor grid: this app also has a rule. Sits on the corner
/// since Apple's artwork fills the tile edge to edge.
struct RuledBadge: View {
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: "hourglass")
            .font(.system(size: size * 0.62, weight: .bold))
            .foregroundStyle(Ember.amber)
            .frame(width: size, height: size)
            .background(Ember.ground, in: Circle())
            .overlay(Circle().strokeBorder(Ember.cardBorder, lineWidth: 1))
            .accessibilityLabel("Has a rule")
    }
}

/// The 12 pt status hourglass and the next time on the right of a home row.
struct StatusChip: View {
    let status: TargetStatus
    let glass: HourglassState
    var allDay = false

    var body: some View {
        HStack(spacing: 5) {
            HourglassView(state: glass)
                .frame(width: 12, height: 16)
            if let text {
                Text(text)
                    .emberBody(11.5, .semibold)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }

    private var text: String? {
        switch status {
        case .anchored: "Anchored"
        case .open(let until): allDay ? "All day" : TimeFormat.until(until)
        case .closed(let next): TimeFormat.chip(next)
        case .exhausted(let next): next.map { TimeFormat.chip($0) }
        case .unconfigured: "Set up"
        case .blockedAllDay: nil
        }
    }

    private var color: Color {
        switch status {
        case .anchored: Ember.ember
        case .open: Ember.moss
        case .unconfigured: Ember.pending
        default: Ember.muted
        }
    }
}

/// Short copy for rows and the hero.
enum RowCopy {
    /// The rule line under a row's name. A rule that varies by day shows today's windows.
    static func detail(target: Target, status: TargetStatus, now: Date = .now) -> String {
        if target.kind.isCategory { return "Everything in it" }
        guard let rule = target.rule else { return "Not enforced yet" }
        guard rule.isEverAllowed else { return "Blocked all day" }
        let budget = TimeFormat.budget(rule.budget(on: Policy.weekday(now)))
        if case .exhausted = status { return "Used up today · \(budget)" }
        if rule.isSameEveryDay, rule.isSameBudgetEveryDay {
            return "\(TimeFormat.schedule(rule)) · \(budget)"
        }
        let today = rule.windows(on: Policy.weekday(now)).map { TimeFormat.window($0) }
        // Avoid pairing "Not today" with a budget figure that isn't on offer.
        guard !today.isEmpty else { return "Not today" }
        return "Today \(today.joined(separator: ", ")) · \(budget)"
    }

    static func pendingLine(_ change: PendingChange) -> String {
        "Change pending · \(change.effectiveAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// The prominent ember glass button used for Save and Allow.
struct ProminentButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Boxed to the label's height: the default large-control spinner is 32pt and
                // would grow the button when it starts working.
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Ember.cream)
                        .frame(width: 16, height: 16)
                }
                Text(title).emberBody(14.5, .bold)
            }
            .foregroundStyle(Ember.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .emberGlassButton(prominent: true, tint: Ember.ember)
        .controlSize(.large)
    }
}

/// A text-only button in Ember, for Remove and other quiet actions.
struct GhostButton: View {
    let title: String
    var color: Color = Ember.ember
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .emberBody(14.5, .bold)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A title, a line of context, one field and two actions: the app's own alert-with-a-field.
/// Not `.alert { TextField }`, whose field UIKit lays out ~15 pt right of center, flush into
/// the dialog's edge, and which crashes inside UIKit's layout if text size changes while it
/// is up. The caller clears its own state in `onCancel` and in the sheet binding's setter,
/// so a swipe down is the same as Cancel.
struct NamingSheet: View {
    let placeholder: String
    @Binding var name: String
    let confirmTitle: String
    var cancelTitle = "Cancel"
    /// Why the last confirm failed, shown in place above the actions. The sheet stays up so
    /// it can be read; the caller clears it once the sheet has gone.
    var error: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    /// Read once, when the sheet appears: confirming can change what the caller built them
    /// from (a first pairing makes the anchor paired), and the sheet would otherwise rewrite
    /// its own title while it slides away.
    @State private var title: String
    @State private var message: String
    @FocusState private var typing: Bool
    /// Seeded near the real content height so the sheet doesn't resize on open.
    @State private var contentHeight: CGFloat = 330

    init(
        title: String,
        message: String,
        placeholder: String,
        name: Binding<String>,
        confirmTitle: String,
        cancelTitle: String = "Cancel",
        error: String? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _title = State(initialValue: title)
        _message = State(initialValue: message)
        self.placeholder = placeholder
        _name = name
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.error = error
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(title)
                    .emberDisplay(24)
                    .foregroundStyle(Ember.cream)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .emberBody(13.5)
                    .foregroundStyle(Ember.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                TextField("Name", text: $name, prompt: Text(placeholder).foregroundStyle(Ember.faint))
                    .emberBody(15)
                    .foregroundStyle(Ember.cream)
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .focused($typing)
                    .onSubmit(onConfirm)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    // The padding around the field is part of the pill, so a tap there types too.
                    .contentShape(Capsule())
                    .onTapGesture { typing = true }
                    .padding(.top, 22)
                if let error {
                    EffectBanner(kind: .error(error))
                        .padding(.top, 12)
                        .transition(.opacity)
                }
                ProminentButton(title: confirmTitle, action: onConfirm)
                    .padding(.top, 18)
                GhostButton(title: cancelTitle, color: Ember.muted, action: onCancel)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground { EmberWall() }
        .onAppear { typing = true }
    }
}

/// A section label with the spacing from the mockups.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Eyebrow(text: text, color: Ember.faint, size: 10.5)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }
}

/// A one-line footnote in Faint.
struct Footnote: View {
    let text: String
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(text)
            .emberBody(10.5)
            .foregroundStyle(Ember.faint)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .padding(.horizontal, 8)
    }
}

/// Hairline between rows in a card.
struct CardDivider: View {
    var body: some View {
        Rectangle().fill(Ember.cardBorder).frame(height: 1)
    }
}
