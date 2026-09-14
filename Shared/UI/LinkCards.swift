import SwiftUI

/// Self-contained like `CompanionNudge` — Ember/theme helpers only, no `SectionLabel` or
/// `CardDivider` — since Shared/UI is compiled into extensions that lack each app's own
/// components. Each app composes these into its Devices screen.

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

/// Everything waiting on an answer: outgoing (added here, confirm before sending) and
/// arrivals (added elsewhere, confirm before taking). Usually empty.
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
                        text: Self.offer(addition, to: othersDescription),
                        primaryTitle: "Send it",
                        onPrimary: { onSend(addition) },
                        onDismiss: { onDeclineSend(addition) }
                    )
                }
            }
        }
    }

    /// Anchor half isn't "block it" — it queues on each device's own anchor list until one
    /// drops, and only an iPhone tag restores it; said here since it should be known before
    /// the tap.
    static func offer(_ addition: SharedAddition, to others: String) -> String {
        switch addition.half {
        case .rules:
            return "Send \(addition.title) to \(others)? Each will block what it can find under that name\(addition.rule == nil ? "." : ", on these hours.")"
        case .anchor:
            return "\(addition.title) is on this Anchor's list. Tell \(others)? Each holds what it can find under that name whenever its anchor drops."
        }
    }
}

// MARK: - A three-way setting

/// Always · Ask · Never — one shared row so the scale is learned once.
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

/// Numbered like `GuideCard` for visual consistency, but these are facts to read, not steps
/// to complete — the join action lives in the caller's card below.
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
