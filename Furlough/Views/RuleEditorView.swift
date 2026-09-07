import SwiftUI

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targetID: UUID

    @State private var nickname = ""
    @State private var drafts: [DraftWindow] = []
    @State private var budget = Furlough.defaultBudgetMinutes
    @State private var loaded = false
    @State private var result: ProposalResult?
    @State private var confirmRemove = false
    @FocusState private var nicknameFocused: Bool

    /// A window with a stable identity while it is being edited.
    struct DraftWindow: Identifiable {
        let id = UUID()
        var window: TimeWindow
    }

    private var target: Target? { model.state.config.target(id: targetID) }
    private var windows: [TimeWindow] { drafts.map(\.window) }
    private var draft: Rule { Rule(windows: windows, dailyBudgetMinutes: budget) }
    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        guard let target else { return false }
        return target.rule != draft || target.nickname != trimmedNickname
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let target {
                    header(target)
                    nicknameCard
                    if !target.kind.isCategory {
                        SectionLabel(text: "Allowed windows")
                        windowsCard
                        SectionLabel(text: "Daily budget")
                        budgetCard
                        EffectBanner(kind: effect(for: target))
                            .padding(.top, 14)
                        ProminentButton(title: "Save") { save() }
                            .disabled(!hasChanges || draft.validationError != nil)
                            .padding(.top, 10)
                    } else {
                        Footnote(text: "Categories are always blocked. Apps inside them that you give windows to are excepted.")
                            .padding(.top, 10)
                        ProminentButton(title: "Save nickname") { save() }
                            .disabled(!hasChanges)
                            .padding(.top, 14)
                    }
                    GhostButton(title: "Remove from Furlough") { confirmRemove = true }
                        .padding(.top, 4)
                    Footnote(text: removalNote(target), alignment: .center)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(Ember.moss)
                        Text("Removed")
                            .emberDisplay(24)
                            .foregroundStyle(Ember.cream)
                        Text("This item is no longer managed.")
                            .emberBody(13)
                            .foregroundStyle(Ember.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .background(EmberWall())
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Rule")
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
        }
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

    // MARK: Sections

    private func header(_ target: Target) -> some View {
        HStack(spacing: 12) {
            TokenTile(kind: target.kind, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                TokenName(kind: target.kind)
                    .emberDisplay(19)
                    .foregroundStyle(Ember.cream)
                Text("Nickname shows on the shield and widget.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var nicknameCard: some View {
        HStack(spacing: 8) {
            Text("Nickname")
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            TextField("Optional", text: $nickname)
                .emberBody(13, .medium)
                .foregroundStyle(Ember.cream)
                .multilineTextAlignment(.trailing)
                .focused($nicknameFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { nicknameFocused = true }
        .emberCard()
    }

    private var windowsCard: some View {
        VStack(spacing: 0) {
            ForEach($drafts) { $draft in
                WindowRow(window: $draft.window) {
                    drafts.removeAll { $0.id == draft.id }
                }
                CardDivider()
            }
            Button { addWindow() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add window")
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
        .emberCard()
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(budget)")
                        .emberNumerals(30)
                        .contentTransition(.numericText())
                    Text("MIN")
                        .font(EmberFont.label(10.5))
                        .tracking(0.06 * 10.5)
                        .foregroundStyle(Ember.muted)
                }
                Spacer()
                Text("across all windows")
                    .emberBody(11)
                    .foregroundStyle(Ember.muted)
            }
            BudgetSlider(value: $budget)
                .padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .emberCard()
    }

    private func effect(for target: Target) -> EffectBanner.Kind {
        if let error = draft.validationError { return .error(error) }
        if !draft.isEverAllowed { return .blockedAllDay }
        if !hasChanges { return .noChanges }
        if target.rule == draft { return .nicknameOnly }
        if Policy.classify(newRule: draft, against: target) == .tightening { return .tightening }
        return .loosening(Date.now.addingTimeInterval(model.state.config.loosenDelay))
    }

    private func removalNote(_ target: Target) -> String {
        target.rule == nil
            ? "Nothing is enforced yet, so removal is immediate."
            : "Removing loosens your rules, so it takes \(TimeFormat.delay(hours: model.state.config.loosenDelayHours))."
    }

    // MARK: Actions

    private func load() {
        guard !loaded, let target else { return }
        loaded = true
        nickname = target.nickname
        let pendingRule = model.state.pending.compactMap { change -> Rule? in
            if case .setRule(let id, let rule) = change.kind, id == targetID { return rule }
            return nil
        }.first
        let rule = pendingRule ?? target.rule ?? Rule()
        var windows = rule.sortedWindows
        budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
        if windows.isEmpty, target.rule == nil {
            windows = [TimeWindow(startMinute: 20 * 60, endMinute: 22 * 60)]
        }
        drafts = windows.map { DraftWindow(window: $0) }
    }

    private func addWindow() {
        let start = windows.map(\.endMinute).max() ?? 12 * 60
        let clampedStart = min(start, Furlough.minutesPerDay - 60)
        let window = TimeWindow(startMinute: clampedStart, endMinute: min(clampedStart + 60, Furlough.minutesPerDay))
        withAnimation(.snappy) { drafts.append(DraftWindow(window: window)) }
    }

    private func save() {
        nicknameFocused = false
        result = model.propose(rule: draft, nickname: nickname, for: targetID)
    }
}

/// One allowed window: two glass time chips, an arrow, the duration, and a quiet remove button.
struct WindowRow: View {
    @Binding var window: TimeWindow
    let onRemove: () -> Void
    @State private var editing: WindowEdge?

    enum WindowEdge: String, Identifiable {
        case start, end
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 8) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    TimeChip(minute: window.startMinute) { editing = .start }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ember.muted)
                    TimeChip(minute: window.endMinute) { editing = .end }
                }
            }
            Spacer(minLength: 4)
            Text(durationText(window.durationMinutes))
                .emberBody(11.5)
                .monospacedDigit()
                .foregroundStyle(window.isValid ? Ember.muted : Ember.ember)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ember.faint)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(item: $editing) { edge in
            TimePickerSheet(
                title: edge == .start ? "Opens at" : "Closes at",
                minute: edge == .start ? $window.startMinute : $window.endMinute,
                allowsMidnight: edge == .end
            )
        }
    }

    private func durationText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0 min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// A glass chip showing a time of day.
struct TimeChip: View {
    let minute: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(TimeFormat.minute(minute))
                .emberBody(13, .semibold)
                .monospacedDigit()
                .foregroundStyle(Ember.cream)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
    }
}

