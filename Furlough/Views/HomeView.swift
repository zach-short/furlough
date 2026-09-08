import FamilyControls
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    /// The Application / Website popover under the + button.
    @State private var showAddChoice = false
    /// Which of the two the picker was opened for; it wears a matching header and footer.
    @State private var pickerFor: AddChoice = .application
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var pickerOutcome: AppModel.PickerOutcome?
    @State private var showSettings = false
    @State private var showPending = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                ScrollView {
                    HomeContent(now: context.date)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 48)
                }
            }
            .background(EmberWall())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                RuleEditorView(targetID: id)
            }
            .navigationDestination(for: AnchorRoute.self) { _ in
                AnchorView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape.fill") { showSettings = true }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { showAddChoice = true }
                        .tint(Ember.cream)
                        .popover(isPresented: $showAddChoice, arrowEdge: .top) {
                            AddChoicePopover(
                                applicationCaption: "Apps and categories, from Apple's picker",
                                websiteCaption: "Any site by its address, from the same picker"
                            ) { choice in
                                showAddChoice = false
                                openPicker(for: choice)
                            }
                            .presentationCompactAdaptation(.popover)
                        }
                }
            }
            .familyActivityPicker(
                headerText: pickerHeader,
                footerText: pickerFooter,
                isPresented: $showPicker,
                selection: $selection
            )
            .onChange(of: showPicker) { _, presented in
                guard !presented else { return }
                let outcome = model.applyPicker(selection)
                if outcome.added > 0 || outcome.removalsScheduled > 0 {
                    pickerOutcome = outcome
                }
            }
            .alert(
                "Selection updated",
                isPresented: Binding(get: { pickerOutcome != nil }, set: { if !$0 { pickerOutcome = nil } }),
                presenting: pickerOutcome
            ) { _ in
                Button("OK") { pickerOutcome = nil }
            } message: { outcome in
                Text(outcome.message)
            }
            .sheet(isPresented: $showPending) { PendingChangesView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    /// Apple's one picker holds apps, categories and websites alike; Website only changes what
    /// it says on the way in. Sites are inside each category, after its apps, as Add Website.
    private var pickerHeader: String {
        switch pickerFor {
        case .application: "Choose apps and categories"
        case .website: "Choose websites"
        }
    }

    private var pickerFooter: String {
        switch pickerFor {
        case .application: "Picking a category adds every app in it, each with its own rule."
        case .website: "Open a category, scroll past its apps to Websites and tap Add Website. Each site gets its own rule."
        }
    }

    /// Opens the picker once the popover has gone. A sheet presented while the popover is
    /// still on its way out is dropped, so this waits out the dismissal first.
    private func openPicker(for choice: AddChoice) {
        pickerFor = choice
        selection = model.pickerSelection
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            showPicker = true
        }
    }
}

/// Everything below the toolbar: the hero and the list grouped by next opening.
struct HomeContent: View {
    @Environment(AppModel.self) private var model
    let now: Date
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
            HeroPager(groups: groups, statuses: statuses, glasses: glasses, runtime: state.runtime, anchor: config.anchor, featured: $featured)
            AnchorCard(anchor: config.anchor)
                .padding(.top, 10)
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
    @Binding var featured: UUID?

    private var pages: [Target] { groups.ordered }
    private var landing: UUID? { groups.open.first?.target.id ?? pages.first?.id }

    var body: some View {
        if pages.isEmpty {
            EmptyHero()
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
            let now = context.date
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
        let budget = target.rule.map { TimeFormat.budget($0.dailyBudgetMinutes) } ?? ""
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
                eyebrow: "Open now · until \(TimeFormat.minute(until))", color: Ember.moss,
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
                sub: "Weigh anchor with your tag · \(RowCopy.detail(target: target, status: status, now: now))"
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

/// Tiny hourglasses in status colours, one per page. Tapping one turns to that page. Laid
/// out by `IndicatorStrip`, so however many apps are managed the strip stays inside the
/// screen instead of pushing the whole home page wider than the phone.
struct HeroIndicator: View {
    let pages: [Target]
    let glasses: [UUID: HourglassState]
    @Binding var featured: UUID?

    var body: some View {
        IndicatorStrip {
            ForEach(pages) { target in
                let current = target.id == featured
                HourglassView(state: glasses[target.id] ?? .unconfigured)
                    .scaleEffect(IndicatorStrip.glassScale * (current ? 1.35 : 1))
                    .opacity(current ? 1 : 0.5)
                    .contentShape(Rectangle())
                    .onTapGesture { featured = target.id }
            }
        }
        .animation(.snappy, value: featured)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }
}

/// Lays the indicator's glasses out in the width it is offered rather than the width they
/// would like: 11 pt glasses in 19 pt tap slots, 9 pt apart, centred. When the slots no
/// longer fit, the gaps close first, then the slots shrink together, so the strip is never
/// wider than the screen. (A plain `HStack` of fixed-size glasses reports its full width
/// whatever it is offered, and a vertical `ScrollView` then grows to match and clips both
/// edges of every row below.)
struct IndicatorStrip: Layout {
    /// A slot at full size: the 11 × 15 glass with a 4 pt tap margin around it.
    static let slot = CGSize(width: 19, height: 23)
    static let gap: CGFloat = 9
    /// Each glass is drawn at its slot's size and scaled down to 11 × 15 inside it, so the
    /// tap margin shrinks with the slot instead of eating the glass.
    static let glassScale: CGFloat = 15 / slot.height

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let fit = Self.fit(count: subviews.count, in: available)
        return CGSize(width: available ?? fit.width, height: fit.slot.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fit = Self.fit(count: subviews.count, in: bounds.width)
        var x = bounds.midX - fit.width / 2
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(fit.slot))
            x += fit.slot.width + fit.gap
        }
    }

    /// The slot size, gap and total width for `count` glasses in `width` (nil: unconstrained).
    static func fit(count: Int, in width: CGFloat?) -> (slot: CGSize, gap: CGFloat, width: CGFloat) {
        let gaps = CGFloat(max(count - 1, 0))
        let ideal = CGFloat(count) * slot.width + gaps * gap
        guard let width, width < ideal, count > 0 else { return (slot, gap, ideal) }
        let tight = CGFloat(count) * slot.width
        if tight <= width {
            return (slot, gaps > 0 ? (width - tight) / gaps : 0, width)
        }
        let scale = width / tight
        return (CGSize(width: slot.width * scale, height: slot.height * scale), 0, width)
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
                Text("Nothing managed yet")
                    .emberDisplay(24)
                    .foregroundStyle(Ember.cream)
                    .padding(.top, 4)
                Text("Tap + to choose apps and websites.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TokenName(kind: target.kind)
                    if !target.nickname.isEmpty {
                        Text(target.nickname)
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                            .lineLimit(1)
                    }
                }
                Text(RowCopy.detail(target: target, status: status, now: now))
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .lineLimit(1)
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
