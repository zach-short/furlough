import SwiftUI

/// The Anchor half, in the detail pane: one action and two rows.
///
/// It was a sheet behind a padlock in the toolbar — a lock icon, unlabelled, over a stack of
/// eleven blocks that put Scope, two add fields and a four-line footnote in front of the one
/// fact a new reader needed, which is that nothing here works until a phone has dropped an
/// anchor once. It is one of the window's two halves now, reached by the segment in the sidebar,
/// and it opens on a three-step checklist until it is set up.
///
/// The Mac has no tag reader and no scheduled drops, so where the phone's page carries four rows
/// this one carries two: Scope, and Your iPhone, which is the whole of what a key means here.
struct MacAnchorPane: View {
    @Environment(MacModel.self) private var model
    /// Hands an Application-or-Website answer to the window's one add flow, bound for this
    /// half's list. The same pipeline the + button uses, so the guide's step and the button
    /// cannot drift apart — the question is asked here only because a popover pops from the
    /// control that was clicked, and this one is a card in the middle of the pane.
    let onChooseApps: (AddChoice) -> Void
    /// Asks the window to explain the link to the phone, in Help's own window beside this one.
    let onExplainDevices: () -> Void

    /// The screen a row opened, shown in place with a Back link rather than pushed: the detail
    /// pane is not in a navigation stack, and `WeekSheet` and `LogView` swap in place for the
    /// same reason.
    @State private var screen: Screen?
    @State private var message: String?
    @State private var asking = false

    private enum Screen: String, Identifiable { case scope, phone; var id: String { rawValue } }

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var isHolding: Bool { anchor.isHolding(at: model.now) }

    /// The three steps this half is set up in. See `HalfGuide.macAnchor`.
    private var guide: HalfGuide {
        HalfGuide.macAnchor(
            config: model.state.config,
            finished: model.finishedGuides.contains(.anchor),
            hasKey: model.hasKey
        )
    }

