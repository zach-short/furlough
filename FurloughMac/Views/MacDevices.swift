import SwiftUI

/// The link between this Mac and the person's other devices: joining it, who is on it, what
/// crosses, and leaving it. The phone's `DevicesScreen`, from the end that holds a lock it
/// cannot open. Hosted by the Anchor half's Devices row and by Settings, each under its own
/// back link.
struct MacDevicesScreen: View {
    @Environment(MacModel.self) private var model
    @State private var name = DeviceLink.isEnrolled ? DeviceLink.name : (Host.current().localizedName ?? "Mac")
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
                LinkStepsCard(platform: .mac)
                joinCard
                    .padding(.top, 10)
            }
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
        .confirmationDialog("Take this Mac off the link?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave the link", role: .destructive) { message = model.leaveLink() }
        } message: {
            Text("The Anchor stops at this Mac — and this Mac will not drop one on its own, since no tag could reach it. Your rules and your list stay exactly as they are.")
        }
    }

    private var linkCard: some View {
        let status = model.link
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.isLinked ? Ember.moss : (status.cloudAvailable ? Ember.amber : Ember.ember))
                    .frame(width: 8, height: 8)
                Text(status.headline)
                    .emberDisplaySmall(13.5)
                    .foregroundStyle(Ember.cream)
                Spacer(minLength: 8)
                Button("Check now") { model.checkLink() }
                    .buttonStyle(.plain)
                    .emberBody(12, .semibold)
                    .foregroundStyle(Ember.ember)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Text(status.detail(now: model.now))
                .emberBody(12)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .emberCard()
    }

    @ViewBuilder
    private var rosterCard: some View {
        SectionLabel(text: "On the link")
        VStack(spacing: 0) {
            LinkedDeviceRow(
                device: DeviceLink.entry(id: AnchorSync.deviceID, name: DeviceLink.name, platform: .mac, existing: nil, now: model.now),
                isThisDevice: true,
                now: model.now
            ) { confirmLeave = true }
            ForEach(model.devices) { device in
                CardDivider()
                LinkedDeviceRow(device: device, isThisDevice: false, now: model.now) { removing = device }
            }
        }
        .emberCard()
        Footnote(text: model.hasKey
            ? "Any device can be taken off from any other, except while the anchor is down."
            : "No iPhone is on the link yet, so this Mac will not drop the anchor: only an iPhone's tag could release it. Link your iPhone from its own Devices screen.")
            .padding(.top, 8)
    }

    @ViewBuilder
    private var settingsCard: some View {
        SectionLabel(text: "What crosses")
        let link = model.state.config.link
        VStack(spacing: 0) {
            LinkChoiceRow(
                title: "Block the website too",
                detail: "When an app is also a site — YouTube, youtube.com — add the site beside the app.",
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
                detail: "Block here what \(othersDescription) add\(model.devices.count == 1 ? "s" : "") there: the app if this Mac has it, and the site either way.",
                selection: link.acceptAdditions
            ) { choice in
                var copy = link
                copy.acceptAdditions = choice
                model.setLinkPreferences(copy)
            }
        }
        .emberCard()
        Footnote(text: "Ask puts a card in the sidebar. Names cross; rules, lists and Screen Time tokens never do, so a phone that takes what this Mac adds blocks the site at once and is offered the app in Apple's picker.")
            .padding(.top, 8)
    }

    @ViewBuilder
    private var joinCard: some View {
        SectionLabel(text: "This Mac")
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ember.amber)
                TextField("Mac", text: $name)
                    .textFieldStyle(.plain)
                    .emberBody(14, .medium)
                    .foregroundStyle(Ember.cream)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            CardDivider()
            ProminentButton(title: "Link this Mac") {
                guard model.cloudAvailable else {
                    message = AnchorSync.cutOffWarning
                    return
                }
                model.enrollDevice(name: name)
            }
            .padding(12)
        }
        .emberCard()
        Footnote(text: "Joining writes one small record to your iCloud and nothing else; leaving deletes it. An iPhone has to be on the link too before this Mac will drop the anchor, since only its tag could release one.")
            .padding(.top, 8)
    }

    private var othersDescription: String {
        DeviceLink.roster().othersDescription(than: AnchorSync.deviceID)
    }

}

/// The same screen behind Settings' one Devices row, in place with a Back link, the way the
/// diagnostics and the log are: this is a sheet, and a sheet that grew a navigation stack for
/// one push would be carrying a bar it has no use for.
struct MacDevicesSettingsView: View {
    @Environment(MacModel.self) private var model
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text("Settings").emberBody(12.5, .semibold)
                }
                .foregroundStyle(Ember.ember)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(lead)
                        .emberBody(12.5)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                    MacDevicesScreen()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var lead: String {
        guard model.cloudAvailable else { return AnchorSync.cutOffWarning }
        return model.isEnrolled
            ? "This Mac is on the link. Drop the anchor on any device here and every one of them locks; only a tag scanned on an iPhone releases them, and what you add can cross too."
            : "Furlough on your iPhone can lock this Mac with its anchor and release it with its tag, and each can be told what the other adds, once both are on the link. Nothing crosses until you link this one."
    }
}

/// The traffic in the sidebar: what this Mac is asking whether to send, and what the others
/// added and it is asking whether to take. Nothing when there is nothing to ask.
struct MacLinkTraffic: View {
    @Environment(MacModel.self) private var model
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
