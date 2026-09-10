import SwiftUI

/// The pieces both apps draw the link with: an offer, the traffic waiting for an answer, a
/// three-way setting, the four things to know before joining, and one device on the roster.
///
/// Self-contained the way `CompanionNudge` is — Ember and the theme helpers only, no
/// `SectionLabel` or `CardDivider` — because Shared/UI is compiled into extensions that carry
/// none of each app's own components. Each app composes these into its Devices screen.

// MARK: - An offer

/// One question with a yes and a not-now: the shape `CompanionNudge` has, for anything the
/// link wants to ask. Amber, because it is an offer and never a warning.
struct LinkNudge: View {
    let symbol: String
    let text: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 1)
                Text(text)
                    .emberBody(12, .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Ember.amber)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .emberBody(12.5, .semibold)
                        .foregroundStyle(Ember.ground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Ember.amber, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onDismiss) {
                    Text("Not this time")
                        .emberBody(12.5, .semibold)
                        .foregroundStyle(Ember.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Ember.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ember.amber.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - The traffic

/// Everything the link is waiting on an answer for, on one half: what this device added and
/// has been told to ask before sending, and what the others added and this device has been
/// told to ask before taking. One card each, oldest first, and nothing at all when there is
/// nothing to ask — which is nearly always.
struct LinkTrafficCard: View {
    let outgoing: [SharedAddition]
    let arrivals: [SharedAdditions.Landing]
    /// "your Mac", "your iPhone and iPad": who a send would reach.
    let othersDescription: String
    /// What to call the device an arrival came from, by its id.
    let nameOf: (String) -> String
    let onSend: (SharedAddition) -> Void
    let onDeclineSend: (SharedAddition) -> Void
    let onAccept: (SharedAdditions.Landing) -> Void
    let onDeclineArrival: (SharedAdditions.Landing) -> Void

    var body: some View {
        if !outgoing.isEmpty || !arrivals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(arrivals, id: \.addition.id) { landing in
                    LinkNudge(
                        symbol: "arrow.down.to.line",
                        text: landing.summary(from: nameOf(landing.addition.origin)),
                        primaryTitle: "Block it here",
                        onPrimary: { onAccept(landing) },
                        onDismiss: { onDeclineArrival(landing) }
                    )
                }
                ForEach(outgoing) { addition in
                    LinkNudge(
                        symbol: "arrow.up.to.line",
                        text: "Send \(addition.title) to \(othersDescription)? Each will block what it can find under that name\(addition.rule == nil ? "." : ", on these hours.")",
                        primaryTitle: "Send it",
                        onPrimary: { onSend(addition) },
                        onDismiss: { onDeclineSend(addition) }
                    )
                }
            }
        }
    }
}

// MARK: - A three-way setting

/// Always · Ask · Never, under a title and a line saying what the thing is. The row every
/// setting about the link is, so the scale is learned once.
struct LinkChoiceRow: View {
    let title: String
    let detail: String
    let selection: LinkChoice
    let onPick: (LinkChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Text(detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ForEach(LinkChoice.allCases, id: \.self) { choice in
                    Button { onPick(choice) } label: {
                        Text(choice.title)
                            .emberBody(12, .semibold)
                            .foregroundStyle(choice == selection ? Ember.ground : Ember.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(choice == selection ? Ember.amber : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(choice == selection ? .clear : Ember.cardBorder, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(choice == selection ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - The four things to know

/// The guide a device is walked through before it joins: four numbered facts, none of them a
/// step to take, and the one action — Link this device — under all of them in the caller's
/// card. Numbered like a `GuideCard` so it reads as the same kind of thing, but nothing here
/// is live or done: it is read, not worked through.
struct LinkStepsCard: View {
    let platform: AnchorRecord.Platform

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(DeviceLink.steps(platform: platform).enumerated()), id: \.element.id) { index, step in
                if index > 0 { Rectangle().fill(Ember.cardBorder).frame(height: 1) }
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.07))
                        Circle().strokeBorder(Ember.cardBorder, lineWidth: 1)
                        Text("\(index + 1)")
                            .font(EmberFont.numerals(11))
                            .foregroundStyle(Ember.amber)
                    }
                    .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .emberDisplaySmall(13.5)
                            .foregroundStyle(Ember.cream)
                        Text(step.detail)
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .emberCard()
    }
}

// MARK: - One device

/// A device on the roster: its name, what it is, when it was last heard from, and the way to
/// take it off. The one for this device says so and carries Leave instead.
struct LinkedDeviceRow: View {
    let device: LinkedDevice
    let isThisDevice: Bool
    let now: Date
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ember.amber)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .emberBody(13, .semibold)
                        .foregroundStyle(Ember.cream)
                    if isThisDevice {
                        Text("this device")
                            .emberBody(11)
                            .foregroundStyle(Ember.faint)
                    }
                }
                Text(detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
            }
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Text(isThisDevice ? "Leave" : "Remove")
                    .emberBody(12, .semibold)
                    .foregroundStyle(Ember.ember)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var symbol: String {
        switch device.platform {
        case .phone: "iphone"
        case .pad: "ipad"
        case .mac: "laptopcomputer"
        }
    }

    private var detail: String {
        let kind = LinkedDevice.defaultName(for: device.platform)
        let key = device.canRelease ? " · holds a key" : ""
        let seen = now.timeIntervalSince(device.lastSeen)
        let heard: String = if seen < 120 {
            "heard from just now"
        } else if seen < 3600 {
            "heard \(Int(seen / 60)) min ago"
        } else if seen < 86_400 {
            "heard \(Int(seen / 3600)) h ago"
        } else {
            "heard \(Int(seen / 86_400)) d ago"
        }
        return "\(kind)\(key) · \(heard)"
    }
}
