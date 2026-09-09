import FamilyControls
import SwiftUI

/// Renders the system icon and name for an opaque Screen Time token.
///
/// A typed host has no token and no system artwork, so it draws itself: its own text and a
/// globe. `TokenName` and `TokenTile` branch on it before they get here, because the sizing
/// each of them does is calibrated to Apple's view and means nothing for ours.
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

/// The app's real name. Apple renders the text and ignores fonts, weights and colours; it only
/// follows Dynamic Type, so `size` is how rows (xSmall, about 14 pt), the editor header
/// (xLarge, about 19 pt) and the hero (xxxLarge, about 23 pt) pick their size.
struct TokenName: View {
    let kind: TargetKind
    var size: DynamicTypeSize = .xSmall

    var body: some View {
        if case .host(let host) = kind {
            // Ours to draw, so it is drawn at the size Apple's view would have come out at,
            // in the system font it uses. A row holding both kinds has to look like one list.
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

    /// What `Label(token)` measures at each of the three sizes this is asked for, from the
    /// sizing lab run on the device on 2026-09-07.
    static func points(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 14
        case .xLarge: 19
        case .xxxLarge: 23
        default: 16
        }
    }
}

/// The real app icon, scaled to fill `size`. The system view is always 32 pt, but how much of
/// it the artwork actually covers depends on the kind of token, so the tile measures the view
/// and scales past whatever padding that kind is known to have. No frame of our own: the
/// artwork brings its rounded square.
struct TokenTile: View {
    let kind: TargetKind
    var size: CGFloat = 34
    @State private var natural = CGSize.zero
    /// A typed site has no artwork of its own, and this is the glyph the + button already uses
    /// for Website, so the two say the same thing.
    static let hostSymbol = "globe"

    var body: some View {
        if case .host = kind {
            // Our own tile, sized in proportion so it sits right at 26 in an import row and at
            // 48 in the editor header. The scaling below is measured against Apple's artwork
            // and would blow a symbol up to fill the frame edge to edge.
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

    /// How much of Apple's 32 pt icon view the artwork of `kind` really covers.
    ///
    /// An app icon is a squircle sitting inside padding and fills 0.655 of the view — measured
    /// on the device in the sizing lab of 2026-09-07 — so its tile scales past that padding to
    /// bring the squircle itself up to `size`. Nothing else has been measured, and everything
    /// else Apple draws for a token is a glyph on a filled rounded rect running edge to edge,
    /// so the rest are left alone. Scaling a view that is already full past padding it does not
    /// have is what made a category come out half again too big, overflowing its frame and
    /// lapping its neighbours in the Anchor grid. Only scale past padding you have measured.
    private static func artworkFraction(of kind: TargetKind) -> CGFloat {
        if case .application = kind { return 0.655 }
        return 1
    }
}

/// The 12 pt status hourglass and the next time on the right of a home row.
struct StatusChip: View {
    let status: TargetStatus
    let glass: HourglassState
    /// The rule has no windows, so there is no closing time to show.
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
        let budget = TimeFormat.budget(rule.dailyBudgetMinutes)
        if case .exhausted = status { return "Used up today · \(budget)" }
        if rule.isSameEveryDay {
            return "\(TimeFormat.schedule(rule)) · \(budget)"
        }
        let today = rule.windows(on: Policy.weekday(now)).map { TimeFormat.window($0) }
        return today.isEmpty ? "Not today · \(budget)" : "Today \(today.joined(separator: ", ")) · \(budget)"
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
                if isBusy { ProgressView().tint(Ember.cream) }
                Text(title).emberBody(14.5, .bold)
            }
            .foregroundStyle(Ember.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(Ember.ember)
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
