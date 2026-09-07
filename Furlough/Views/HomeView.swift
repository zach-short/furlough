import FamilyControls
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
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
                    Button("Add", systemImage: "plus") {
                        selection = model.pickerSelection
                        showPicker = true
                    }
                    .tint(Ember.cream)
                }
            }
            .familyActivityPicker(
                headerText: "Choose what Furlough manages",
                footerText: "Picking a category adds every app in it, each with its own rule.",
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
}

/// Everything below the toolbar: the hero and the list grouped by next opening.
struct HomeContent: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let state = model.state
        let config = Policy.effectiveConfig(state, now: now)
        let statuses = Dictionary(uniqueKeysWithValues: config.targets.map { target in
            (target.id, Policy.status(of: target, runtime: state.runtime, now: now))
        })
        let groups = HomeGroups(targets: config.targets, statuses: statuses, now: now)

        VStack(alignment: .leading, spacing: 0) {
            HeroView(groups: groups, now: now)
            ForEach(groups.sections) { section in
                SectionLabel(text: section.title)
                VStack(spacing: 0) {
                    ForEach(Array(section.targets.enumerated()), id: \.element.id) { index, target in
                        if index > 0 { CardDivider() }
                        NavigationLink(value: target.id) {
                            TargetRow(
                                target: target,
                                status: statuses[target.id] ?? .unconfigured,
                                pending: state.pending.first { $0.targetID == target.id }
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

/// The list order from the spec: Open now · Later today · Tomorrow · Always blocked · Needs a schedule.
struct HomeGroups {
    struct Section: Identifiable {
        let title: String
        let targets: [Target]
        var id: String { title }
    }

    var open: [(target: Target, until: Date, untilMinute: Int)] = []
    var laterToday: [(target: Target, at: Date)] = []
    var tomorrow: [(target: Target, at: Date?)] = []
    var alwaysBlocked: [Target] = []
    var unconfigured: [Target] = []

    init(targets: [Target], statuses: [UUID: TargetStatus], now: Date) {
        for target in targets {
            switch statuses[target.id] ?? .unconfigured {
            case .open(let until):
                open.append((target, Policy.date(atMinute: until, of: now), until))
            case .closed(let next):
                if next.isTomorrow {
                    tomorrow.append((target, Policy.date(at: next, from: now)))
                } else {
                    laterToday.append((target, Policy.date(at: next, from: now)))
                }
            case .exhausted(let next):
                tomorrow.append((target, next.map { Policy.date(at: $0, from: now) }))
            case .blockedAllDay:
                alwaysBlocked.append(target)
            case .unconfigured:
                unconfigured.append(target)
            }
        }
        open.sort { $0.until < $1.until }
        laterToday.sort { $0.at < $1.at }
        tomorrow.sort { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
    }

    var isEmpty: Bool {
        open.isEmpty && laterToday.isEmpty && tomorrow.isEmpty && alwaysBlocked.isEmpty && unconfigured.isEmpty
    }

    var sections: [Section] {
        [
            Section(title: "Open now", targets: open.map(\.target)),
            Section(title: "Later today", targets: laterToday.map(\.target)),
            Section(title: "Tomorrow", targets: tomorrow.map(\.target)),
            Section(title: "Always blocked", targets: alwaysBlocked),
            Section(title: "Needs a schedule", targets: unconfigured),
        ].filter { !$0.targets.isEmpty }
    }

    /// The target that opens soonest, with when.
    var nextOpening: (target: Target, at: Date)? {
        if let soon = laterToday.first { return soon }
        if let soon = tomorrow.first(where: { $0.at != nil }), let at = soon.at { return (soon.target, at) }
        return nil
    }
}

/// The top of the home screen: hourglass, eyebrow, name, ticking countdown, sub line.
struct HeroView: View {
    let groups: HomeGroups
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HourglassView(isOpen: !groups.open.isEmpty)
                .frame(width: 74, height: 98)
                .shadow(color: Ember.amber.opacity(0.45), radius: 22)
            VStack(alignment: .leading, spacing: 0) {
                if let first = groups.open.first {
                    Eyebrow(text: "Open now · until \(TimeFormat.minute(first.untilMinute))", color: Ember.moss)
                    name(for: first.target)
                    Countdown(to: first.until)
                    subline(budgetLine(first.target, "budget today") + (groups.open.count > 1 ? " · \(groups.open.count - 1) more open" : ""))
                } else if let next = groups.nextOpening {
                    Eyebrow(text: "Next window", color: Ember.amber)
                    name(for: next.target)
                    Countdown(to: next.at)
                    subline("opens \(TimeFormat.nextOpen(NextOpen(minuteOfDay: Policy.minuteOfDay(next.at), isTomorrow: !Calendar.current.isDate(next.at, inSameDayAs: now)))) · \(budgetLine(next.target, "a day"))")
                } else if groups.isEmpty {
                    Eyebrow(text: "Furlough", color: Ember.amber)
                    title("Nothing managed yet")
                    subline("Tap + to choose apps and websites.")
                } else if !groups.alwaysBlocked.isEmpty {
                    Eyebrow(text: "Always blocked", color: Ember.muted)
                    title(count(groups.alwaysBlocked.count, "item", "items") + " blocked")
                    subline("No windows today.")
                } else {
                    Eyebrow(text: "Needs a schedule", color: Ember.pending)
                    title(count(groups.unconfigured.count, "app", "apps") + " waiting")
                    subline("Nothing is enforced until you set a schedule.")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func name(for target: Target) -> some View {
        TokenName(kind: target.kind)
            .emberDisplay(24)
            .foregroundStyle(Ember.cream)
            .padding(.top, 4)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .emberDisplay(24)
            .foregroundStyle(Ember.cream)
            .padding(.top, 4)
    }

    private func subline(_ text: String) -> some View {
        Text(text)
            .emberBody(11.5)
            .foregroundStyle(Ember.muted)
            .padding(.top, 6)
    }

    private func budgetLine(_ target: Target, _ suffix: String) -> String {
        let budget = target.rule.map { TimeFormat.budget($0.dailyBudgetMinutes) } ?? ""
        return "\(budget) \(suffix)"
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }
}

/// Ticks once a second toward `end`.
struct Countdown: View {
    let to: Date

    init(to end: Date) { to = end }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(TimeFormat.countdown(from: context.date, to: to))
                .emberNumerals(42)
                .padding(.top, 6)
        }
    }
}

struct TargetRow: View {
    let target: Target
    let status: TargetStatus
    let pending: PendingChange?

    var body: some View {
        HStack(spacing: 10) {
            TokenTile(kind: target.kind, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TokenName(kind: target.kind)
                        .emberDisplaySmall(13.5)
                        .foregroundStyle(Ember.cream)
                    if !target.nickname.isEmpty {
                        Text(target.nickname)
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                            .lineLimit(1)
                    }
                }
                Text(RowCopy.detail(target: target, status: status))
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
            StatusChip(status: status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
