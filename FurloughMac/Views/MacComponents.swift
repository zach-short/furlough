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

/// The web filter's directions, one instruction at a time.
///
/// Two rounds of this were a paragraph and then a numbered list, and both failed the same way:
/// there is one step that decides whether any of it works — Network Extensions lives under **By
/// Category** and does not exist under By App — and a step like that is invisible in a list you
/// skim. So the walkthrough shows a single instruction, a drawing of the control it means, the
/// trap it carries if it has one, and a button that does the thing where a button can. Both
/// onboarding and Settings > Web draw it from `WebFilter.Status.guidance`.
struct FilterDirections: View {
    let guidance: WebFilter.Guidance
    var size: CGFloat = 12.5
    let perform: (WebFilter.Guidance.Action) -> Void
    @State private var index = 0

    private var current: WebFilter.Guidance.Step? {
        guard !guidance.steps.isEmpty else { return nil }
        return guidance.steps[min(index, guidance.steps.count - 1)]
    }

    private var isLast: Bool { index >= guidance.steps.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(guidance.lead)
                .emberBody(size)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let current { stepCard(current) }
            if let caution = guidance.caution { warning(caution, size: size - 1) }
        }
        // A status change is a different walkthrough, so it starts at its own first step.
        .onChange(of: guidance) { _, _ in index = 0 }
    }

    private func stepCard(_ step: WebFilter.Guidance.Step) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Eyebrow(text: "Step \(index + 1) of \(guidance.steps.count)", color: Ember.amber, size: 9.5)
                Spacer()
                pips
            }
            Text(step.text)
                .emberBody(size + 2.5, .semibold)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
            if let figure = step.figure {
                StepFigure(kind: figure)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let note = step.note { warning(note, size: size - 1.5) }
            controls(step)
        }
        .padding(14)
        .emberCard()
    }

    /// One dot per step, so the length of the walk is visible without reading it.
    private var pips: some View {
        HStack(spacing: 4) {
            ForEach(guidance.steps.indices, id: \.self) { position in
                Circle()
                    .fill(position == index ? Ember.amber : Ember.cardBorder)
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func controls(_ step: WebFilter.Guidance.Step) -> some View {
        HStack(spacing: 8) {
            if let action = step.action {
                Button(action.title) {
                    perform(action)
                    if !isLast { index += 1 }
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
            } else if !isLast {
                Button("Next") { index += 1 }
                    .buttonStyle(.glassProminent)
                    .tint(Ember.ember)
            }
            if index > 0 {
                Button("Back") { index -= 1 }
                    .buttonStyle(.glass)
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .padding(.top, 2)
    }

    private func warning(_ text: String, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: size - 1, weight: .bold))
                .foregroundStyle(Ember.pending)
            Text(text)
                .emberBody(size)
                .foregroundStyle(Ember.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small drawing of the part of System Settings a step is about, in Furlough's own tokens.
///
/// Deliberately not screenshots. A screenshot of System Settings goes stale at every macOS
/// redesign, carries a whole window of things that are not the point, and cannot emphasise the
/// one control that matters. These show that control and little else, with the thing to click
/// picked out in Ember.
struct StepFigure: View {
    let kind: WebFilter.Guidance.Figure

    var body: some View {
        Group {
            switch kind {
            case .systemSettings: systemSettings
            case .general: general
            case .scrollDown: scrollDown
            case .byCategory: byCategory
            case .networkExtensionsRow: networkExtensionsRow
            case .furloughToggle: furloughToggle
            case .allowDialog: allowDialog
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ember.cardBorder, lineWidth: 1)
        )
    }

    // MARK: The figures

    private var systemSettings: some View {
        HStack(spacing: 9) {
            glyph("gearshape.fill", tint: Ember.muted)
            Text("System Settings").emberBody(12, .medium).foregroundStyle(Ember.cream)
        }
    }

    private var general: some View {
        HStack(spacing: 10) {
            VStack(spacing: 3) {
                sidebarRow("Appearance", picked: false)
                sidebarRow("General", picked: true)
                sidebarRow("Accessibility", picked: false)
            }
            .frame(width: 108)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Ember.faint)
            pane("Login Items & Extensions", picked: true)
        }
    }

    private var scrollDown: some View {
        VStack(alignment: .leading, spacing: 4) {
            pane("Open at Login", picked: false)
            pane("App Background Activity", picked: false)
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ember.amber)
                Text("keep scrolling").emberBody(9.5).foregroundStyle(Ember.faint)
            }
            .padding(.leading, 2)
            pane("Extensions", picked: true)
        }
    }

    private var byCategory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Extensions").emberBody(10, .semibold).foregroundStyle(Ember.muted)
            HStack(spacing: 0) {
                segment("By App", picked: false)
                segment("By Category", picked: true)
            }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var networkExtensionsRow: some View {
        HStack(spacing: 9) {
            glyph("network", tint: Ember.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text("Network Extensions").emberBody(11.5, .medium).foregroundStyle(Ember.cream)
                Text("Furlough Web Filter").emberBody(9.5).foregroundStyle(Ember.faint)
            }
            Spacer(minLength: 8)
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ember.ember)
                .padding(3)
                .background(Ember.ember.opacity(0.18), in: Circle())
        }
    }

    private var furloughToggle: some View {
        HStack(spacing: 9) {
            glyph("hourglass", tint: Ember.amber)
            Text("Furlough Web Filter").emberBody(11.5, .medium).foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            Capsule()
                .fill(Ember.ember)
                .frame(width: 30, height: 17)
                .overlay(alignment: .trailing) {
                    Circle().fill(.white).frame(width: 13, height: 13).padding(.trailing, 2)
                }
        }
    }

    private var allowDialog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“Furlough” would like to filter network content.")
                .emberBody(10.5, .medium)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                pill("Don't Allow", picked: false)
                pill("Allow", picked: true)
            }
        }
    }

    // MARK: Parts

    private func glyph(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func sidebarRow(_ title: String, picked: Bool) -> some View {
        Text(title)
            .emberBody(9.5, picked ? .semibold : .regular)
            .foregroundStyle(picked ? Ember.cream : Ember.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(picked ? Ember.ember : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func pane(_ title: String, picked: Bool) -> some View {
        Text(title)
            .emberBody(10, picked ? .semibold : .regular)
            .foregroundStyle(picked ? Ember.cream : Ember.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(picked ? Ember.ember.opacity(0.22) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(picked ? Ember.ember : Color.clear, lineWidth: 1)
            )
    }

    private func segment(_ title: String, picked: Bool) -> some View {
        Text(title)
            .emberBody(10, picked ? .semibold : .regular)
            .foregroundStyle(picked ? Ember.cream : Ember.faint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(picked ? Ember.ember : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func pill(_ title: String, picked: Bool) -> some View {
        Text(title)
            .emberBody(9.5, picked ? .semibold : .regular)
            .foregroundStyle(picked ? Ember.cream : Ember.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(picked ? Ember.ember : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
