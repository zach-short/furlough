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
                TargetListView(now: context.date)
            }
            .navigationTitle("Furlough")
            .navigationDestination(for: UUID.self) { id in
                RuleEditorView(targetID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !model.state.pending.isEmpty {
                        Button("\(model.state.pending.count) pending", systemImage: "clock.arrow.circlepath") {
                            showPending = true
                        }
                        .tint(.orange)
                    }
                    Button("Add", systemImage: "plus") {
                        selection = model.pickerSelection
                        showPicker = true
                    }
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

struct TargetListView: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let state = model.state
        let config = Policy.effectiveConfig(state, now: now)
        let statuses = Dictionary(uniqueKeysWithValues: config.targets.map { target in
            (target.id, Policy.status(of: target, runtime: state.runtime, now: now))
        })
        let open = config.targets.filter { if case .open = statuses[$0.id] { true } else { false } }
        let unconfigured = config.targets.filter { statuses[$0.id] == .unconfigured }
        let categories = config.targets.filter(\.kind.isCategory)
        let blocked = config.targets.filter { target in
            !target.kind.isCategory && !open.contains(target) && !unconfigured.contains(target)
        }

        List {
            section("Open now", open, statuses)
            section("Set a schedule", unconfigured, statuses)
            section("Blocked", blocked, statuses)
            section("Categories · always blocked", categories, statuses)
        }
        .overlay {
            if config.targets.isEmpty {
                ContentUnavailableView(
                    "Nothing managed yet",
                    systemImage: "hourglass",
                    description: Text("Tap + to choose apps and websites.")
                )
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ targets: [Target], _ statuses: [UUID: TargetStatus]) -> some View {
        if !targets.isEmpty {
            Section(title) {
                ForEach(targets) { target in
                    NavigationLink(value: target.id) {
                        TargetRow(
                            target: target,
                            status: statuses[target.id] ?? .unconfigured,
                            pending: model.state.pending.first { $0.targetID == target.id }
                        )
                    }
                }
            }
        }
    }
}

struct TargetRow: View {
    let target: Target
    let status: TargetStatus
    let pending: PendingChange?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TokenLabel(kind: target.kind)
                if !target.nickname.isEmpty {
                    Text("· \(target.nickname)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !target.kind.isCategory {
                Text(TimeFormat.rule(target.rule))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(TimeFormat.status(status), systemImage: statusSymbol)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            if let pending {
                Text("Change pending · \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusSymbol: String {
        switch status {
        case .open: "lock.open"
        case .unconfigured: "exclamationmark.triangle"
        case .exhausted: "hourglass.bottomhalf.filled"
        case .closed, .blockedAllDay: "lock"
        }
    }

    private var statusColor: Color {
        switch status {
        case .open: .green
        case .unconfigured: .orange
        default: .secondary
        }
    }
}

/// Renders the system icon and name for an opaque Screen Time token.
struct TokenLabel: View {
    let kind: TargetKind

    var body: some View {
        switch kind {
        case .application(let token): Label(token)
        case .webDomain(let token): Label(token)
        case .category(let token): Label(token)
        }
    }
}