/// A short sheet with a wheel picker on the wall.
struct TimePickerSheet: View {
    let title: String
    @Binding var minute: Int
    var allowsMidnight = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            Eyebrow(text: title, color: Ember.amber)
                .padding(.top, 22)
            Text(TimeFormat.minute(minute))
                .emberNumerals(30)
                .contentTransition(.numericText())
            DatePicker("Time", selection: dateBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            ProminentButton(title: "Done") { dismiss() }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .presentationBackground { EmberWall() }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Policy.date(atMinute: min(minute, Furlough.minutesPerDay - 1), of: .now) },
            set: { date in
                let picked = Policy.minuteOfDay(date)
                minute = (allowsMidnight && picked == Furlough.minutesPerDay - 1) ? Furlough.minutesPerDay : picked
            }
        )
    }
}

/// The tinted line above Save that says what the edit will do.
struct EffectBanner: View {
    enum Kind {
        case error(String)
        case blockedAllDay
        case noChanges
        case nicknameOnly
        case tightening
        case loosening(Date)
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .emberBody(12, .semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
    }

    private var symbol: String {
        switch kind {
        case .error: "exclamationmark.triangle.fill"
        case .blockedAllDay: "lock.fill"
        case .noChanges, .nicknameOnly: "checkmark"
        case .tightening: "bolt.fill"
        case .loosening: "clock"
        }
    }

    private var text: String {
        switch kind {
        case .error(let message): message
        case .blockedAllDay: "No windows · blocked all day, applies immediately"
        case .noChanges: "No changes"
        case .nicknameOnly: "Nickname only · applies immediately"
        case .tightening: "Tighter than now · applies immediately"
        case .loosening(let when): "Looser than now · takes effect \(when.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private var color: Color {
        switch kind {
        case .error: Ember.ember
        case .blockedAllDay, .nicknameOnly: Ember.muted
        case .noChanges: Ember.faint
        case .tightening: Ember.moss
        case .loosening: Ember.pending
        }
    }
}
