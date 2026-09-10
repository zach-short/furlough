import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Every app on this Mac, searchable. Picking one adds it.
struct AddAppSheet: View {
    let onPick: (InstalledApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [InstalledApp] = []
    @State private var query = ""

    private var filtered: [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(trimmed) || $0.bundleID.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        SheetFrame(title: "Add an app", width: 520, height: 600) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ember.faint)
                    TextField("Search apps", text: $query)
                        .textFieldStyle(.plain)
                        .emberBody(13)
                        .foregroundStyle(Ember.cream)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .emberCard()
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sections, id: \.title) { section in
                            SectionLabel(text: section.title)
                            VStack(spacing: 0) {
                                ForEach(section.apps) { app in
                                    Button {
                                        onPick(app)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 28, height: 28)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(app.name).emberBody(13, .medium).foregroundStyle(Ember.cream)
                                                Text(app.bundleID).emberBody(10.5).foregroundStyle(Ember.faint)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(Ember.ember)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if app.id != section.apps.last?.id { CardDivider() }
                                }
                            }
                            .emberCard()
                        }
                        if filtered.isEmpty {
                            Text(apps.isEmpty ? "Looking for apps…" : "No app matches.")
                                .emberBody(13)
                                .foregroundStyle(Ember.muted)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .task { apps = AppCatalog.installed() }
    }

    private struct Section { let title: String; let apps: [InstalledApp] }

    private var sections: [Section] {
        let list = filtered
        let running = list.filter(\.isRunning)
        let rest = query.isEmpty ? list.filter { !$0.isRunning } : list
        return [
            Section(title: "Running now", apps: query.isEmpty ? running : []),
            Section(title: query.isEmpty ? "All apps" : "Matches", apps: rest),
        ].filter { !$0.apps.isEmpty }
    }
}

/// A website by host.
struct AddSiteSheet: View {
    /// Returns why not, or nil when it landed and the sheet should close. A refusal rather than
    /// an outcome, because since the halves this sheet feeds two of them: what the Anchor does
    /// with a host is put it on a list, and there is no `Target` to hand back.
    let onAdd: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var message: String?

    var body: some View {
        SheetFrame(title: "Add a website", width: 460, height: 260) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ember.amber)
                    TextField("youtube.com", text: $text)
                        .textFieldStyle(.plain)
                        .emberBody(14, .medium)
                        .foregroundStyle(Ember.cream)
                        .onSubmit(add)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .emberCard()
                Footnote(text: "The host and its subdomains: youtube.com also covers m.youtube.com. Paste a full address if you like; only the host is kept. Works in Safari, Chrome, Arc, Brave, Edge and other Chromium browsers.")
                    .padding(.top, 8)
                if let message {
                    Text(message)
                        .emberBody(12)
                        .foregroundStyle(Ember.ember)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                }
                Spacer()
                ProminentButton(title: "Add") { add() }
                    .disabled(Hosts.normalize(text) == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func add() {
        if let why = onAdd(text) { message = why } else { dismiss() }
    }
}

/// Offered right after an app or a site is added: the other half of the same thing. Blocking
/// the YouTube app and leaving youtube.com open is the gap most people find a week later, so
/// the site is offered while the app is still in hand, one toggle each, all on to start.
/// Nothing here enforces anything; like any add, each one waits for a schedule.
struct CompanionSheet: View {
    /// One thing to offer: what it would be added as, and how the row says it.
    struct Item: Identifiable, Hashable {
        let kind: TargetKind
        let title: String
        let subtitle: String
        var id: TargetKind { kind }
    }

