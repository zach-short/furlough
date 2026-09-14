import SwiftUI

struct MacAnchorPane: View {
    @Environment(MacModel.self) private var model
    let onChooseApps: (AddChoice) -> Void
    let onExplainDevices: () -> Void

    // Not a NavigationStack; sub-screens swap in place here, as WeekSheet and LogView also do.
    @State private var screen: Screen?
    @State private var message: String?
    @State private var asking = false

    private enum Screen: String, Identifiable { case scope, phone; var id: String { rawValue } }

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var isHolding: Bool { anchor.isHolding(at: model.now) }

    private var guide: HalfGuide {
        HalfGuide.macAnchor(
            config: model.state.config,
            finished: model.finishedGuides.contains(.anchor),
            hasKey: model.hasKey
        )
    }

    var body: some View {
        Group {
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
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task { model.checkLink() }
        .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: The guide

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
            dropButton
        default:
            EmptyView()
        }
    }

    // MARK: Set up

    private var setUpPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacLinkTraffic(half: .anchor)
                .padding(.bottom, 8)
            stateCard
            SectionLabel(text: "Settings")
            settingsCard
            Footnote(text: listFootnote)
                .padding(.top, 8)
        }
    }

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
        // Checked before hasKey, like macDrop: an old latch doesn't mean a phone is reachable now.
        if !model.cloudAvailable { return "\(held) · iCloud unreachable" }
        if !model.hasKey { return "\(held) · no iPhone on the link" }
        return "\(held) · ready"
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingsRow(title: "Scope", detail: scopeSummary) { screen = .scope }
            CardDivider()
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

    private var helpCard: some View {
        Button(action: onExplainDevices) {
            HelpRow(topic: .devices)
        }
        .buttonStyle(.plain)
        .emberCard()
    }
}

// MARK: - Marks

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

struct HeldMark: View {
    var size: CGFloat = 9

    var body: some View {
        AnchorShape()
            .fill(Ember.faint)
            .frame(width: size * 0.8, height: size)
            .accessibilityLabel("Held by the anchor")
    }
}

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
