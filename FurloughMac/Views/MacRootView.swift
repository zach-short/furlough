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
    /// The Application / Website popover under the + button.
    @State private var showAddChoice = false
    @State private var showAddApp = false
    @State private var showAddSite = false
    @State private var showPending = false
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showAnchor = false
    /// The other half of what was just added, held until the add sheet has fully gone: a sheet
    /// presented over one still leaving is dropped, so the offer waits for `onDismiss`.
    @State private var pendingCompanion: CompanionPrompt?
    @State private var companionPrompt: CompanionPrompt?
    /// The window's clock, kept on the model so the sidebar and the detail pane count in step.
    private var now: Date { model.now }

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
        .sheet(isPresented: $showAddApp, onDismiss: offerCompanion) {
            AddAppSheet { app in
                let isNew = model.state.config.target(bundleID: app.bundleID) == nil
                let outcome = model.addApp(bundleID: app.bundleID, name: app.name)
                selection = outcome.added?.id
                guard isNew, let added = outcome.added else { return }
                pendingCompanion = CompanionPrompt(added: added, items: companionSites(for: app))
            }
        }
        .sheet(isPresented: $showAddSite, onDismiss: offerCompanion) {
            AddSiteSheet { raw in
                let isNew = Hosts.normalize(raw).map { model.state.config.target(host: $0) == nil } ?? false
                let outcome = model.addHost(raw)
                if let added = outcome.added {
                    selection = added.id
                    if isNew, case .host(let host) = added.kind {
                        pendingCompanion = CompanionPrompt(added: added, items: companionApps(for: host))
                    }
                }
                return outcome
            }
        }
        .sheet(item: $companionPrompt) { prompt in
            CompanionSheet(added: prompt.added, items: prompt.items) { chosen in
                var hosts: [String] = []
                var apps: [(bundleID: String, name: String)] = []
                for item in chosen {
                    switch item.kind {
                    case .host(let host): hosts.append(host)
                    case .macApp(let bundleID): apps.append((bundleID, item.title))
                    }
                }
                model.addHosts(hosts)
                model.addApps(apps)
            }
        }
        .sheet(isPresented: $showPending) { PendingSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showAnchor) { AnchorSheet() }
        .sheet(isPresented: $showHelp) { HelpSheet() }
        .onChange(of: model.state.config.targets.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    /// What was just added and what goes with it.
    private struct CompanionPrompt: Identifiable {
        let id = UUID()
        let added: Target
        let items: [CompanionSheet.Item]
    }

    /// Runs once the add sheet is gone. Nothing to offer means no sheet.
    private func offerCompanion() {
        defer { pendingCompanion = nil }
        guard let pending = pendingCompanion, !pending.items.isEmpty else { return }
        companionPrompt = pending
    }

    /// The websites `app` is also at that are not in Furlough yet; a host already covered by a
    /// parent domain counts as in.
    private func companionSites(for app: InstalledApp) -> [CompanionSheet.Item] {
        app.companionHosts
            .filter { model.state.config.target(host: $0) == nil }
            .map { CompanionSheet.Item(kind: .host($0), title: $0, subtitle: "The site and its subdomains, in every browser") }
    }

    /// The installed apps `host` is also in that are not in Furlough yet.
    private func companionApps(for host: String) -> [CompanionSheet.Item] {
        AppCatalog.apps(for: host)
            .filter { model.state.config.target(bundleID: $0.bundleID) == nil }
            .map { CompanionSheet.Item(kind: .macApp(bundleID: $0.bundleID), title: $0.name, subtitle: $0.bundleID) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let state = model.state
        let summary = Policy.summary(state: state, now: now)
        let config = Policy.effectiveConfig(state, now: now)
        let targets = config.targets
        let statuses = Dictionary(uniqueKeysWithValues: targets.map { target in
            (target.id, Policy.status(of: target, config: config, runtime: state.runtime, now: now))
        })
        let groups = HomeGroups(targets: targets, statuses: statuses, now: now)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                GlassCircleButton(symbol: summary.isAnchored ? "lock.fill" : "lock.open") { showAnchor = true }
                    .help("Anchor")
                GlassCircleButton(symbol: "clock.arrow.circlepath", badge: summary.pendingCount) { showPending = true }
                    .help("Pending changes")
                GlassCircleButton(symbol: "gearshape") { showSettings = true }
                    .help("Settings")
                GlassCircleButton(symbol: "questionmark") { showHelp = true }
                    .help("Help")
                Button {
                    showAddChoice = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ember.cream)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .clipShape(Circle())
                .help("Add an app or website")
                .popover(isPresented: $showAddChoice, arrowEdge: .bottom) {
                    AddChoicePopover(
                        applicationCaption: "Any app on this Mac",
                        websiteCaption: "A site and its subdomains, in any browser"
                    ) { choice in
                        showAddChoice = false
                        switch choice {
                        case .application: showAddApp = true
                        case .website: showAddSite = true
                        }
                    }
                }
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
                        ForEach(groups.sections) { section in
                            SectionLabel(text: section.title)
                            VStack(spacing: 0) {
                                ForEach(section.targets) { target in
                                    row(target, status: statuses[target.id] ?? .unconfigured)
                                    if target.id != section.targets.last?.id { CardDivider() }
                                }
                            }
                            .emberCard()
                        }
                    }
                    MacRecordSection()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .padding(.top, 6)
        }
    }

    private func row(_ target: Target, status: TargetStatus) -> some View {
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
                    // The rule line stays, as on the phone: a change waiting says so on a line
                    // of its own rather than hiding the rule being enforced until then.
                    Text(RowCopy.detail(target: target, status: status, now: now))
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                        .lineLimit(1)
                    if let pending {
                        Text(RowCopy.pendingLine(pending))
                            .emberBody(10.5, .semibold)
                            .foregroundStyle(Ember.pending)
                            .lineLimit(1)
                    }
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

    /// Nothing selected, but something is managed: the phone's hero, paging through every app
    /// with the living hourglass, so the window opens on the sand rather than on an invitation.
    private var hero: some View {
        let state = model.state
        let config = Policy.effectiveConfig(state, now: now)
        let statuses = Dictionary(uniqueKeysWithValues: config.targets.map { target in
            (target.id, Policy.status(of: target, config: config, runtime: state.runtime, now: now))
        })
        let groups = HomeGroups(targets: config.targets, statuses: statuses, now: now)
        return MacHeroPager(
            targets: groups.ordered,
            statuses: statuses,
            runtime: state.runtime,
            now: now,
            usedSeconds: { model.enforcer.usedSeconds(for: $0) },
            onOpen: { selection = $0 }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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
        } else if !model.state.config.targets.isEmpty {
            hero
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
