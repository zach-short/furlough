import SwiftUI

struct MacRootView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isOnboarded {
                MacHomeView(start: model.startHalf)
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

/// The main window: two halves under one segment. Rules is the list of apps and sites on the
/// left with the selected one's rule on the right; the Anchor is what it holds on the left with
/// the drop on the right.
///
/// The Anchor used to be a padlock in the toolbar opening a sheet — an unlabelled lock icon over
/// a stack of eleven blocks, which is the shape of a feature rather than of half an app. The
/// segment is how you get there now, and the padlock is gone: the app draws its own anchor mark
/// everywhere else, and it draws it here too, on the state card the segment leads to.
struct MacHomeView: View {
    @Environment(MacModel.self) private var model
    @Environment(HelpRoute.self) private var route
    @Environment(\.openWindow) private var openWindow
    /// Which half is on screen. Seeded from the intro's answer and this view's own after that.
    @State private var half: Half
    @State private var selection: UUID?
    /// The Application / Website popover under the + button.
    @State private var showAddChoice = false
    /// The same popover, under the Rules guide's first step and under the row at the foot of what
    /// the anchor holds. A popover anchors to the view it is attached to, and the toolbar's + is
    /// nowhere near either of them — one shared flag would pop the question off the wrong control.
    @State private var showGuideAddChoice = false
    @State private var showHeldAddChoice = false
    @State private var showAddApp = false
    @State private var showAddSite = false
    /// Which half the add being made belongs to: a rule target, or the anchor's list. Set by
    /// whatever opened the picker, read when it comes back with something.
    @State private var addDestination: Half = .rules
    @State private var showPending = false
    @State private var showSettings = false
    /// Why an add to the anchor was refused, if it was.
    @State private var anchorMessage: String?
    /// The other half of what was just added, held until the add sheet has fully gone: a sheet
    /// presented over one still leaving is dropped, so the offer waits for `onDismiss`.
    @State private var pendingCompanion: CompanionPrompt?
    @State private var companionPrompt: CompanionPrompt?
    /// A website was just added and the filter has never been offered. Held until every other
    /// sheet in the chain has finished, for the reason `offerCompanion` gives: a sheet presented
    /// over one still leaving is dropped.
    @State private var pendingFilterHost: String?
    @State private var filterOfferHost: FilterOfferHost?
    /// The window's clock, kept on the model so the sidebar and the detail pane count in step.
    private var now: Date { model.now }

