import Combine
import SwiftUI

struct MacRootView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isOnboarded {
                MacHomeView()
            } else {
                MacOnboardingView()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Ember.ember)
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
        ) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

/// The main window: the list of apps and sites on the left, the selected one's rule on the right.
struct MacHomeView: View {
    @Environment(MacModel.self) private var model
    @State private var selection: UUID?
    @State private var showAddApp = false
    @State private var showAddSite = false
    @State private var showPending = false
    @State private var showSettings = false
    @State private var now = Date.now
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            EmberWall()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 340)
                Rectangle().fill(Ember.cardBorder).frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $showAddApp) {
            AddAppSheet { app in
                let outcome = model.addApp(bundleID: app.bundleID, name: app.name)
                selection = outcome.added?.id
            }
        }
        .sheet(isPresented: $showAddSite) {
            AddSiteSheet { raw in
                let outcome = model.addHost(raw)
                if let added = outcome.added { selection = added.id }
                return outcome
            }
        }
        .sheet(isPresented: $showPending) { PendingSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .onChange(of: model.state.config.targets.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let summary = Policy.summary(state: model.state, now: now)
        let targets = model.state.config.targets
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                GlassCircleButton(symbol: "clock.arrow.circlepath", badge: summary.pendingCount) { showPending = true }
                    .help("Pending changes")
                GlassCircleButton(symbol: "gearshape") { showSettings = true }
                    .help("Settings")
                Menu {
                    Button("Add app…") { showAddApp = true }
                    Button("Add website…") { showAddSite = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ember.cream)
                        .frame(width: 34, height: 34)
                }
                .menuStyle(.button)
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .clipShape(Circle())
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add an app or website")
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Furlough", color: Ember.amber)
                Text(headline(summary))
                    .emberDisplay(26)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let line = subline(summary) {
                    Text(line)
                        .emberBody(12.5)
                        .foregroundStyle(Ember.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if targets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nothing yet.")
                                .emberDisplaySmall(15)
                                .foregroundStyle(Ember.cream)
                            Text("Add the apps and websites that eat your time, then give each one allowed windows and a daily budget.")
                                .emberBody(12.5)
                                .foregroundStyle(Ember.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .emberCard()
                        .padding(.top, 16)
                    } else {
                        ForEach(groups(targets), id: \.title) { group in
                            SectionLabel(text: group.title)
                            VStack(spacing: 0) {
                                ForEach(group.targets) { target in
                                    row(target)
                                    if target.id != group.targets.last?.id { CardDivider() }
                                }
                            }
                            .emberCard()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .padding(.top, 6)
        }
    }

    private func row(_ target: Target) -> some View {
        let status = Policy.status(of: target, config: model.state.config, runtime: model.state.runtime, now: now)
        let pending = model.state.pending.first { $0.targetID == target.id }
        let selected = selection == target.id
        return Button {
            selection = target.id
        } label: {
            HStack(spacing: 10) {
                KindTile(kind: target.kind, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .emberDisplaySmall(13.5)
                        .foregroundStyle(Ember.cream)
                        .lineLimit(1)
                    Text(pending.map { "Change pending · \($0.effectiveAt.formatted(date: .abbreviated, time: .shortened))" }
                         ?? RowCopy.detail(target: target, status: status, now: now))
                        .emberBody(11)
                        .foregroundStyle(pending == nil ? Ember.muted : Ember.pending)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                StatusChip(status: status, glass: .of(target, status: status, runtime: model.state.runtime, now: now), allDay: target.rule?.isAllDay ?? false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? Color.white.opacity(0.06) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct Group {
        let title: String
        let targets: [Target]
    }

    private func groups(_ targets: [Target]) -> [Group] {
        var open: [Target] = [], later: [Target] = [], blocked: [Target] = [], setup: [Target] = []
        for target in targets {
            switch Policy.status(of: target, config: model.state.config, runtime: model.state.runtime, now: now) {
            case .open: open.append(target)
            case .unconfigured: setup.append(target)
            case .closed(let next) where next.isToday: later.append(target)
            default: blocked.append(target)
            }
        }
        return [
            Group(title: "Open now", targets: open),
            Group(title: "Later today", targets: later),
            Group(title: "Blocked", targets: blocked),
            Group(title: "Set up", targets: setup),
        ].filter { !$0.targets.isEmpty }
    }

    private func headline(_ summary: Policy.Summary) -> String {
        if let until = summary.openUntil, let name = summary.openNames.first {
            let extra = summary.openNames.count > 1 ? " +\(summary.openNames.count - 1)" : ""
            return "\(name)\(extra) open · \(TimeFormat.countdown(from: now, to: until))"
        }
        if let name = summary.allDayNames.first {
            let extra = summary.allDayNames.count > 1 ? " +\(summary.allDayNames.count - 1)" : ""
            return "\(name)\(extra) open all day"
        }
        if summary.isEmpty { return "No unblock button." }
        if summary.blockedCount > 0 { return "\(summary.blockedCount) blocked." }
        return "Nothing enforced yet."
    }

    private func subline(_ summary: Policy.Summary) -> String? {
        if summary.openUntil == nil, !summary.allDayNames.isEmpty {
            return "Up to the budget · resets at midnight"
        }
        if let at = summary.nextOpenAt, let name = summary.nextOpenNames.first {
            let when = Policy.daysAhead(of: at, from: now) == 0
                ? at.formatted(date: .omitted, time: .shortened)
                : at.formatted(.dateTime.weekday(.wide).hour().minute())
            return "\(name) opens \(when)"
        }
        if summary.unconfiguredCount > 0 { return "\(summary.unconfiguredCount) waiting for a schedule" }
        return nil
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, model.state.config.target(id: selection) != nil {
            MacRuleEditor(targetID: selection)
                .id(selection)
        } else {
            VStack(spacing: 14) {
                LivingHourglass(state: .open(level: 0.62, warned: false))
                    .compositingGroup()
                    .frame(width: 96, height: 128)
                    .shadow(color: Ember.amber.opacity(0.45), radius: 24)
                Text(model.state.config.targets.isEmpty ? "Start with the worst offender." : "Pick something on the left.")
                    .emberDisplay(24)
                    .foregroundStyle(Ember.cream)
                Text("Each app or website gets allowed windows and a daily minute budget. Tightening applies instantly; loosening waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)).")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                HStack(spacing: 10) {
                    Button("Add app…") { showAddApp = true }
                        .buttonStyle(.glassProminent)
                        .tint(Ember.ember)
                    Button("Add website…") { showAddSite = true }
                        .buttonStyle(.glass)
                }
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding(40)
        }
    }
}
