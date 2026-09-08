import SwiftUI

/// The editor's windows as seven per-day lists of spans: what the week grid draws and the
/// day editor changes. Each day's spans are joined wherever they overlap or touch. Going back
/// to windows merges identical spans across days into one window on all of those days, so
/// the editor's list stays as short as it can be.
struct WeekDraft: Equatable {
    private var spans: [Int: [TimeWindow]] = [:]

    init(windows: [TimeWindow]) {
        for weekday in 1...7 {
            spans[weekday] = TimeWindow.joined(windows.filter { $0.applies(on: weekday) }.map(\.span))
        }
    }

    func spans(on weekday: Int) -> [TimeWindow] { spans[weekday] ?? [] }

    /// No spans on any day: the rule is open all day, every day, up to the budget.
    var isAllDay: Bool { spans.values.allSatisfy(\.isEmpty) }

    mutating func set(_ hours: [TimeWindow], on weekday: Int) {
        spans[weekday] = TimeWindow.joined(hours.map(\.span))
    }

    /// Adds the hours of `source` to every day in `days`, on top of what each already had.
    mutating func apply(from source: Int, to days: Weekdays) {
        let hours = spans(on: source)
        for weekday in 1...7 where weekday != source && days.contains(weekday: weekday) {
            spans[weekday] = TimeWindow.joined(spans(on: weekday) + hours)
        }
    }

    /// One window per distinct span, on every day that has it.
    var windows: [TimeWindow] {
        var days: [TimeWindow: Weekdays] = [:]
        for weekday in 1...7 {
            for span in spans(on: weekday) {
                days[span, default: []].formUnion(Weekdays(weekday: weekday))
            }
        }
        return days
            .map { TimeWindow(startMinute: $0.key.startMinute, endMinute: $0.key.endMinute, days: $0.value) }
            .sorted()
    }
}

/// The week at a glance: seven columns on a 24-hour grid. Tap a day to see and change its hours.
struct WeekSheet: View {
    @Binding var week: WeekDraft
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WeekGrid(week: week, today: Policy.weekday(.now)) { selectedDay = $0 }
                        .padding(.horizontal, 8)
                        .padding(.top, 12)
                        .padding(.bottom, 14)
                        .emberCard()
                    Footnote(text: "Tap a day to see and change its hours.", alignment: .center)
                        .padding(.top, 8)
                    SectionLabel(text: "In words")
                    Text(summary)
                        .emberBody(12.5)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .emberCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedDay) { weekday in
                DayEditor(week: $week, weekday: weekday)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Week")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Ember.cream)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Ember.ground)
    }

    private var summary: String {
        let windows = week.windows
        guard !windows.isEmpty else { return "No windows. Open all day, every day, up to the budget." }
        return TimeFormat.schedule(Rule(windows: windows)).replacingOccurrences(of: " · ", with: "\n")
    }
}

/// Day initials across the top, hours down the side, one tappable column per day.
struct WeekGrid: View {
    let week: WeekDraft
    let today: Int
    let onSelect: (Int) -> Void
    private let hourHeight: CGFloat = 19
    private let gutter: CGFloat = 40
    private let calendar = Calendar.current
    private var gridHeight: CGFloat { 24 * hourHeight }

