import SwiftUI

/// The four screens behind the Anchor page's settings card: Schedule, Tags, Scope and Your Mac.
///
/// Each was a section on the Anchor screen itself — a label, a card, and a footnote underneath
/// saying the one thing you had to know before touching it. Eleven blocks deep, the two controls
/// a new person actually needed were sixth and ninth. So each section is a row now, and the
/// footnote that used to sit under its card is the first sentence of the screen the row opens:
/// the fact arrives when the thing it is about does, rather than three scrolls before it.
///
/// Every screen reads the anchor live and every one of them locks while it is down, the same as
/// the cards did. The alerts and confirmations came with their cards, so each screen owns its
/// own — the Anchor page keeps only the ones its reader can raise.

/// The chrome the four share: the title in the bar, the lead under it, the cards below.
///
/// No heading of its own above the lead. The bar already names the screen, and a page that
/// opens by saying its own name twice is the thing the Anchor page's old header was doing.
struct AnchorSettingScreen<Content: View>: View {
    let title: String
    let lead: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(lead)
                    .emberBody(13.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 48)
        }
        .background(EmberWall())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
        }
    }
}

// MARK: Schedule

/// The drop times, and the way to change them while the anchor is off. Edited as one draft in
/// `AnchorScheduleSheet`, because the whole set is classified at once.
struct AnchorScheduleScreen: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var sorted: [AnchorSchedule] {
        anchor.schedules.sorted { ($0.minuteOfDay, $0.days.rawValue) < ($1.minuteOfDay, $1.days.rawValue) }
    }

    var body: some View {
        AnchorSettingScreen(title: "Schedule", lead: lead) {
            VStack(alignment: .leading, spacing: 0) {
                if anchor.schedules.isEmpty {
                    Text("No scheduled drops.")
                        .emberBody(13)
                        .foregroundStyle(Ember.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                } else {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, schedule in
                        if index > 0 { CardDivider() }
                        row(schedule)
                    }
                }
                if !anchor.isAnchored {
                    CardDivider()
                    Button {
                        editing = true
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
        .sheet(isPresented: $editing) {
            AnchorScheduleSheet(schedules: anchor.schedules)
        }
    }

    private func row(_ schedule: AnchorSchedule) -> some View {
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

    private var lead: String {
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
}

// MARK: Tags

/// The keys: what each is called, what it is, and the way to add or forget one.
///
/// Pairing from here is a scan asked for by hand, and it ends in the naming alert. The other way
/// in — a tag Furlough does not know, held up at the Anchor page while its reader was armed —
/// stays on that page, because that is where the tag was.
struct AnchorTagsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var forgetting: PairedTag?
    @State private var renaming: PairedTag?
    @State private var draftName = ""
    @State private var message: String?

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var tagCount: String { "\(anchor.tags.count) of \(Furlough.maxAnchorTags)" }

    var body: some View {
        AnchorSettingScreen(title: "Tags", lead: lead) {
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
                        row(tag)
                    }
                }
                if !anchor.isAnchored {
                    CardDivider()
                    pairRow
                }
            }
            .emberCard()
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
        .alert("Tags", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    @ViewBuilder
    private var pairRow: some View {
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

    /// One key: what it is called, what it is, and the way to change either. Both controls are
    /// gone while anchored, like the app list on the page behind this one.
    private func row(_ tag: PairedTag) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Text(label(tag.id))
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

    private var lead: String {
        let cap = "Up to \(Furlough.maxAnchorTags), so a key can live at each place you do."
        return "Anchoring works without a tag. Weighing anchor needs one, so keep every tag somewhere that makes you think. \(cap)"
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

    private func label(_ id: Data) -> String {
        let hex = id.map { String(format: "%02X", $0) }.joined()
        return "…\(hex.suffix(4))"
    }
}

// MARK: Scope

/// How far the anchor reaches: the list, or the whole phone but the list. Locked while anchored
/// along with everything else. The list does not survive a switch (see `AppModel.setAnchorScope`),
/// so a list that holds anything asks first.
struct AnchorScopeScreen: View {
    @Environment(AppModel.self) private var model
    /// The scope tapped while the list still holds something, waiting on a confirmation:
    /// switching starts the list again, and a curated list is worth a second look first.
    @State private var switchingTo: AnchorProfile.Scope?

    private var anchor: AnchorProfile { model.state.config.anchor }

    var body: some View {
        AnchorSettingScreen(title: "Scope", lead: lead) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    chip(.chosen, "Chosen apps")
                    chip(.everythingExcept, "Everything except")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                Text(summary)
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
    }

    private var lead: String {
        anchor.isAnchored
            ? "Unanchor with your tag to change the scope."
            : "Switching starts the list again, so the one you have now is not carried over."
    }

    private var summary: String {
        switch anchor.scope {
        case .chosen: "Only what is listed is held. Everything else keeps its own rules."
        case .everythingExcept: "Every app and website is held. Only what is listed stays open."
        }
    }

    private func chip(_ scope: AnchorProfile.Scope, _ title: String) -> some View {
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
}

// MARK: Your Mac

/// Whether the two devices are actually talking, and a button that asks.
///
/// Nothing else on this phone says the Anchor reaches the Mac at all, and there is no screen
/// where the link could be set up, because there is nothing to set up. So the Anchor — the one
/// half it is about — carries the way in.
///
/// The severe warning is the lead here rather than a banner on the page in front. A phone that
/// cannot reach iCloud cannot release an anchor it drops on a Mac, which is the one failure
/// Furlough has no other way out of; the row that opens this screen wears an ember dot and says
/// so in its own words, and this is where the whole of it is said.
struct AnchorMacScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AnchorSettingScreen(title: "Your Mac", lead: lead) {
            linkCard
            devicesRow
                .padding(.top, 10)
        }
    }

    private var lead: String {
        model.cloudAvailable
            ? "One Anchor across both devices, carried on your own iCloud. Nothing to pair and nothing to switch on."
            : AnchorSync.cutOffWarning
    }

    /// The Mac draws the same card from the same `LinkStatus`, so both ends describe one link in
    /// one set of words.
    private var linkCard: some View {
        let status = model.link
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.isLinked ? Ember.moss : (status.cloudAvailable ? Ember.amber : Ember.ember))
                    .frame(width: 8, height: 8)
                Text(status.headline)
                    .emberDisplaySmall(14)
                    .foregroundStyle(Ember.cream)
                Spacer(minLength: 8)
                Button("Check now") { model.checkLink() }
                    .buttonStyle(.plain)
                    .emberBody(12.5, .semibold)
                    .foregroundStyle(Ember.ember)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            // Not when iCloud is unreachable: the lead above is that case said in full, and this
            // line is its first clause over again. Every other state the lead cannot know.
            if status.cloudAvailable {
                Text(status.detail(now: model.clock.now))
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 13)
            } else {
                Color.clear.frame(height: 13)
            }
        }
        .emberCard()
        // Asked when the screen opens, so the status is about now rather than about whenever
        // the app last happened to hear something.
        .task { model.checkLink() }
    }

    /// The row into Help's page about the two devices — the same row Help's own hub draws,
    /// because that is what it is.
    private var devicesRow: some View {
        NavigationLink { DevicesHelp() } label: {
            HelpRow(title: "Across your devices", detail: "What the Anchor carries to your Mac") {
                HelpTile(symbol: "laptopcomputer.and.iphone")
            }
        }
        .buttonStyle(.plain)
        .emberCard()
    }
}
