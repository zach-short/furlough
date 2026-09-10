import SwiftUI

/// The link between this iPhone and the person's other devices: joining it, who is on it,
/// what crosses, and leaving it. Reached from the Anchor page's Devices row and from Settings,
/// which host the same content under their own titles.
///
/// Off the link, the screen is the four things to know, a name, and one button. On it, the
/// screen is the roster and the three settings. The two states share nothing but the lead,
/// because a person reads each once: the guide before joining, the roster ever after.
struct DevicesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var name = DeviceLink.name
    @State private var message: String?
    @State private var removing: LinkedDevice?
    @State private var confirmLeave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isEnrolled {
                linkCard
                rosterCard
                    .padding(.top, 10)
                settingsCard
                    .padding(.top, 10)
            } else {
                LinkStepsCard(platform: AnchorSync.platform)
                joinCard
                    .padding(.top, 10)
            }
            helpRow
                .padding(.top, 10)
        }
        .task { model.checkLink() }
        .alert("Devices", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Take \(removing?.name ?? "this device") off the link?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Take it off the link", role: .destructive) {
                if let device = removing { message = model.revokeDevice(device.id) }
                removing = nil
            }
        } message: {
            Text("It stops hearing the Anchor and stops sending or taking what is added, the next time it reads iCloud. It can join again from its own Devices screen.")
        }
        .confirmationDialog("Take this iPhone off the link?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave the link", role: .destructive) { message = model.leaveLink() }
        } message: {
            Text("The Anchor stops at this iPhone, and nothing added here or elsewhere crosses. Your rules and your list stay exactly as they are.")
        }
    }

    /// What the link says of itself. Not shown while iCloud is unreachable: the lead above says
    /// that case in full.
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
    }

    /// Everyone on the link, this iPhone first.
    @ViewBuilder
    private var rosterCard: some View {
        SectionLabel(text: "On the link")
        VStack(spacing: 0) {
            LinkedDeviceRow(
                device: DeviceLink.entry(
                    id: AnchorSync.deviceID, name: DeviceLink.name, platform: AnchorSync.platform,
                    existing: nil, now: model.clock.now
                ),
                isThisDevice: true,
                now: model.clock.now
            ) { confirmLeave = true }
            ForEach(model.devices) { device in
                CardDivider()
                LinkedDeviceRow(device: device, isThisDevice: false, now: model.clock.now) { removing = device }
            }
        }
        .emberCard()
        Footnote(text: model.devices.isEmpty
            ? "Nothing else is on the link yet. Open Furlough on your Mac or iPad and link it from its own Devices screen; it appears here once it has."
            : "Any device can be taken off from any other, except while the anchor is down.")
            .padding(.top, 8)
    }

    /// The three questions about what crosses, each Always, Ask or Never.
    @ViewBuilder
    private var settingsCard: some View {
        SectionLabel(text: "What crosses")
        let link = model.state.config.link
        VStack(spacing: 0) {
            LinkChoiceRow(
                title: "Block the website too",
                detail: "When an app is also a site — YouTube, youtube.com — block both as one row.",
                selection: link.companionSite
            ) { choice in
                var copy = link
                copy.companionSite = choice
                model.setLinkPreferences(copy)
            }
            CardDivider()
            LinkChoiceRow(
                title: "Send what I add",
                detail: "Tell \(othersDescription) the name of what you add here, so each can block what it finds.",
                selection: link.sendAdditions
            ) { choice in
                var copy = link
                copy.sendAdditions = choice
                model.setLinkPreferences(copy)
            }
            CardDivider()
            LinkChoiceRow(
                title: "Take what my other devices add",
                detail: "Block here what \(othersDescription) add\(model.devices.count == 1 ? "s" : "") there, and the site at once; an app still needs Apple's picker.",
                selection: link.acceptAdditions
            ) { choice in
                var copy = link
                copy.acceptAdditions = choice
                model.setLinkPreferences(copy)
            }
        }
        .emberCard()
        Footnote(text: "Ask puts a card on the page it is about. A picked app can only be sent, or paired with its site, once Furlough has seen it: right away with Screen Time data access, otherwise the first time the shield covers it. Names cross; rules, lists and tokens never do.")
            .padding(.top, 8)
    }

    /// Name it, and join.
    @ViewBuilder
    private var joinCard: some View {
        SectionLabel(text: "This iPhone")
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: AnchorSync.platform == .pad ? "ipad" : "iphone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ember.amber)
                TextField(LinkedDevice.defaultName(for: AnchorSync.platform), text: $name)
                    .textFieldStyle(.plain)
                    .emberBody(14, .medium)
                    .foregroundStyle(Ember.cream)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            CardDivider()
            ProminentButton(title: "Link this \(LinkedDevice.defaultName(for: AnchorSync.platform))") {
                guard model.cloudAvailable else {
                    message = AnchorSync.cutOffWarning
                    return
                }
                model.enrollDevice(name: name)
            }
            .padding(12)
        }
        .emberCard()
        Footnote(text: "Name it for the shelf it sits on, so the roster on your other devices reads the way you think. Joining writes one small record to your iCloud and nothing else; leaving deletes it.")
            .padding(.top, 8)
    }

    private var helpRow: some View {
        NavigationLink { DevicesHelp() } label: {
            HelpRow(title: "Across your devices", detail: "What the link carries, and what it never does") {
                HelpTile(symbol: "laptopcomputer.and.iphone")
            }
        }
        .buttonStyle(.plain)
        .emberCard()
    }

    private var othersDescription: String {
        DeviceLink.roster().othersDescription(than: AnchorSync.deviceID)
    }

}

/// The traffic on one half of Home: what this iPhone is asking whether to send, and what the
/// others added and it is asking whether to take. Nothing when there is nothing to ask.
struct LinkTraffic: View {
    @Environment(AppModel.self) private var model
    let half: Half
    @State private var message: String?

    var body: some View {
        let roster = DeviceLink.roster()
        LinkTrafficCard(
            outgoing: model.outgoing.filter { $0.half == half },
            arrivals: model.arrivals.filter { $0.addition.half == half },
            othersDescription: roster.othersDescription(than: AnchorSync.deviceID),
            nameOf: { id in roster.device(id).map { "Your \($0.name)" } ?? "Another device" },
            onSend: { model.sendOutgoing($0) },
            onDeclineSend: { model.declineOutgoing($0) },
            onAccept: { message = model.acceptArrival($0) },
            onDeclineArrival: { model.declineArrival($0) }
        )
        .alert("Devices", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}
