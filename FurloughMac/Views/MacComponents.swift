import AppKit
import SwiftUI

// The small Ember Glass controls, as in Furlough/Views/Components.swift on iOS. They are
// duplicated here rather than moved so the phone's files stay untouched; unify them into
// Shared/UI when both sides are quiet.

/// The prominent ember glass button used for Save and Start.
struct ProminentButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy { ProgressView().controlSize(.small).tint(Ember.cream) }
                Text(title).emberBody(14, .bold)
            }
            .foregroundStyle(Ember.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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
                .emberBody(13.5, .bold)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A round glass button with a symbol, for the header.
struct GlassCircleButton: View {
    let symbol: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ember.cream)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text("\(badge)")
                    .font(EmberFont.label(9))
                    .foregroundStyle(Ember.ground)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(Ember.pending, in: Capsule())
                    .offset(x: 4, y: -3)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Eyebrow(text: text, color: Ember.faint, size: 10.5)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

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

struct CardDivider: View {
    var body: some View {
        Rectangle().fill(Ember.cardBorder).frame(height: 1)
    }
}

/// A row inside a card that does something.
struct CardAction: View {
    let title: String
    var symbol: String?
    var color: Color = Ember.ember
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                }
                Text(title).emberBody(13, .semibold)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The app's icon, or a globe for a website.
struct KindTile: View {
    let kind: TargetKind
    var size: CGFloat = 34

    var body: some View {
        switch kind {
        case .macApp(let bundleID):
            if let icon = AppInfo.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                symbol("app.dashed")
            }
        case .host:
            symbol("globe")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(Ember.amber)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(Ember.cardBorder, lineWidth: 1))
    }
}

/// The 12 pt status hourglass and the next time on the right of a row.
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

enum RowCopy {
    /// The rule line under a row's name. A rule that varies by day shows today's windows.
    static func detail(target: Target, status: TargetStatus, now: Date = .now) -> String {
        guard let rule = target.rule else { return "Not enforced yet" }
        guard rule.isEverAllowed else { return "Blocked all day" }
        // Today's budget beside today's hours: the row is a statement about right now.
        let budget = TimeFormat.budget(rule.budget(on: Policy.weekday(now)))
        if case .exhausted = status { return "Used up today · \(budget)" }
        if rule.isSameEveryDay, rule.isSameBudgetEveryDay {
            return "\(TimeFormat.schedule(rule)) · \(budget)"
        }
        let today = rule.windows(on: Policy.weekday(now)).map { TimeFormat.window($0) }
        // A day worth nothing has no hours and no figure worth printing: "Not today · 0 min"
        // offers a budget that is not on offer.
        guard !today.isEmpty else { return "Not today" }
        return "Today \(today.joined(separator: ", ")) · \(budget)"
    }

    static func pendingLine(_ change: PendingChange) -> String {
        "Change pending · \(change.effectiveAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// A sheet chrome: title, Done, dark ground.
struct SheetFrame<Content: View>: View {
    let title: String
    var width: CGFloat = 520
    var height: CGFloat = 560
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EmberWall()
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.glass)
                        .tint(Ember.cream)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                content()
            }
        }
        .frame(width: width, height: height)
        .preferredColorScheme(.dark)
    }
}

/// The web filter's directions for whatever state it is in: where you stand, the steps out, and
/// the trap, drawn from `WebFilter.Status.guidance` so onboarding and Settings > Web cannot word
/// them differently. The numbers are the point — the two approvals are several scrolls apart in
/// System Settings and one of them is under a heading you reach only by going past a list that
/// looks like the end of the page.
struct FilterDirections: View {
    let guidance: WebFilter.Guidance
    /// Onboarding has room to talk; the Settings card is a footnote under a row.
    var size: CGFloat = 12.5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guidance.lead)
                .emberBody(size)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !guidance.steps.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(guidance.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text("\(index + 1)")
                                .emberBody(size - 1, .semibold)
                                .monospacedDigit()
                                .foregroundStyle(Ember.amber)
                                .frame(width: 12, alignment: .trailing)
                            Text(step)
                                .emberBody(size)
                                .foregroundStyle(Ember.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let caution = guidance.caution {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: size - 2.5, weight: .bold))
                        .foregroundStyle(Ember.pending)
                    Text(caution)
                        .emberBody(size - 1)
                        .foregroundStyle(Ember.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
