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
    @State private var result: ProposalResult?
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
    }

    private var target: Target? { model.state.config.target(id: targetID) }
    private var windows: [TimeWindow] { drafts.map(\.window) }
    private var draft: Rule { Rule(windows: windows, dailyBudgetMinutes: budget) }
    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        guard let target else { return false }
        return target.rule != draft || (target.nickname != trimmedNickname && !trimmedNickname.isEmpty)
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
            Button("Remove", role: .destructive) { result = model.removeTarget(id: targetID) }
        }
        .alert("Saved", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }), presenting: result) { _ in
            Button("OK") { result = nil }
        } message: { result in
            Text(result.message)
        }
    }

    // MARK: Sections

    private func header(_ target: Target) -> some View {
        let status = Policy.status(of: target, config: model.state.config, runtime: model.state.runtime, now: now)
        return HStack(spacing: 14) {
            KindTile(kind: target.kind, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.displayName)
                    .emberDisplay(24)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Text(subtitle(target, status: status))
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .lineLimit(1)
            }
            Spacer()
            HourglassView(state: .of(target, status: status, runtime: model.state.runtime, now: now))
                .frame(width: 30, height: 40)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
    }

    private func subtitle(_ target: Target, status: TargetStatus) -> String {
        let identity: String = switch target.kind {
        case .macApp(let bundleID): bundleID
        case .host(let host): "\(host) and its subdomains"
        }
        guard let rule = target.rule, rule.isEverAllowed else { return identity }
        let used = model.usedSeconds(for: target.id) / 60
        return "\(TimeFormat.status(status)) · \(used) of \(rule.dailyBudgetMinutes) min used today · \(identity)"
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
        }
        .emberCard()
    }

    private var copyCandidates: [Target] {
        model.state.config.targets.filter { $0.id != targetID && ($0.rule?.isEverAllowed ?? false) }
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
                Text("per day, in total")
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
        case noChanges, nicknameOnly, tightening, loosening(Date), blockedAllDay, error(String)
    }

    private func effect(for target: Target) -> Effect {
        if let error = draft.validationError { return .error(error) }
        if !draft.isEverAllowed { return .blockedAllDay }
        if !hasChanges { return .noChanges }
        if target.rule == draft { return .nicknameOnly }
        if Policy.classify(newRule: draft, against: target) == .tightening { return .tightening }
        return .loosening(Date.now.addingTimeInterval(model.state.config.loosenDelay))
    }

    private func effectBanner(for target: Target) -> some View {
        let (symbol, text, color): (String, String, Color) = switch effect(for: target) {
        case .noChanges: ("checkmark.circle", "No changes.", Ember.faint)
        case .nicknameOnly: ("textformat", "Only the name changes; that is instant.", Ember.muted)
        case .tightening: ("bolt.fill", "Tighter than now, so it applies the moment you save.", Ember.moss)
        case .loosening(let date): ("clock", "This loosens your rules. It takes effect \(date.formatted(date: .abbreviated, time: .shortened)); until then the current rule holds.", Ember.pending)
        case .blockedAllDay: ("lock.fill", "No windows means blocked all day.", Ember.muted)
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
        var windows = rule.sortedWindows
        budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
        if windows.isEmpty, target.rule == nil {
            windows = [TimeWindow(startMinute: 20 * 60, endMinute: 22 * 60)]
        }
        drafts = windows.map { DraftWindow(window: $0) }
        byDay = !rule.isSameEveryDay
    }

    private func adopt(_ rule: Rule) {
        withAnimation(.snappy) {
            drafts = rule.sortedWindows.map { DraftWindow(window: $0) }
            budget = rule.dailyBudgetMinutes > 0 ? rule.dailyBudgetMinutes : Furlough.defaultBudgetMinutes
            byDay = !rule.isSameEveryDay
        }
    }

    private func addWindow() {
        var start = windows.map(\.endMinute).max() ?? 12 * 60
        if start > Furlough.minutesPerDay - 60 { start = 0 }
        let window = TimeWindow(startMinute: start, endMinute: min(start + 60, Furlough.minutesPerDay))
        withAnimation(.snappy) { drafts.append(DraftWindow(window: window)) }
    }

    private func save() {
        drafts = DraftWindow.joined(drafts)
        result = model.propose(rule: draft, nickname: nickname, for: targetID)
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
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Weekdays.ordered(calendar: calendar), id: \.self) { weekday in
                let on = days.contains(weekday: weekday)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { days.toggle(weekday: weekday) }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(EmberFont.label(10))
                        .foregroundStyle(on ? Ember.ground : Ember.faint)
                        .frame(width: 24, height: 24)
                        .background(on ? Ember.amber : Color.white.opacity(0.07), in: Circle())
                        .overlay(Circle().strokeBorder(on ? Color.clear : Ember.cardBorder, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(calendar.standaloneWeekdaySymbols[weekday - 1])
            }
            Spacer(minLength: 6)
            Text(days.isEmpty ? "No days" : TimeFormat.days(days, calendar: calendar))
                .emberBody(10.5)
                .foregroundStyle(days.isEmpty ? Ember.ember : Ember.faint)
                .lineLimit(1)
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
