import SwiftUI

/// The Anchor: apps locked behind a physical tag. One of Home's two pages, beside Rules.
struct AnchorPage: View {
    /// Whether this is the page in front. A page-style `TabView` builds the adjacent page too,
    /// and this one can arm an NFC reader on sight, so only the current page should do so.
    /// Also gated by `AppModel.autoArmsReader`, a separate setting.
    let isCurrent: Bool
    let onChooseApps: () -> Void
    /// Opens a rule editor on the stack this page is in: the grid's way into the other half.
    let onOpenRule: (UUID) -> Void

    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var draftName = ""
    /// Whether the next drop lifts itself at `liftMinute`, rather than only by the tag.
    /// Not persisted — this only shapes the next drop.
    @State private var liftsBySelf = false
    @State private var liftMinute = 18 * 60
    @State private var pickingLift = false
    /// True while Apple's scan sheet is up, to keep a second reader from being armed under it.
    @State private var listening = false
    /// A paired tag was held up with the anchor off (which would lock it, not unlock). Held
    /// until confirmed, since that's a way to lock yourself out.
    @State private var droppingWithTag: PairedTag?
    @State private var pairingScanned: Data?

    @Environment(\.scenePhase) private var scenePhase

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var anchorCaution: (text: String, isSevere: Bool)? { model.anchorCaution }

    private var guide: HalfGuide {
        HalfGuide.anchor(config: model.state.config, finished: model.finishedGuides.contains(.anchor))
    }

