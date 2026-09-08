import Combine
import SwiftUI

/// The rule for one app or site: nickname, allowed windows with their days, daily budget.
/// Same semantics as the phone: the first rule is instant, tightening is instant, loosening
/// waits out the delay.
struct MacRuleEditor: View {
    @Environment(MacModel.self) private var model
    let targetID: UUID

    @State private var nickname = ""
    @State private var drafts: [DraftWindow] = []
    @State private var budget = Furlough.defaultBudgetMinutes
    @State private var byDay = false
    @State private var loaded = false
    @State private var showApply = false
    /// Targets chosen in the apply sheet, applied once the sheet has gone so the alert can show.
    @State private var applyTo: [UUID]?
    @State private var showWeek = false
    /// What the last save did, shown in the Saved alert.
    @State private var saved: String?
    @State private var confirmRemove = false
    @State private var now = Date.now
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
    private var windows: [TimeWindow] { drafts.map(\.window) }
    private var draft: Rule { Rule(windows: windows, dailyBudgetMinutes: budget) }
    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        guard let target else { return false }
        return !(target.rule?.isEquivalent(to: draft) ?? false) || (target.nickname != trimmedNickname && !trimmedNickname.isEmpty)
    }

    /// The draft as a week for the visual editor. Writing back merges identical spans across
    /// days into one window and sets the Same every day toggle to match.
    private var weekDraft: Binding<WeekDraft> {
        Binding(
            get: { WeekDraft(windows: windows) },
            set: { week in
                let merged = TimeWindow.grouped(week.windows)
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
                    SectionLabel(text: "Allowed windows")
                    windowsCard
                    SectionLabel(text: "Daily budget")
                    budgetCard(target)
                    effectBanner(for: target)
                        .padding(.top, 14)
                    ProminentButton(title: "Save") { save() }
                        .disabled(!hasChanges || draft.validationError != nil)
                        .padding(.top, 10)
                        .keyboardShortcut(.defaultAction)
                    GhostButton(title: "Remove from Furlough") { confirmRemove = true }
                        .padding(.top, 4)
                    Footnote(text: removalNote(target), alignment: .center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 40)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onReceive(clock) { now = $0 }
        .onAppear(perform: load)
        .confirmationDialog("Remove from Furlough?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { saved = model.removeTarget(id: targetID).message }
        }
        .sheet(isPresented: $showApply, onDismiss: {
            guard let ids = applyTo else { return }
            applyTo = nil
            applyToOthers(ids)
        }) {
            ApplyRuleSheet(
                candidates: applyCandidates,
                rule: draft,
                delayHours: model.state.config.loosenDelayHours
            ) { ids in applyTo = ids }
        }
        .sheet(isPresented: $showWeek) {
            WeekSheet(week: weekDraft)
        }
        .alert("Saved", isPresented: Binding(get: { saved != nil }, set: { if !$0 { saved = nil } }), presenting: saved) { _ in
            Button("OK") { saved = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: Sections

    /// The phone's hero for this app: living hourglass, countdown, and what is used today.
    private func header(_ target: Target) -> some View {
        TargetHero(
            target: target,
            status: Policy.status(of: target, config: model.state.config, runtime: model.state.runtime, now: now),
            runtime: model.state.runtime,
            usedSeconds: model.usedSeconds(for: target.id),
            now: now
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
    }

    private var nicknameCard: some View {
        HStack(spacing: 8) {
            Text("Name")
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            TextField("Name", text: $nickname)
                .textFieldStyle(.plain)
                .emberBody(13, .medium)
                .foregroundStyle(Ember.cream)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
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
                        .toggleStyle(.switch)
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
                    onRemove: { withAnimation(.snappy) { drafts.removeAll { $0.id == draft.id } } }
                )
                CardDivider()
            }
            CardAction(title: "Add window", symbol: "plus") { addWindow() }
            CardDivider()
            CardAction(title: "Visualize windows", symbol: "calendar") { showWeek = true }
            if !copyCandidates.isEmpty {
                CardDivider()
                Menu {
                    ForEach(copyCandidates) { source in
                        Button("\(source.displayName) · \(TimeFormat.rule(source.rule))") {
                            if let rule = source.rule { adopt(rule) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .bold))
                        Text("Use windows from another app").emberBody(13, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            if !applyCandidates.isEmpty {
                CardDivider()
                CardAction(title: "Apply these windows to other apps", symbol: "arrowshape.turn.up.right") { showApply = true }
                    .disabled(draft.validationError != nil)
                    .opacity(draft.validationError == nil ? 1 : 0.45)
            }
        }
        .emberCard()
    }

    private var copyCandidates: [Target] {
        model.state.config.targets.filter { $0.id != targetID && ($0.rule?.isEverAllowed ?? false) }
    }

    /// Every other app and site, set up or not.
    private var applyCandidates: [Target] {
        model.state.config.targets.filter { $0.id != targetID }
    }

    private func budgetCard(_ target: Target) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(budget)")
                        .emberNumerals(30)
                        .contentTransition(.numericText())
                    Text("MIN")
                        .font(EmberFont.label(10.5))
                        .tracking(1.4)
                        .foregroundStyle(Ember.faint)
                }
                Spacer()
                Text(drafts.isEmpty ? "for the whole day" : "across all windows")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            BudgetSlider(value: $budget)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
            CardDivider()
            HStack(spacing: 6) {
                ForEach([15, 30, 60, 120], id: \.self) { preset in
                    Button("\(preset)") { withAnimation(.snappy) { budget = preset } }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .tint(budget == preset ? Ember.amber : Ember.cream)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .emberCard()
    }

    // MARK: Effect

    private enum Effect {
        case noChanges, nicknameOnly, tightening, loosening(Date), error(String)
    }

    private func effect(for target: Target) -> Effect {
        if let error = draft.validationError { return .error(error) }
        if !hasChanges { return .noChanges }
        if target.rule?.isEquivalent(to: draft) ?? false { return .nicknameOnly }
        if Policy.classify(newRule: draft, against: target) == .tightening { return .tightening }
        return .loosening(Date.now.addingTimeInterval(model.state.config.loosenDelay))
    }

    private func effectBanner(for target: Target) -> some View {
        let (symbol, text, color): (String, String, Color) = switch effect(for: target) {
        case .noChanges: ("checkmark.circle", "No changes.", Ember.faint)
        case .nicknameOnly: ("textformat", "Only the name changes; that is instant.", Ember.muted)
        case .tightening: ("bolt.fill", "Tighter than now, so it applies the moment you save.", Ember.moss)
        case .loosening(let date): ("clock", "This loosens your rules. It takes effect \(date.formatted(date: .abbreviated, time: .shortened)); until then the current rule holds.", Ember.pending)
        case .error(let message): ("exclamationmark.triangle.fill", message, Ember.ember)
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .padding(.top, 1)
            Text(text)
                .emberBody(12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
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
        drafts = TimeWindow.grouped(rule.windows).map { DraftWindow(window: $0) }
        byDay = !rule.isSameEveryDay
    }

    /// Replaces the draft with another target's rule. Nothing is saved until Save.
    private func adopt(_ rule: Rule) {
        withAnimation(.snappy) {
            drafts = TimeWindow.grouped(rule.windows).map { DraftWindow(window: $0) }
            budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
            byDay = !rule.isSameEveryDay
        }
    }

    /// The first window is an evening. Each one after that goes on the same days as the last
    /// row, where those days have room: after the latest window, or from the first free hour
    /// once the evening is taken, so "later on weekends" starts as the early-morning window
    /// it has to be. Nothing is added when those days are full. Rows are only joined when
    /// the rule is saved: the time fields commit as you type, so joining sooner would move a
    /// row out from under the cursor.
    private func addWindow() {
        var window = TimeWindow(startMinute: 20 * 60, endMinute: 22 * 60)
        if let last = drafts.last {
            guard let free = TimeWindow.nextFree(after: windows, on: last.window.days) else { return }
            window = free
        }
        withAnimation(.snappy) { drafts = DraftWindow.sorted(drafts + [DraftWindow(window: window)]) }
    }

    private func save() {
        drafts = DraftWindow.tidy(drafts)
        saved = model.propose(rule: draft, nickname: nickname, for: targetID).message
    }

    /// Saves the draft here and gives it to `ids` as well, in one go.
    private func applyToOthers(_ ids: [UUID]) {
        drafts = DraftWindow.tidy(drafts)
        saved = model.apply(rule: draft, nickname: nickname, for: targetID, andTo: ids).message
    }
}

/// One allowed window: two time fields, the duration, a quiet remove button, and, when the
/// rule varies by day, a strip of day toggles beneath. An end of 12:00 AM means midnight.
struct WindowRow: View {
    @Binding var window: TimeWindow
    var showsDays = false
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TimeField(minute: $window.startMinute, allowsMidnight: false)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.muted)
                TimeField(minute: $window.endMinute, allowsMidnight: true)
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
                .help("Remove window")
            }
            if showsDays {
                DayStrip(days: $window.days)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func durationText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0 min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// An hour-and-minute field bound to a minute of the day. 1440 (midnight) shows as 12:00 AM
/// and is only meaningful as a window's end.
struct TimeField: View {
    @Binding var minute: Int
    let allowsMidnight: Bool

    var body: some View {
        DatePicker("Time", selection: date, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .labelsHidden()
            .font(EmberFont.numerals(12))
            .fixedSize()
    }

    private var date: Binding<Date> {
        Binding(
            get: { Policy.date(atMinute: minute % Furlough.minutesPerDay, of: .now) },
            set: { picked in
                let m = Policy.minuteOfDay(picked)
                minute = (m == 0 && allowsMidnight) ? Furlough.minutesPerDay : m
            }
        )
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
                        .frame(width: 24, height: 24)
                        .background(isLocked ? Ember.cream : on ? Ember.amber : Color.white.opacity(0.07), in: Circle())
                        .overlay(Circle().strokeBorder(on || isLocked ? Color.clear : Ember.cardBorder, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .help(calendar.standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 6)
            Text(days.isEmpty ? (placeholder ?? "No days") : TimeFormat.days(days, calendar: calendar))
                .emberBody(10.5)
                .foregroundStyle(days.isEmpty && placeholder == nil ? Ember.ember : Ember.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// The daily budget slider: 5–240 minutes in steps of 5, piecewise linear between the ticks.
struct BudgetSlider: View {
    @Binding var value: Int
    @State private var dragging = false

    static let anchors = [5, 30, 60, 120, 240]
    static let step = 5
    private let knob: CGFloat = 20

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let usable = max(1, geo.size.width - knob)
                let x = CGFloat(Self.fraction(for: value)) * usable
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                    Capsule().fill(Ember.sliderFill)
                        .frame(width: x + knob / 2, height: 6)
                        .shadow(color: Ember.amber.opacity(0.45), radius: 6)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: knob, height: knob)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .scaleEffect(dragging ? 1.12 : 1)
                        .offset(x: x)
                }
                .frame(height: knob)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            dragging = true
                            let fraction = Double(min(max(0, gesture.location.x - knob / 2), usable) / usable)
                            value = Self.value(for: fraction)
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(height: knob)
            GeometryReader { geo in
                let usable = max(1, geo.size.width - knob)
                ForEach(Self.anchors, id: \.self) { tick in
                    Text("\(tick)")
                        .font(EmberFont.numerals(9.5))
                        .foregroundStyle(Ember.faint)
                        .position(x: knob / 2 + CGFloat(Self.fraction(for: tick)) * usable, y: 6)
                }
            }
            .frame(height: 12)
        }
        .animation(.easeOut(duration: 0.15), value: dragging)
    }

    static func fraction(for value: Int) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        let clamped = Double(min(max(value, first), last))
        for index in 0..<(anchors.count - 1) {
            let lower = Double(anchors[index])
            let upper = Double(anchors[index + 1])
            if clamped <= upper {
                return (Double(index) + (clamped - lower) / (upper - lower)) / Double(anchors.count - 1)
            }
        }
        return 1
    }

    static func value(for fraction: Double) -> Int {
        let segments = Double(anchors.count - 1)
        let scaled = min(max(fraction, 0), 1) * segments
        let index = min(Int(scaled), anchors.count - 2)
        let lower = Double(anchors[index])
        let upper = Double(anchors[index + 1])
        let raw = lower + (scaled - Double(index)) * (upper - lower)
        return Int((raw / Double(step)).rounded()) * step
    }
}
