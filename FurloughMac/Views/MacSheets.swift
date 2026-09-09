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
/// The Anchor on the Mac: its list, its scope, and one button to drop it. No release here — a
/// Mac has no tag reader — so the release arrives through iCloud from the phone's tag scan,
/// and dropping is refused until a phone has been heard from. The list is this Mac's own,
/// bundle identifiers and hosts, since a Screen Time token means nothing here.
struct AnchorSheet: View {
    @Environment(MacModel.self) private var model
    @State private var apps: [InstalledApp] = []
    @State private var query = ""
    @State private var host = ""
    @State private var message: String?
    @State private var switchingTo: AnchorProfile.Scope?

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var isHolding: Bool { anchor.isHolding(at: model.now) }

    /// Installed apps matching the search and not already listed, a handful at a time.
    private var found: [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return Array(apps.filter { app in
            !anchor.contains(.macApp(bundleID: app.bundleID))
                && (app.name.localizedCaseInsensitiveContains(trimmed) || app.bundleID.localizedCaseInsensitiveContains(trimmed))
        }.prefix(8))
    }

    var body: some View {
        SheetFrame(title: "Anchor", width: 560, height: 640) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    stateCard
                    SectionLabel(text: "Scope")
                    scopeCard
                    SectionLabel(text: anchor.anchorsEverything ? "Stays open" : "Held")
                    listCard
                    if !isHolding {
                        addCard
                            .padding(.top, 10)
                    }
                    Footnote(text: footnote)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .task { apps = AppCatalog.installed() }
        .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Start the list again?",
            isPresented: Binding(get: { switchingTo != nil }, set: { if !$0 { switchingTo = nil } }),
            titleVisibility: .visible
        ) {
            Button(switchingTo == .everythingExcept ? "Anchor everything except a list" : "Anchor chosen apps only") {
                if let scope = switchingTo { model.setAnchorScope(scope) }
                switchingTo = nil
            }
            Button("Keep it as it is", role: .cancel) { switchingTo = nil }
        } message: {
            Text(switchingTo == .everythingExcept
                ? "The list becomes what stays open, starting from every app you tiered Essential. What it holds now is not carried over."
                : "The list becomes what is held, starting empty.")
        }
    }

    private var stateCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: isHolding ? "Anchored" : "Free", color: isHolding ? Ember.ember : Ember.moss)
                Text(stateLine)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
            }
            Spacer(minLength: 8)
            if !isHolding {
                Button {
                    if let why = model.dropAnchor() { message = why }
                } label: {
                    Text("Drop anchor")
                        .emberBody(13, .bold)
                        .foregroundStyle(Ember.cream)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .disabled(!anchor.hasSomethingToHold)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .emberCard()
    }

    private var stateLine: String {
        let held = anchor.heldDescription
        if isHolding, let since = anchor.anchoredAt {
            let lift = anchor.until.map { " · lifts \(TimeFormat.clock($0))" } ?? ""
            return "\(held) since \(since.formatted(date: .omitted, time: .shortened))\(lift)"
        }
        if anchor.scope == .chosen, anchor.kinds.isEmpty { return "Nothing chosen yet" }
        if !model.phoneSeen { return "\(held) · waiting to hear from your iPhone" }
        return "\(held) · ready"
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                scopeChip(.chosen, "Chosen apps")
                scopeChip(.everythingExcept, "Everything except")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Text(anchor.anchorsEverything
                ? "Every app and website is held. Only what is listed stays open."
                : "Only what is listed is held. Everything else keeps its own rules.")
                .emberBody(12)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .emberCard()
    }

    private func scopeChip(_ scope: AnchorProfile.Scope, _ title: String) -> some View {
        let isOn = anchor.scope == scope
        return Button {
            guard !isOn else { return }
            if anchor.kinds.isEmpty { model.setAnchorScope(scope) } else { switchingTo = scope }
        } label: {
            Text(title)
                .emberBody(12, .semibold)
                .foregroundStyle(isOn ? Ember.ground : Ember.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
        .disabled(isHolding)
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            if anchor.kinds.isEmpty {
                Text(anchor.anchorsEverything ? "Nothing stays open." : "Nothing held yet.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                if anchor.scope == .chosen, !isHolding, !model.state.config.anchorCandidates.isEmpty {
                    CardDivider()
                    Button {
                        var copy = anchor
                        copy.add(model.state.config.anchorCandidates)
                        model.setAnchorKinds(copy.kinds)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Add everything you already block")
                                .emberBody(13, .semibold)
                        }
                        .foregroundStyle(Ember.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(Array(anchor.kinds.enumerated()), id: \.offset) { index, kind in
                if index > 0 { CardDivider() }
                HStack(spacing: 10) {
                    KindTile(kind: kind, size: 28)
                    Text(name(of: kind))
                        .emberBody(13, .medium)
                        .foregroundStyle(Ember.cream)
                        .lineLimit(1)
                    Spacer()
                    if !isHolding {
                        Button {
                            model.setAnchorKinds(anchor.kinds.filter { $0 != kind })
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
            }
        }
        .emberCard()
    }

    private var addCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.faint)
                TextField("Add an app", text: $query)
                    .textFieldStyle(.plain)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            ForEach(found) { app in
                CardDivider()
                Button {
                    add(.macApp(bundleID: app.bundleID))
                    query = ""
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                        Text(app.name).emberBody(13, .medium).foregroundStyle(Ember.cream)
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
            }
            CardDivider()
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.amber)
                TextField("Add a website, like youtube.com", text: $host)
                    .textFieldStyle(.plain)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                    .onSubmit(addHost)
                Button(action: addHost) {
                    Text("Add")
                        .emberBody(12, .semibold)
                        .foregroundStyle(Hosts.normalize(host) == nil ? Ember.faint : Ember.ember)
                }
                .buttonStyle(.plain)
                .disabled(Hosts.normalize(host) == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .emberCard()
    }

    private var footnote: String {
        if isHolding {
            return "Scan the paired tag in Furlough on your iPhone to release it, there and here. The list cannot change until then."
        }
        let reach = anchor.anchorsEverything
            ? "Everything not listed is blocked while anchored: apps are quit, and sites go to the shield page in every browser Furlough may read. Finder, the Dock and System Settings are never blocked."
            : "Anything listed is blocked while anchored. Windows and budgets still apply the rest of the time."
        return "\(reach) Dropping anchor here locks your iPhone too, through your iCloud account, and dropping it there locks this Mac. Only the tag on your iPhone releases either."
    }

    private func name(of kind: TargetKind) -> String {
        switch kind {
        case .macApp(let bundleID):
            model.state.config.target(bundleID: bundleID)?.displayName ?? AppInfo.name(for: bundleID) ?? bundleID
        case .host(let host):
            host
        }
    }

    private func add(_ kind: TargetKind) {
        guard !anchor.contains(kind) else { return }
        model.setAnchorKinds(anchor.kinds + [kind])
    }

    private func addHost() {
        guard let normalized = Hosts.normalize(host) else { return }
        add(.host(normalized))
        host = ""
    }
}

struct AddSiteSheet: View {
    let onAdd: (String) -> MacModel.AddOutcome
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
        let outcome = onAdd(text)
        if outcome.added != nil { dismiss() } else { message = outcome.message }
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
    @State private var confirmReset = false
    @State private var confirmRemoveFilter = false
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
        return review == nil ? "Settings" : "Restore from a file"
    }

    var body: some View {
        SheetFrame(title: title, width: 560, height: 640) {
            if showLog {
                LogView(onBack: { showLog = false })
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
                model.resetEverything()
                dismiss()
            }
        } message: {
            Text("Every app, rule and pending change is forgotten, along with today's usage. Furlough stays set up and keeps running.")
        }
        #endif
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "Loosening delay")
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Delay").emberBody(13).foregroundStyle(Ember.cream)
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

                SectionLabel(text: "Web")
                filterCard
                Footnote(text: filterFootnote)
                    .padding(.top, 8)

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
                Footnote(text: "The tab reader: Furlough reads each browser's address bar and sends a blocked tab to its shield page, so macOS asks once per browser. If one was refused, allow Furlough under System Settings > Privacy & Security > Automation.")
                    .padding(.top, 8)

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
                    CardDivider()
                    row("Notifications", model.notificationsGranted == true ? "Allowed" : "Off")
                    CardDivider()
                    // The phone shows this too. It matters more here: the desktop widget reads
                    // the rules through the group, so without it the widget is simply blank,
                    // with nothing anywhere to say why.
                    row(
                        "App Group",
                        SharedStore.isAppGroupAvailable ? "OK" : "Missing",
                        color: SharedStore.isAppGroupAvailable ? Ember.muted : Ember.ember
                    )
                    CardDivider()
                    row("Last enforcement", stamp(model.state.runtime.lastReconcile))
                    CardDivider()
                    CardAction(title: "Re-apply enforcement now") { model.enforce(reason: "manual") }
                    if model.notificationsGranted != true {
                        CardDivider()
                        CardAction(title: "Allow notifications") { Task { await model.requestNotifications() } }
                    }
                    CardDivider()
                    CardAction(title: "Activity log", symbol: "list.bullet", color: Ember.cream) { showLog = true }
                }
                .emberCard()

                SectionLabel(text: "Your setup")
                VStack(spacing: 0) {
                    CardAction(title: "Download my setup", symbol: "square.and.arrow.down", color: Ember.cream) { exportSetup() }
                    CardDivider()
                    CardAction(title: "Restore from a file", symbol: "square.and.arrow.up", color: Ember.cream) { showImporter = true }
                }
                .emberCard()
                Footnote(text: "Saves your apps, websites, rules, budgets, tiers and delay as a JSON file. Mac targets are bundle identifiers and hosts, so this file is the whole setup and another Mac can take it as it stands.\n\nRestoring is a proposal, not a rewind: every rule in the file goes through the same delay the rule editor does, so anything in it that loosens your rules waits. You see the whole of it before any of it happens.")
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                SectionLabel(text: "The one escape")
                Text("Furlough has no unblock button. On the Mac it enforces by quitting blocked apps and sending blocked tabs to its shield page, so it has to keep running: Quit is refused while anything is blocked. Force Quit (Option-Command-Escape) ends enforcement until Furlough is opened again, the way turning off Screen Time access does on the phone. It is documented on purpose.")
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)

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
                    Footnote(text: "Not in the shipping build. Reset everything forgets every app, website, rule, pending change and today's usage, and lifts every block.\n\nHide these buttons puts this section away. Show testing buttons, or five clicks on Version under Help > About, brings it back.")
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
            case .awaitingApproval, .disabledInSettings:
                CardDivider()
                CardAction(title: "Open System Settings…") { WebFilter.openSystemSettings() }
                CardDivider()
                CardAction(title: "Check again", color: Ember.cream) { Task { await filter.refresh() } }
            case .filterOff:
                CardDivider()
                CardAction(title: "Turn the filter on") { Task { await filter.enableFilter() } }
            case .on:
                CardDivider()
                CardAction(title: "Remove the web filter", color: Ember.muted) { confirmRemoveFilter = true }
            case .notInApplications, .installing:
                EmptyView()
            }
        }
        .emberCard()
    }

    private var filterFootnote: String {
        let what = "The web filter is a system extension that sees every connection this Mac opens and refuses the ones to a blocked site, from any app: Firefox, a site saved to the Dock, anything that loads a site outside a browser. Those get the floating card rather than the shield page."
        switch model.enforcer.webFilter.status {
        case .notInApplications:
            return what + "\n\nmacOS only loads it from an app in the Applications folder. Move Furlough there and open it again."
        case .notInstalled:
            return what + "\n\nmacOS asks twice: once to allow the extension, under System Settings > General > Login Items & Extensions, and once to let it filter."
        case .awaitingApproval:
            return what + "\n\nAllow it under System Settings > General > Login Items & Extensions > Network Extensions, then check again here."
        case .disabledInSettings:
            return what + "\n\nIt was switched off in System Settings. Sites are enforced by the tab reader alone until it is turned on again, under General > Login Items & Extensions > Network Extensions."
        case .filterOff:
            return what + "\n\nThe extension is in place but macOS is not sending it any traffic. Turning it on asks the filtering question again."
        case .failed(let reason):
            return what + "\n\n" + reason
        case .installing, .on:
            return what + "\n\nWhile something is blocked, connections that cannot be named are refused over QUIC and the browser falls back to the ordinary kind, where the name can be read. That is invisible, and only while a rule is in force."
        }
    }

    private func filterColor(_ status: WebFilter.Status) -> Color {
        switch status {
        case .on: Ember.moss
        case .awaitingApproval, .installing: Ember.pending
        case .disabledInSettings, .filterOff, .failed, .notInApplications: Ember.ember
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

    private func stamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
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
    let onBack: () -> Void
    @State private var entries = SharedStore.logEntries()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { onBack() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text("Settings").emberBody(12.5, .semibold)
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
