import SwiftUI

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targetID: UUID

    @State private var nickname = ""
    @State private var drafts: [DraftWindow] = []
    @State private var budget = Furlough.defaultBudgetMinutes
    @State private var loaded = false
    /// Whether each window shows its day strip. Off means every window applies every day.
    @State private var byDay = false
    @State private var showCopy = false
    @State private var showWeek = false
    @State private var result: ProposalResult?
    @State private var confirmRemove = false
    @FocusState private var nicknameFocused: Bool

    /// A window with a stable identity while it is being edited.
    struct DraftWindow: Identifiable {
        let id = UUID()
        var window: TimeWindow

        /// Rows on the same days that overlap or touch, joined into the earlier row, in order.
        static func joined(_ rows: [DraftWindow]) -> [DraftWindow] {
            var result: [DraftWindow] = []
            for row in rows.sorted(by: { $0.window < $1.window }) {
                if let index = result.lastIndex(where: { $0.window.days == row.window.days }),
                   row.window.startMinute <= result[index].window.endMinute {
                    result[index].window.endMinute = max(result[index].window.endMinute, row.window.endMinute)
                } else {
                    result.append(row)
                }
            }
            return result
        }
    }

    private var target: Target? { model.state.config.target(id: targetID) }
    private var windows: [TimeWindow] { drafts.map(\.window) }
    private var draft: Rule { Rule(windows: windows, dailyBudgetMinutes: budget) }
    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        guard let target else { return false }
        return target.rule != draft || target.nickname != trimmedNickname
    }

    /// Other apps and sites with windows worth copying.
    private var copyCandidates: [Target] {
        model.state.config.targets.filter {
            $0.id != targetID && !$0.kind.isCategory && ($0.rule?.isEverAllowed ?? false)
        }
    }

    /// The draft as a week for the visual editor. Writing back merges identical spans across
    /// days into one window and sets the Same every day toggle to match.
    private var weekDraft: Binding<WeekDraft> {
        Binding(
            get: { WeekDraft(windows: windows) },
            set: { week in
                let merged = week.windows
                drafts = merged.map { DraftWindow(window: $0) }
                byDay = !merged.allSatisfy { $0.days == .all }
            }
        )
    }

    private var sameEveryDay: Binding<Bool> {
        Binding(
            get: { !byDay },
            set: { on in
                withAnimation(.snappy) {
                    byDay = !on
                    if on {
                        for index in drafts.indices { drafts[index].window.days = .all }
                        drafts = DraftWindow.joined(drafts)
                    }
                }
            }
        )
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
        .sheet(isPresented: $showCopy) {
            CopyRuleSheet(candidates: copyCandidates) { source in
                if let rule = source.rule { adopt(rule) }
            }
        }
        .sheet(isPresented: $showWeek) {
            WeekSheet(week: weekDraft)
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
                TokenName(kind: target.kind, size: .xLarge)
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
            if drafts.isEmpty {
                Text("No windows. Open all day, up to the budget.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            } else {
                HStack(spacing: 12) {
                    Text("Same every day")
                        .emberBody(13)
                        .foregroundStyle(Ember.cream)
                    Spacer()
                    Toggle("Same every day", isOn: sameEveryDay)
                        .labelsHidden()
                        .tint(Ember.ember)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            CardDivider()
            ForEach($drafts) { $draft in
                WindowRow(
                    window: $draft.window,
                    showsDays: byDay,
                    onCommit: { withAnimation(.snappy) { drafts = DraftWindow.joined(drafts) } },
                    onRemove: { drafts.removeAll { $0.id == draft.id } }
                )
                CardDivider()
            }
            cardAction("Add window", symbol: "plus") { addWindow() }
            CardDivider()
            cardAction("Visualize windows", symbol: "calendar") { showWeek = true }
            if !copyCandidates.isEmpty {
                CardDivider()
                cardAction("Use windows from another app", symbol: "doc.on.doc") { showCopy = true }
            }
        }
        .emberCard()
    }

    private func cardAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
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
                Text(drafts.isEmpty ? "for the whole day" : "across all windows")
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
        budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
        drafts = rule.sortedWindows.map { DraftWindow(window: $0) }
        byDay = !rule.isSameEveryDay
    }

    /// Replaces the draft with another target's rule. Nothing is saved until Save.
    private func adopt(_ rule: Rule) {
        withAnimation(.snappy) {
            drafts = rule.sortedWindows.map { DraftWindow(window: $0) }
            budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
            byDay = !rule.isSameEveryDay
        }
    }

    /// The first window is an evening. Each one after that is the hour after the latest, or
    /// from midnight once the evening is taken, so "later on weekends" starts as the
    /// early-morning window it has to be.
    private func addWindow() {
        var window = TimeWindow(startMinute: 20 * 60, endMinute: 22 * 60)
        if var start = windows.map(\.endMinute).max() {
            if start > Furlough.minutesPerDay - 60 { start = 0 }
            window = TimeWindow(startMinute: start, endMinute: min(start + 60, Furlough.minutesPerDay))
        }
        withAnimation(.snappy) { drafts.append(DraftWindow(window: window)) }
    }

    private func save() {
        nicknameFocused = false
        result = model.propose(rule: draft, nickname: nickname, for: targetID)
    }
}

/// One allowed window: two glass time chips, an arrow, the duration, a quiet remove button,
/// and, when the rule varies by day, a strip of day toggles beneath. `onCommit` fires when
/// a time picker closes, so the owner can join rows that now touch.
struct WindowRow: View {
    @Binding var window: TimeWindow
    var showsDays = false
    var onCommit: () -> Void = {}
    let onRemove: () -> Void
    @State private var editing: WindowEdge?

    enum WindowEdge: String, Identifiable {
        case start, end
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            if showsDays {
                DayStrip(days: $window.days)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(item: $editing, onDismiss: onCommit) { edge in
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

/// Seven round day toggles in the calendar's order, amber when on, with the days named beside them.
struct DayStrip: View {
    @Binding var days: Weekdays
    /// Shown in cream and not toggleable: the day whose hours are being applied elsewhere.
    var locked: Weekdays = []
    /// Replaces "No days" when an empty pick is fine rather than an error.
    var placeholder: String?
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Weekdays.ordered(calendar: calendar), id: \.self) { weekday in
                let on = days.contains(weekday: weekday)
                let isLocked = locked.contains(weekday: weekday)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { days.toggle(weekday: weekday) }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(EmberFont.label(10))
                        .foregroundStyle(on || isLocked ? Ember.ground : Ember.faint)
                        .frame(width: 26, height: 26)
                        .background(isLocked ? Ember.cream : on ? Ember.amber : Color.white.opacity(0.07), in: Circle())
                        .overlay(Circle().strokeBorder(on || isLocked ? Color.clear : Ember.cardBorder, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 6)
            Text(days.isEmpty ? (placeholder ?? "No days") : TimeFormat.days(days, calendar: calendar))
                .emberBody(10.5)
                .foregroundStyle(days.isEmpty && placeholder == nil ? Ember.ember : Ember.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .sensoryFeedback(.selection, trigger: days)
    }
}

/// Picks another app or site whose windows, days and budget replace the draft.
struct CopyRuleSheet: View {
    let candidates: [Target]
    let onPick: (Target) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, target in
                            if index > 0 { CardDivider() }
                            Button {
                                onPick(target)
                                dismiss()
                            } label: {
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
                                        Text(TimeFormat.rule(target.rule))
                                            .emberBody(11.5)
                                            .foregroundStyle(Ember.muted)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Ember.faint)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .emberCard()
                    Footnote(text: "Copies its windows, days and daily budget into this rule. Nothing changes until you tap Save.", alignment: .center)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Use windows from")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Ember.cream)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Ember.ground)
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
        case .noChanges, .nicknameOnly: "checkmark"
        case .tightening: "bolt.fill"
        case .loosening: "clock"
        }
    }

    private var text: String {
        switch kind {
        case .error(let message): message
        case .noChanges: "No changes"
        case .nicknameOnly: "Nickname only · applies immediately"
        case .tightening: "Tighter than now · applies immediately"
        case .loosening(let when): "Looser than now · takes effect \(when.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private var color: Color {
        switch kind {
        case .error: Ember.ember
        case .nicknameOnly: Ember.muted
        case .noChanges: Ember.faint
        case .tightening: Ember.moss
        case .loosening: Ember.pending
        }
    }
}
