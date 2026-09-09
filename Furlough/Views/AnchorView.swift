import FamilyControls
import SwiftUI

enum AnchorRoute: Hashable {
    case editor
}

/// The Anchor profile: apps locked behind a physical tag. Anchor from here or from the home
/// card; weigh anchor only by scanning one of the paired tags.
struct AnchorView: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var showFromRules = false
    /// The rules sheet was left for Apple's picker, which opens once the sheet is gone.
    @State private var pickerAfterSheet = false
    @State private var message: String?
    @State private var forgetting: PairedTag?
    @State private var renaming: PairedTag?
    @State private var draftName = ""
    /// The scope tapped while the list still holds something, waiting on a confirmation:
    /// switching starts the list again, and a curated list is worth a second look first.
    @State private var switchingTo: AnchorProfile.Scope?
    /// A drop made from here lifts by itself at `liftMinute`. Off, the tag is the only way
    /// back, as ever. Not stored: it is how the next drop is made, not a setting.
    @State private var liftsBySelf = false
    @State private var liftMinute = 18 * 60
    @State private var pickingLift = false
    @State private var editingSchedule = false

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var anchorCaution: (text: String, isSevere: Bool)? { model.anchorCaution }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                stateCard
                if !anchor.isAnchored {
                    timedCard
                        .padding(.top, 10)
                }
                SectionLabel(text: "Scope")
                scopeCard
                SectionLabel(text: anchor.anchorsEverything ? "Stays open" : "Apps")
                appsCard
                if let caution = anchorCaution {
                    CautionBanner(text: caution.text, isSevere: caution.isSevere)
                        .padding(.top, 12)
                }
                Footnote(text: listFootnote)
                    .padding(.top, 8)
                SectionLabel(text: "Schedule")
                scheduleCard
                Footnote(text: scheduleFootnote)
                    .padding(.top, 8)
                SectionLabel(text: "Tags")
                tagCard
                Footnote(text: tagFootnote)
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
                Text("Anchor")
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
        }
        .familyActivityPicker(
            headerText: anchor.anchorsEverything ? "Choose what stays open while anchored" : "Choose what the anchor holds",
            footerText: anchor.anchorsEverything ? "Picking a category keeps every app in it open." : "Picking a category locks every app in it.",
            isPresented: $showPicker,
            selection: $selection
        )
        .onChange(of: showPicker) { _, presented in
            guard !presented else { return }
            model.setAnchorSelection(selection)
        }
        .sheet(isPresented: $pickingLift) {
            TimePickerSheet(title: "Lifts at", minute: $liftMinute)
        }
        .sheet(isPresented: $editingSchedule) {
            AnchorScheduleSheet(schedules: anchor.schedules)
        }
        .sheet(isPresented: $showFromRules, onDismiss: {
            guard pickerAfterSheet else { return }
            pickerAfterSheet = false
            openPicker()
        }) {
            AnchorFromRulesSheet(candidates: model.state.config.anchorCandidates) { ids in
                model.addToAnchor(targetIDs: ids)
            } onPickOthers: {
                pickerAfterSheet = true
            }
        }
        .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Start the list again?",
            isPresented: Binding(get: { switchingTo != nil }, set: { if !$0 { switchingTo = nil } }),
            titleVisibility: .visible
        ) {
            Button(switchingTo == .everythingExcept ? "Anchor everything except a list" : "Anchor chosen apps only") {
                if let scope = switchingTo { model.setAnchorScope(scope) }
                switchingTo = nil
            }
            Button("Keep it as it is", role: .cancel) { switchingTo = nil }
        } message: {
            Text(switchingTo == .everythingExcept
                ? "The list becomes what stays open, starting from every app you tiered Essential. What it holds now is not carried over."
                : "The list becomes what is held, starting empty. What you already block is offered first.")
        }
        .confirmationDialog(
            "Forget this tag?",
            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget \(forgetting?.name ?? "tag")", role: .destructive) {
                if let tag = forgetting { model.unpairTag(id: tag.id) }
                forgetting = nil
            }
            Button("Keep it", role: .cancel) { forgetting = nil }
        } message: {
            Text(anchor.tags.count == 1
                ? "This is the last key. Anchoring is refused until you pair another."
                : "The other tags still release the anchor.")
        }
        .alert(
            "Name this tag",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Home", text: $draftName)
            Button("Save") {
                if let tag = renaming { model.renameTag(id: tag.id, to: draftName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Name it for the place it lives in, so you know which key you are looking for.")
        }
    }

    private var tagFootnote: String {
        let cap = "Up to \(Furlough.maxAnchorTags), so a key can live at each place you do."
        return "Anchoring works without a tag. Weighing anchor needs one, so keep every tag somewhere that makes you think. \(cap)"
    }

    private var listFootnote: String {
        if anchor.isAnchored { return "Unanchor with your tag to change the list." }
        switch anchor.scope {
        case .chosen:
            return "Anything here is blocked while anchored. Windows and budgets still apply the rest of the time."
        case .everythingExcept:
            return "Everything not listed here is blocked while anchored. What is listed keeps its own windows and budget."
        }
    }

    /// How far the anchor reaches: the list, or the whole phone but the list. Locked while
    /// anchored along with everything else. The list does not survive a switch (see
    /// `AppModel.setAnchorScope`), so a list that holds anything asks first.
    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                scopeChip(.chosen, "Chosen apps")
                scopeChip(.everythingExcept, "Everything except")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Text(scopeSummary)
                .emberBody(12)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .emberCard()
    }

    private var scopeSummary: String {
        switch anchor.scope {
        case .chosen: "Only what is listed is held. Everything else keeps its own rules."
        case .everythingExcept: "Every app and website is held. Only what is listed stays open."
        }
    }

    private func scopeChip(_ scope: AnchorProfile.Scope, _ title: String) -> some View {
        let isOn = anchor.scope == scope
        return Button {
            guard !isOn else { return }
            if anchor.kinds.isEmpty { model.setAnchorScope(scope) } else { switchingTo = scope }
        } label: {
            Text(title)
                .emberBody(12, .semibold)
                .foregroundStyle(isOn ? Ember.ground : Ember.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? Ember.amber : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isOn ? .clear : Ember.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(anchor.isAnchored)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 12) {
            AnchorGlyph(isAnchored: anchor.isAnchored, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Anchor")
                    .emberDisplay(19)
                    .foregroundStyle(Ember.cream)
                Text("One tap to lock. The tag to unlock.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var stateCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: anchor.isAnchored ? "Anchored" : "Free", color: anchor.isAnchored ? Ember.ember : Ember.moss)
                Text(stateLine)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
            }
            Spacer(minLength: 8)
            AnchorToggleButton(until: timedUntil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .emberCard()
    }

    private var stateLine: String {
        let held = anchor.heldDescription
        if anchor.isAnchored, let since = anchor.anchoredAt {
            let lift = anchor.until.map { " · lifts \(TimeFormat.clock($0))" } ?? ""
            return "\(held) since \(since.formatted(date: .omitted, time: .shortened))\(lift)"
        }
        if anchor.scope == .chosen, anchor.kinds.isEmpty { return "Nothing chosen yet" }
        if !anchor.isPaired { return "\(held) · pair a tag to enable" }
        return "\(held) · ready"
    }

    /// The moment a drop made now would lift by itself: the chosen time later today, or
    /// tomorrow when it is already past or too close — the monitor cannot be woken for less
    /// than a quarter of an hour. Nil when the tag is the only way back.
    private var timedUntil: Date? {
        guard liftsBySelf else { return nil }
        let now = model.clock.now
        let soonest = now.addingTimeInterval(TimeInterval(Furlough.minimumWindowMinutes * 60))
        let today = Policy.date(atMinute: liftMinute, of: now)
        if today >= soonest { return today }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return Policy.date(atMinute: liftMinute, of: tomorrow)
    }

    /// Whether the next drop lifts by itself. Off, the tag is the only way back, as ever.
    private var timedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Lifts by itself")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer(minLength: 8)
                if liftsBySelf {
                    TimeChip(minute: liftMinute) { pickingLift = true }
                }
                Toggle("Lifts by itself", isOn: $liftsBySelf.animation(.snappy))
                    .labelsHidden()
                    .tint(Ember.ember)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Text(timedLine)
                .emberBody(11.5)
                .foregroundStyle(Ember.muted)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .emberCard()
    }

    private var timedLine: String {
        guard let until = timedUntil else { return "Only the tag lifts it." }
        let day = Calendar.current.isDateInToday(until) ? "today" : "tomorrow"
        return "Anchor lifts \(day) at \(TimeFormat.clock(until)), or sooner with the tag."
    }

    private var sortedSchedules: [AnchorSchedule] {
        anchor.schedules.sorted { ($0.minuteOfDay, $0.days.rawValue) < ($1.minuteOfDay, $1.days.rawValue) }
    }

    /// The drop times, and the way to change them while the anchor is off. Edited as one draft
    /// in `AnchorScheduleSheet`, because the whole set is classified at once.
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if anchor.schedules.isEmpty {
                Text("No scheduled drops.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            } else {
                ForEach(Array(sortedSchedules.enumerated()), id: \.element.id) { index, schedule in
                    if index > 0 { CardDivider() }
                    scheduleRow(schedule)
                }
            }
            if !anchor.isAnchored {
                CardDivider()
                Button {
                    editingSchedule = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: anchor.schedules.isEmpty ? "plus" : "clock")
                            .font(.system(size: 12, weight: .bold))
                        Text(anchor.schedules.isEmpty ? "Add a drop time" : "Change the schedule")
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
        }
        .emberCard()
    }

    private func scheduleRow(_ schedule: AnchorSchedule) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(TimeFormat.minute(schedule.minuteOfDay)) · \(TimeFormat.days(schedule.days))")
                    .emberBody(13)
                    .monospacedDigit()
                    .foregroundStyle(Ember.cream)
                Text(schedule.liftMinuteOfDay.map { "Lifts at \(TimeFormat.minute($0))" } ?? "Until the tag")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var scheduleFootnote: String {
        if anchor.isAnchored { return "Unanchor with your tag to change the schedule." }
        let rule = "Adding a time applies at once. Removing or shortening one waits out the delay, and can be cancelled from Pending until then."
        guard let next = anchor.schedules.nextDrop(after: model.clock.now) else {
            return "The anchor drops by itself at each time, on its days. \(rule)"
        }
        return "Next drop \(nextDropWords(next)). \(rule)"
    }

    /// "today at 10:00 PM", "tomorrow at 10:00 PM", "Monday at 10:00 PM".
    private func nextDropWords(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = TimeFormat.clock(date)
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)"
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if anchor.kinds.isEmpty {
                Text(anchor.anchorsEverything ? "Nothing stays open." : "No apps yet.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Array(anchor.kinds.enumerated()), id: \.offset) { _, kind in
                        TokenTile(kind: kind, size: 44)
                    }
                }
                .padding(12)
            }
            if !anchor.isAnchored {
                CardDivider()
                Button {
                    // An empty list starts from the rules: what Furlough already blocks is
                    // offered first, and Apple's picker, which lists every app on the phone,
                    // is one tap further on. Once the anchor holds anything, straight to the
                    // picker, filled in with the list. The offer is for the chosen scope only:
                    // under everything-except what is already blocked is already held, and
                    // the list is what stays open, so it goes straight to the picker too.
                    if anchor.scope == .chosen, anchor.kinds.isEmpty, !model.state.config.anchorCandidates.isEmpty {
                        showFromRules = true
                    } else {
                        openPicker()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(chooseTitle)
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
        }
        .emberCard()
    }

    private var tagCard: some View {
        VStack(spacing: 0) {
            if anchor.tags.isEmpty {
                HStack {
                    Text("None paired")
                        .emberBody(13)
                        .foregroundStyle(Ember.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            } else {
                ForEach(Array(anchor.tags.enumerated()), id: \.element.id) { index, tag in
                    if index > 0 { CardDivider() }
                    tagRow(tag)
                }
            }
            if !anchor.isAnchored {
                CardDivider()
                if anchor.canPairMore {
                    Button {
                        Task { await pair() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wave.3.right")
                                .font(.system(size: 12, weight: .bold))
                            Text(anchor.isPaired ? "Pair another tag" : "Pair a tag")
                                .emberBody(13, .semibold)
                            Spacer(minLength: 8)
                            Text(tagCount)
                                .emberBody(11.5)
                                .monospacedDigit()
                                .foregroundStyle(Ember.muted)
                        }
                        .foregroundStyle(Ember.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text("\(tagCount) · forget one to pair another")
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
            }
        }
        .emberCard()
    }

    /// One key: what it is called, what it is, and the way to change either. Both controls are
    /// gone while anchored, like the app list above them.
    private func tagRow(_ tag: PairedTag) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Text(tagLabel(tag.id))
                    .emberBody(11)
                    .monospacedDigit()
                    .foregroundStyle(Ember.muted)
            }
            Spacer(minLength: 8)
            if !anchor.isAnchored {
                Button {
                    draftName = tag.name
                    renaming = tag
                } label: {
                    Text("Rename")
                        .emberBody(12, .semibold)
                        .foregroundStyle(Ember.ember)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    forgetting = tag
                } label: {
                    Text("Forget")
                        .emberBody(12, .semibold)
                        .foregroundStyle(Ember.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var tagCount: String { "\(anchor.tags.count) of \(Furlough.maxAnchorTags)" }

    private var chooseTitle: String {
        switch (anchor.scope, anchor.kinds.isEmpty) {
        case (.chosen, true): "Choose apps"
        case (.chosen, false): "Change apps"
        case (.everythingExcept, true): "Choose what stays open"
        case (.everythingExcept, false): "Change what stays open"
        }
    }

    private func openPicker() {
        selection = model.anchorSelection
        showPicker = true
    }

    private func pair() async {
        switch await model.pairTag() {
        // Straight into the name: an identifier's last four digits are not a place, and the
        // scan is done, so nothing is waiting on the typing.
        case .paired(let tag):
            draftName = ""
            renaming = tag
        case .failed(let reason): message = reason
        default: break
        }
    }

    private func tagLabel(_ id: Data) -> String {
        let hex = id.map { String(format: "%02X", $0) }.joined()
        return "…\(hex.suffix(4))"
    }
}

/// The Anchor's first offer, before Apple's picker: the apps and sites Furlough already blocks,
/// every one checked to start, with All / None and a row each to change that. Adding takes in
/// what is checked; "Choose from all apps instead" goes on to the picker. Shown while the
/// anchor holds nothing and something has a rule, so a list that starts empty starts with what
/// matters rather than with the whole phone.
struct AnchorFromRulesSheet: View {
    let candidates: [Target]
    let onAdd: ([UUID]) -> Void
    let onPickOthers: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>

    init(candidates: [Target], onAdd: @escaping ([UUID]) -> Void, onPickOthers: @escaping () -> Void) {
        self.candidates = candidates
        self.onAdd = onAdd
        self.onPickOthers = onPickOthers
        _selected = State(initialValue: Set(candidates.map(\.id)))
    }

    private var chosen: [Target] { candidates.filter { selected.contains($0.id) } }
    private var allChosen: Bool { selected.count == candidates.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Everything you already block. Anchored, each one is shut at any hour; free, it keeps its windows.")
                        .emberBody(13)
                        .foregroundStyle(Ember.muted)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
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
                    ProminentButton(title: buttonTitle) {
                        onAdd(chosen.map(\.id))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                    .padding(.top, 14)
                    GhostButton(title: "Choose from all apps instead", color: Ember.muted) {
                        onPickOthers()
                        dismiss()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Already blocked")
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

    private var summary: String {
        let count = chosen.count
        guard count > 0 else { return "Nothing chosen." }
        return "\(count) of \(candidates.count) will be held while anchored."
    }

    private var buttonTitle: String {
        let count = chosen.count
        guard count > 0 else { return "Add" }
        return "Add \(count) \(noun)"
    }

    /// What the chosen rows are, the way "Apply to 3 apps" says it: the app and site kinds
    /// have a word each, and a category in the mix makes the lot "items".
    private var noun: String {
        var apps = 0, sites = 0, other = 0
        for target in chosen {
            switch target.kind {
            case .application: apps += 1
            case .webDomain, .host: sites += 1
            case .category: other += 1
            }
        }
        let count = chosen.count
        return switch (apps, sites, other) {
        case (count, _, _): count == 1 ? "app" : "apps"
        case (_, count, _): count == 1 ? "site" : "sites"
        case (_, _, 0): "apps and sites"
        default: count == 1 ? "item" : "items"
        }
    }
}

/// Edits the anchor's drop times as one draft with one Save, the way a rule is edited,
/// because the whole set is classified at once: more drops or longer holds land now, fewer
/// or shorter ones queue behind the delay. The banner above Save says which before it happens.
struct AnchorScheduleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [AnchorSchedule]
    @State private var message: String?
    private let original: [AnchorSchedule]

    init(schedules: [AnchorSchedule]) {
        original = schedules
        _drafts = State(initialValue: schedules)
    }

    private var effect: EffectBanner.Kind {
        if drafts == original { return .noChanges }
        if drafts.contains(where: { $0.days.isEmpty }) { return .error("Each drop needs at least one day.") }
        if drafts.contains(where: { $0.liftMinuteOfDay == $0.minuteOfDay }) { return .error("A lift has to come after its drop.") }
        if let reason = ActivityLimit.reason(schedules: drafts, in: model.state) { return .error(reason) }
        switch Policy.classify(newSchedules: drafts, against: original) {
        case .tightening:
            return .tightening
        case .loosening:
            let hours = model.state.config.anchorDelayHours
            return .loosening(model.clock.now.addingTimeInterval(TimeInterval(hours) * 3600))
        }
    }

    private var canSave: Bool {
        switch effect {
        case .noChanges, .error: false
        default: true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("At each time, on its days, the anchor drops by itself. It holds until the tag, or until the lift you give it.")
                        .emberBody(13)
                        .foregroundStyle(Ember.muted)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    VStack(spacing: 0) {
                        if drafts.isEmpty {
                            Text("No drop times yet.")
                                .emberBody(13)
                                .foregroundStyle(Ember.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                        }
                        ForEach($drafts) { $draft in
                            ScheduleDraftRow(schedule: $draft) {
                                withAnimation(.snappy) { drafts.removeAll { $0.id == draft.id } }
                            }
                            CardDivider()
                        }
                        Button {
                            withAnimation(.snappy) {
                                drafts.append(AnchorSchedule(minuteOfDay: 22 * 60, days: .weekdays))
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Add a drop time")
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
                    EffectBanner(kind: effect)
                        .padding(.top, 12)
                    ProminentButton(title: "Save") { save() }
                        .disabled(!canSave)
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
                    Text("Schedule")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Ember.cream)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Ember.ground)
        .alert("Schedule", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {
                message = nil
                dismiss()
            }
        } message: {
            Text(message ?? "")
        }
    }

    private func save() {
        switch model.setAnchorSchedules(drafts) {
        case .unchanged, .appliedNow:
            dismiss()
        case .scheduled(let date):
            message = ProposalResult.scheduled(date).message
        }
    }
}

/// One drop time in the schedule editor: when, on which days, and whether it lifts by itself.
struct ScheduleDraftRow: View {
    @Binding var schedule: AnchorSchedule
    let onRemove: () -> Void
    @State private var editing: Edge?

    enum Edge: String, Identifiable {
        case drop, lift
        var id: String { rawValue }
    }

    private static let defaultLift = 7 * 60

    private var liftsBySelf: Binding<Bool> {
        Binding(
            get: { schedule.liftMinuteOfDay != nil },
            set: { on in schedule.liftMinuteOfDay = on ? (schedule.liftMinuteOfDay ?? Self.defaultLift) : nil }
        )
    }

    private var liftMinute: Binding<Int> {
        Binding(
            get: { schedule.liftMinuteOfDay ?? Self.defaultLift },
            set: { schedule.liftMinuteOfDay = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Drops at")
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                TimeChip(minute: schedule.minuteOfDay) { editing = .drop }
                Spacer(minLength: 8)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Ember.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove this drop time")
            }
            DayStrip(days: $schedule.days)
            HStack(spacing: 8) {
                Text("Lifts")
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                if let lift = schedule.liftMinuteOfDay {
                    TimeChip(minute: lift, nextDay: lift <= schedule.minuteOfDay) { editing = .lift }
                } else {
                    Text("with the tag")
                        .emberBody(12, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                Spacer(minLength: 8)
                Toggle("Lifts by itself", isOn: liftsBySelf.animation(.snappy))
                    .labelsHidden()
                    .tint(Ember.ember)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .sheet(item: $editing) { edge in
            TimePickerSheet(
                title: edge == .drop ? "Drops at" : "Lifts at",
                minute: edge == .drop ? $schedule.minuteOfDay : liftMinute,
                nextDayAfter: edge == .lift ? schedule.minuteOfDay : nil
            )
        }
    }
}

/// Anchor when free, Unanchor (scan the tag to release it) when anchored. Alerts explain a wrong tag or failure.
struct AnchorToggleButton: View {
    @Environment(AppModel.self) private var model
    /// When the drop made here lifts by itself; nil for the tag alone, which the home card
    /// always passes, since only the Anchor screen offers a time.
    var until: Date?
    @State private var busy = false
    @State private var message: String?
    @State private var confirmAnchor = false

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var caution: (text: String, isSevere: Bool)? { model.anchorCaution }

    var body: some View {
        Group {
            if anchor.isAnchored {
                Button {
                    Task { await unanchor() }
                } label: {
                    Label("Unanchor", systemImage: "wave.3.right")
                        .emberBody(13, .bold)
                        .foregroundStyle(Ember.cream)
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    if caution != nil { confirmAnchor = true } else { drop() }
                } label: {
                    Text("Anchor")
                        .emberBody(13, .bold)
                        .foregroundStyle(Ember.cream)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .disabled(!anchor.canAnchor)
            }
        }
        .disabled(busy)
        .confirmationDialog(
            "Anchor this?",
            isPresented: $confirmAnchor,
            titleVisibility: .visible
        ) {
            Button("Anchor anyway", role: .destructive) { drop() }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text(caution?.text ?? "")
        }
        .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func drop() {
        switch model.anchor(until: until) {
        case .failed(let reason): message = reason
        default: break
        }
    }

    private func unanchor() async {
        busy = true
        defer { busy = false }
        switch await model.unanchorWithTag() {
        case .wrongTag: message = "That is not a paired tag."
        case .failed(let reason): message = reason
        default: break
        }
    }
}

/// The home-screen entry to the Anchor profile, with its state and the Anchor / Unanchor button.
struct AnchorCard: View {
    let anchor: AnchorProfile

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: AnchorRoute.editor) {
                HStack(spacing: 10) {
                    AnchorGlyph(isAnchored: anchor.isAnchored, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Anchor")
                                .emberDisplaySmall(13.5)
                                .foregroundStyle(Ember.cream)
                            Eyebrow(text: anchor.isAnchored ? "Anchored" : "Free", color: anchor.isAnchored ? Ember.ember : Ember.moss, size: 9)
                        }
                        Text(subtitle)
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            AnchorToggleButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .emberCard()
    }

    /// "3 items · ready", or under the wider scope "Everything except 3 · since 6:12 PM".
    private var subtitle: String {
        let held = anchor.heldDescription
        if anchor.scope == .chosen, anchor.kinds.isEmpty { return "Tap to choose apps and pair a tag" }
        if !anchor.isPaired { return "\(held) · pair a tag to enable" }
        if anchor.isAnchored, let since = anchor.anchoredAt {
            let lift = anchor.until.map { " · lifts \(TimeFormat.clock($0))" } ?? ""
            return "\(held) · since \(since.formatted(date: .omitted, time: .shortened))\(lift)"
        }
        return "\(held) · ready"
    }
}

/// The anchor in a tile, ember while anchored.
struct AnchorGlyph: View {
    let isAnchored: Bool
    var size: CGFloat = 34

    var body: some View {
        let radius = size >= 44 ? Ember.tileRadiusLarge : Ember.tileRadius
        AnchorShape()
            .fill(isAnchored ? Ember.ember : Ember.muted)
            .frame(width: size * 0.52, height: size * 0.52)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: isAnchored ? Ember.ember.opacity(0.35) : .clear, radius: 10)
    }
}
