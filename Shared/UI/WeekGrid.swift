import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The map between a minute of the day and a point down a day column. One type rather than the
/// same division written at six call sites, so a mark that is not a window — the Anchor's drop,
/// one day — can be drawn against the same grid without deriving it again.
struct WeekMetrics: Equatable {
    /// The phone draws 19, the Mac 17; each keeps the height its sheet was laid out around.
    var hourHeight: CGFloat
    var gutter: CGFloat

    var height: CGFloat { 24 * hourHeight }

    func y(ofMinute minute: Int) -> CGFloat { CGFloat(minute) / 60 * hourHeight }

    func minute(atY y: CGFloat) -> Int {
        let minute = Int((y / hourHeight * 60).rounded())
        return min(Furlough.minutesPerDay, max(0, minute))
    }

    /// A quarter-hour window is under five points tall, so there is a floor: something has to be
    /// visible and grabbable even at the shortest a window may be.
    func height(of span: TimeWindow) -> CGFloat {
        max(4, CGFloat(span.durationMinutes) / 60 * hourHeight)
    }
}

/// Where in a block the pointer is. The bands at the top and bottom resize, the middle moves; a
/// block too short to print its own times is all middle, and the day's list of pickers is where
/// one that small gets resized.
enum WindowGrab {
    case move, start, end

    static let edgeFloor: CGFloat = 24

    static func at(y: CGFloat, height: CGFloat) -> WindowGrab {
        guard height >= edgeFloor else { return .move }
        let edge = min(9, height / 3)
        if y <= edge { return .start }
        if y >= height - edge { return .end }
        return .move
    }
}

/// The week as seven 24-hour columns, and — unless it is only a picture — the place the windows
/// are edited: drag a block to move it inside its day, drag an edge to resize it, tap empty
/// track to add one. Every edit is written back through `WeekDraft.set(_:on:)`, so joining and
/// the merge into windows happen in the one place that already knew how, and the sentence the
/// sheet prints underneath rewrites itself as the block moves.
///
/// A block never leaves the column it was grabbed in. A window belongs to the days it applies
/// to, and the block drawn on Wednesday may be one face of a window that also runs Monday and
/// Tuesday; dragging it sideways would have to split that window silently. "Apply to other
/// days" in the day's editor is the named, additive way to reach another day.
struct WeekGrid: View {
    @Binding var week: WeekDraft
    let today: Int
    var metrics: WeekMetrics
    /// Off where the grid is only a picture. It is also ignored while the rule has no windows
    /// at all: every column then draws one all-day block that is not in the model, and dragging
    /// that would invent a window on one day and silently block the other six.
    var isEditable = true
    let onSelect: (Int) -> Void

    @State private var drag: Drag?
    private let calendar = Calendar.current

    /// Nothing moves until the finger has: a still finger belongs to the context menu.
    private static let slop: CGFloat = 2

    private struct Drag {
        var weekday: Int
        var index: Int
        var grab: WindowGrab
        /// The span as it was when the drag began, and the day around it. Every frame is
        /// computed from these plus the total translation, so a drag cannot accumulate drift.
        var origin: TimeWindow
        var base: [TimeWindow]
        /// The day as it is being drawn, before `set` joins anything: a block keeps its identity
        /// under the finger even when it lands flush against its neighbour.
        var spans: [TimeWindow]
        var moved = false
    }

    private var isLive: Bool { isEditable && !week.isAllDay }