    var body: some View {
        withPresentations(
            ScrollView {
                Group {
                    if guide.isRunning { guidePane } else { setUpPane }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 48)
            }
            // No wall or title of its own: Home draws the wall behind the pager, and the
            // toolbar segment already names this page.
            //
            // Keyed on `isCurrent` so a swipe onto this page arms the reader too, gated by
            // `AppModel.autoArmsReader` (off by default) so it doesn't surprise someone who
            // just came here to choose apps.
            .task(id: isCurrent) {
                guard isCurrent, model.autoArmsReader, anchor.isAnchored || anchor.canAnchor else { return }
                await listen()
            }
            // Core NFC reads for the foreground app only, and the sheet belongs to this page.
            // Swiping to the other half with it still up would hand the reader to nobody.
            .onChange(of: isCurrent) { _, current in
                if !current { model.stopReadingTags() }
            }
            .onDisappear { model.stopReadingTags() }
            // Backgrounding only: Apple's own scan sheet also takes the scene to `.inactive`,
            // which would cancel the reader the moment it's armed if handled there too.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.stopReadingTags() }
            }
            // Anchor is the last page, so a further swipe left has nowhere to go in the
            // TabView; simultaneous so it doesn't steal the page-back swipe toward Rules.
            // Rules -> swipe left -> Anchor -> swipe left -> the NFC sheet.
            .simultaneousGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        guard isCurrent, !listening, TagScanner.isAvailable else { return }
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard horizontal < -60, abs(horizontal) > abs(vertical) * 1.5 else { return }
                        Task { await listen() }
                    }
            )
        )
    }

    private var guidePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.cloudAvailable {
                CautionBanner(text: AnchorSync.cutOffWarning, isSevere: true)
                    .padding(.bottom, 6)
            }
            GuideCard(guide: guide) { guideButton(at: guide.live) }
        }
    }

    @ViewBuilder
    private func guideButton(at live: Int?) -> some View {
        switch live {
        case 0:
            if TagScanner.isAvailable {
                GuideButton(
                    title: listening ? "Listening…" : "Hold a tag up",
                    systemImage: "wave.3.right"
                ) {
                    Task { await listen() }
                }
                .disabled(listening)
            } else {
                Text("This iPhone has no reader Furlough can use, so a tag cannot be paired on it.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.ember)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case 1:
            GuideButton(title: "Choose apps", systemImage: "plus") { chooseApps() }
        case 2:
            // The real button, so the first drop goes through the same path (caution dialog
            // included) as every later one.
            AnchorToggleButton()
        default:
            EmptyView()
        }
    }

    private var setUpPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinkTraffic(half: .anchor)
                .padding(.bottom, 6)
            stateCard
            SectionLabel(text: anchor.anchorsEverything ? "Stays open" : "Held")
            appsCard
            SectionLabel(text: "Settings")
            settingsCard
            Footnote(text: listFootnote)
                .padding(.top, 8)
        }
    }

    /// Gathered here since `body` is at the type-checker's limit without them, and both panes
    /// raise the same ones (e.g. pairing from the guide ends in the same naming alert).
    private func withPresentations(_ content: some View) -> some View {
        content
            .sheet(isPresented: $pickingLift) {
                TimePickerSheet(title: "Lifts at", minute: $liftMinute)
            }
            .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            // A tag held up with the anchor off would lock, not unlock. The tag has never been able
            // to do that before, so it says what it is about to take away and waits to be told yes.
            .confirmationDialog(
                "Anchor with \(droppingWithTag?.name ?? "this tag")?",
                isPresented: Binding(get: { droppingWithTag != nil }, set: { if !$0 { droppingWithTag = nil } }),
                titleVisibility: .visible
            ) {
                Button("Anchor now", role: anchorCaution?.isSevere == true ? .destructive : nil) {
                    droppingWithTag = nil
                    dropWithTag()
                }
                Button("Not yet", role: .cancel) { droppingWithTag = nil }
            } message: {
                Text(tagDropMessage)
            }
            // Combined into one alert: SwiftUI drops the second of two presentations requested
            // in the same breath, so this can't hand off from a dialog to a separate alert.
            .alert(
                anchor.isPaired ? "Pair this as another key?" : "Pair this tag?",
                isPresented: Binding(get: { pairingScanned != nil }, set: { if !$0 { pairingScanned = nil } })
            ) {
                TextField("Kitchen drawer", text: $draftName)
                Button("Pair it") {
                    if let scanned = pairingScanned { keep(scanned) }
                    pairingScanned = nil
                }
                Button("Not this one", role: .cancel) { pairingScanned = nil }
            } message: {
                Text(anchor.isPaired
                    ? "Furlough does not know this tag. Every paired tag lifts the anchor on its own, so this is a key at a second place — \(tagCount) used. Name it for the place it will live in."
                    : "Furlough does not know this tag. Pair it and it becomes the key: nothing else lifts an anchor once it is down. Name it for the place it will live in.")
            }
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

    private var stateCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AnchorGlyph(isAnchored: anchor.isAnchored, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: anchor.isAnchored ? "Anchored" : "Free", color: anchor.isAnchored ? Ember.ember : Ember.moss)
                    Text(stateLine)
                        .emberBody(13)
                        .foregroundStyle(Ember.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                AnchorToggleButton(until: timedUntil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            if !anchor.isAnchored {
                CardDivider()
                timedRow
            }
            if TagScanner.isAvailable {
                CardDivider()
                readerRow
            }
        }
        .emberCard()
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(title: "Schedule", detail: scheduleSummary) { AnchorScheduleScreen() }
            CardDivider()
            settingsRow(title: "Tags", detail: tagSummary) { AnchorTagsScreen() }
            CardDivider()
            settingsRow(title: "Scope", detail: scopeSummary) { AnchorScopeScreen() }
            CardDivider()
            settingsRow(title: "Devices", detail: macSummary, dot: macDot) { AnchorMacScreen() }
        }
        .emberCard()
        // Checked on open so the row reflects the current state, not a stale cached one.
        .task { model.checkLink() }
    }

    private func settingsRow<Screen: View>(
        title: String,
        detail: String,
        dot: Color? = nil,
        @ViewBuilder screen: @escaping () -> Screen
    ) -> some View {
        NavigationLink { screen() } label: {
            HStack(spacing: 10) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .emberDisplaySmall(13.5)
                        .foregroundStyle(Ember.cream)
                    Text(detail)
                        .emberBody(11.5)
                        .foregroundStyle(Ember.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ember.faint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "10:00 PM weekdays · lifts 7:00 AM". More than one drop time is a count: a row has space
    /// for a fact, and the screen behind it has space for the list.
    private var scheduleSummary: String {
        let all = anchor.schedules.sorted { ($0.minuteOfDay, $0.days.rawValue) < ($1.minuteOfDay, $1.days.rawValue) }
        guard let first = all.first else { return "No drop times" }
        guard all.count == 1 else { return "\(all.count) drop times" }
        let lift = first.liftMinuteOfDay.map { "lifts \(TimeFormat.minute($0))" } ?? "until the tag"
        return "\(TimeFormat.minute(first.minuteOfDay)) \(TimeFormat.daysInline(first.days)) · \(lift)"
    }

    /// "Kitchen drawer · 1 of 3". The first key's name, because that is what a person is looking
    /// for when they open this, and the count because the cap is worth knowing before the drawer.
    private var tagSummary: String {
        guard let first = anchor.tags.first else { return "None paired" }
        return "\(first.name) · \(tagCount)"
    }

    private var scopeSummary: String {
        anchor.anchorsEverything ? "Everything except a list" : "Chosen apps"
    }

    private var macSummary: String {
        let status = model.link
        guard status.cloudAvailable else { return "Not linked · iCloud Drive is off" }
        guard status.enrolled else { return "Off the link · link this iPhone to lock your Mac too" }
        let others = model.devices.count
        return others == 0 ? "\(status.headline) · nothing else on the link yet" : "\(status.headline) · \(others) other\(others == 1 ? "" : "s")"
    }

    private var macDot: Color {
        let status = model.link
        if status.isLinked { return Ember.moss }
        return status.cloudAvailable ? Ember.amber : Ember.ember
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

    /// Nil when the tag is the only way back. Rolls to tomorrow if today's time is already
    /// past or within `Furlough.minimumWindowMinutes` (the monitor's minimum wake window).
    private var timedUntil: Date? {
        guard liftsBySelf else { return nil }
        let now = model.clock.now
        let soonest = now.addingTimeInterval(TimeInterval(Furlough.minimumWindowMinutes * 60))
        let today = Policy.date(atMinute: liftMinute, of: now)
        if today >= soonest { return today }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return Policy.date(atMinute: liftMinute, of: tomorrow)
    }

    private var timedRow: some View {
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
    }

    private var timedLine: String {
        guard let until = timedUntil else { return "Only the tag lifts it." }
        let day = Calendar.current.isDateInToday(until) ? "today" : "tomorrow"
        return "Anchor lifts \(day) at \(TimeFormat.clock(until)), or sooner with the tag."
    }

    /// Tapping re-arms the reader, needed after a cancel or after Core NFC's session times out.
    private var readerRow: some View {
        Button {
            Task { await listen() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(readerIsUseful ? Ember.ember : Ember.muted)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(readerTitle)
                        .emberBody(13, .semibold)
                        .foregroundStyle(Ember.cream)
                    Text(readerLine)
                        .emberBody(11.5)
                        .foregroundStyle(Ember.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(listening)
    }

    private var readerIsUseful: Bool { anchor.isAnchored || anchor.canAnchor }

    private var readerTitle: String {
        if listening { return "Listening" }
        if anchor.isAnchored { return "Hold your tag up to weigh anchor" }
        if !anchor.isPaired { return "Hold a tag up to pair it" }
        if !anchor.hasSomethingToHold { return "Choose what the anchor holds" }
        return "Hold your tag up to anchor"
    }

    private var readerLine: String {
        if listening { return "Hold the top of your phone to the tag." }
        if anchor.isAnchored {
            return "Any paired tag lifts it. An unknown tag is refused while the anchor is down."
        }
        if !anchor.isPaired {
            return "Any NTAG sticker, or the tag that came with another blocking product."
        }
        if !anchor.hasSomethingToHold {
            return "A key with nothing to lock. Choose apps above and the tag anchors from here."
        }
        return "A paired tag anchors, and asks first. A tag Furlough does not know is offered as another key."
    }

    private var tagDropMessage: String {
        let lift = timedUntil.map { "It lifts at \(TimeFormat.clock($0)), or sooner with a tag." }
            ?? "Nothing but a tag lifts it."
        if let caution = anchorCaution { return "\(caution.text) \(lift)" }
        return "\(anchor.heldDescription) goes behind the tag. \(lift)"
    }

    /// Never re-arms in a loop: Core NFC's session stops on its own after about a minute.
    private func listen() async {
        guard TagScanner.isAvailable, !listening else { return }
        listening = true
        defer { listening = false }
        switch await model.readTag(prompt: readerPrompt) {
        case .read(let reading): act(on: reading)
        case .failed(let why): message = why
        case .quiet: break
        }
    }

    private var readerPrompt: String {
        if anchor.isAnchored { return "Hold your iPhone to a paired tag to weigh anchor." }
        if !anchor.isPaired { return "Hold your iPhone to the tag you want to pair." }
        return "Hold your iPhone to a tag. A paired one anchors; a new one is offered as another key."
    }

    /// The one branch. Releasing goes straight through — it is what a tag has always done, and
    /// it was just held up to say so. The other two ask first.
    private func act(on reading: AnchorProfile.TagReading) {
        switch reading {
        case .weigh(let tag):
            if case .failed(let why) = model.weighAnchor(with: tag.id) { message = why }
        case .drop(let tag):
            droppingWithTag = tag
        case .pairFirst(let scanned), .pairAnother(let scanned):
            draftName = ""
            pairingScanned = scanned
        case .refused(let why):
            message = why
        }
    }

    private func dropWithTag() {
        switch model.anchor(until: timedUntil) {
        case .failed(let reason): message = reason
        default: break
        }
    }

    /// An empty typed name is ignored by `renameTag`, which keeps the model's placeholder —
    /// a tag is never nameless, only unhelpfully named.
    private func keep(_ scanned: Data) {
        switch model.pair(identifier: scanned) {
        case .paired(let tag): model.renameTag(id: tag.id, to: draftName)
        case .failed(let reason): message = reason
        default: break
        }
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
                            .overlay(alignment: .bottomTrailing) {
                                if model.state.config.target(kind: kind)?.rule != nil {
                                    RuledBadge().offset(x: 4, y: 4)
                                }
                            }
                            .contextMenu { gridMenu(for: kind) }
                    }
                }
                .padding(12)
            }
            if !anchor.isAnchored {
                CardDivider()
                Button {
                    chooseApps()
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

    private var tagCount: String { "\(anchor.tags.count) of \(Furlough.maxAnchorTags)" }

    private var chooseTitle: String {
        switch (anchor.scope, anchor.kinds.isEmpty) {
        case (.chosen, true): "Choose apps"
        case (.chosen, false): "Change apps"
        case (.everythingExcept, true): "Choose what stays open"
        case (.everythingExcept, false): "Change what stays open"
        }
    }

    private func chooseApps() { onChooseApps() }

    @ViewBuilder
    private func gridMenu(for kind: TargetKind) -> some View {
        if let target = model.state.config.target(kind: kind) {
            Button(target.rule == nil ? "Give it hours too" : "Open its rule", systemImage: "hourglass") {
                onOpenRule(target.id)
            }
        } else {
            Button("Give it hours too", systemImage: "hourglass") {
                onOpenRule(model.targetForRule(kind))
            }
        }
    }
}

/// The Anchor's first offer, before Apple's picker: apps and sites already blocked, all checked
/// to start. Shown when the anchor holds nothing but something already has a rule.
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

/// Edits the anchor's drop times as one draft with one Save; the whole set is classified at
/// once, so a looser change queues behind the delay while a tightening lands now.
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
                        ForEach(drafts) { draft in
                            ScheduleDraftRow(schedule: binding(for: draft)) {
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

    /// By id, not index: `ForEach($drafts)`'s positional binding goes out of range when a row
    /// removes itself while still momentarily in the tree, which crashed on the last row's
    /// remove button. An edit for a row that's gone is silently dropped instead.
    private func binding(for draft: AnchorSchedule) -> Binding<AnchorSchedule> {
        Binding(
            get: { drafts.first { $0.id == draft.id } ?? draft },
            set: { edited in
                guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
                drafts[index] = edited
            }
        )
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
