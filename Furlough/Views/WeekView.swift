import SwiftUI

/// The week, and the day behind it. `WeekDraft` is in `Shared/Core` and the grid, the blocks and
/// the day bar are in `Shared/UI`, so the Mac draws and edits exactly the same picture; what is
/// left here is this platform's chrome and its list of pickers.
struct WeekSheet: View {
    @Binding var week: WeekDraft
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WeekGrid(
                        week: $week,
                        today: Policy.weekday(.now),
                        metrics: WeekMetrics(hourHeight: 19, gutter: 40)
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

    /// With no windows anywhere the grid is a picture of an open week, not seven blocks to drag:
    /// see `WeekGrid`. So the line underneath points at the only thing that can start one.
    private var help: String {
        week.isAllDay
            ? "Tap a day's name to give it its first window."
            : "Drag a window to move it, its edges to resize. Tap empty track to add one, a day's name for exact times."
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

    /// No-op when the day is full; the new window stays unjoined until its times are edited.
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
