import SwiftUI

/// The week, and the day behind it. `WeekDraft` is in `Shared/Core` and the grid, the blocks and
/// the day bar are in `Shared/UI`, so this draws and edits exactly the same picture the phone
/// does; what is left here is this platform's chrome and its list of pickers.
struct WeekSheet: View {
    @Binding var week: WeekDraft
    @State private var selectedDay: Int?
    private let calendar = Calendar.current

    var body: some View {
        SheetFrame(title: selectedDay.map { calendar.standaloneWeekdaySymbols[$0 - 1] } ?? "Week", width: 600, height: 680) {
            if let weekday = selectedDay {
                DayEditor(week: $week, weekday: weekday) { selectedDay = nil }
                    .id(weekday)
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WeekGrid(
                    week: $week,
                    today: Policy.weekday(.now),
                    metrics: WeekMetrics(hourHeight: 17, gutter: 44)
                ) { selectedDay = $0 }
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .emberCard()
                Footnote(text: help, alignment: .center)
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
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    /// With no windows anywhere the grid is a picture of an open week, not seven blocks to drag:
    /// see `WeekGrid`. So the line underneath points at the only thing that can start one.
    private var help: String {
        week.isAllDay
            ? "Click a day's name to give it its first window."
            : "Drag a window to move it, its edges to resize. Click empty track to add one, a day's name for exact times."
    }

    private var summary: String {
        let windows = week.windows
        guard !windows.isEmpty else { return "No windows. Open all day, every day, up to the budget." }
        return TimeFormat.schedule(Rule(windows: windows)).replacingOccurrences(of: " · ", with: "\n")
    }
}

struct DayEditor: View {
    @Binding var week: WeekDraft
    let weekday: Int
    let onBack: () -> Void
    @State private var rows: [MacRuleEditor.DraftWindow] = []
    @State private var loaded = false
    @State private var applyTo: Weekdays = []
    @State private var appliedNote: String?
    private let calendar = Calendar.current

    private var windows: [TimeWindow] { rows.map(\.window) }
    private var error: String? { Rule(windows: windows).validationError }
    private var name: String { calendar.standaloneWeekdaySymbols[weekday - 1] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text("Week").emberBody(12.5, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
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
                            WindowRow(window: $row.window, onRemove: { remove(row) })
                            CardDivider()
                        }
                        CardAction(title: "Add window", symbol: "plus") { addWindow() }
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
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: load)
        .onChange(of: windows) { _, _ in sync() }
    }

    private var applyTitle: String {
        applyTo.isEmpty ? "Apply to other days" : "Apply to \(TimeFormat.days(applyTo, calendar: calendar))"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        rows = week.spans(on: weekday).map { MacRuleEditor.DraftWindow(window: $0) }
    }

    private func addWindow() {
        guard let window = TimeWindow.nextFree(after: windows, on: .all) else { return }
        withAnimation(.snappy) {
            rows = MacRuleEditor.DraftWindow.sorted(rows + [MacRuleEditor.DraftWindow(window: window)])
        }
    }

    private func remove(_ row: MacRuleEditor.DraftWindow) {
        withAnimation(.snappy) { rows.removeAll { $0.id == row.id } }
    }

    private func sync() {
        week.set(windows, on: weekday)
        appliedNote = nil
    }

    private func apply() {
        let days = applyTo
        withAnimation(.snappy) { rows = MacRuleEditor.DraftWindow.tidy(rows) }
        week.set(windows, on: weekday)
        week.apply(from: weekday, to: days)
        applyTo = []
        appliedNote = "\(TimeFormat.days(days, calendar: calendar)) now \(days.count == 1 ? "has" : "have") \(name)'s hours too."
    }
}