    var body: some View {
        Group {
            // Before it is set up this pane is the checklist and nothing else, centred in the
            // pane the way the other half's guide is. Everything else scrolls: a sub-screen can
            // be taller than a small window.
            if screen == nil, guide.isRunning {
                guidePane
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch screen {
                        case .scope: MacAnchorScopeScreen(onBack: { screen = nil })
                        case .phone: MacAnchorPhoneScreen(onBack: { screen = nil }, onExplainDevices: onExplainDevices)
                        case nil: setUpPane
                        }
                    }
                    // Centred, and the column the width the rule editor uses, so the two halves
                    // put their content in the same place.
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        // Asked when the pane arrives, so the link row is about now rather than about whenever
        // the app last happened to hear something.
        .task { model.checkLink() }
        .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: The guide

    /// Hear from the phone, choose what it holds, drop it. The severe banner outranks even this:
    /// a Mac that cannot reach iCloud can never be released, and it bears on the third step.
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
            // Nothing on this Mac can do the step; what it can do is look again. The link's own
            // words go under the button, because "not yet" and "iCloud is off" are two different
            // reasons to still be on this step.
            VStack(alignment: .leading, spacing: 8) {
                GuideButton(title: "Check again", systemImage: "arrow.clockwise") { model.checkLink() }
                Text(model.link.detail(now: model.now))
                    .emberBody(11.5)
                    .foregroundStyle(model.cloudAvailable ? Ember.muted : Ember.ember)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case 1:
            GuideButton(title: "Choose apps", systemImage: "plus") { asking = true }
                .popover(isPresented: $asking, arrowEdge: .bottom) {
                    AddChoicePopover(
                        applicationCaption: "Any app on this Mac, held while anchored",
                        websiteCaption: "A site and its subdomains, held while anchored"
                    ) { choice in
                        asking = false
                        onChooseApps(choice)
                    }
                }
        case 2:
            // The real one, so the first drop goes through exactly what every later drop does.
            dropButton
        default:
            EmptyView()
        }
    }

    // MARK: Set up

    /// One action and two rows. What it holds is the sidebar's, the way the rules list is: this
    /// is the window's left-hand column and the half's list belongs in it, which is also what
    /// keeps this pane down to the drop and the two things that are settings rather than acts.
    private var setUpPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // What the link is asking about on this half, when it is asking anything.
            MacLinkTraffic(half: .anchor)
                .padding(.bottom, 8)
            stateCard
            SectionLabel(text: "Settings")
            settingsCard
            Footnote(text: listFootnote)
                .padding(.top, 8)
        }
    }

    /// Where the anchor stands and the button that changes it. The mark is here rather than in a
    /// header: the segment in the sidebar already names this half, and what a glyph is good for
    /// is saying at a glance whether the anchor is down.
    private var stateCard: some View {
        HStack(spacing: 12) {
            AnchorGlyph(isAnchored: isHolding, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: isHolding ? "Anchored" : "Free", color: isHolding ? Ember.ember : Ember.moss)
                Text(stateLine)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !isHolding { dropButton }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .emberCard()
    }

    private var dropButton: some View {
        Button {
            if let why = model.dropAnchor() { message = why }
        } label: {
            Text("Drop anchor")
                .emberBody(13, .bold)
                .foregroundStyle(Ember.cream)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(Ember.ember)
        .disabled(!anchor.hasSomethingToHold)
    }

    private var stateLine: String {
        let held = anchor.heldDescription
        if isHolding, let since = anchor.anchoredAt {
            let lift = anchor.until.map { " · lifts \(TimeFormat.clock($0))" } ?? ""
            return "\(held) since \(since.formatted(date: .omitted, time: .shortened))\(lift)"
        }
        if anchor.scope == .chosen, anchor.kinds.isEmpty { return "Nothing chosen yet" }
        // Ahead of `phoneSeen`, and for the same reason `macDrop` checks it first: a latch set
        // by some earlier account says nothing about whether a phone can be heard from now.
        if !model.cloudAvailable { return "\(held) · iCloud unreachable" }
        if !model.hasKey { return "\(held) · no iPhone on the link" }
        return "\(held) · ready"
    }

    /// Scope and Your iPhone: the two things about the anchor on a Mac that are settings rather
    /// than acts. Each was a card and a footnote on the sheet; each is a row and a screen now,
    /// and the footnote is the first sentence you read when the screen opens.
    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(title: "Scope", detail: scopeSummary) { screen = .scope }
            CardDivider()
            // The dot, and the iCloud warning folded into the words beside it. It used to be a
            // severe banner at the top of the sheet; it belongs on the one row it is about,
            // which is also the only row that can be wrong without anybody having done anything.
            settingsRow(title: "Devices", detail: phoneSummary, dot: phoneDot) { screen = .phone }
        }
        .emberCard()
    }

    private func settingsRow(title: String, detail: String, dot: Color? = nil, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 10) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ember.faint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scopeSummary: String {
        anchor.anchorsEverything ? "Everything except a list" : "Chosen apps"
    }

    private var phoneSummary: String {
        let status = model.link
        guard status.cloudAvailable else { return "Not linked · iCloud Drive is off" }
        guard status.enrolled else { return "Off the link · link this Mac to be locked with your iPhone" }
        guard model.hasKey else { return "\(status.headline) · no iPhone on it yet" }
        let others = model.devices.count
        return "\(status.headline) · \(others) other\(others == 1 ? "" : "s")"
    }

    private var phoneDot: Color {
        let status = model.link
        if status.isLinked { return Ember.moss }
        return status.cloudAvailable ? Ember.amber : Ember.ember
    }

    private var listFootnote: String {
        if isHolding {
            return "Scan the paired tag in Furlough on your iPhone to release it, there and here. The list cannot change until then."
        }
        switch anchor.scope {
        case .chosen:
            return "Anything here is blocked while anchored. Windows and budgets still apply the rest of the time."
        case .everythingExcept:
            return "Everything not listed here is blocked while anchored: apps are quit, and sites go to the shield page. Finder, the Dock and System Settings are never blocked."
        }
    }
}

// MARK: - The two screens behind the rows