    var body: some View {
        let ordered = Weekdays.ordered(calendar: calendar)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Color.clear.frame(width: metrics.gutter, height: 1)
                ForEach(ordered, id: \.self) { weekday in
                    DayHeader(
                        short: calendar.shortStandaloneWeekdaySymbols[weekday - 1].uppercased(),
                        name: calendar.standaloneWeekdaySymbols[weekday - 1],
                        hours: accessibilityValue(for: weekday),
                        isToday: weekday == today,
                        onAdd: isLive ? { addInFirstGap(on: weekday) } : nil
                    ) { onSelect(weekday) }
                }
            }
            HStack(alignment: .top, spacing: 0) {
                hourLabels
                    .frame(width: metrics.gutter, height: metrics.height, alignment: .topLeading)
                ZStack(alignment: .top) {
                    hourLines
                    HStack(spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element) { index, weekday in
                            if index > 0 {
                                Rectangle().fill(Ember.cardBorder).frame(width: 1)
                            }
                            DayColumn(
                                spans: shown(on: weekday),
                                metrics: metrics,
                                isToday: weekday == today,
                                edits: isLive ? edits(for: weekday) : nil
                            )
                        }
                    }
                }
                .frame(height: metrics.height)
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: snappedSpan) { _, _ in drag?.moved == true }
        #endif
    }

    /// The dragged day is drawn from the drag's own working copy; every other day from the draft.
    private func shown(on weekday: Int) -> [TimeWindow] {
        if let drag, drag.weekday == weekday { return drag.spans }
        return week.isAllDay ? [Rule.allDay] : week.spans(on: weekday)
    }

    /// What the haptic ticks on: the dragged span, which only changes on a snap.
    private var snappedSpan: TimeWindow? {
        guard let drag, drag.spans.indices.contains(drag.index) else { return nil }
        return drag.spans[drag.index]
    }

    private func edits(for weekday: Int) -> DayEdits {
        DayEdits(
            name: calendar.standaloneWeekdaySymbols[weekday - 1],
            dragging: drag?.weekday == weekday ? drag?.index : nil,
            onDrag: { index, startY, height, translation in
                self.dragged(on: weekday, index: index, startY: startY, height: height, by: translation)
            },
            onDrop: { index, startY, height, translation in
                self.dropped(on: weekday, index: index, startY: startY, height: height, by: translation)
            },
            onNudge: { index, minutes, resizing in
                self.nudge(on: weekday, index: index, by: minutes, resizing: resizing)
            },
            onRemove: { index in self.remove(on: weekday, index: index) },
            onAdd: { minute in self.add(on: weekday, at: minute) },
            onOpen: { onSelect(weekday) }
        )
    }

    // MARK: The gestures

    private func dragged(on weekday: Int, index: Int, startY: CGFloat, height: CGFloat, by translation: CGFloat) {
        // A fresh grab, which is any change before the finger has actually moved: where in the
        // block it went down decides move or resize, and the day is captured before anything is
        // written to it. Re-reading it while nothing has moved is what recovers from a gesture
        // the context menu took over.
        if drag == nil || !(drag?.weekday == weekday && drag?.index == index && drag?.moved == true) {
            let spans = week.spans(on: weekday)
            guard spans.indices.contains(index) else { return }
            drag = Drag(
                weekday: weekday,
                index: index,
                grab: WindowGrab.at(y: startY, height: height),
                origin: spans[index],
                base: spans,
                spans: spans
            )
        }
        guard var current = drag, abs(translation) >= Self.slop else { return }
        let minutes = Int((translation / metrics.hourHeight * 60).rounded())
        switch current.grab {
        case .move:
            current.spans = WeekDraft.moved(current.base, at: index, startingAt: current.origin.startMinute + minutes)
        case .start:
            current.spans = WeekDraft.resized(current.base, at: index, startTo: current.origin.startMinute + minutes)
        case .end:
            current.spans = WeekDraft.resized(current.base, at: index, endTo: current.origin.endMinute + minutes)
        }
        current.moved = true
        drag = current
        week.set(current.spans, on: weekday)
    }

    /// The last place the finger was is only ever reported here — the change before a lift is
    /// routinely dropped — so the end of a drag is run through the same arithmetic before it is
    /// let go, or a block lands a step short of where it was left.
    ///
    /// A press that never moved is a tap, and a tap on a window opens the day it is in, where
    /// the pickers say the exact minute the grid can only draw.
    private func dropped(on weekday: Int, index: Int, startY: CGFloat, height: CGFloat, by translation: CGFloat) {
        dragged(on: weekday, index: index, startY: startY, height: height, by: translation)
        let moved = drag?.moved == true
        drag = nil
        if !moved { onSelect(weekday) }
    }

    private func nudge(on weekday: Int, index: Int, by minutes: Int, resizing: Bool) {
        let spans = week.spans(on: weekday)
        guard spans.indices.contains(index) else { return }
        week.set(
            resizing
                ? WeekDraft.resized(spans, at: index, endTo: spans[index].endMinute + minutes)
                : WeekDraft.moved(spans, at: index, startingAt: spans[index].startMinute + minutes),
            on: weekday
        )
    }

    private func remove(on weekday: Int, index: Int) {
        week.set(WeekDraft.removed(week.spans(on: weekday), at: index), on: weekday)
    }

    private func add(on weekday: Int, at minute: Int) {
        guard let added = WeekDraft.added(to: week.spans(on: weekday), at: minute) else { return }
        week.set(added, on: weekday)
    }

    /// The keyboard and VoiceOver route to a new window: the same next free slot the day's
    /// "Add window" button uses, since neither can point at a place on the track.
    private func addInFirstGap(on weekday: Int) {
        let spans = week.spans(on: weekday)
        guard let free = TimeWindow.nextFree(after: spans, on: .all) else { return }
        week.set(spans + [free], on: weekday)
    }

    // MARK: The frame

    private var hourLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: 0, through: 21, by: 3)), id: \.self) { hour in
                Text(TimeFormat.shortMinute(hour * 60))
                    .font(EmberFont.numerals(8.5))
                    .foregroundStyle(Ember.faint)
                    .lineLimit(1)
                    .frame(width: metrics.gutter - 8, alignment: .trailing)
                    .offset(y: CGFloat(hour) * metrics.hourHeight - 5)
            }
        }
    }

    private var hourLines: some View {
        ZStack(alignment: .top) {
            ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { hour in
                Rectangle()
                    .fill(Ember.cardBorder)
                    .frame(height: 1)
                    .offset(y: CGFloat(hour) * metrics.hourHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func accessibilityValue(for weekday: Int) -> String {
        if week.isAllDay { return "All day" }
        let spans = week.spans(on: weekday)
        guard !spans.isEmpty else { return "No windows" }
        return spans.map { TimeFormat.window($0) }.joined(separator: ", ")
    }
}

/// The day's name, and the way into its list of pickers now that the column itself is a drawing
/// surface. It also carries what the column used to say to VoiceOver — a schedule has to stay
/// readable to someone who will never drag anything.
struct DayHeader: View {
    let short: String
    let name: String
    let hours: String
    let isToday: Bool
    /// Nil where the grid is only a picture.
    var onAdd: (() -> Void)?
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            Text(short)
                .font(EmberFont.label(9.5))
                .tracking(0.08 * 9.5)
                .foregroundStyle(isToday ? Ember.amber : Ember.faint)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.07 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(name)
        .accessibilityValue(hours)
        .accessibilityHint("Opens the day's exact times")
        .accessibilityAction(named: "Add a window") { onAdd?() }
    }
}

/// What a live column may do to the day it draws. Nil where the grid is only a picture; the
/// grid itself owns the one drag in flight, so these hand it back the raw gesture.
struct DayEdits {
    /// The day said in full, for VoiceOver: "Wednesday".
    let name: String
    /// Which block is under the finger, so it can be drawn lifted.
    let dragging: Int?
    let onDrag: (_ index: Int, _ startY: CGFloat, _ height: CGFloat, _ translation: CGFloat) -> Void
    let onDrop: (_ index: Int, _ startY: CGFloat, _ height: CGFloat, _ translation: CGFloat) -> Void
    let onNudge: (_ index: Int, _ minutes: Int, _ resizing: Bool) -> Void
    let onRemove: (_ index: Int) -> Void
    let onAdd: (_ minute: Int) -> Void
    let onOpen: () -> Void
}

struct DayColumn: View {
    let spans: [TimeWindow]
    let metrics: WeekMetrics
    let isToday: Bool
    var edits: DayEdits?

    /// The column is what a drag is measured against, and the one per instance is what keeps
    /// seven of them apart. Measuring against the block itself does not work: its space travels
    /// with it, so every frame subtracts the distance already moved from the distance to move
    /// and the block creeps to half of where the finger is.
    @State private var space = UUID()

    #if os(macOS)
    @FocusState private var focused: Int?
    #endif

    var body: some View {
        ZStack(alignment: .top) {
            (isToday ? Ember.amber.opacity(0.07) : Color.clear)
            ForEach(Array(spans.enumerated()), id: \.offset) { index, span in
                block(index, span)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .coordinateSpace(.named(space))
        // Empty track adds one. On the tap rather than a long press: a press is invisible, and
        // a sheet this size does not scroll under the finger the way a page does, which is the
        // only thing the press would have protected against.
        .gesture(
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded { value in edits?.onAdd(metrics.minute(atY: value.location.y)) },
            including: edits == nil ? .none : .all
        )
        .accessibilityHidden(edits == nil)
    }

    /// Placed by padding above it rather than by `offset`, which moves what is drawn and leaves
    /// the block's own coordinate space at the top of the column — so a gesture attached to it
    /// reads a grab near the top of a late-evening block as one at its bottom edge. The padding
    /// is not hit-tested, so empty track above a window still belongs to the column.
    @ViewBuilder
    private func block(_ index: Int, _ span: TimeWindow) -> some View {
        let height = metrics.height(of: span)
        let top = metrics.y(ofMinute: span.startMinute)
        let drawn = WindowBlock(span: span, height: height, isLifted: edits?.dragging == index, isLive: edits != nil)
            .frame(height: height)
        if let edits {
            keyboard(
                drawn
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                            .onChanged { value in
                                edits.onDrag(index, value.startLocation.y - top, height, value.translation.height)
                            }
                            .onEnded { value in
                                edits.onDrop(index, value.startLocation.y - top, height, value.translation.height)
                            }
                    )
                    .contextMenu {
                        Button("Open \(edits.name)") { edits.onOpen() }
                        Button("Remove window", role: .destructive) { edits.onRemove(index) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Window on \(edits.name)")
                    .accessibilityValue(TimeFormat.span(span))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: edits.onNudge(index, WeekDraft.snapMinutes, false)
                        case .decrement: edits.onNudge(index, -WeekDraft.snapMinutes, false)
                        @unknown default: break
                        }
                    }
                    .accessibilityAction(named: "Remove window") { edits.onRemove(index) }
                    .accessibilityAction(named: "Open \(edits.name)") { edits.onOpen() },
                index: index,
                edits: edits
            )
            .padding(.top, metrics.y(ofMinute: span.startMinute))
        } else {
            drawn.padding(.top, metrics.y(ofMinute: span.startMinute))
        }
    }

    /// Arrow keys move a focused block by a quarter hour, shift-arrows resize it from the
    /// bottom, delete removes it. The Mac only: the phone's block answers to the finger and to
    /// VoiceOver's adjustable action, and making it focusable there would put seven columns of
    /// blocks into a tab order nothing on the phone uses.
    @ViewBuilder
    private func keyboard(_ view: some View, index: Int, edits: DayEdits) -> some View {
        #if os(macOS)
        view
            .focusable()
            .focused($focused, equals: index)
            .onKeyPress(phases: .down) { press in
                let resizing = press.modifiers.contains(.shift)
                if press.key == .upArrow {
                    edits.onNudge(index, -WeekDraft.snapMinutes, resizing)
                } else if press.key == .downArrow {
                    edits.onNudge(index, WeekDraft.snapMinutes, resizing)
                } else if press.key == .delete || press.key == .deleteForward {
                    edits.onRemove(index)
                } else {
                    return .ignored
                }
                return .handled
            }
        #else
        view
        #endif
    }
}

struct WindowBlock: View {
    let span: TimeWindow
    let height: CGFloat
    var isLifted = false
    var isLive = false

    #if os(macOS)
    @State private var resizeCursor = false
    #endif

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Ember.amber.opacity(isLifted ? 1 : 0.92))
            .overlay(alignment: .top) {
                if height >= 24 { label(span.startMinute).padding(.top, 3) }
            }
            .overlay(alignment: .bottom) {
                if height >= 48 { label(span.endMinute).padding(.bottom, 3) }
            }
            .shadow(color: .black.opacity(isLifted ? 0.45 : 0), radius: isLifted ? 5 : 0, y: isLifted ? 2 : 0)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .cursor(isLive: isLive, height: height, wants: setCursor)
    }

    private func label(_ minute: Int) -> some View {
        Text(TimeFormat.shortMinute(minute))
            .font(EmberFont.numerals(8))
            .foregroundStyle(Ember.ground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
    }

    /// Pushed and popped in pairs, which is why the flag exists: an unbalanced pop would leave
    /// the whole app wearing the resize cursor.
    private func setCursor(_ wanted: Bool) {
        #if os(macOS)
        guard wanted != resizeCursor else { return }
        resizeCursor = wanted
        if wanted { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        #endif
    }
}

private extension View {
    /// The Mac has no touch, so an edge that resizes has to say so before it is grabbed.
    @ViewBuilder
    func cursor(isLive: Bool, height: CGFloat, wants: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        onContinuousHover { phase in
            switch phase {
            case .active(let point): wants(isLive && WindowGrab.at(y: point.y, height: height) != .move)
            case .ended: wants(false)
            @unknown default: wants(false)
            }
        }
        .onDisappear { wants(false) }
        #else
        self
        #endif
    }
}
