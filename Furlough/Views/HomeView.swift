import SwiftUI

/// Home: the two halves as two pages under one toolbar.
///
/// Rules and the Anchor are co-equal, and this screen used to say otherwise. The hero, the list
/// and the + were Rules', and the Anchor was a card in the middle of them that pushed a screen
/// away — a feature of the app rather than half of it. Now the segment in the title's place
/// switches between two pages, a swipe does the same, and the toolbar is about whichever page
/// is under it. Which one it opens on is the intro's question, answered on the start pane and
/// kept in `AppModel.startHalf`.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    /// Which half is on screen. Seeded from the intro's answer and this view's own after that,
    /// so a swipe holds for the rest of the run rather than snapping back on every rebuild.
    @State private var half: Half
    /// The Application / Website popover under the + button.
    @State private var showAddChoice = false
    /// What the popover asked for; `addTargetsFlow` takes it from here to Apple's picker.
    @State private var addRequest: AddRequest?
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showPending = false

    init(start: Half) { _half = State(initialValue: start) }

    var body: some View {
        NavigationStack {
            // A pager rather than a switch, so the two halves can be swiped between as well as
            // tapped. Selection is the same `half` the segment reads, so the two ways of moving
            // cannot disagree.
            TabView(selection: $half) {
                // The guide's first step opens the same picker the + does, so it hands the
                // request up rather than growing a second add flow of its own.
                RulesPage(onChooseApps: { addRequest = .plain(.application) })
                    .tag(Half.rules)
                // The Anchor arms an NFC reader on sight, and a pager builds the page beside the
                // one you are looking at. So it is told whether it is the page in front, and
                // only the page in front listens.
                AnchorPage(isCurrent: half == .anchor)
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
                ToolbarItem(placement: .principal) {
                    HalfSegment(half: $half)
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
                // The + acts on the page it is over. The Anchor page chooses what it holds from
                // its own row, so until that + has an anchor destination of its own it is not
                // drawn over a page it cannot add to.
                if half == .rules {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add", systemImage: "plus") { showAddChoice = true }
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
            }
            .addTargetsFlow($addRequest)
            .sheet(isPresented: $showPending) { PendingChangesView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showHelp) { HelpView() }
        }
    }
}

/// Rules · Anchor, in the title's place: the one control that says the app is two things and
/// neither of them is the main one. Glass, because it sits in the toolbar with the buttons.
struct HalfSegment: View {
    @Binding var half: Half

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Half.allCases, id: \.self) { value in
                Button {
                    guard value != half else { return }
                    // withAnimation, because a page-style TabView slides for a gesture but jumps
                    // for a plain assignment, and the two ways across should be one movement.
                    withAnimation(.snappy(duration: 0.3)) { half = value }
                } label: {
                    Text(value.title)
                        .emberBody(12.5, .bold)
                        .foregroundStyle(value == half ? Ember.cream : Ember.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(value == half ? Color.white.opacity(0.14) : .clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.title)
                .accessibilityAddTraits(value == half ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }
}

/// The everyday half: the hero, and the list grouped by next opening — with the three-step
/// guide above them until this half is set up.
///
/// The guide sits over the page rather than replacing it, because its own last step is about
/// the list: by the time "Read your list" is live there is a list to read, and hiding it to
/// show a card telling you to read it would be the joke this pass is trying not to make. On an
/// empty page there is nothing underneath anyway — `EmptyHero` stands down while the guide
/// runs, since the guide is the better version of the same sentence.
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
            // Where Furlough can read the fortnight, the shortest way to a first rule is the
            // fortnight. Where it cannot, the picker is the step and the tour stays in Settings.
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

/// Everything below the toolbar on the Rules page: the hero and the list grouped by next
/// opening. The Anchor's card used to sit between the two; it is the page beside this one now.
struct HomeContent: View {
    @Environment(AppModel.self) private var model
    let now: Date
    /// False while the guide is running: an empty hero saying "tap +" under a checklist whose
    /// live step is a Choose apps button would be the same instruction twice, in the weaker
    /// words.
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

/// The list order from the spec: Open now · Later today · Tomorrow · Later this week · Always blocked ·
/// Needs a schedule, with Anchored first whenever the anchor is on.
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

    /// Every target in the list's order: one hero page each.
    var ordered: [Target] { sections.flatMap(\.targets) }
}

/// The header (H1 in design/HOURGLASS.md): one page per managed app in the list's order,
/// swiped horizontally, with a strip of tiny status hourglasses as the page indicator, so
/// the strip itself is a status summary. Lands on the first open app. Tapping a page opens
/// its rule editor.
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

    var body: some View {
        if pages.isEmpty {
            if showsEmptyHero { EmptyHero() }
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages) { target in
                            NavigationLink(value: target.id) {
                                HeroPage(target: target, status: statuses[target.id] ?? .unconfigured, runtime: runtime, anchor: anchor)
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
                .padding(.horizontal, -16)
                HeroIndicator(pages: pages, glasses: glasses, featured: $featured)
            }
            .onAppear {
                if !pages.contains(where: { $0.id == featured }) { featured = landing }
            }
            .onChange(of: pages.map(\.id)) { _, ids in
                if let current = featured, !ids.contains(current) { featured = landing }
            }
        }
    }
}

/// One page: the living hourglass, eyebrow, name, the big line and a sub line for one
/// target's status. Ticks once a second so the sand and the countdown share a clock.
struct HeroPage: View {
    @Environment(AppModel.self) private var model
    let target: Target
    let status: TargetStatus
    let runtime: RuntimeState
    let anchor: AnchorProfile

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
                    .shadow(color: (glass.glow ?? .clear).opacity(0.4), radius: 20)
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

/// The hero before anything is managed: an empty glass and the one thing to do.
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
                // Both ways in, because there are two and only one of them used to be offered.
                // The Anchor is the page beside this one now, not a card under this hero, so
                // "below" would send someone looking at the list for it.
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
    var now: Date = .now

    var body: some View {
        HStack(spacing: 10) {
            TokenTile(kind: target.kind, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                // A nickname takes the name's place in the display face, as it does on the
                // hero; without one the system name can only be sized, not restyled.
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
                    // One row for one habit, and one small mark to say the row is two doors. A
                    // second row would be the bug this feature exists to remove.
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