/// The chrome the two share: a Back link, the title, the lead under it, the cards below. No
/// heading of its own above the lead — the title line already names the screen.
private struct MacAnchorScreen<Content: View>: View {
    let title: String
    let lead: String
    let onBack: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text("Anchor").emberBody(12.5, .semibold)
                }
                .foregroundStyle(Ember.ember)
            }
            .buttonStyle(.plain)
            Text(title)
                .emberDisplay(24)
                .foregroundStyle(Ember.cream)
                .padding(.top, 10)
            Text(lead)
                .emberBody(12.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            content
                .padding(.top, 10)
        }
    }
}

/// How far the anchor reaches: the list, or every app on this Mac but the list. Locked while
/// anchored. The list does not survive a switch, so a list that holds anything asks first.
private struct MacAnchorScopeScreen: View {
    @Environment(MacModel.self) private var model
    let onBack: () -> Void
    @State private var switchingTo: AnchorProfile.Scope?

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var isHolding: Bool { anchor.isHolding(at: model.now) }

    var body: some View {
        MacAnchorScreen(title: "Scope", lead: lead, onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    chip(.chosen, "Chosen apps")
                    chip(.everythingExcept, "Everything except")
                }
                .padding(12)
                CardDivider()
                Text(anchor.anchorsEverything
                    ? "Every app and website is held. Only what is listed stays open."
                    : "Only what is listed is held. Everything else keeps its own rules.")
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
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
                : "The list becomes what is held, starting empty.")
        }
    }

    private var lead: String {
        if isHolding { return "The anchor is down. Scan your tag on your iPhone to change how far it reaches." }
        return "Switching starts the list again: what it holds now is not carried over, because the two scopes read the same list opposite ways round."
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isHolding)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Whether the two devices are actually talking, and a button that asks.
///
/// Nothing else on this Mac says the Anchor reaches the phone at all, and there is no screen
/// where the link could be set up, because there is nothing to set up. So the Anchor — the one
/// half it is about — carries the way in.
///
/// The severe warning is the lead here rather than a banner on the pane in front. A Mac that
/// cannot reach iCloud cannot be released by the one thing that could release it, which is the
/// failure Furlough has no other way out of; the row that opens this screen wears an ember dot
/// and says so in its own words, and this is where the whole of it is said.
private struct MacAnchorPhoneScreen: View {
    @Environment(MacModel.self) private var model
    let onBack: () -> Void
    let onExplainDevices: () -> Void

    var body: some View {
        MacAnchorScreen(title: "Devices", lead: lead, onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                MacDevicesScreen()
                helpCard
                    .padding(.top, 10)
            }
        }
    }

    private var lead: String {
        guard model.cloudAvailable else { return AnchorSync.cutOffWarning }
        return model.isEnrolled
            ? "An iPhone's tag is the only thing that lifts an anchor, here or there. This Mac is on the link: a drop on any device here locks it, and what you add can cross too."
            : "An iPhone's tag is the only thing that lifts an anchor, here or there. Link this Mac to your iPhone and a drop on either locks both; nothing crosses until you do."
    }

    /// The same row Help's own hub draws, so it is plainly a link into Help rather than a
    /// setting of its own.
    private var helpCard: some View {
        Button(action: onExplainDevices) {
            HelpRow(topic: .devices)
        }
        .buttonStyle(.plain)
        .emberCard()
    }
}

// MARK: - Marks

/// The anchor in a tile, ember while anchored. The phone's `AnchorGlyph`, which is what the
/// toolbar's SF padlock used to stand in for.
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

/// The anchor, small enough to sit inside a line of a sidebar row: this one is on the anchor's
/// list too. A mark rather than a second list, as on the phone.
struct HeldMark: View {
    var size: CGFloat = 9

    var body: some View {
        AnchorShape()
            .fill(Ember.faint)
            .frame(width: size * 0.8, height: size)
            .accessibilityLabel("Held by the anchor")
    }
}

/// The mirror of `HeldMark`, in the corner of a tile in the anchor's grid: this app has hours in
/// the other half.
struct RuledBadge: View {
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: "hourglass")
            .font(.system(size: size * 0.62, weight: .bold))
            .foregroundStyle(Ember.amber)
            .frame(width: size, height: size)
            .background(Ember.ground, in: Circle())
            .overlay(Circle().strokeBorder(Ember.cardBorder, lineWidth: 1))
            .accessibilityLabel("Has a rule")
    }
}