    init(start: Half) { _half = State(initialValue: start) }

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
        .sheet(isPresented: $showAddApp, onDismiss: offerCompanion) { addAppSheet }
        .sheet(isPresented: $showAddSite, onDismiss: offerCompanion) { addSiteSheet }
        .sheet(item: $companionPrompt, onDismiss: offerWebFilter) { prompt in
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
        .sheet(item: $filterOfferHost) { host in
            WebFilterOfferSheet(host: host.value)
        }
        .sheet(isPresented: $showPending) { PendingSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .alert("Anchor", isPresented: Binding(get: { anchorMessage != nil }, set: { if !$0 { anchorMessage = nil } })) {
            Button("OK") { anchorMessage = nil }
        } message: {
            Text(anchorMessage ?? "")
        }
        .onChange(of: model.state.config.targets.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        .toolbar { windowActions }
    }

    // MARK: The add flow

    /// One picker for both halves, told where what it finds is going. The Anchor used to carry
    /// its own search field and its own host field inside the sheet; there is one pipeline now,
    /// so the + button and the half's own Choose apps row cannot drift apart.
    private var addAppSheet: some View {
        AddAppSheet { app in
            guard addDestination == .rules else {
                anchorMessage = model.addToAnchor(.macApp(bundleID: app.bundleID))
                return
            }
            let isNew = model.state.config.target(bundleID: app.bundleID) == nil
            let outcome = model.addApp(bundleID: app.bundleID, name: app.name)
            selection = outcome.added?.id
            // The sheet is the Ask. Told Always, the model has added the sites already and the
            // filter below finds nothing; told Never, it is not asked.
            guard isNew, let added = outcome.added, model.state.config.link.companionSite != .never else { return }
            pendingCompanion = CompanionPrompt(added: added, items: companionSites(for: app))
        }
    }

    private var addSiteSheet: some View {
        AddSiteSheet { raw in
            guard addDestination == .rules else {
                guard let host = Hosts.normalize(raw) else { return "That does not look like a website." }
                let refusal = model.addToAnchor(.host(host))
                if refusal == nil { pendingFilterHost = host }
                return refusal
            }
            let isNew = Hosts.normalize(raw).map { model.state.config.target(host: $0) == nil } ?? false
            let outcome = model.addHost(raw)
            guard let added = outcome.added else { return outcome.message }
            selection = added.id
            if isNew, case .host(let host) = added.kind {
                if model.state.config.link.companionSite != .never {
                    pendingCompanion = CompanionPrompt(added: added, items: companionApps(for: host))
                }
                pendingFilterHost = host
            }
            return nil
        }
    }

    /// The Application-or-Website question, worded for where the answer is going.
    private func addChoice(for destination: Half) -> some View {
        AddChoicePopover(
            applicationCaption: destination == .anchor ? "Any app on this Mac, held while anchored" : "Any app on this Mac",
            websiteCaption: destination == .anchor
                ? "A site and its subdomains, held while anchored"
                : "A site and its subdomains, in any browser"
        ) { choice in
            showAddChoice = false
            showGuideAddChoice = false
            addDestination = destination
            switch choice {
            case .application: showAddApp = true
            case .website: showAddSite = true
            }
        }
    }

    /// The + button: opens the picker for the half being looked at — over Rules a rule target,
    /// over the Anchor its list, unless Settings has been told otherwise.
    private func add(on half: Half) {
        addDestination = model.addDestination(on: half)
        showAddChoice = true
    }

    // MARK: Toolbar

    /// The window's actions. macOS 26 draws the Liquid Glass, groups adjacent items into one
    /// capsule, and keeps the traffic lights clear.
    @ToolbarContentBuilder
    private var windowActions: some ToolbarContent {
        let summary = toolbarSummary
        // With no window title to sit beside, a primary action packs against the traffic
        // lights instead of the trailing edge. The flexible spacer is what sends it right.
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            // The count in words, not a badge: a toolbar item has nowhere to hang one, and
            // saying it is how the phone says it too.
            if summary.pendingCount > 0 {
                Button("\(summary.pendingCount) pending") { showPending = true }
                    .tint(Ember.pending)
                    .help("Pending changes")
            } else {
                Button("Pending changes", systemImage: "clock.arrow.circlepath") { showPending = true }
                    .tint(Ember.cream)
                    .help("Pending changes")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
                .tint(Ember.cream)
                .help("Settings")
        }
        ToolbarItem(placement: .primaryAction) {
            // The hub, not wherever Help was left: the question mark is the way in, and a page
            // still showing from the last visit would silently stand in for it.
            Button("Help", systemImage: "questionmark") { openHelp(on: nil) }
                .tint(Ember.cream)
                .help("Help")
        }
        // Add is its own capsule, away from the two that only open something.
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button("Add", systemImage: "plus") { add(on: half) }
                .tint(Ember.cream)
                .help(half == .anchor && model.addDestination(on: .anchor) == .anchor
                    ? "Add to the anchor"
                    : "Add an app or website")
                .popover(isPresented: $showAddChoice, arrowEdge: .bottom) {
                    addChoice(for: addDestination)
                }
        }
    }

    /// What the toolbar needs to know. The sidebar works out its own from the same call: this
    /// is a loop over the targets, not a query, and both are rebuilt on the same clock.
    private var toolbarSummary: Policy.Summary { Policy.summary(state: model.state, now: now) }

    /// What was just added and what goes with it.
    private struct CompanionPrompt: Identifiable {
        let id = UUID()
        let added: Target
        let items: [CompanionSheet.Item]
    }

    /// The site the filter offer is about. `String` is not `Identifiable`, and the sheet needs
    /// something to be presented by.
    private struct FilterOfferHost: Identifiable {
        let value: String
        var id: String { value }
    }

    /// Runs once the add sheet is gone. Nothing to offer means no sheet — and then the web
    /// filter gets its turn, since it is the last thing in the chain either way.
    private func offerCompanion() {
        defer { pendingCompanion = nil }
        guard let pending = pendingCompanion, !pending.items.isEmpty else { return offerWebFilter() }
        companionPrompt = pending
    }

    /// The web filter, once a website is actually in Furlough and every sheet the add raised has
    /// gone. Asks `MacModel` rather than deciding here: the condition is about the config and the
    /// filter's own state, not about which button was pressed. See `shouldOfferWebFilter`.
    private func offerWebFilter() {
        defer { pendingFilterHost = nil }
        guard let host = pendingFilterHost, model.shouldOfferWebFilter else { return }
        filterOfferHost = FilterOfferHost(value: host)
    }

    /// Puts Help on a page, then brings its window up — in that order, since the window reads
    /// the route rather than being handed one. Already open, it comes forward showing the page
    /// just asked for.
    private func openHelp(on topic: HelpTopic?) {
        route.topic = topic
        openWindow(id: HelpRoute.windowID)
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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
            MacHalfSegment(half: $half)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // What the link is asking about on this half, when it is asking anything.
                    MacLinkTraffic(half: half)
                        .padding(.bottom, 8)
                    switch half {
                    case .rules: rulesList
                    case .anchor: heldList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .padding(.top, 6)
        }
    }

    /// The same three lines for both halves — eyebrow, headline, sub — with the words changing.
    /// The Rules half also says when the anchor is down, because an anchor changes what every
    /// rule on the list means for as long as it holds.
    @ViewBuilder
    private var header: some View {
        let anchor = model.state.config.anchor
        let isHolding = anchor.isHolding(at: now)
        switch half {
        case .rules:
            let summary = toolbarSummary
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
                if isHolding {
                    Text("Anchored · \(anchor.heldDescription)")
                        .emberBody(12.5, .semibold)
                        .foregroundStyle(Ember.ember)
                }
            }
        case .anchor:
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: isHolding ? "Anchored" : "Free", color: isHolding ? Ember.ember : Ember.moss)
                Text(anchor.kinds.isEmpty && !anchor.anchorsEverything ? "Nothing held yet" : anchor.heldDescription)
                    .emberDisplay(26)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(anchorSubline)
                    .emberBody(12.5)
                    .foregroundStyle(Ember.muted)
            }
        }
    }

    private var anchorSubline: String {
        let anchor = model.state.config.anchor
        if anchor.isHolding(at: now), let since = anchor.anchoredAt {
            return "since \(since.formatted(date: .omitted, time: .shortened)) · your iPhone's tag lifts it"
        }
        if !model.cloudAvailable { return "iCloud unreachable · nothing can be released" }
        if !model.hasKey { return "no iPhone on the link" }
        if !anchor.hasSomethingToHold { return "choose what it holds" }
        return "ready to drop"
    }

    /// Everything Furlough manages, grouped by when it next opens.
    @ViewBuilder
    private var rulesList: some View {
        let state = model.state
        let config = Policy.effectiveConfig(state, now: now)
        let targets = config.targets
        let statuses = Dictionary(uniqueKeysWithValues: targets.map { target in
            (target.id, Policy.status(of: target, config: config, runtime: state.runtime, now: now))
        })
        let groups = HomeGroups(targets: targets, statuses: statuses, now: now)
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
                        row(target, status: statuses[target.id] ?? .unconfigured, anchor: config.anchor)
                        if target.id != section.targets.last?.id { CardDivider() }
                    }
                }
                .emberCard()
            }
        }
        MacRecordSection()
    }

    private func row(_ target: Target, status: TargetStatus, anchor: AnchorProfile) -> some View {
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
                    HStack(spacing: 5) {
                        Text(RowCopy.detail(target: target, status: status, now: now))
                            .emberBody(11)
                            .foregroundStyle(Ember.muted)
                            .lineLimit(1)
                        // The other half, in one mark: this row is on the anchor's list too.
                        if anchor.willHold(target) { HeldMark() }
                    }
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
        .contextMenu { anchorMenu(for: target) }
    }

    /// The way across from a rules row: hold this one too, or stop holding it. The mirror of the
    /// held list's own menu, and the reason neither half grows a list of the other's contents.
    @ViewBuilder
    private func anchorMenu(for target: Target) -> some View {
        let anchor = model.state.config.anchor
        if anchor.isHolding(at: now) {
            EmptyView()
        } else if anchor.contains(target.kind) {
            Button(anchor.anchorsEverything ? "Stop letting it through" : "Take it off the anchor") {
                model.setAnchorKinds(anchor.kinds.filter { $0 != target.kind })
            }
        } else {
            Button(anchor.anchorsEverything ? "Let it through while anchored" : "Also hold it in the Anchor") {
                anchorMessage = model.addToAnchor(target.kind)
            }
        }
    }

    /// What the anchor holds — or, under the other scope, what stays open. The list lives here
    /// rather than in the pane beside it for the reason the rules list does: this is the window's
    /// left-hand column, and the half's list belongs in it.
    @ViewBuilder
    private var heldList: some View {
        let anchor = model.state.config.anchor
        let isHolding = anchor.isHolding(at: now)
        SectionLabel(text: anchor.anchorsEverything ? "Stays open" : "Held")
        VStack(spacing: 0) {
            if anchor.kinds.isEmpty {
                Text(anchor.anchorsEverything ? "Nothing stays open." : "Nothing held yet.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            }
            ForEach(Array(anchor.kinds.enumerated()), id: \.offset) { index, kind in
                if index > 0 { CardDivider() }
                heldRow(kind, isHolding: isHolding)
            }
            if !isHolding {
                CardDivider()
                Button { showHeldAddChoice = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(chooseTitle(anchor))
                            .emberBody(13, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHeldAddChoice, arrowEdge: .bottom) {
                    addChoice(for: .anchor)
                }
            }
        }
        .emberCard()
        if anchor.scope == .chosen, !isHolding, !model.state.config.anchorCandidates.isEmpty, anchor.kinds.isEmpty {
            Button {
                var copy = anchor
                copy.add(model.state.config.anchorCandidates)
                model.setAnchorKinds(copy.kinds)
            } label: {
                Text("Add everything you already block")
                    .emberBody(12.5, .semibold)
                    .foregroundStyle(Ember.ember)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private func heldRow(_ kind: TargetKind, isHolding: Bool) -> some View {
        let target = model.state.config.target(kind: kind)
        return HStack(spacing: 10) {
            KindTile(kind: kind, size: 28)
            Text(name(of: kind))
                .emberBody(13, .medium)
                .foregroundStyle(Ember.cream)
                .lineLimit(1)
            // The mirror of the anchor on a rules row: this one has hours in the other half.
            if target?.rule != nil { RuledBadge(size: 13) }
            Spacer(minLength: 6)
            if !isHolding {
                Button {
                    model.setAnchorKinds(model.state.config.anchor.kinds.filter { $0 != kind })
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ember.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Take it off the list")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contextMenu { heldMenu(for: kind, target: target) }
    }

    /// The other half, from a held row: hours for something the anchor already holds.
    @ViewBuilder
    private func heldMenu(for kind: TargetKind, target: Target?) -> some View {
        if let target {
            Button(target.rule == nil ? "Give it hours too" : "Open its rule") { openRule(target.id) }
        } else {
            Button("Give it hours too") { openNewRule(for: kind) }
        }
    }

    /// Something the anchor holds that Furlough has no rule target for yet: make one, then open
    /// its editor on the empty rule, on the other half.
    private func openNewRule(for kind: TargetKind) {
        let added: Target?
        switch kind {
        case .macApp(let bundleID):
            added = model.addApp(bundleID: bundleID, name: AppInfo.name(for: bundleID) ?? bundleID).added
        case .host(let host):
            added = model.addHost(host).added
        }
        if let added { openRule(added.id) }
    }

    /// The way across: the rules half, with that target's editor open.
    private func openRule(_ id: UUID) {
        selection = id
        withAnimation(.snappy(duration: 0.25)) { half = .rules }
    }

    private func chooseTitle(_ anchor: AnchorProfile) -> String {
        switch (anchor.scope, anchor.kinds.isEmpty) {
        case (.chosen, true): "Choose apps"
        case (.chosen, false): "Add to the list"
        case (.everythingExcept, true): "Choose what stays open"
        case (.everythingExcept, false): "Add to what stays open"
        }
    }

    private func name(of kind: TargetKind) -> String {
        switch kind {
        case .macApp(let bundleID):
            model.state.config.target(bundleID: bundleID)?.displayName ?? AppInfo.name(for: bundleID) ?? bundleID
        case .host(let host):
            host
        }
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
        switch half {
        case .rules: rulesDetail
        case .anchor:
            MacAnchorPane(
                onChooseApps: { choice in
                    addDestination = .anchor
                    switch choice {
                    case .application: showAddApp = true
                    case .website: showAddSite = true
                    }
                },
                onExplainDevices: { openHelp(on: .devices) }
            )
        }
    }

    /// The editor for what is selected, the guide while this half is still being set up, and the
    /// hero the rest of the time. Selection first, because the guide's second step opens an
    /// editor and would otherwise be covering the thing it just asked for.
    @ViewBuilder
    private var rulesDetail: some View {
        let guide = HalfGuide.macRules(config: model.state.config, finished: model.finishedGuides.contains(.rules))
        if let selection, model.state.config.target(id: selection) != nil {
            MacRuleEditor(targetID: selection)
                .id(selection)
        } else if guide.isRunning {
            // Centred in the pane, like the hero and the empty state it stands in for, rather
            // than pinned to the top left of a pane three times its height.
            GuideCard(guide: guide) { rulesGuideButton(at: guide.live) }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.state.config.targets.isEmpty {
            hero
        } else {
            emptyDetail
        }
    }

    @ViewBuilder
    private func rulesGuideButton(at live: Int?) -> some View {
        switch live {
        case 0:
            GuideButton(title: "Add an app or website", systemImage: "plus") {
                showGuideAddChoice = true
            }
            .popover(isPresented: $showGuideAddChoice, arrowEdge: .bottom) {
                addChoice(for: .rules)
            }
        case 1:
            if let next = model.state.config.targets.first(where: { $0.rule == nil }) {
                GuideButton(title: "Write the rule", systemImage: "hourglass") { selection = next.id }
            }
        case 2:
            GuideButton(title: "Done") { model.finishGuide(.rules) }
        default:
            EmptyView()
        }
    }

    /// The half is set up and then emptied again: every target removed, with the guide long
    /// finished. Rare, and still a screen somebody can be on.
    private var emptyDetail: some View {
        VStack(spacing: 14) {
            LivingHourglass(state: .open(level: 0.62, warned: false))
                .compositingGroup()
                .frame(width: 96, height: 128)
                .shadow(color: Ember.amber.opacity(0.45), radius: 24)
            Text("Start with the worst offender.")
                .emberDisplay(24)
                .foregroundStyle(Ember.cream)
            Text("Each app or website gets allowed windows and a daily minute budget. Tightening applies instantly; loosening waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)).")
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button("Add app…") {
                    addDestination = .rules
                    showAddApp = true
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                Button("Add website…") {
                    addDestination = .rules
                    showAddSite = true
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(40)
    }
}
