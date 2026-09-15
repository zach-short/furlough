import SwiftUI

/// The four screens behind the Anchor page's settings card: Schedule, Tags, Scope and Your Mac.
/// Each reads the anchor live and locks while it's down; alerts/confirmations belong to
/// whichever screen raises them.

/// Chrome shared with Settings' own menu screens. `lead` is optional since some screens
/// (About, Diagnostics) have nothing to say before their first card.
struct AnchorSettingScreen<Content: View>: View {
    let title: String
    var lead = ""
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !lead.isEmpty {
                    Text(lead)
                        .emberBody(13.5)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 14)
                }
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

/// Edited as one draft in `AnchorScheduleSheet` since the whole set is classified at once.
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

/// Pairing an unknown tag held up at the Anchor page itself (while armed) is handled there,
/// not here.
struct AnchorTagsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var forgetting: PairedTag?
    @State private var renaming: PairedTag?
    @State private var draftName = ""
    @State private var message: String?
    /// Re-opens `TagPlacementView` (normally shown once on first pairing) on demand.
    @State private var placing = false

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
            placementRow
                .padding(.top, 10)
            automationsRow
                .padding(.top, 6)
            SectionLabel(text: "Scanner")
            autoArmCard
        }
        .sheet(isPresented: $placing) { TagPlacementView() }
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

    private var placementRow: some View {
        Button {
            placing = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Where to leave it")
                    .emberBody(12.5, .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Ember.muted)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Sits right under "Where to leave it": the two pieces of advice about living with the
    /// Anchor day to day, rather than pairing or scoping it.
    private var automationsRow: some View {
        NavigationLink {
            AutomationsHelp()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                Text("Have something else drop it for you")
                    .emberBody(12.5, .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Ember.muted)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Off by default: arming is already reachable by hand, and an unrequested scan sheet
    /// would surprise people who haven't opted in.
    private var autoArmCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Open the scanner when Anchor opens")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer(minLength: 8)
                Toggle(
                    "Open the scanner when Anchor opens",
                    isOn: Binding(get: { model.autoArmsReader }, set: { model.setAutoArmsReader($0) })
                )
                .labelsHidden()
                .tint(Ember.ember)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Text("Off, arriving here waits for you to tap Hold a tag up. On, it starts listening the moment there is a tag to pair or an anchor to lift.")
                .emberBody(11.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .emberCard()
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

    /// Rename/Forget hidden while anchored, like the app list on the page behind this one.
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

/// Switching scope resets the list (see `AppModel.setAnchorScope`), so a non-empty list
/// confirms first.
struct AnchorScopeScreen: View {
    @Environment(AppModel.self) private var model
    /// Pending scope, held while confirming a reset.
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

// MARK: Devices

/// `DevicesScreen` is the shared content; Settings hosts the same screen under its own row.
/// The severe warning here matters because a phone that can't reach iCloud can't release an
/// anchor dropped on a Mac — the one failure Furlough has no other way out of.
struct AnchorMacScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AnchorSettingScreen(title: "Devices", lead: lead) {
            DevicesScreen()
        }
    }

    private var lead: String {
        guard model.cloudAvailable else { return AnchorSync.cutOffWarning }
        return model.isEnrolled
            ? "This iPhone is on the link. Drop the anchor on any device here and every one of them locks; only a tag scanned on an iPhone releases them."
            : "Furlough on your Mac or iPad can be locked by this iPhone's anchor and released by its tag, once both are on the link. Nothing crosses until you link this one."
    }
}
