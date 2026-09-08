import AppKit
import SwiftUI

/// The floating card shown when Furlough quits a blocked app: what was blocked and when it
/// opens next. Non-activating, above everything, gone after a few seconds or a click.
@MainActor
final class ShieldPanel {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(name: String, title: String, subtitle: String, icon: NSImage?) {
        let card = ShieldCard(name: name, title: title, subtitle: subtitle, icon: icon) { [weak self] in self?.hide() }
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
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
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

/// The Mac shield: the iOS block screen's copy on an Ember Glass card.
struct ShieldCard: View {
    let name: String
    let title: String
    let subtitle: String
    let icon: NSImage?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "hourglass")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Ember.amber)
                }
            }
            .frame(width: 44, height: 44)
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
