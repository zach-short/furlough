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
    @State private var showApply = false
    /// Targets chosen in the apply sheet, applied once the sheet has gone so the alert can show.
    @State private var applyTo: [UUID]?
    @State private var showWeek = false
    /// What the last save did, shown in the alert that closes the editor.
    @State private var saved: String?
    @State private var confirmRemove = false
    /// The tier in the draft. Saved through `AppModel.setUtility`, which decides on its own
    /// whether it lands now or queues.
    @State private var tier = Utility.unset
    @State private var confirmBlockEssential = false
    /// Set when the companion nudge is taken up: the flow below opens the guide or the picker.
    @State private var addRequest: AddRequest?
    @FocusState private var nicknameFocused: Bool

    /// A window with a stable identity while it is being edited.
    struct DraftWindow: Identifiable {
        let id = UUID()
        var window: TimeWindow

        /// Rows on the same days that overlap or touch, joined into the earlier row. A night
        /// is left out of it: its end is a time on the next morning, so it neither swallows a
        /// later row nor is swallowed by an earlier one. A night that does overlap its
        /// neighbours is caught by validation once it is split, and said so.
        static func joined(_ rows: [DraftWindow]) -> [DraftWindow] {
            var result: [DraftWindow] = []
            for row in rows.sorted(by: { $0.window < $1.window }) {
                if !row.window.isNight,
                   let index = result.lastIndex(where: { $0.window.days == row.window.days }),
                   !result[index].window.isNight,
                   row.window.startMinute <= result[index].window.endMinute {
                    result[index].window.endMinute = max(result[index].window.endMinute, row.window.endMinute)
                } else {
                    result.append(row)
                }
            }
            return result
        }

        /// Rows by group of days, then by time of day: the order the list always reads in.
        static func sorted(_ rows: [DraftWindow]) -> [DraftWindow] {
            let order = TimeWindow.grouped(rows.map(\.window))
            return rows.sorted { a, b in
                (order.firstIndex(of: a.window) ?? 0) < (order.firstIndex(of: b.window) ?? 0)
            }
        }

        /// Joined, then sorted: what a committed edit leaves behind.
        static func tidy(_ rows: [DraftWindow]) -> [DraftWindow] { sorted(joined(rows)) }
    }

    private var target: Target? { model.state.config.target(id: targetID) }
    /// The rows as Furlough stores them: a night becomes its evening and the morning after.
    private var windows: [TimeWindow] { drafts.flatMap { $0.window.split } }
    private var draft: Rule { Rule(windows: windows, dailyBudgetMinutes: savedBudget) }
    /// A typed host is saved with a whole day of budget — the value `Rule.unrestricted` uses
    /// for "no limit" — whatever the slider last held. Forced here rather than in `load()` so
    /// that no other path into the draft can give one a limit that nothing would enforce:
    /// "Use windows from another app" copies a budget, and the week sheet writes windows back
    /// through the same binding. A budget of 0 would mean blocked all day, so it cannot be that.
    private var savedBudget: Int { target?.kind.isHost == true ? Furlough.minutesPerDay : budget }
    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        guard let target else { return false }
        return !(target.rule?.isEquivalent(to: draft) ?? false)
            || target.nickname != trimmedNickname
            || target.utility != tier
    }

    /// What Furlough would have guessed, offered only while Zach has not answered for himself.
    private var suggestion: Utility? {
        guard let target, !target.hasChosenUtility else { return nil }
        return AppUtility.suggestion(for: target)?.utility
    }

    /// What blocking this one costs, when it is worth saying. Nil for the tiers Furlough exists
    /// to block, and nil for a draft that restricts nothing.
    private var caution: String? {
        // A draft that restricts nothing is not a block, so there is nothing to warn about.
        guard let target, !Rule.unrestricted.isEquivalent(to: draft) else { return nil }
        return UtilityText.blocking(
            name: target.displayName,
            utility: tier,
            detail: AppUtility.suggestion(for: target)?.detail
        )
    }

    /// What a night takes from the day after it, said under the windows while one is drafted.
    static let nightNote = """
        A window that runs past midnight opens the early hours of the next day too, and the \
        budget resets at midnight, so those hours get a fresh one.
        """

    /// Other apps and sites with windows worth copying.
    private var copyCandidates: [Target] {
        model.state.config.targets.filter {
            $0.id != targetID && !$0.kind.isCategory && ($0.rule?.isEverAllowed ?? false)
        }
    }

    /// Other apps and sites this draft can be given to, set up or not.
    private var applyCandidates: [Target] {
        model.state.config.targets.filter { $0.id != targetID && !$0.kind.isCategory }
    }

    /// The draft as a week for the visual editor. Writing back merges identical spans across
    /// days into one window and sets the Same every day toggle to match.
    private var weekDraft: Binding<WeekDraft> {
        Binding(
            get: { WeekDraft(windows: windows) },
            set: { week in
                let merged = TimeWindow.grouped(TimeWindow.folded(week.windows))
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
                        drafts = DraftWindow.tidy(drafts)
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
                    if let companion = model.companion(for: target) {
                        CompanionNudge(companion: companion) {
                            switch companion {
                            // Sites need no picker any more: they are names, so they are added
                            // on the spot. The nudge then goes on its own, because the hosts it
                            // was offering are among the ones Furlough knows.
                            case .sites(let hosts): model.addHosts(hosts)
                            // Still the picker: only Apple can mint an app's token, and
                            // `FamilyActivityData` — the one API that could do it without her —
                            // is EU-only for anyone who installs from the App Store. So the
                            // trip is made as short as it can be instead: one question, and
                            // what comes back already wears this target's hours.
                            case .app(let name):
                                addRequest = .companion(.application, of: target.id, titled: name)
                            }
                        } onDismiss: {
                            model.dismissCompanion(for: target.id)
                        }
                        .padding(.bottom, 14)
                    }
                    nicknameCard
                    if !target.kind.isCategory {
                        SectionLabel(text: "Allowed windows")
                        windowsCard
                        if drafts.contains(where: { $0.window.isNight }) {
                            Footnote(text: Self.nightNote)
                                .padding(.top, 8)
                        }
                        if target.kind.isHost {
                            Footnote(text: Self.hostBudgetNote)
                                .padding(.top, 14)
                        } else {
                            SectionLabel(text: "Daily budget")
                            budgetCard
                        }
                        SectionLabel(text: "How much it is worth")
                        UtilityPicker(
                            selection: $tier,
                            baseDelayHours: model.state.config.loosenDelayHours,
                            suggestion: suggestion
                        )
                        if let caution {
                            CautionBanner(text: caution, isSevere: tier == .essential)
                                .padding(.top, 14)
                        }
                        EffectBanner(kind: effect(for: target))
                            .padding(.top, 14)
                        ProminentButton(title: "Save") { attemptSave() }
                            .disabled(!hasChanges || draft.validationError != nil || limitReason != nil)
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
        .addTargetsFlow($addRequest)
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
        .confirmationDialog(
            "Block something essential?",
            isPresented: $confirmBlockEssential,
            titleVisibility: .visible
        ) {
            Button("Block it anyway", role: .destructive) { save() }
            Button("Keep it open", role: .cancel) {}
        } message: {
            Text(caution ?? "")
        }
        .confirmationDialog("Remove from Furlough?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                saved = model.removeTarget(id: targetID).message
            }
        }
        .sheet(isPresented: $showCopy) {
            CopyRuleSheet(candidates: copyCandidates) { source in
                if let rule = source.rule { adopt(rule) }
            }
        }
        .sheet(isPresented: $showApply, onDismiss: {
            guard let ids = applyTo else { return }
            applyTo = nil
            applyToOthers(ids)
        }) {
            ApplyRuleSheet(
                candidates: applyCandidates,
                rule: draft,
                delayHours: model.state.config.loosenDelayHours,
                limitReason: { ids in ActivityLimit.reason(applying: draft, to: [targetID] + ids, in: model.state) }
            ) { ids in applyTo = ids }
        }
        .sheet(isPresented: $showWeek) {
            WeekSheet(week: weekDraft)
        }
        .alert("Saved", isPresented: Binding(get: { saved != nil }, set: { if !$0 { saved = nil } }), presenting: saved) { _ in
            Button("OK") {
                saved = nil
                dismiss()
            }
        } message: { message in
            Text(message)
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
                    onCommit: { withAnimation(.snappy) { drafts = DraftWindow.tidy(drafts) } },
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
            if !applyCandidates.isEmpty {
                CardDivider()
                cardAction("Apply these windows to other apps", symbol: "arrowshape.turn.up.right") { showApply = true }
                    .disabled(draft.validationError != nil || limitReason != nil)
                    .opacity(draft.validationError == nil && limitReason == nil ? 1 : 0.45)
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

    /// Why a site added by name has hours and no limit. One line, said where the budget would
    /// have been, rather than left for someone to notice as an absence.
    private static let hostBudgetNote = "No daily budget: iOS counts a site only when it comes from Apple's picker, and this one was typed. Its hours are enforced."

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

    /// Why the draft will not fit inside iOS's 20 monitored activities once saved, or nil.
    /// Checked here rather than at registration, which only finds out after the rule is saved.
    private var limitReason: String? {
        ActivityLimit.reason(applying: draft, to: [targetID], in: model.state)
    }

    private func effect(for target: Target) -> EffectBanner.Kind {
        if let error = draft.validationError { return .error(error) }
        if let limitReason { return .error(limitReason) }
        if !hasChanges { return .noChanges }
        if target.rule?.isEquivalent(to: draft) ?? false { return .nicknameOnly }
        if Policy.classify(newRule: draft, against: target) == .tightening { return .tightening }
        return .loosening(model.clock.now.addingTimeInterval(model.state.config.delay(for: target)))
    }

    private func removalNote(_ target: Target) -> String {
        target.rule == nil
            ? "Nothing is enforced yet, so removal is immediate."
            : "Removing loosens your rules, so it takes \(TimeFormat.delay(hours: model.state.config.delayHours(for: target)))."
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
        tier = pendingTier ?? target.utility
        budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
        drafts = TimeWindow.grouped(TimeWindow.folded(rule.windows)).map { DraftWindow(window: $0) }
        byDay = !rule.isSameEveryDay
    }

    /// Replaces the draft with another target's rule. Nothing is saved until Save.
    private func adopt(_ rule: Rule) {
        withAnimation(.snappy) {
            drafts = TimeWindow.grouped(TimeWindow.folded(rule.windows)).map { DraftWindow(window: $0) }
            budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
            byDay = !rule.isSameEveryDay
        }
    }

    /// The first window is an evening. Each one after that goes on the same days as the last
    /// row, where those days have room: after the latest window, or from the first free hour
    /// once the evening is taken, so "later on weekends" starts as the early-morning window
    /// it has to be. The list keeps its order; the new row is not joined until its times are
    /// set. Nothing is added when those days are full.
    private func addWindow() {
        var window = TimeWindow(startMinute: 20 * 60, endMinute: 22 * 60)
        if let last = drafts.last {
            guard let free = TimeWindow.nextFree(after: windows, on: last.window.days) else { return }
            window = free
        }
        withAnimation(.snappy) { drafts = DraftWindow.sorted(drafts + [DraftWindow(window: window)]) }
    }

    /// A tier already queued for this target is what the editor should show, the same way a
    /// queued rule is: otherwise the chips would say one thing and the pending list another.
    private var pendingTier: Utility? {
        model.state.pending.compactMap { change -> Utility? in
            if case .setUtility(let id, let level) = change.kind, id == targetID { return level }
            return nil
        }.first
    }

    /// Blocking something essential is the one edit here that cannot be undone in a hurry, so
    /// it is the one that asks twice.
    private func attemptSave() {
        if caution != nil, tier == .essential {
            nicknameFocused = false
            confirmBlockEssential = true
        } else {
            save()
        }
    }

    private func save() {
        nicknameFocused = false
        // The tier first: a tightening of it lands now and so lengthens the wait the rule
        // itself is about to be given, while a loosening of it queues and changes nothing yet.
        let tierResult = model.setUtility(tier, for: targetID)
        let ruleResult = model.propose(rule: draft, nickname: nickname, for: targetID)
        saved = [tierResult, ruleResult]
            .filter { $0 != .unchanged }
            .map(\.message)
            .joined(separator: "\n\n")
        if saved?.isEmpty ?? true { saved = ProposalResult.unchanged.message }
    }

    /// Saves the draft here and gives it to `ids` as well, in one go.
    private func applyToOthers(_ ids: [UUID]) {
        nicknameFocused = false
        saved = model.apply(rule: draft, nickname: nickname, for: targetID, andTo: ids).message
    }
}

/// One allowed window: two glass time chips, an arrow, the duration, a quiet remove button,
/// and, when the rule varies by day, a strip of day toggles beneath. `onCommit` fires when
/// a time picker closes, so the owner can join rows that now touch. An end earlier than the
/// start is a night: the chip marks it "+1", the duration counts through midnight, and the
/// row is stored as the evening and the morning after.
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
                        TimeChip(minute: window.endMinute, nextDay: window.isNight) { editing = .end }
                    }
                }
                Spacer(minLength: 4)
                Text(durationText(window.spanMinutes))
                    .emberBody(11.5)
                    .monospacedDigit()
                    .foregroundStyle(window.isValidDraft ? Ember.muted : Ember.ember)
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
        .onChange(of: window.days) { _, _ in onCommit() }
        .sheet(item: $editing, onDismiss: onCommit) { edge in
            TimePickerSheet(
                title: edge == .start ? "Opens at" : "Closes at",
                minute: edge == .start ? $window.startMinute : $window.endMinute,
                allowsMidnight: edge == .end,
                nextDayAfter: edge == .end ? window.startMinute : nil
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

/// Picks the other apps and sites that get this rule, any number at once. Each row shows what
/// it has now; the line above the button says what applying will do, since each one is judged
/// on its own: tighter lands now, looser waits out the delay.
struct ApplyRuleSheet: View {
    let candidates: [Target]
    let rule: Rule
    let delayHours: Int
    /// Why saving to this set of targets would not fit inside iOS's activity limit, or nil.
    /// Each target keeps its own rule while a loosening waits, so a wide apply can overflow
    /// even when the rule is small.
    var limitReason: ([UUID]) -> String? = { _ in nil }
    let onApply: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []

    private var chosen: [Target] { candidates.filter { selected.contains($0.id) } }
    private var allChosen: Bool { selected.count == candidates.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, target in
                            if index > 0 { CardDivider() }
                            row(target)
                        }
                    }
                    .emberCard()
                    .sensoryFeedback(.selection, trigger: selected)
                    Footnote(text: summary, alignment: .center)
                        .padding(.top, 10)
                    if let reason = limitReason(chosen.map(\.id)) {
                        EffectBanner(kind: .error(reason))
                            .padding(.top, 10)
                    }
                    ProminentButton(title: buttonTitle) {
                        onApply(chosen.map(\.id))
                        dismiss()
                    }
                    .disabled(selected.isEmpty || limitReason(chosen.map(\.id)) != nil)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Apply windows to")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Ember.cream)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(allChosen ? "None" : "All") {
                        withAnimation(.snappy(duration: 0.2)) {
                            selected = allChosen ? [] : Set(candidates.map(\.id))
                        }
                    }
                    .tint(Ember.cream)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Ember.ground)
    }

    private func row(_ target: Target) -> some View {
        let on = selected.contains(target.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if on { selected.remove(target.id) } else { selected.insert(target.id) }
            }
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
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(on ? Ember.amber : Ember.faint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
        let apps = chosen.filter { if case .application = $0.kind { return true }; return false }.count
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

/// A glass chip showing a time of day.
struct TimeChip: View {
    let minute: Int
    /// The time falls on the morning after the window opened, so the chip says "+1".
    var nextDay = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(TimeFormat.minute(minute))
                    .emberBody(13, .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Ember.cream)
                if nextDay {
                    Text("+1")
                        .font(EmberFont.label(9))
                        .foregroundStyle(Ember.amber)
                        .accessibilityLabel("next day")
                }
            }
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
    /// The start this end is judged against. A time at or before it lands on the next morning,
    /// which the readout says while the wheel is still turning.
    var nextDayAfter: Int?
    @Environment(\.dismiss) private var dismiss

    private var isNextDay: Bool {
        guard let nextDayAfter else { return false }
        return minute < nextDayAfter
    }

    var body: some View {
        VStack(spacing: 8) {
            Eyebrow(text: title, color: Ember.amber)
                .padding(.top, 22)
            Text(TimeFormat.minute(minute))
                .emberNumerals(30)
                .contentTransition(.numericText())
            Text("next day")
                .emberBody(11.5)
                .foregroundStyle(Ember.amber)
                .opacity(isNextDay ? 1 : 0)
            DatePicker("Time", selection: dateBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            ProminentButton(title: "Done") { dismiss() }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationBackground { EmberWall() }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Policy.date(atMinute: min(minute, Furlough.minutesPerDay - 1), of: .now) },
            set: { date in
                let picked = Policy.minuteOfDay(date)
                // Both ends of the wheel mean the same midnight, and only an end can be one.
                let isMidnight = picked == 0 || picked == Furlough.minutesPerDay - 1
                minute = (allowsMidnight && isMidnight) ? Furlough.minutesPerDay : picked
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
