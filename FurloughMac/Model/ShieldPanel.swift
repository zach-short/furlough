import AppKit
import SwiftUI

@MainActor
final class ShieldPanel {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// `grace` is a duration, not a date: the card renders against the system clock, Furlough its own.
    func show(
        name: String, title: String, subtitle: String, icon: NSImage?,
        glass: HourglassState = .doneForToday, grace: TimeInterval? = nil
    ) {
        let card = ShieldCard(name: name, title: title, subtitle: subtitle, icon: icon, glass: glass, grace: grace) { [weak self] in self?.hide() }
        let hosting = NSHostingView(rootView: card)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.setContentSize(size)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY + frame.height * 0.18))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        hideTask?.cancel()
        // +1s so the countdown visibly reaches zero before the panel hides.
        let seconds = grace.map { $0 + 1 } ?? 7
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }
}

struct ShieldCard: View {
    let name: String
    let title: String
    let subtitle: String
    let icon: NSImage?
    /// Live SwiftUI view here, unlike the static image iOS's shield gets.
    var glass: HourglassState = .doneForToday
    var grace: TimeInterval?
    let onDismiss: () -> Void

    /// Below this, the countdown would vanish before it could be read.
    private static let worthShowing: TimeInterval = 5

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LivingHourglass(state: glass)
                .frame(width: 40, height: 53)
                .compositingGroup()
                .shadow(color: (glass.glow ?? .clear).opacity(0.4), radius: 12)
                .overlay(alignment: .bottomTrailing) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                            .offset(x: 6, y: 2)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Furlough", color: Ember.amber)
                Text(title)
                    .emberDisplaySmall(17)
                    .foregroundStyle(Ember.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .emberBody(12.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let grace, grace >= Self.worthShowing {
                    Text("Quitting in \(Date.now.addingTimeInterval(grace), style: .timer) — save your work")
                        .emberBody(12)
                        .foregroundStyle(Ember.amber)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Ember.faint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(Ember.ground.opacity(0.96), in: RoundedRectangle(cornerRadius: Ember.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Ember.cardRadius, style: .continuous)
                .strokeBorder(Ember.cardBorder, lineWidth: 1)
        )
        .shadow(color: Ember.ember.opacity(0.25), radius: 30, y: 8)
        .padding(24)
        .preferredColorScheme(.dark)
    }
}
