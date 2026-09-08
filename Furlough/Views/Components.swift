import FamilyControls
import SwiftUI

/// Renders the system icon and name for an opaque Screen Time token.
struct TokenLabel: View {
    let kind: TargetKind

    var body: some View {
        switch kind {
        case .application(let token): Label(token)
        case .webDomain(let token): Label(token)
        case .category(let token): Label(token)
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
        TokenLabel(kind: kind)
            .labelStyle(.titleOnly)
            .lineLimit(1)
            .dynamicTypeSize(size)
            .environment(\.legibilityWeight, .bold)
    }
}

/// The real app icon, scaled to fill `size`. The system view is always 32 pt and its artwork
/// fills about two thirds of it, so the tile measures the view and scales past the padding.
/// No frame of our own: the artwork brings its rounded square.
struct TokenTile: View {
    let kind: TargetKind
    var size: CGFloat = 34
    @State private var natural = CGSize.zero
    private static let artworkFraction: CGFloat = 0.655

    var body: some View {
        let longest = max(natural.width, natural.height)
        let scale = longest > 0 ? size / (longest * Self.artworkFraction) : 1
        TokenLabel(kind: kind)
            .labelStyle(.iconOnly)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
            .scaleEffect(scale)
            .frame(width: size, height: size)
    }
}

/// The glyph and time on the right of a home row.
struct StatusChip: View {
    let status: TargetStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
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

    private var symbol: String {
        switch status {
        case .bricked: "cube.fill"
        case .open: "lock.open.fill"
        case .unconfigured: "exclamationmark.triangle.fill"
        case .exhausted: "hourglass.bottomhalf.filled"
        case .closed, .blockedAllDay: "lock.fill"
        }
    }

    private var text: String? {
        switch status {
        case .bricked: "Bricked"
        case .open(let until): TimeFormat.minute(until)
        case .closed(let next): TimeFormat.chip(next)
        case .exhausted(let next): next.map(TimeFormat.chip)
        case .unconfigured: "Set up"
        case .blockedAllDay: nil
        }
    }

    private var color: Color {
        switch status {
        case .bricked: Ember.ember
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
        guard rule.isEverAllowed else { return "No windows" }
        let budget = TimeFormat.budget(rule.dailyBudgetMinutes)
        if case .exhausted = status { return "Used up today · \(budget)" }
        if rule.isSameEveryDay {
            return "\(TimeFormat.schedule(rule)) · \(budget)"
        }
        let today = rule.windows(on: Policy.weekday(now)).map(TimeFormat.window)
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