    var body: some View {
        let ordered = Weekdays.ordered(calendar: calendar)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 1)
                ForEach(ordered, id: \.self) { weekday in
                    Text(calendar.shortStandaloneWeekdaySymbols[weekday - 1].uppercased())
                        .font(EmberFont.label(9.5))
                        .tracking(0.08 * 9.5)
                        .foregroundStyle(weekday == today ? Ember.amber : Ember.faint)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                hourLabels
                    .frame(width: gutter, height: gridHeight, alignment: .topLeading)
                ZStack(alignment: .top) {
                    hourLines
                    HStack(spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element) { index, weekday in
                            if index > 0 {
                                Rectangle().fill(Ember.cardBorder).frame(width: 1)
                            }
                            Button {
                                onSelect(weekday)
                            } label: {
                                DayColumn(
                                    spans: week.isAllDay ? [Rule.allDay] : week.spans(on: weekday),
                                    hourHeight: hourHeight,
                                    isToday: weekday == today
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                            .accessibilityValue(accessibilityValue(for: weekday))
                        }
                    }
                }
                .frame(height: gridHeight)
            }
        }
    }

    /// Each label centred on its hour line, right-aligned with a gap before the columns.
    private var hourLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: 0, through: 21, by: 3)), id: \.self) { hour in
                Text(TimeFormat.shortMinute(hour * 60))
                    .font(EmberFont.numerals(8.5))
                    .foregroundStyle(Ember.faint)
                    .lineLimit(1)
                    .frame(width: gutter - 8, alignment: .trailing)
                    .offset(y: CGFloat(hour) * hourHeight - 5)
            }
        }
    }

    private var hourLines: some View {
        ZStack(alignment: .top) {
            ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                Rectangle()
                    .fill(Ember.cardBorder)
                    .frame(height: 1)
                    .offset(y: CGFloat(hour) * hourHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func accessibilityValue(for weekday: Int) -> String {
        if week.isAllDay { return "All day" }
        let spans = week.spans(on: weekday)
        guard !spans.isEmpty else { return "No windows" }
        return spans.map(TimeFormat.window).joined(separator: ", ")
    }
}

/// One day of the grid: a faint tint when it is today, and an amber block per window.
struct DayColumn: View {
    let spans: [TimeWindow]
    let hourHeight: CGFloat
    let isToday: Bool

    var body: some View {
        ZStack(alignment: .top) {
            (isToday ? Ember.amber.opacity(0.07) : Color.clear)
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                let height = max(4, CGFloat(span.durationMinutes) / 60 * hourHeight)
                WindowBlock(span: span, height: height)
                    .frame(height: height)
                    .offset(y: CGFloat(span.startMinute) / 60 * hourHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// An amber block with its start at the top and, when tall enough, its end at the bottom.
struct WindowBlock: View {
    let span: TimeWindow
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Ember.amber.opacity(0.92))
            .overlay(alignment: .top) {
                if height >= 24 { label(span.startMinute).padding(.top, 3) }
            }
            .overlay(alignment: .bottom) {
                if height >= 48 { label(span.endMinute).padding(.bottom, 3) }
            }
            .padding(.horizontal, 2)
    }

    private func label(_ minute: Int) -> some View {
        Text(TimeFormat.shortMinute(minute))
            .font(EmberFont.numerals(8))
            .foregroundStyle(Ember.ground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
    }
}

/// One day's hours: a 24-hour bar, the editable windows, and "apply to other days".
struct DayEditor: View {
    @Binding var week: WeekDraft
    let weekday: Int
    @State private var rows: [RuleEditorView.DraftWindow] = []
    @State private var loaded = false
    @State private var applyTo: Weekdays = []
    @State private var appliedNote: String?
    @State private var applied = 0
    private let calendar = Calendar.current

    private var windows: [TimeWindow] { rows.map(\.window) }
    private var error: String? { Rule(windows: windows).validationError }
    private var name: String { calendar.standaloneWeekdaySymbols[weekday - 1] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DayBar(spans: week.isAllDay ? [Rule.allDay] : TimeWindow.joined(windows))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .emberCard()
                SectionLabel(text: "Windows on \(name)")
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(week.isAllDay
                            ? "No windows on any day, so \(name) is open all day, up to the budget. Add one here and the other days are blocked until they get their own."
                            : "No windows. \(name) is blocked all day.")
                            .fixedSize(horizontal: false, vertical: true)
                            .emberBody(13)
                            .foregroundStyle(Ember.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                        CardDivider()
                    }
                    ForEach($rows) { $row in
                        WindowRow(window: $row.window, onCommit: commit, onRemove: { remove(row) })
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
                if let error {
                    Text(error)
                        .emberBody(11.5, .semibold)
                        .foregroundStyle(Ember.ember)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                }
                SectionLabel(text: "Apply to other days")
                DayStrip(days: $applyTo, locked: Weekdays(weekday: weekday), placeholder: "Choose days")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .emberCard()
                ProminentButton(title: applyTitle) { apply() }
                    .disabled(applyTo.isEmpty || error != nil)
                    .padding(.top, 10)
                Footnote(text: appliedNote ?? "Adds \(name)'s hours to those days, on top of what they have.", alignment: .center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .background(EmberWall())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(name)
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
        }
        .onAppear(perform: load)
        .sensoryFeedback(.success, trigger: applied)
    }

    private var applyTitle: String {
        applyTo.isEmpty ? "Apply to other days" : "Apply to \(TimeFormat.days(applyTo, calendar: calendar))"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        rows = week.spans(on: weekday).map { RuleEditorView.DraftWindow(window: $0) }
    }

    /// A new row where the day has room, slotted into time order and left unjoined until its
    /// times are set. Nothing is added when the day is full.
    private func addWindow() {
        guard let window = TimeWindow.nextFree(after: windows, on: .all) else { return }
        withAnimation(.snappy) {
            rows = RuleEditorView.DraftWindow.sorted(rows + [RuleEditorView.DraftWindow(window: window)])
        }
        sync()
    }

    /// After a time edit: rows that now overlap or touch become one, in order, then the week is updated.
    private func commit() {
        withAnimation(.snappy) { rows = RuleEditorView.DraftWindow.tidy(rows) }
        sync()
    }

    private func remove(_ row: RuleEditorView.DraftWindow) {
        withAnimation(.snappy) { rows.removeAll { $0.id == row.id } }
        sync()
    }

    private func sync() {
        week.set(windows, on: weekday)
        appliedNote = nil
    }

    private func apply() {
        let days = applyTo
        week.set(windows, on: weekday)
        week.apply(from: weekday, to: days)
        applied += 1
        applyTo = []
        appliedNote = "\(TimeFormat.days(days, calendar: calendar)) now \(days.count == 1 ? "has" : "have") \(name)'s hours too."
    }
}

/// A horizontal 24-hour bar with an amber segment per window and ticks at 6, 12 and 18.
struct DayBar: View {
    let spans: [TimeWindow]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    ForEach([6, 12, 18], id: \.self) { hour in
                        Rectangle()
                            .fill(Ember.cardBorder)
                            .frame(width: 1)
                            .offset(x: CGFloat(hour) / 24 * width)
                    }
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Ember.amber.opacity(0.92))
                            .frame(width: max(2, CGFloat(span.durationMinutes) / CGFloat(Furlough.minutesPerDay) * width))
                            .offset(x: CGFloat(span.startMinute) / CGFloat(Furlough.minutesPerDay) * width)
                    }
                }
            }
            .frame(height: 26)
            GeometryReader { geo in
                ForEach([6, 12, 18], id: \.self) { hour in
                    Text(TimeFormat.shortMinute(hour * 60))
                        .font(EmberFont.numerals(9))
                        .foregroundStyle(Ember.faint)
                        .position(x: CGFloat(hour) / 24 * geo.size.width, y: 6)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement()
        .accessibilityLabel("Hours")
        .accessibilityValue(spans.isEmpty ? "No windows" : spans.map(TimeFormat.window).joined(separator: ", "))
    }
}
