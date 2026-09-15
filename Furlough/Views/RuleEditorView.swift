import SwiftUI

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let targetID: UUID

    @State private var nickname = ""
    @State private var drafts: [DraftWindow] = []
    @State private var budget = Furlough.defaultBudgetMinutes
    /// On when the week is seven figures rather than one, mirroring `byDay` for the windows.
    @State private var budgetByDay = false
    /// Sunday-first, index = Calendar's weekday minus one. Only read while `budgetByDay` is on.
    @State private var dayBudgets = [Int](repeating: Furlough.defaultBudgetMinutes, count: 7)
    @State private var loaded = false
    /// Whether each window shows its day strip. Off means every window applies every day.
    @State private var byDay = false
    @State private var showCopy = false
    @State private var showApply = false
    /// Targets chosen in the apply sheet, applied once the sheet has gone so the alert can show.
    @State private var applyTo: [UUID]?
    @State private var showWeek = false
    @State private var saved: String?
    @State private var confirmRemove = false
    /// Saved through `AppModel.setUtility`, which decides on its own whether it lands now or queues.
    @State private var tier = Utility.unset
    /// `Utility.unset` reads as `.useful` in the picker, so this distinguishes an actual choice
    /// from the untouched default — see `answeredTier`.
    @State private var tierTouched = false
    @State private var confirmBlockEssential = false
    /// Set when "Change it" is tapped on the first-rule card, revealing the full editor.
    /// One-way for this visit.
    @State private var changing = false
    /// The suggestion currently in the fields, so the offer doesn't re-offer what's already there.
    @State private var appliedSuggestion: RuleSuggestion.Draft?
    @State private var addRequest: AddRequest?
    @State private var linked: String?
    @State private var confirmUnlink: TargetKind?
    @FocusState private var nicknameFocused: Bool

    /// A window with a stable identity while it is being edited.
    struct DraftWindow: Identifiable {
        let id = UUID()
        var window: TimeWindow

        /// Rows on the same days that overlap or touch, joined into the earlier row. Night
        /// windows are excluded since their end lands the next morning; an overlap there is
        /// caught by validation instead.
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

        static func sorted(_ rows: [DraftWindow]) -> [DraftWindow] {
            let order = TimeWindow.grouped(rows.map(\.window))
            return rows.sorted { a, b in
                (order.firstIndex(of: a.window) ?? 0) < (order.firstIndex(of: b.window) ?? 0)
            }
        }

        static func tidy(_ rows: [DraftWindow]) -> [DraftWindow] { sorted(joined(rows)) }
    }

    private var target: Target? { model.state.config.target(id: targetID) }
    /// A night becomes its evening and the morning after, as Furlough stores it.
    private var windows: [TimeWindow] { drafts.flatMap { $0.window.split } }
    private var draft: Rule {
        Rule(windows: windows, dailyBudgetMinutes: savedBudget, budgetByWeekday: savedBudgetByWeekday).normalized
    }
    /// A target nothing counts (`isCounted == false`, not `kind.isHost` — a linked site shares
    /// its app's real budget) is forced to `Rule.unrestricted`'s whole-day value here, so no
    /// other path (copy, week sheet) can give it an unenforceable limit.
    private var savedBudget: Int { target?.isCounted == false ? Furlough.minutesPerDay : budget }
    /// Nil for an uncounted target, for the same reason as `savedBudget`. `normalized` drops
    /// the array again when all seven agree.
    private var savedBudgetByWeekday: [Int]? {
        guard budgetByDay, target?.isCounted != false else { return nil }
        return dayBudgets
    }
    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        guard let target else { return false }
        return !(target.rule?.isEquivalent(to: draft) ?? false)
            || target.nickname != trimmedNickname
            || target.utility != tier
    }

    private var suggestion: Utility? {
        guard let target, !target.hasChosenUtility else { return nil }
        return AppUtility.suggestion(for: target)?.utility
    }

    /// Offered only while the target has no rule and none is queued — a cold-start suggestion,
    /// never a second way to edit a rule someone is already living under.
    private var ruleSuggestion: RuleSuggestion.Draft? {
        guard let target, pendingRule == nil else { return nil }
        return RuleSuggestion.suggestion(for: target, chosen: answeredTier)
    }

    /// The card the editor opens on instead of its own sections, or nil for the full editor.
    /// Only for a target with no rule at all.
    private var firstRule: RuleSuggestion.Draft? {
        guard !changing, let target, !target.kind.isCategory else { return nil }
        return ruleSuggestion
    }

    /// Nil until the tier chips are actually touched or a tier is saved — an untouched picker
    /// reads `.useful`, which is not itself an answer.
    private var answeredTier: Utility? {
        guard let target else { return nil }
        return target.hasChosenUtility || tierTouched ? tier : nil
    }

    private var nicknameOffer: String? {
        guard let target, trimmedNickname.isEmpty else { return nil }
        return AppUtility.offeredNickname(for: target)
    }

    /// Nil for tiers Furlough doesn't block, and for a draft that restricts nothing.
    private var caution: String? {
        guard let target, !Rule.unrestricted.isEquivalent(to: draft) else { return nil }
        return UtilityText.blocking(
            name: target.displayName,
            utility: tier,
            detail: AppUtility.suggestion(for: target)?.detail
        )
    }

    static let nightNote = """
        A window that runs past midnight opens the early hours of the next day too, and the \
        budget resets at midnight, so those hours get a fresh one.
        """

    private var hasCopySources: Bool { !copyCandidates.isEmpty || ruleSuggestion != nil }

    private var copyCandidates: [Target] {
        model.state.config.targets.filter {
            $0.id != targetID && !$0.kind.isCategory && ($0.rule?.isEverAllowed ?? false)
        }
    }

    private var applyCandidates: [Target] {
        model.state.config.targets.filter { $0.id != targetID && !$0.kind.isCategory }
    }

    /// Writing back merges identical spans across days into one window and updates the
    /// Same-every-day toggle to match.
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

    /// Turning it off seeds all seven days from the current single figure, so the toggle shows
    /// the week already had rather than seven defaults.
    private var sameBudgetEveryDay: Binding<Bool> {
        Binding(
            get: { !budgetByDay },
            set: { on in
                withAnimation(.snappy) {
                    budgetByDay = !on
                    if !on { dayBudgets = [Int](repeating: budget, count: 7) }
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let target {
                    header(target)
                    undoCard(target)
                    if let suggestion = firstRule {
                        firstRulePane(target, suggestion)
                    } else {
                        fullEditor(target)
                    }
                    GhostButton(title: "Remove from Furlough") { confirmRemove = true }
                        .padding(.top, 4)
                    Footnote(text: removalNote(target), alignment: .center)
                } else {
                    removedPane
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
        // "No budget" only makes sense while windows narrow the day; with no windows left it
        // would enforce nothing, so fall back to the top of the ordinary range instead.
        .onChange(of: drafts.isEmpty) { _, isEmpty in
            guard isEmpty else { return }
            let ceiling = BudgetSlider.anchors.last ?? 240
            if budget >= BudgetSlider.noBudget { budget = ceiling }
            for index in dayBudgets.indices where dayBudgets[index] >= BudgetSlider.noBudget {
                dayBudgets[index] = ceiling
            }
        }
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
            CopyRuleSheet(candidates: copyCandidates, suggestion: ruleSuggestion?.rule) { rule in
                adopt(rule)
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
        .modifier(HalfChangeAlerts(
            unlinking: $confirmUnlink,
            done: $linked,
            name: target?.displayName ?? "this app",
            delay: TimeFormat.delay(hours: model.state.config.delayHours(for: target)),
            unlink: { kind in linked = model.unlink(kind, from: targetID).message }
        ))
        .alert("Saved", isPresented: Binding(get: { saved != nil }, set: { if !$0 { saved = nil } }), presenting: saved) { _ in
            Button("OK") {
                saved = nil
                dismiss()
            }
        } message: { message in
            Text(message)
        }
    }

    // MARK: The editor, in sections

    /// Lifted out of `body`, like the sections below, since the type checker times out on it
    /// as one expression.
    @ViewBuilder
    private func fullEditor(_ target: Target) -> some View {
        nudge(target)
        nicknameCard
        if let name = nicknameOffer {
            SuggestionOffer(text: "Call it \(name)") { nickname = name }
                .padding(.top, 8)
                .padding(.horizontal, 8)
        }
        if !target.kind.isCategory {
            ruleSection(target)
        } else {
            Footnote(text: "Categories are always blocked. Apps inside them that you give windows to are excepted.")
                .padding(.top, 10)
            ProminentButton(title: "Save nickname") { save() }
                .disabled(!hasChanges)
                .padding(.top, 14)
        }
    }

    @ViewBuilder
    private func firstRulePane(_ target: Target, _ suggestion: RuleSuggestion.Draft) -> some View {
        SectionLabel(text: "The first rule")
        VStack(alignment: .leading, spacing: 4) {
            Text(RuleSuggestion.statement(suggestion, counted: target.isCounted))
                .emberDisplaySmall(16)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
            if let tier = RuleSuggestion.tier(for: target, chosen: answeredTier) {
                Text(RuleSuggestion.because(tier))
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .emberCard()
        ProminentButton(title: "Save this rule") { saveFirstRule(suggestion) }
            .padding(.top, 14)
        GhostButton(title: "Change it", color: Ember.muted) { beginChanging(suggestion) }
            .padding(.top, 2)
        Footnote(text: Self.firstRuleNote, alignment: .center)
    }

    private static let firstRuleNote = "Adding an app enforces nothing on its own. Saving its first rule is what starts it."

    private var removedPane: some View {
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

    @ViewBuilder
    private func ruleSection(_ target: Target) -> some View {
        SectionLabel(text: "Allowed windows")
        windowsCard
        // Suppressed only while it matches what's already in the fields (e.g. right after
        // "Change it"); reappears once moving the tier chips changes the suggestion.
        if let draft = ruleSuggestion, draft != appliedSuggestion {
            SuggestionOffer(text: RuleSuggestion.offer(draft, counted: target.isCounted)) {
                applySuggestion(draft)
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)
        }
        if drafts.contains(where: { $0.window.isNight }) {
            Footnote(text: Self.nightNote)
                .padding(.top, 8)
        }
        budgetSection(target)
        halves(target)
        anchorSection(target)
        SectionLabel(text: "How much it is worth")
        UtilityPicker(
            selection: tierBinding,
            baseDelayHours: model.state.config.loosenDelayHours,
            suggestion: suggestion
        )
        if let caution {
            CautionBanner(text: caution, isSevere: tier == .essential)
                .padding(.top, 14)
        }
        EffectBanner(kind: effect(for: target))
            .padding(.top, 14)
        if let preview = consequence(for: target) {
            ConsequenceCard(preview: preview)
                .padding(.top, 10)
        }
        ProminentButton(title: "Save") { attemptSave() }
            .disabled(!hasChanges || draft.validationError != nil || limitReason != nil)
            .padding(.top, 10)
    }

    @ViewBuilder
    private func nudge(_ target: Target) -> some View {
        if let companion = model.companion(for: target) {
            CompanionNudge(companion: companion) {
                switch companion {
                case .sites(let hosts): linked = model.linkHosts(hosts, to: target.id).message
                // Apple's `FamilyActivityData` could mint an app token directly but is EU-only
                // for App Store installs, so this still goes through the picker.
                case .app(let name):
                    addRequest = .companion(.application, of: target.id, titled: name)
                }
            } onDismiss: {
                model.dismissCompanion(for: target.id)
            }
            .padding(.bottom, 14)
        } else if model.awaitsName(target) {
            // A picked app has no name until Furlough has seen it, and the site name follows
            // that — said here so the missing site doesn't read as the setting being ignored.
            Footnote(text: "The website this app is also at follows once Furlough has seen the app — right away with Screen Time data access, otherwise the first time the shield covers it.")
                .padding(.bottom, 14)
        }
    }

    // MARK: The other halves

    @ViewBuilder
    private func budgetSection(_ target: Target) -> some View {
        if !target.isCounted {
            Footnote(text: Self.hostBudgetNote)
                .padding(.top, 14)
        } else {
            SectionLabel(text: "Daily budget")
            budgetCard
            if !target.uncountedHosts.isEmpty {
                Footnote(text: Self.linkedHostBudgetNote(target.uncountedHosts))
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func halves(_ target: Target) -> some View {
        if target.isLinked {
            SectionLabel(text: "Also blocks")
            alsoCard(target)
        }
        if let other = mergeCandidate(target) {
            MergeOffer(name: other.displayName, into: target.displayName) {
                linked = model.merge(other.id, into: target.id).message
            }
            .padding(.top, 14)
        }
    }

    /// One at a time: offering more than one merge candidate would be a list to work through
    /// rather than a question to answer.
    private func mergeCandidate(_ target: Target) -> Target? { model.mergeable(with: target).first }

    // MARK: The other half

    /// Acts at once rather than on Save: the anchor's list is not a rule and waits out no delay.
    @ViewBuilder
    private func anchorSection(_ target: Target) -> some View {
        let anchor = model.state.config.anchor
        SectionLabel(text: "The Anchor")
        HStack(spacing: 12) {
            if anchor.anchorsEverything {
                // Stated, not editable here: the "except" list belongs to the Anchor page.
                Text(anchor.willHold(target) ? "Held while anchored" : "Stays open while anchored")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer(minLength: 8)
                AnchorShape()
                    .fill(anchor.willHold(target) ? Ember.ember : Ember.faint)
                    .frame(width: 11, height: 14)
            } else {
                Text("Also hold it in the Anchor")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer(minLength: 8)
                Toggle("Also hold it in the Anchor", isOn: heldBinding(target))
                    .labelsHidden()
                    .tint(Ember.ember)
                    .disabled(anchor.isAnchored)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .emberCard()
        Footnote(text: anchorNote(target))
            .padding(.top, 8)
    }

    /// On only once every linked half is on the anchor's list; toggling on adds them all.
    private func heldBinding(_ target: Target) -> Binding<Bool> {
        Binding(
            get: { model.state.config.anchor.lists(target) },
            set: { on in
                if on {
                    model.addToAnchor(targetIDs: [target.id])
                } else {
                    model.removeFromAnchor(targetIDs: [target.id])
                }
            }
        )
    }

    private func anchorNote(_ target: Target) -> String {
        let anchor = model.state.config.anchor
        if anchor.isAnchored { return "Unanchor with your tag to change what it holds." }
        if anchor.anchorsEverything {
            return "The anchor holds everything except a short list. Change that list on the Anchor page."
        }
        if anchor.lists(target) {
            return "Shut at any hour while the anchor is down, and only your tag lifts it. Free, the hours above apply as ever."
        }
        return "The anchor holds only what it has been given. This changes nothing until it is dropped."
    }

    @ViewBuilder
    private func alsoCard(_ target: Target) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((target.also ?? []).enumerated()), id: \.offset) { index, kind in
                if index > 0 { CardDivider() }
                HStack(spacing: 10) {
                    Image(systemName: kind.isHost ? "globe" : "square.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ember.faint)
                        .frame(width: 16)
                    if let host = kind.hostName {
                        Text(host)
                            .emberBody(13)
                            .foregroundStyle(Ember.cream)
                    } else {
                        TokenName(kind: kind, size: .small)
                    }
                    Spacer(minLength: 8)
                    if queuedUnlink(target).contains(kind) {
                        Text("Coming off")
                            .emberBody(11, .semibold)
                            .foregroundStyle(Ember.pending)
                    } else {
                        Button("Unlink") { confirmUnlink = kind }
                            .buttonStyle(.plain)
                            .emberBody(12, .semibold)
                            .foregroundStyle(Ember.ember)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .emberCard()
        Footnote(text: "Blocked on the hours above, as one thing. Taking a half off loosens your rules, so it takes \(TimeFormat.delay(hours: model.state.config.delayHours(for: target))).")
            .padding(.top, 8)
    }

    private func queuedUnlink(_ target: Target) -> [TargetKind] {
        model.state.pending.compactMap { change in
            if case .unlink(let id, let kind) = change.kind, id == target.id { return kind }
            return nil
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
            if hasCopySources {
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

    /// The honest gap in a linked pair, said in one line rather than left to be discovered. The
    /// windows do cover the site; the budget cannot, and nothing on iOS can make it.
    private static func linkedHostBudgetNote(_ hosts: [String]) -> String {
        let list = UtilityText.list(hosts)
        let it = hosts.count == 1 ? "it" : "them"
        return "\(list) shares these hours. Time spent there does not come off the budget — iOS counts a site only when it comes from Apple's picker, and \(it) \(hosts.count == 1 ? "was" : "were") typed."
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if budgetByDay {
                ForEach(Weekdays.ordered(), id: \.self) { weekday in
                    DayBudgetRow(weekday: weekday, minutes: dayBudget(weekday), allowsNoBudget: !drafts.isEmpty)
                    CardDivider()
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        if budget >= BudgetSlider.noBudget {
                            Text("No budget")
                                .emberDisplay(26)
                                .foregroundStyle(Ember.cream)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(budget)")
                                    .emberNumerals(30)
                                    .contentTransition(.numericText())
                                Text("MIN")
                                    .font(EmberFont.label(10.5))
                                    .tracking(0.06 * 10.5)
                                    .foregroundStyle(Ember.muted)
                            }
                        }
                        Spacer()
                        Text(budgetNote)
                            .emberBody(11)
                            .foregroundStyle(Ember.muted)
                            .multilineTextAlignment(.trailing)
                    }
                    BudgetSlider(value: $budget, allowsNoBudget: !drafts.isEmpty)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
                CardDivider()
            }
            HStack(spacing: 12) {
                Text("Same budget every day")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer()
                Toggle("Same budget every day", isOn: sameBudgetEveryDay)
                    .labelsHidden()
                    .tint(Ember.ember)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .emberCard()
    }

    /// "No budget" still needs saying the windows keep closing, or it reads as no rule at all.
    private var budgetNote: String {
        if budget >= BudgetSlider.noBudget { return "the windows still close" }
        return drafts.isEmpty ? "for the whole day" : "across all windows"
    }

    private func dayBudget(_ weekday: Int) -> Binding<Int> {
        Binding(
            get: { dayBudgets.indices.contains(weekday - 1) ? dayBudgets[weekday - 1] : budget },
            set: { if dayBudgets.indices.contains(weekday - 1) { dayBudgets[weekday - 1] = $0 } }
        )
    }

    /// Checked here (not at registration) so iOS's 20-activity limit is caught before Save.
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

    @ViewBuilder
    private func undoCard(_ target: Target) -> some View {
        if let undo = model.undo(for: targetID) {
            UndoCard(
                name: target.displayName,
                restoresNothing: undo.rule == nil,
                deviceExpiry: model.clock.device(undo.expiresAt)
            ) {
                model.undoRule(for: targetID)
                loaded = false
                load()
            }
            .padding(.top, 18)
        }
    }

    /// Nil when there's nothing worth saying: a loosening (the banner already covers those),
    /// an invalid draft, or no change at all.
    private func consequence(for target: Target?) -> Consequence.Preview? {
        guard hasChanges, draft.validationError == nil, limitReason == nil else { return nil }
        return Consequence.preview(rule: draft, for: target, config: model.state.config, now: model.clock.now)
    }

    private func removalNote(_ target: Target) -> String {
        target.rule == nil
            ? "Nothing is enforced yet, so removal is immediate."
            : "Removing loosens your rules, so it takes \(TimeFormat.delay(hours: model.state.config.delayHours(for: target)))."
    }

    // MARK: Actions

    /// Tracks `tierTouched` alongside the value, since `UtilityPicker` can't itself say whether
    /// what it wrote is a real answer or just its default.
    private var tierBinding: Binding<Utility> {
        Binding(
            get: { tier },
            set: { chosen in
                tier = chosen
                tierTouched = true
            }
        )
    }

    private var pendingRule: Rule? {
        model.state.pending.compactMap { change -> Rule? in
            if case .setRule(let id, let rule) = change.kind, id == targetID { return rule }
            return nil
        }.first
    }

    private func load() {
        guard !loaded, let target else { return }
        loaded = true
        nickname = target.nickname
        let rule = pendingRule ?? target.rule ?? Rule()
        tier = pendingTier ?? target.utility
        budget = rule.representativeBudget > 0 ? rule.representativeBudget : Furlough.defaultBudgetMinutes
        seedBudgets(rule)
        drafts = TimeWindow.grouped(TimeWindow.folded(rule.windows)).map { DraftWindow(window: $0) }
        byDay = !rule.isSameEveryDay
    }

    /// Seeded even for a single-budget rule, so switching the toggle off shows that budget on
    /// all seven days rather than the default.
    private func seedBudgets(_ rule: Rule) {
        budgetByDay = !rule.isSameBudgetEveryDay
        dayBudgets = (1...7).map { rule.budget(on: $0) }
    }

    /// The window is appended (via `tidy`) rather than replacing existing rows, so a tap can
    /// never discard hours already typed; the budget does overwrite, since an untouched slider
    /// holds a default rather than an answer.
    private func applySuggestion(_ draft: RuleSuggestion.Draft) {
        appliedSuggestion = draft
        withAnimation(.snappy) {
            budget = draft.budgetMinutes
            budgetByDay = false
            dayBudgets = [Int](repeating: draft.budgetMinutes, count: 7)
            if let window = draft.window {
                drafts = DraftWindow.tidy(drafts + [DraftWindow(window: window)])
                byDay = !drafts.allSatisfy { $0.window.days == .all }
            }
        }
    }

    /// Applies the suggestion to the fields first, then saves through the normal path, so the
    /// editor is showing the saved rule if Save has something to say.
    private func saveFirstRule(_ suggestion: RuleSuggestion.Draft) {
        applySuggestion(suggestion)
        attemptSave()
    }

    private func beginChanging(_ suggestion: RuleSuggestion.Draft) {
        applySuggestion(suggestion)
        withAnimation(.snappy) { changing = true }
    }

    /// Replaces the draft with another target's rule. Nothing is saved until Save.
    private func adopt(_ rule: Rule) {
        withAnimation(.snappy) {
            drafts = TimeWindow.grouped(TimeWindow.folded(rule.windows)).map { DraftWindow(window: $0) }
            budget = rule.representativeBudget > 0 ? rule.representativeBudget : Furlough.defaultBudgetMinutes
            seedBudgets(rule)
            byDay = !rule.isSameEveryDay
        }
    }

    /// Defaults to an evening window; picks the next free slot on the last row's days, or
    /// Furlough's suggested window for the first row on an unset target. Adds nothing when
    /// those days are full.
    private func addWindow() {
        var window = TimeWindow(startMinute: 20 * 60, endMinute: 22 * 60)
        if let last = drafts.last {
            guard let free = TimeWindow.nextFree(after: windows, on: last.window.days) else { return }
            window = free
        } else if let suggested = ruleSuggestion?.window {
            window = suggested
        }
        withAnimation(.snappy) { drafts = DraftWindow.sorted(drafts + [DraftWindow(window: window)]) }
    }

    private var pendingTier: Utility? {
        model.state.pending.compactMap { change -> Utility? in
            if case .setUtility(let id, let level) = change.kind, id == targetID { return level }
            return nil
        }.first
    }

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
        // Tier saved first: a tightening applies immediately and extends the rule's own delay;
        // a loosening queues and changes nothing yet.
        let tierResult = model.setUtility(tier, for: targetID)
        let ruleResult = model.propose(rule: draft, nickname: nickname, for: targetID)
        saved = [tierResult, ruleResult]
            .filter { $0 != .unchanged }
            .map(\.message)
            .joined(separator: "\n\n")
        if saved?.isEmpty ?? true { saved = ProposalResult.unchanged.message }
    }

    private func applyToOthers(_ ids: [UUID]) {
        nicknameFocused = false
        saved = model.apply(rule: draft, nickname: nickname, for: targetID, andTo: ids).message
    }
}

/// `onCommit` fires when a time picker closes, so the owner can join rows that now touch. An
/// end earlier than the start is a night: stored as the evening and the morning after.
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
                EmberGlassEffectContainer(spacing: 8) {
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

struct DayStrip: View {
    @Binding var days: Weekdays
    /// Shown in cream and not toggleable.
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
                        .frame(minWidth: 26, minHeight: 26)
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

/// Picks another app or site whose windows, days and budget replace the draft. The first row
/// can be Furlough's own starting rule for the target being edited, when it has one.
struct CopyRuleSheet: View {
    let candidates: [Target]
    var suggestion: Rule?
    let onPick: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        if let suggestion {
                            suggestionRow(suggestion)
                        }
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, target in
                            if index > 0 || suggestion != nil { CardDivider() }
                            Button {
                                if let rule = target.rule { onPick(rule) }
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

    private func suggestionRow(_ rule: Rule) -> some View {
        Button {
            onPick(rule)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ember.amber)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Ember.tileRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Ember.tileRadius, style: .continuous).strokeBorder(Ember.cardBorder, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Furlough's starting rule")
                        .emberBody(13, .semibold)
                        .foregroundStyle(Ember.cream)
                    Text(TimeFormat.rule(rule))
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

/// Picks the other apps and sites that get this rule, any number at once. Each is judged on
/// its own: tighter lands now, looser waits out the delay.
struct ApplyRuleSheet: View {
    let candidates: [Target]
    let rule: Rule
    let delayHours: Int
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
        .emberGlass(interactive: true, in: .rect(cornerRadius: 10))
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

/// A `ViewModifier` rather than more links on the editor's own chain, whose modifier chain (one
/// expression to the type checker) was already at its time limit.
private struct HalfChangeAlerts: ViewModifier {
    @Binding var unlinking: TargetKind?
    @Binding var done: String?
    let name: String
    let delay: String
    let unlink: (TargetKind) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Stop blocking the other half?",
                isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }),
                titleVisibility: .visible,
                presenting: unlinking
            ) { kind in
                Button("Unlink", role: .destructive) {
                    unlink(kind)
                    unlinking = nil
                }
                Button("Keep it blocked", role: .cancel) { unlinking = nil }
            } message: { kind in
                Text("\(kind.hostName ?? "The other half") stops being blocked and \(name) carries on alone. That loosens your rules, so it takes \(delay).")
            }
            // Separate from the editor's "Saved" alert (which dismisses the screen): this leaves
            // the same row on screen since there's nowhere else to go.
            .alert(
                "Done",
                isPresented: Binding(get: { done != nil }, set: { if !$0 { done = nil } }),
                presenting: done
            ) { _ in
                Button("OK") { done = nil }
            } message: { message in
                Text(message)
            }
    }
}

/// Offers to merge a pair added before linking existed (and so left as two rows) into one.
/// A tightening — two budgets become one shared, tighter one — so no delay applies.
struct MergeOffer: View {
    let name: String
    let into: String
    let onMerge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 1)
                Text("\(name) is already here, on a row of its own. It is the same thing as \(into) — one row means one schedule and one budget across both, instead of two of each.")
                    .emberBody(12, .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Ember.amber)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onMerge) {
                Text("Make them one")
                    .emberBody(12.5, .semibold)
                    .foregroundStyle(Ember.ground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Ember.amber, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Ember.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ember.amber.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Reverts an edit that hasn't taken effect yet, exactly to its prior state — not an unblock.
struct UndoCard: View {
    let name: String
    /// True when the edit was this target's first rule, so undoing leaves it enforcing nothing.
    let restoresNothing: Bool
    /// The expiry on the *device's* clock, because the system renders this timer itself and
    /// knows nothing about Furlough's. `Clock.Reading.device` is what converts it.
    let deviceExpiry: Date
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Eyebrow(text: "Not set yet", color: Ember.pending, size: 10.5)
                Spacer()
                // Ticked manually (not `Text(timerInterval:)`) so it renders on `deviceExpiry`'s
                // clock. Font spelt out rather than via `emberNumerals`, which bakes in a color
                // that would override the one set below.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimeFormat.countdown(from: context.date, to: deviceExpiry))
                        .font(EmberFont.numerals(12))
                        .monospacedDigit()
                        .tracking(-0.02 * 12)
                        .foregroundStyle(Ember.pending)
                }
            }
            Text(restoresNothing
                 ? "You just set the first rule for \(name). It can go back to enforcing nothing."
                 : "You just changed \(name). It can go back to exactly the rule it had.")
                .emberBody(12.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            GhostButton(title: "Undo this change", color: Ember.pending, action: action)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .emberCard()
    }
}

/// What the rule on screen would do, shown before it's saved: today, and the cost of undoing.
struct ConsequenceCard: View {
    let preview: Consequence.Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.moss)
                    .padding(.top, 1)
                Text(preview.today)
                    .emberBody(12.5, .semibold)
                    .foregroundStyle(Ember.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(preview.undoing)
                .emberBody(11.5)
                .foregroundStyle(Ember.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 21)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Ember.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ember.cardBorder, lineWidth: 1)
        )
    }
}
