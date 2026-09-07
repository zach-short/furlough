import SwiftUI

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targetID: UUID

    @State private var nickname = ""
    @State private var windows: [TimeWindow] = []
    @State private var budget = Furlough.defaultBudgetMinutes
    @State private var loaded = false
    @State private var result: ProposalResult?
    @State private var confirmRemove = false

    private var target: Target? { model.state.config.target(id: targetID) }
    private var draft: Rule { Rule(windows: windows, dailyBudgetMinutes: budget) }
    private var hasChanges: Bool {
        guard let target else { return false }
        return target.rule != draft || target.nickname != nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            if let target {
                Section {
                    TokenLabel(kind: target.kind)
                    TextField("Nickname", text: $nickname)
                } footer: {
                    Text("Apple hides real app names from Furlough outside this screen. A nickname shows on the shield, the widget, and notifications.")
                }

                if !target.kind.isCategory {
                    Section {
                        ForEach($windows) { $window in
                            WindowRow(window: $window)
                        }
                        .onDelete { windows.remove(atOffsets: $0) }
                        Button("Add window", systemImage: "plus") { addWindow() }
                    } header: {
                        Text("Allowed windows")
                    } footer: {
                        Text("Same every day. Outside these times the app is shielded. Each window needs at least \(Furlough.minimumWindowMinutes) minutes.")
                    }

                    Section {
                        Stepper(value: $budget, in: 5...240, step: 5) {
                            Text("\(TimeFormat.budget(budget)) per day")
                        }
                    } header: {
                        Text("Daily budget")
                    } footer: {
                        Text("Total minutes across all windows. When it runs out, the app is shielded until tomorrow.")
                    }

                    Section {
                        effectRow(for: target)
                        Button("Save") { save() }
                            .disabled(!hasChanges || draft.validationError != nil)
                    }
                } else {
                    Section {
                        Button("Save nickname") { save() }
                            .disabled(!hasChanges)
                    } footer: {
                        Text("Categories are always blocked. Apps inside them that you give windows to are excepted.")
                    }
                }

                Section {
                    Button("Remove from Furlough", role: .destructive) { confirmRemove = true }
                } footer: {
                    Text(target.rule == nil
                         ? "Nothing is enforced yet, so removal is immediate."
                         : "Removal loosens your rules, so it takes \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)) to apply.")
                }
            } else {
                ContentUnavailableView("Removed", systemImage: "checkmark", description: Text("This item is no longer managed."))
            }
        }
        .navigationTitle(target?.displayName ?? "Rule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .confirmationDialog("Remove from Furlough?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                result = model.removeTarget(id: targetID)
            }
        }
        .alert("Saved", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }), presenting: result) { _ in
            Button("OK") {
                result = nil
                dismiss()
            }
        } message: { result in
            Text(result.message)
        }
    }

    @ViewBuilder
    private func effectRow(for target: Target) -> some View {
        if let error = draft.validationError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        } else if !draft.isEverAllowed {
            Label("No windows: blocked all day. Applies immediately.", systemImage: "lock").foregroundStyle(.secondary)
        } else if !hasChanges {
            Label("No changes.", systemImage: "checkmark").foregroundStyle(.secondary)
        } else if target.rule == draft {
            Label("Nickname only. Applies immediately.", systemImage: "checkmark").foregroundStyle(.secondary)
        } else if Policy.classify(newRule: draft, against: target) == .tightening {
            Label("Tighter than now. Applies immediately.", systemImage: "bolt").foregroundStyle(.green)
        } else {
            let when = Date.now.addingTimeInterval(model.state.config.loosenDelay)
            Label("Looser than now. Takes effect \(when.formatted(date: .abbreviated, time: .shortened)).", systemImage: "clock")
                .foregroundStyle(.orange)
        }
    }

    private func load() {
        guard !loaded, let target else { return }
        loaded = true
        nickname = target.nickname
        let pendingRule = model.state.pending.compactMap { change -> Rule? in
            if case .setRule(let id, let rule) = change.kind, id == targetID { return rule }
            return nil
        }.first
        let rule = pendingRule ?? target.rule ?? Rule()
        windows = rule.sortedWindows
        budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
        if windows.isEmpty, target.rule == nil {
            windows = [TimeWindow(startMinute: 20 * 60, endMinute: 22 * 60)]
        }
    }

    private func addWindow() {
        let start = (windows.map(\.endMinute).max() ?? 12 * 60)
        let clampedStart = min(start, Furlough.minutesPerDay - 60)
        windows.append(TimeWindow(startMinute: clampedStart, endMinute: min(clampedStart + 60, Furlough.minutesPerDay)))
    }

    private func save() {
        result = model.propose(rule: draft, nickname: nickname, for: targetID)
    }
}

struct WindowRow: View {
    @Binding var window: TimeWindow

    var body: some View {
        HStack {
            DatePicker("From", selection: binding(\.startMinute), displayedComponents: .hourAndMinute)
                .labelsHidden()
            Text("to").foregroundStyle(.secondary)
            DatePicker("To", selection: binding(\.endMinute), displayedComponents: .hourAndMinute)
                .labelsHidden()
            Spacer()
            Text("\(window.durationMinutes) min")
                .font(.caption)
                .foregroundStyle(window.isValid ? Color.secondary : Color.red)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<TimeWindow, Int>) -> Binding<Date> {
        Binding(
            get: { Policy.date(atMinute: min(window[keyPath: keyPath], Furlough.minutesPerDay - 1), of: .now) },
            set: { date in
                let minute = Policy.minuteOfDay(date)
                let isEnd = keyPath == \TimeWindow.endMinute
                window[keyPath: keyPath] = (isEnd && minute == Furlough.minutesPerDay - 1) ? Furlough.minutesPerDay : minute
            }
        )
    }
}