    /// What was just added, and whose other half these are.
    let added: Target
    let items: [Item]
    let onAdd: ([Item]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<TargetKind>

    init(added: Target, items: [Item], onAdd: @escaping ([Item]) -> Void) {
        self.added = added
        self.items = items
        self.onAdd = onAdd
        _chosen = State(initialValue: Set(items.map(\.kind)))
    }

    /// What one row measures: a 30pt tile with 8pt above and below, and the divider under it.
    /// The sheet is sized in whole rows, so this has to be what a row really is — sized by the
    /// row before it was drawn, the card sat in a taller box and the sheet had a band of air
    /// under it that grew with every row.
    private let rowHeight: CGFloat = 50

    /// True when what was added is an app, so the offer is its websites.
    private var addedIsApp: Bool { if case .macApp = added.kind { return true }; return false }
    private var selected: [Item] { items.filter { chosen.contains($0.kind) } }

    var body: some View {
        SheetFrame(title: title, width: 460, height: 240 + CGFloat(min(items.count, 4)) * rowHeight) {
            VStack(alignment: .leading, spacing: 0) {
                Text(explanation)
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                            if item.id != items.last?.id { CardDivider() }
                        }
                    }
                    .emberCard()
                }
                .scrollBounceBehavior(.basedOnSize)
                Footnote(text: "Nothing is enforced until it has a schedule. Set \(added.displayName)'s, then apply those windows to \(items.count == 1 ? "it" : "the rest") from its editor so they keep the same hours.")
                    .padding(.top, 10)
                ProminentButton(title: buttonTitle) {
                    onAdd(selected)
                    dismiss()
                }
                .disabled(selected.isEmpty)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 12)
                Button(addedIsApp ? "Just the app" : "Just the site") { dismiss() }
                    .buttonStyle(.plain)
                    .emberBody(12.5, .medium)
                    .foregroundStyle(Ember.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            KindTile(kind: item.kind, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .emberBody(13, .medium)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Text(item.subtitle)
                    .emberBody(11)
                    .foregroundStyle(Ember.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(item.title, isOn: Binding(
                get: { chosen.contains(item.kind) },
                set: { on in
                    withAnimation(.snappy(duration: 0.2)) {
                        if on { chosen.insert(item.kind) } else { chosen.remove(item.kind) }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Ember.ember)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch (addedIsApp, items.count) {
        case (true, 1): "Also block \(items[0].title)?"
        case (true, _): "Also block its websites?"
        case (false, 1): "Also block the \(items[0].title) app?"
        case (false, _): "Also block its apps?"
        }
    }

    private var explanation: String {
        let several = items.count > 1
        return addedIsApp
            ? "\(added.displayName) is in. \(several ? "The sites are" : "The site is") the same thing in a browser tab; blocked together, there is no back door."
            : "\(added.displayName) is in. \(several ? "The apps are" : "The app is") the same thing without the browser; blocked together, there is no back door."
    }

    private var buttonTitle: String {
        switch selected.count {
        case 0: "Add"
        case 1: "Add it too"
        case let n: "Add \(n) too"
        }
    }
}

/// Picks the other apps and sites that get this rule, any number at once. Each row shows what
/// it has now; the line above the button says what applying will do, since each one is judged
/// on its own: tighter lands now, looser waits out the delay.
struct ApplyRuleSheet: View {
    let candidates: [Target]
    let rule: Rule
    let delayHours: Int
    let onApply: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []

    private var chosen: [Target] { candidates.filter { selected.contains($0.id) } }
    private var allChosen: Bool { selected.count == candidates.count }

    var body: some View {
        SheetFrame(title: "Apply windows to", width: 520, height: 520) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(allChosen ? "Select none" : "Select all") {
                        withAnimation(.snappy(duration: 0.2)) {
                            selected = allChosen ? [] : Set(candidates.map(\.id))
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .tint(Ember.cream)
                }
                .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(candidates) { target in
                            row(target)
                            if target.id != candidates.last?.id { CardDivider() }
                        }
                    }
                    .emberCard()
                }
                Footnote(text: summary, alignment: .center)
                    .padding(.top, 10)
                ProminentButton(title: buttonTitle) {
                    onApply(chosen.map(\.id))
                    dismiss()
                }
                .disabled(selected.isEmpty)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func row(_ target: Target) -> some View {
        let on = selected.contains(target.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if on { selected.remove(target.id) } else { selected.insert(target.id) }
            }
        } label: {
            HStack(spacing: 10) {
                KindTile(kind: target.kind, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.displayName)
                        .emberBody(13, .medium)
                        .foregroundStyle(Ember.cream)
                        .lineLimit(1)
                    Text(TimeFormat.rule(target.rule))
                        .emberBody(11)
                        .foregroundStyle(Ember.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? Ember.amber : Ember.faint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// What applying does to the chosen rows, each judged against what it has now.
    private var summary: String {
        guard !chosen.isEmpty else {
            return "Gives each one these windows, days and daily budget, and saves them here too."
        }
        var now = 0, later = 0, same = 0
        for target in chosen {
            if target.rule?.isEquivalent(to: rule) ?? false {
                same += 1
            } else if Policy.classify(newRule: rule, against: target) == .tightening {
                now += 1
            } else {
                later += 1
            }
        }
        var parts: [String] = []
        if now > 0 { parts.append("Tighter for \(now), applied now") }
        if later > 0 { parts.append("Looser for \(later), after \(TimeFormat.delay(hours: delayHours))") }
        if same > 0 { parts.append("\(same) unchanged") }
        return parts.joined(separator: " · ")
    }

    private var buttonTitle: String {
        let count = chosen.count
        guard count > 0 else { return "Apply" }
        let apps = chosen.filter { if case .macApp = $0.kind { return true }; return false }.count
        let noun = switch (apps, count) {
        case (count, 1): "app"
        case (count, _): "apps"
        case (0, 1): "site"
        case (0, _): "sites"
        default: "apps and sites"
        }
        return "Apply to \(count) \(noun)"
    }
}

struct PendingSheet: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        let pending = model.state.pending.sorted { $0.effectiveAt < $1.effectiveAt }
        SheetFrame(title: "Pending", width: 520, height: 520) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let clock = model.state.clock()
                    if !clock.isTrusted {
                        ClockBanner(drift: clock.drift)
                    }
                    if pending.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(Ember.moss)
                            Text("Nothing pending")
                                .emberDisplay(24)
                                .foregroundStyle(Ember.cream)
                            Text("Loosening edits wait here until they take effect.")
                                .emberBody(13)
                                .foregroundStyle(Ember.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                    ForEach(pending) { change in
                        PendingCard(
                            change: change,
                            target: change.targetID.flatMap { model.state.config.target(id: $0) },
                            delta: PendingText.delta(for: change, in: model.state.config)
                        ) {
                            withAnimation(.snappy) { model.cancelPending(id: change.id) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

struct PendingCard: View {
    let change: PendingChange
    let target: Target?
    let delta: PendingText.Delta
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let target {
                    KindTile(kind: target.kind, size: 34)
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Ember.pending)
                        .frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(target?.displayName ?? PendingText.subject(of: change.kind) ?? "Loosening delay")
                        .emberDisplaySmall(13.5)
                        .foregroundStyle(Ember.cream)
                    PendingDeltaView(delta: delta)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Text("Takes effect \(change.effectiveAt.formatted(date: .abbreviated, time: .shortened)) · \(change.effectiveAt, style: .relative) from now")
                .emberBody(11, .semibold)
                .foregroundStyle(Ember.pending)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
            CardDivider()
            GhostButton(title: "Cancel change", action: onCancel)
        }
        .emberCard()
    }
}

struct SettingsSheet: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var delayHours = Furlough.defaultLoosenDelayHours
    @State private var result: ProposalResult?
    @State private var showLog = false
    /// The screen behind the one Diagnostics row. In place, with a Back link, like the log:
    /// this is a sheet, and a sheet that grew a navigation stack for two pushes would be
    /// carrying a bar it has no use for.
    @State private var showDiagnostics = false
    @State private var confirmReset = false
    @State private var confirmRemoveFilter = false
    /// Two seconds of "Copied" after the diagnostics go to the pasteboard.
    @State private var copiedDiagnostics = false
    @State private var setupFile: SetupDocument?
    @State private var setupName = ""
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var review: ImportPlan?
    @State private var importError: String?
    /// What the import just did, waiting to be said. The review is dropped as the alert goes up,
    /// so this is shown over Settings rather than over a screen that is on its way out.
    @State private var imported: String?
    #if DEBUG || TESTING_TOOLS
    @State private var showTesting = TestingTools.isShown
    #endif

    private var title: String {
        if showLog { return "Activity log" }
        if showDiagnostics { return "Diagnostics" }
        return review == nil ? "Settings" : "Restore from a file"
    }

    var body: some View {
        SheetFrame(title: title, width: 560, height: 640) {
            if showLog {
                LogView(backTitle: showDiagnostics ? "Diagnostics" : "Settings") { showLog = false }
            } else if showDiagnostics {
                MacDiagnosticsView(onBack: { showDiagnostics = false }, onOpenLog: { showLog = true })
            } else if let review {
                MacImportReview(plan: review, onBack: { self.review = nil }) {
                    imported = model.applyImport(review)
                    self.review = nil
                }
            } else {
                settings
            }
        }
        .onAppear {
            delayHours = model.state.config.loosenDelayHours
            model.refreshBrowserAccess()
            #if DEBUG || TESTING_TOOLS
            // Help is where the section is asked for — Version, five clicks — and Help is a
            // sheet of its own, so this screen finds out on the way back in.
            showTesting = TestingTools.isShown
            #endif
            Task { await model.enforcer.webFilter.refresh() }
        }
        .confirmationDialog("Remove the web filter?", isPresented: $confirmRemoveFilter, titleVisibility: .visible) {
            Button("Remove the web filter", role: .destructive) { model.enforcer.webFilter.remove() }
        } message: {
            Text("Sites stay enforced in Safari and the Chromium browsers through the tab reader. Firefox, Dock web apps and everything else open up. Install it again here whenever you like.")
        }
        .alert("Delay", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }), presenting: result) { _ in
            Button("OK") { result = nil }
        } message: { result in
            Text(result.message)
        }
        .fileExporter(
            isPresented: Binding(get: { setupFile != nil }, set: { if !$0 { setupFile = nil } }),
            document: setupFile,
            contentType: .json,
            defaultFilename: setupName
        ) { outcome in
            setupFile = nil
            if case .failure(let error) = outcome {
                exportError = error.localizedDescription
                SharedStore.log("export failed: \(error)")
            } else {
                SharedStore.log("exported setup")
            }
        }
        .alert("Download my setup", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }), presenting: exportError) { _ in
            Button("OK") { exportError = nil }
        } message: { error in
            Text(error)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { outcome in
            switch outcome {
            case .success(let url):
                switch model.review(fileAt: url) {
                case .success(let plan): review = plan
                case .failure(let refusal): importError = refusal.message
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Restore from a file", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }), presenting: importError) { _ in
            Button("OK") { importError = nil }
        } message: { error in
            Text(error)
        }
        .alert("Restored", isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } }), presenting: imported) { _ in
            Button("OK") { imported = nil }
        } message: { message in
            Text(message)
        }
        #if DEBUG || TESTING_TOOLS
        .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) {
                // Dismissed before the reset, where the phone does it after. The reset puts the
                // Mac back to onboarding, which swaps `MacHomeView` — the view presenting this
                // sheet — out from under it; closing while the presenter is still there leaves
                // AppKit nothing to tidy up after.
                dismiss()
                model.resetEverything()
            }
        } message: {
            Text("Every app, website, rule and pending change is forgotten, along with today's usage and the Anchor, and Furlough goes back to its first run. The web filter and the browser permissions you have given macOS are kept.")
        }
        #endif
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                startCard

                delayCard

                webCard

                browsersCard

                enforcementCard

                setupCard

                diagnosticsCard

                #if DEBUG || TESTING_TOOLS
                if showTesting {
                    SectionLabel(text: "Testing")
                    VStack(spacing: 0) {
                        CardAction(title: "Reset everything") { confirmReset = true }
                        CardDivider()
                        CardAction(title: "Hide these buttons") {
                            TestingTools.isShown = false
                            showTesting = false
                        }
                    }
                    .emberCard()
                    Footnote(text: "Not in the shipping build. Reset everything forgets every app, website, rule, pending change, the Anchor and today's usage, lifts every block, takes the login item and the watchdog back off, and returns to onboarding — a fresh install, apart from the web filter and the browser permissions, which macOS would make you grant again and which are kept.\n\nHide these buttons puts this section away. Show testing buttons, or five clicks on Version under Help > About, brings it back.")
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                } else {
                    // The same way back the phone has, for the same reason: the reset button is
                    // used during a test pass, and a hidden gesture is a poor only route to it.
                    CardAction(title: "Show testing buttons") {
                        TestingTools.isShown = true
                        showTesting = true
                    }
                    .emberCard()
                    .padding(.bottom, 20)
                }
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: Start

    /// The three things about how Furlough opens: which half the window opens on, what the +
    /// means over the Anchor half, and the checklists again.
    ///
    /// At the top because these are the settings a person came here to change. The intro asks
    /// the first one once, in the pane that says the app is two halves; this is the only other
    /// place it can be answered, and the pane is not coming back.
    @ViewBuilder
    private var startCard: some View {
        SectionLabel(text: "Start")
        VStack(spacing: 0) {
            halfRow(title: "Opens on", selection: model.startHalf) { model.setStartHalf($0) }
            CardDivider()
            addRow
            CardDivider()
            CardAction(
                title: "Run the setup guide again",
                detail: guideDetail,
                color: model.finishedGuides.isEmpty ? Ember.faint : Ember.ember
            ) {
                model.restartGuides()
            }
            .disabled(model.finishedGuides.isEmpty)
        }
        .emberCard()
        Footnote(text: "Over the Rules half + always makes a rule.")
            .padding(.top, 8)
    }

    /// What + does over the Anchor half.
    ///
    /// The + acts on the half you are looking at, which over the Anchor means its list — and the
    /// one person that reading fails is the one who set the anchor up months ago and has read +
    /// as "give an app hours" ever since. So it is a preference rather than a rule, and only
    /// about the Anchor half: over Rules the button has no second reading to choose between.
    private var addRow: some View {
        HStack(spacing: 12) {
            Text("On the Anchor half, + adds")
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                chip("To the anchor", isOn: model.anchorHalfAdds == .anchor) { model.setAnchorHalfAdds(.anchor) }
                chip("A new rule", isOn: model.anchorHalfAdds == .rules) { model.setAnchorHalfAdds(.rules) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// Says what pressing it would do, and then what it did — both derived from the same set, so
    /// the row answers for itself rather than raising an alert to say something happened.
    private var guideDetail: String {
        let finished = model.finishedGuides
        guard !finished.isEmpty else { return "Both checklists are showing in the window." }
        if finished.count == 1, let only = finished.first {
            return "Puts the three steps back on the \(only.title) half."
        }
        return "Puts the three steps back on both halves."
    }

    private func halfRow(title: String, selection: Half, onPick: @escaping (Half) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(Half.allCases, id: \.self) { half in
                    chip(half.title, isOn: half == selection) { onPick(half) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// One of a pair: the chosen one is filled, the other an outline. Not a `Picker`, because
    /// both choices have to be readable at once — the question is which of two things this
    /// means, and a menu that shows one answer at a time is a poor way to ask it.
    private func chip(_ title: String, isOn: Bool, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .emberBody(12, .semibold)
                .foregroundStyle(isOn ? Ember.ground : Ember.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? Ember.amber : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isOn ? .clear : Ember.cardBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Rules

    @ViewBuilder
    private var delayCard: some View {
        SectionLabel(text: "Rules")
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Loosening delay").emberBody(13).foregroundStyle(Ember.cream)
                Spacer()
                Text(TimeFormat.delay(hours: delayHours))
                    .emberBody(13, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Ember.cream)
                Stepper("Loosening delay", value: $delayHours, in: 1...168, step: delayHours >= 24 ? 24 : 1)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            CardDivider()
            GhostButton(title: "Save delay") { result = model.setDelay(hours: delayHours) }
                .disabled(delayHours == model.state.config.loosenDelayHours)
                .opacity(delayHours == model.state.config.loosenDelayHours ? 0.4 : 1)
        }
        .emberCard()
        Footnote(text: "Raising the delay applies immediately. Lowering it waits out the current delay.")
            .padding(.top, 8)
    }

    // MARK: Web

    /// The filter, and the walkthrough — which is only here while there is something to walk
    /// through. Six numbered steps under a status that reads On is a page of directions to a
    /// place you are already standing in, and it was the tallest thing on this screen.
    @ViewBuilder
    private var webCard: some View {
        let status = model.enforcer.webFilter.status
        SectionLabel(text: "Web")
        filterCard
        if !status.isOn {
            Footnote(text: WebFilter.explainer)
                .padding(.top, 8)
            FilterDirections(
                guidance: status.guidance,
                size: 11.5,
                perform: model.enforcer.webFilter.perform
            )
            .padding(.horizontal, 8)
            .padding(.top, 10)
        }
    }

    // MARK: Browsers

    @ViewBuilder
    private var browsersCard: some View {
        SectionLabel(text: "Browsers")
        VStack(spacing: 0) {
            if model.browserAccess.isEmpty {
                Text("No supported browser is running. Furlough asks for access the first time one is in front.")
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            ForEach(model.browserAccess) { browser in
                row(browser.name, label(browser.status), color: browser.status == .denied ? Ember.ember : Ember.muted)
                CardDivider()
            }
            CardAction(title: "Ask for browser access now") {
                model.enforcer.browsers.requestAccess()
                model.refreshBrowserAccess()
            }
        }
        .emberCard()
        Footnote(text: "Furlough reads each browser's address bar and sends a blocked tab to its shield page, so macOS asks once per browser. Allow a refused one under System Settings > Privacy & Security > Automation.")
            .padding(.top, 8)
    }

    // MARK: Enforcement

    /// The two switches, and the one escape in a footnote rather than a paragraph. Everything
    /// else that stood under this label was a status row or a button for when something looks
    /// wrong, and all of it is one push behind Diagnostics now.
    @ViewBuilder
    private var enforcementCard: some View {
        SectionLabel(text: "Enforcement")
        VStack(spacing: 0) {
            HStack {
                Text("Open at login").emberBody(13).foregroundStyle(Ember.cream)
                Spacer()
                Toggle("Open at login", isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Ember.ember)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            CardDivider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reopen after a Force Quit").emberBody(13).foregroundStyle(Ember.cream)
                    Text("Force Quit still lifts every block. This brings Furlough back within a minute.")
                        .emberBody(11.5)
                        .foregroundStyle(Ember.muted)
                }
                Spacer()
                Toggle("Reopen after a Force Quit", isOn: Binding(get: { model.watchdogIsOn }, set: { model.setWatchdog($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Ember.ember)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .emberCard()
        Footnote(text: "Furlough enforces by quitting blocked apps, so Quit is refused while anything is blocked. Force Quit is the one escape, and it is documented on purpose.")
            .padding(.top, 8)
    }

    // MARK: Your setup

    @ViewBuilder
    private var setupCard: some View {
        SectionLabel(text: "Your setup")
        VStack(spacing: 0) {
            CardAction(title: "Download my setup", symbol: "square.and.arrow.down", color: Ember.cream) { exportSetup() }
            CardDivider()
            CardAction(title: "Restore from a file", symbol: "square.and.arrow.up", color: Ember.cream) { showImporter = true }
        }
        .emberCard()
        Footnote(text: "Rules, budgets, tiers and delay, as a file. The Anchor stays on this Mac. Restoring goes through the same delay as editing.")
            .padding(.top, 8)
    }

    // MARK: Diagnostics

    /// One row: whether anything is wrong, and the first thing that is if something is.
    ///
    /// The rows it replaced are all still here, one push in. What changed is that a person who
    /// came to Settings to change the delay no longer reads five statuses on the way.
    @ViewBuilder
    private var diagnosticsCard: some View {
        let summary = model.diagnostics
        SectionLabel(text: "Diagnostics")
        VStack(spacing: 0) {
            Button { showDiagnostics = true } label: {
                HStack(spacing: 10) {
                    Circle().fill(dot(for: summary.level)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.line).emberBody(13).foregroundStyle(Ember.cream)
                        Text(Diagnostics.macDetail).emberBody(11.5).foregroundStyle(Ember.muted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ember.faint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .emberCard()
        .padding(.bottom, 20)
    }

    private func dot(for level: Diagnostics.Level) -> Color {
        switch level {
        case .well: Ember.moss
        case .warn: Ember.amber
        case .bad: Ember.ember
        }
    }

    /// The web filter: its state, and the one action that state calls for.
    @ViewBuilder
    private var filterCard: some View {
        let filter = model.enforcer.webFilter
        let status = filter.status
        VStack(spacing: 0) {
            row("Web filter", status.label, color: filterColor(status))
            switch status {
            case .notInstalled, .failed:
                CardDivider()
                CardAction(title: "Install the web filter") { filter.install() }
            // Nothing for the states in the middle of the walk: their buttons belong to the step
            // that calls for them, in the walkthrough below this card.
            case .awaitingApproval, .disabledInSettings, .filterOff, .filterDenied:
                EmptyView()
            case .on:
                CardDivider()
                CardAction(title: "Remove the web filter", color: Ember.muted) { confirmRemoveFilter = true }
            case .notInApplications, .installing:
                EmptyView()
            }
            CardDivider()
            CardAction(title: copiedDiagnostics ? "Copied" : "Copy diagnostics", symbol: "doc.on.doc", color: Ember.muted) {
                Task {
                    let report = await filter.diagnostics()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    await filter.logDiagnostics(because: "asked for from Settings > Web")
                    copiedDiagnostics = true
                    try? await Task.sleep(for: .seconds(2))
                    copiedDiagnostics = false
                }
            }
        }
        .emberCard()
    }

    private func filterColor(_ status: WebFilter.Status) -> Color {
        switch status {
        case .on: Ember.moss
        case .awaitingApproval, .installing: Ember.pending
        case .disabledInSettings, .filterOff, .failed, .filterDenied, .notInApplications: Ember.ember
        case .notInstalled: Ember.muted
        }
    }

    private func label(_ status: BrowserAccess.Status) -> String {
        switch status {
        case .allowed: "Allowed"
        case .denied: "Refused"
        case .notAsked: "Not asked yet"
        case .notRunning: "Not running"
        }
    }

    private func row(_ title: String, _ value: String, color: Color = Ember.muted) -> some View {
        HStack {
            Text(title).emberBody(13).foregroundStyle(Ember.cream)
            Spacer()
            Text(value).emberBody(13).foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Builds the file and opens the save panel. Reading the store is the whole of it: an
    /// export changes nothing, so alone among the buttons on this screen it needs no delay,
    /// no confirmation and no enforcement pass afterwards.
    private func exportSetup() {
        do {
            let export = ConfigExport.current()
            setupFile = SetupDocument(data: try export.json())
            setupName = export.suggestedFilename
        } catch {
            exportError = error.localizedDescription
            SharedStore.log("export failed: \(error)")
        }
    }
}

struct LogView: View {
    /// What the Back link says. The log is one push behind Diagnostics now and Diagnostics is
    /// one behind Settings, so the link has to name the screen it actually returns to.
    var backTitle = "Settings"
    let onBack: () -> Void
    @State private var entries = SharedStore.logEntries()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { onBack() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text(backTitle).emberBody(12.5, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Refresh") { entries = SharedStore.logEntries() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ember.muted)
                    .emberBody(12.5)
                    .padding(.trailing, 14)
                Button("Clear") {
                    SharedStore.clearLog()
                    entries = []
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ember.muted)
                .emberBody(12.5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entries.reversed().enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(EmberFont.mono(11))
                            .foregroundStyle(Ember.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if entries.isEmpty {
                        Text("Nothing logged yet.").emberBody(13).foregroundStyle(Ember.muted).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

/// Everything the Settings screen used to say under Enforcement, one push behind the row that
/// says whether any of it is wrong.
///
/// Nothing here is a setting. It is what Furlough can see about itself — the two permissions,
/// the App Group the widget reads through, what the web filter is doing, when enforcement last
/// ran — and the two things a person can do about it: run the whole pass again, and read what
/// the enforcer has been doing. Help's *If something gets stuck* sends people here by name.
struct MacDiagnosticsView: View {
    @Environment(MacModel.self) private var model
    let onBack: () -> Void
    let onOpenLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text("Settings").emberBody(12.5, .semibold)
                }
                .foregroundStyle(Ember.ember)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        row("Notifications", model.notificationsGranted == true ? "Allowed" : "Off")
                        CardDivider()
                        // The phone shows this too. It matters more here: the desktop widget
                        // reads the rules through the group, so without it the widget is simply
                        // blank, with nothing anywhere to say why.
                        row(
                            "App Group",
                            SharedStore.isAppGroupAvailable ? "OK" : "Missing",
                            color: SharedStore.isAppGroupAvailable ? Ember.muted : Ember.ember
                        )
                        CardDivider()
                        row("Web filter", model.enforcer.webFilter.status.label)
                        CardDivider()
                        row("Browsers", browserSummary)
                        CardDivider()
                        row("Last enforcement", stamp(model.state.runtime.lastReconcile))
                    }
                    .emberCard()

                    SectionLabel(text: "If something looks wrong")
                    VStack(spacing: 0) {
                        CardAction(title: "Re-apply enforcement now") { model.enforce(reason: "manual") }
                        if model.notificationsGranted != true {
                            CardDivider()
                            CardAction(title: "Allow notifications") { Task { await model.requestNotifications() } }
                        }
                        CardDivider()
                        CardAction(title: "Activity log", symbol: "list.bullet", color: Ember.cream) { onOpenLog() }
                    }
                    .emberCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear { model.refreshBrowserAccess() }
    }

    /// The per-browser rows stay in Settings > Browsers, where the button that asks for access
    /// is. This is the count, so a refused one is visible from here without saying it twice.
    private var browserSummary: String {
        let running = model.browserAccess
        guard !running.isEmpty else { return "None running" }
        let refused = running.filter { $0.status == .denied }
        if refused.isEmpty { return "\(running.count) running · all readable" }
        return "\(refused.count) of \(running.count) refused"
    }

    private func row(_ title: String, _ value: String, color: Color = Ember.muted) -> some View {
        HStack {
            Text(title).emberBody(13).foregroundStyle(Ember.cream)
            Spacer()
            Text(value)
                .emberBody(13)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func stamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }
}
