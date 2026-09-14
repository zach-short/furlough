import SwiftUI

/// Home: Rules and the Anchor as two co-equal pages under one toolbar. Initial page comes
/// from `AppModel.startHalf`.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    /// Kept in view state (not re-derived) so a swipe doesn't snap back on rebuild.
    @State private var half: Half
    @State private var showAddChoice = false
    /// Feeds `addTargetsFlow`, which takes it to Apple's picker.
    @State private var addRequest: AddRequest?
    /// Held here rather than as links, since the anchor grid's "Give it hours too" pushes
    /// one from a context menu, which has no link to attach to.
    @State private var path: [UUID] = []
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showPending = false

    init(start: Half) { _half = State(initialValue: start) }

    var body: some View {
        NavigationStack(path: $path) {
            // TabView (not a switch) so swiping and the segment tap drive the same selection.
            TabView(selection: $half) {
                RulesPage(onChooseApps: { addRequest = .plain(.application) })
                    .tag(Half.rules)
                // A page-style TabView renders the page beside the one shown; the Anchor arms
                // NFC on sight, so only the current page may listen (see `isCurrent`).
                AnchorPage(
                    isCurrent: half == .anchor,
                    onChooseApps: { addRequest = .anchor },
                    onOpenRule: { path.append($0) }
                )
                .tag(Half.anchor)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(EmberWall())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                RuleEditorView(targetID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape.fill") { showSettings = true }
                        .tint(Ember.cream)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Help", systemImage: "questionmark.circle.fill") { showHelp = true }
                        .tint(Ember.cream)
                }
                if !model.state.pending.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showPending = true } label: {
                            Text("\(model.state.pending.count) pending")
                                .emberBody(13, .semibold)
                        }
                        .tint(Ember.pending)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                // The + targets whichever page it's on, unless Settings overrides the
                // destination (see `addDestination`). Anchor add skips the App/Website
                // popover: both come from the one picker there.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        if model.addDestination(on: half) == .anchor {
                            addRequest = .anchor
                        } else {
                            showAddChoice = true
                        }
                    }
                    .tint(Ember.cream)
                    .popover(isPresented: $showAddChoice, arrowEdge: .top) {
                        AddChoicePopover(
                            applicationCaption: "Apps and categories, from Apple's picker",
                            websiteCaption: "Type the address. Hours, but no daily limit"
                        ) { choice in
                            showAddChoice = false
                            addRequest = .plain(choice)
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .addTargetsFlow($addRequest)
            .sheet(isPresented: $showPending) { PendingChangesView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showHelp) { HelpView() }
            .overlay(alignment: .bottom) {
                HalfTabBar(half: $half)
                    .padding(.bottom, 6)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

/// Rules/Anchor switcher, floating over the bottom of the page rather than spanning it —
/// an icon over a label per side, so it reads as a compact nav control, not a full tab bar.
struct HalfTabBar: View {
    @Binding var half: Half

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Half.allCases, id: \.self) { value in
                Button {
                    guard value != half else { return }
                    // withAnimation needed: a page TabView jumps (doesn't slide) on a plain assignment.
                    withAnimation(.snappy(duration: 0.3)) { half = value }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: value.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 22, height: 20)
                        Text(value.title)
                            .emberBody(10.5, .bold)
                            .frame(height: 13)
                    }
                    .foregroundStyle(value == half ? Ember.amber : Ember.muted)
                    .frame(width: 68)
                    .padding(.vertical, 9)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.title)
                .accessibilityAddTraits(value == half ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(5)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Rules page: hero, list grouped by next opening, and the setup guide (until finished).
private struct RulesPage: View {
    @Environment(AppModel.self) private var model
    let onChooseApps: () -> Void

    private var hasUsageNumbers: Bool { UsageReader.hasDataAccess(model.authorization) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let config = model.state.config
            let guide = HalfGuide.rules(
                config: config,
                hasUsageNumbers: hasUsageNumbers,
                finished: model.finishedGuides.contains(.rules)
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if guide.isRunning {
                        GuideCard(guide: guide) { button(at: guide.live, config: config) }
                            .padding(.bottom, 6)
                    }
                    LinkTraffic(half: .rules)
                        .padding(.bottom, 6)
                    HomeContent(now: model.clock.honest(context.date), showsEmptyHero: !guide.isRunning)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
        }
    }

    @ViewBuilder
    private func button(at live: Int?, config: Config) -> some View {
        switch live {
        case 0:
            // With usage data, guide to the fortnight view; otherwise to the app picker.
            if hasUsageNumbers {
                NavigationLink { UsageView() } label: {
                    GuideButtonLabel(title: "See where the time went", systemImage: "chart.bar.fill")
                }
                .guideButton()
            } else {
                GuideButton(title: "Choose apps", systemImage: "plus") { onChooseApps() }
            }
        case 1:
            if let next = config.targets.first(where: { $0.rule == nil }) {
                NavigationLink(value: next.id) {
                    GuideButtonLabel(title: "Write the rule", systemImage: "hourglass")
                }
                .guideButton()
            }
        case 2:
            GuideButton(title: "Done") { model.finishGuide(.rules) }
        default:
            EmptyView()
        }
    }
}

/// Everything below the toolbar on the Rules page: the hero and the list grouped by next opening.
struct HomeContent: View {
    @Environment(AppModel.self) private var model
    let now: Date
    /// False while the guide runs, to avoid duplicating its "tap +" instruction.
    var showsEmptyHero = true
    /// The hero page being shown; survives the minute ticks that rebuild this view.
    @State private var featured: UUID?

    var body: some View {
        let state = model.state
        let config = Policy.effectiveConfig(state, now: now)
        let statuses = Dictionary(uniqueKeysWithValues: config.targets.map { target in
            (target.id, Policy.status(of: target, config: config, runtime: state.runtime, now: now))
        })
        let glasses = Dictionary(uniqueKeysWithValues: config.targets.map { target in
            (target.id, HourglassState.of(target, status: statuses[target.id] ?? .unconfigured, runtime: state.runtime, now: now))
        })
        let groups = HomeGroups(targets: config.targets, statuses: statuses, now: now)

        VStack(alignment: .leading, spacing: 0) {
            HeroPager(groups: groups, statuses: statuses, glasses: glasses, runtime: state.runtime, anchor: config.anchor, showsEmptyHero: showsEmptyHero, featured: $featured)
            ForEach(groups.sections) { section in
                SectionLabel(text: section.title)
                VStack(spacing: 0) {
                    ForEach(Array(section.targets.enumerated()), id: \.element.id) { index, target in
                        if index > 0 { CardDivider() }
                        NavigationLink(value: target.id) {
                            TargetRow(
                                target: target,
                                status: statuses[target.id] ?? .unconfigured,
                                glass: glasses[target.id] ?? .unconfigured,
                                pending: state.pending.first { $0.targetID == target.id },
                                held: config.anchor.willHold(target),
                                now: now
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .emberCard()
            }
        }
    }
}

/// Section order: Anchored (when armed) · Open now · Later today · Tomorrow · Later this week ·
/// Always blocked · Needs a schedule.
struct HomeGroups {
    struct Section: Identifiable {
        let title: String
        let targets: [Target]
        var id: String { title }
    }

    var anchored: [Target] = []
    var open: [(target: Target, until: Date, untilMinute: Int)] = []
    var laterToday: [(target: Target, at: Date)] = []
    var tomorrow: [(target: Target, at: Date?)] = []
    /// Two or more days out: targets whose windows skip tomorrow.
    var laterThisWeek: [(target: Target, at: Date)] = []
    var alwaysBlocked: [Target] = []
    var unconfigured: [Target] = []

    init(targets: [Target], statuses: [UUID: TargetStatus], now: Date) {
        for target in targets {
            switch statuses[target.id] ?? .unconfigured {
            case .anchored:
                anchored.append(target)
            case .open(let until):
                open.append((target, Policy.date(atMinute: until, of: now), until))
            case .closed(let next):
                let at = Policy.date(at: next, from: now)
                switch next.daysAhead {
                case 0: laterToday.append((target, at))
                case 1: tomorrow.append((target, at))
                default: laterThisWeek.append((target, at))
                }
            case .exhausted(let next):
                if let next, next.daysAhead >= 2 {
                    laterThisWeek.append((target, Policy.date(at: next, from: now)))
                } else {
                    tomorrow.append((target, next.map { Policy.date(at: $0, from: now) }))
                }
            case .blockedAllDay:
                alwaysBlocked.append(target)
            case .unconfigured:
                unconfigured.append(target)
            }
        }
        open.sort { $0.until < $1.until }
        laterToday.sort { $0.at < $1.at }
        tomorrow.sort { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
        laterThisWeek.sort { $0.at < $1.at }
    }

    var isEmpty: Bool {
        anchored.isEmpty && open.isEmpty && laterToday.isEmpty && tomorrow.isEmpty && laterThisWeek.isEmpty
            && alwaysBlocked.isEmpty && unconfigured.isEmpty
    }

    var sections: [Section] {
        [
            Section(title: "Anchored", targets: anchored),
            Section(title: "Open now", targets: open.map(\.target)),
            Section(title: "Later today", targets: laterToday.map(\.target)),
            Section(title: "Tomorrow", targets: tomorrow.map(\.target)),
            Section(title: "Later this week", targets: laterThisWeek.map(\.target)),
            Section(title: "Always blocked", targets: alwaysBlocked),
            Section(title: "Needs a schedule", targets: unconfigured),
        ].filter { !$0.targets.isEmpty }
    }

    var ordered: [Target] { sections.flatMap(\.targets) }
}

/// H1 in design/HOURGLASS.md: one page per managed app, swiped horizontally; the page
/// indicator is a strip of status hourglasses. Lands on the first open app.
struct HeroPager: View {
    let groups: HomeGroups
    let statuses: [UUID: TargetStatus]
    let glasses: [UUID: HourglassState]
    let runtime: RuntimeState
    let anchor: AnchorProfile
    var showsEmptyHero = true
    @Binding var featured: UUID?

    private var pages: [Target] { groups.ordered }
    private var landing: UUID? { groups.open.first?.target.id ?? pages.first?.id }

    /// One entry per scroll position: the real pages, plus (when there's more than one) a
    /// trailing duplicate of the first page so swiping right past the last one lands on
    /// something — its id is snapped back to the real first page immediately after.
    private struct LoopPage: Identifiable {
        let id: UUID
        let target: Target
    }

    private var loopPages: [LoopPage] {
        let real = pages.map { LoopPage(id: $0.id, target: $0) }
        guard pages.count > 1, let first = pages.first else { return real }
        return real + [LoopPage(id: Self.loopSentinelID(for: first.id), target: first)]
    }

    /// A stable id, distinct from any real target id, for the trailing loop duplicate of `id`.
    private static func loopSentinelID(for id: UUID) -> UUID {
        var bytes = id.uuid
        bytes.0 ^= 0xFF
        return UUID(uuid: bytes)
    }

    var body: some View {
        if pages.isEmpty {
            if showsEmptyHero { EmptyHero() }
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(loopPages) { page in
                            NavigationLink(value: page.target.id) {
                                HeroPage(target: page.target, status: statuses[page.target.id] ?? .unconfigured, runtime: runtime, anchor: anchor)
                                    .padding(.horizontal, 22)
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $featured)
                .scrollIndicators(.hidden)
                // scrollClipDisabled + a looser clip shape: the default clip cut off the glow's
                // halo at the page edge. Left/right edges are kept to avoid bleed from neighbors.
                .scrollClipDisabled()
                .clipShape(SpillingRect(spill: HeroPage.glowSpill))
                .padding(.horizontal, -16)
                HeroIndicator(pages: pages, glasses: glasses, featured: $featured)
            }
            .onAppear {
                if !pages.contains(where: { $0.id == featured }) { featured = landing }
            }
            .onChange(of: pages.map(\.id)) { _, ids in
                if let current = featured, !ids.contains(current) { featured = landing }
            }
            .onChange(of: featured) { _, new in
                guard let new, let first = pages.first, pages.count > 1,
                      new == Self.loopSentinelID(for: first.id) else { return }
                // Landed on the trailing loop duplicate: snap to the real first page without
                // animation so the wrap reads as continuous instead of a visible rewind.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { featured = first.id }
            }
        }
    }
}

/// Shape receives its view's frame, so growing rect vertically only re-clips that axis.
private struct SpillingRect: Shape {
    let spill: CGFloat

    func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: 0, dy: -spill)) }
}

/// One page: the living hourglass, eyebrow, name, the big line and a sub line for one
/// target's status. Ticks once a second so the sand and countdown share a clock.
struct HeroPage: View {
    @Environment(AppModel.self) private var model
    let target: Target
    let status: TargetStatus
    let runtime: RuntimeState
    let anchor: AnchorProfile

    /// A blur of `glowRadius` fades out by ~3x that distance, so the pager's clip is opened
    /// this far to avoid cutting off the halo.
    static let glowSpill: CGFloat = 3 * glowRadius
    private static let glowRadius: CGFloat = 20

    private struct Line {
        enum Big {
            case countdown(to: Date)
            case countUp(from: Date)
            case quiet(String)
        }

        var eyebrow: String
        var color: Color
        var big: Big
        var sub: String
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = model.clock.honest(context.date)
            let glass = HourglassState.of(target, status: status, runtime: runtime, now: now)
            let line = line(now: now)
            HStack(alignment: .center, spacing: 14) {
                LivingHourglass(state: glass)
                    .frame(width: 74, height: 98)
                    .compositingGroup()
                    .shadow(color: (glass.glow ?? .clear).opacity(0.4), radius: Self.glowRadius)
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: line.eyebrow, color: line.color)
                    name
                    big(line.big, now: now)
                    Text(line.sub)
                        .emberBody(11.5)
                        .foregroundStyle(Ember.muted)
                        .lineLimit(2)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
    }

    /// A nickname gets the display face; the system name can only be sized, not restyled.
    @ViewBuilder
    private var name: some View {
        if target.nickname.isEmpty {
            TokenName(kind: target.kind, size: .xxxLarge)
                .padding(.top, 4)
        } else {
            Text(target.nickname)
                .emberDisplay(24)
                .foregroundStyle(Ember.cream)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func big(_ big: Line.Big, now: Date) -> some View {
        switch big {
        case .countdown(let end):
            Text(TimeFormat.countdown(from: now, to: end))
                .emberNumerals(42)
                .padding(.top, 6)
        case .countUp(let start):
            Text(TimeFormat.countdown(from: start, to: now))
                .emberNumerals(42)
                .padding(.top, 6)
        case .quiet(let text):
            Text(text)
                .font(EmberFont.numerals(30))
                .tracking(-0.6)
                .foregroundStyle(Ember.muted)
                .padding(.top, 10)
        }
    }

    private func line(now: Date) -> Line {
        let budget = target.rule.map { TimeFormat.budget($0.budget(on: Policy.weekday(now))) } ?? ""
        switch status {
        case .open(let until):
            let end = Policy.date(atMinute: until, of: now)
            if runtime.wasWarned(target.id, dayKey: Policy.dayKey(now)) {
                return Line(
                    eyebrow: "Open now · \(Furlough.warningMinutes) min left", color: Ember.amber,
                    big: .countdown(to: end), sub: "\(budget) budget · under \(Furlough.warningMinutes) min left"
                )
            }
            if target.rule?.isAllDay ?? false {
                return Line(
                    eyebrow: "Open all day", color: Ember.moss,
                    big: .countdown(to: end), sub: "\(budget) budget · resets at midnight"
                )
            }
            return Line(
                eyebrow: "Open now · until \(TimeFormat.until(until))", color: Ember.moss,
                big: .countdown(to: end), sub: "\(budget) budget today"
            )
        case .closed(let next):
            return Line(
                eyebrow: "Next window", color: Ember.amber,
                big: .countdown(to: Policy.date(at: next, from: now)), sub: "opens \(TimeFormat.nextOpen(next)) · \(budget) a day"
            )
        case .exhausted(let next):
            if let next {
                return Line(
                    eyebrow: "Used up today", color: Ember.ember,
                    big: .countdown(to: Policy.date(at: next, from: now)), sub: "opens \(TimeFormat.nextOpen(next)) · \(budget) a day"
                )
            }
            return Line(eyebrow: "Used up today", color: Ember.ember, big: .quiet("spent"), sub: "\(budget) a day")
        case .anchored:
            let since = anchor.anchoredAt
            return Line(
                eyebrow: since.map { "Anchored · since \($0.formatted(date: .omitted, time: .shortened))" } ?? "Anchored",
                color: Ember.ember,
                big: since.map { .countUp(from: $0) } ?? .quiet("locked"),
                sub: "\(anchor.until.map { "Lifts \(TimeFormat.clock($0)), or sooner with your tag" } ?? "Unanchor with your tag") · \(RowCopy.detail(target: target, status: status, now: now))"
            )
        case .blockedAllDay:
            return Line(
                eyebrow: "Always blocked", color: Ember.muted, big: .quiet("all day"),
                sub: target.kind.isCategory ? "Everything in it is blocked." : "No budget · tap to set one"
            )
        case .unconfigured:
            return Line(
                eyebrow: "Needs a schedule", color: Ember.pending, big: .quiet("not enforced"),
                sub: "Tap to set windows and a budget"
            )
        }
    }
}

struct EmptyHero: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            LivingHourglass(state: .unconfigured)
                .frame(width: 74, height: 98)
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "Furlough", color: Ember.amber)
                Text("Nothing held yet")
                    .emberDisplay(24)
                    .foregroundStyle(Ember.cream)
                    .padding(.top, 4)
                Text("Tap + to give an app hours and a budget. The Anchor — one tap, one tag — is the page beside this one.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

struct TargetRow: View {
    let target: Target
    let status: TargetStatus
    let glass: HourglassState
    let pending: PendingChange?
    /// Whether the anchor also holds this target; shown as a mark, not a duplicate row.
    var held = false
    var now: Date = .now

    var body: some View {
        HStack(spacing: 10) {
            TokenTile(kind: target.kind, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                if target.nickname.isEmpty {
                    TokenName(kind: target.kind)
                } else {
                    Text(target.nickname)
                        .emberDisplaySmall(13.5)
                        .foregroundStyle(Ember.cream)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text(RowCopy.detail(target: target, status: status, now: now))
                        .emberBody(11.5)
                        .foregroundStyle(Ember.muted)
                        .lineLimit(1)
                    if held { HeldMark() }
                    // Shown as a mark on the existing row, not a second row, to avoid duplicating it.
                    if target.isLinked {
                        HStack(spacing: 2.5) {
                            Image(systemName: "globe")
                                .font(.system(size: 8.5, weight: .semibold))
                            if let host = target.hosts.first {
                                Text(target.hosts.count > 1 ? "\(host) +\(target.hosts.count - 1)" : host)
                                    .emberBody(10)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(Ember.faint)
                        .layoutPriority(-1)
                    }
                }
                if let pending {
                    Text(RowCopy.pendingLine(pending))
                        .emberBody(10.5, .semibold)
                        .foregroundStyle(Ember.pending)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            StatusChip(status: status, glass: glass, allDay: target.rule?.isAllDay ?? false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
