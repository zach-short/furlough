import AppKit
import Foundation

/// The menu bar item: an hourglass, and the countdown while something is open.
///
/// AppKit rather than SwiftUI's `MenuBarExtra`, and not by preference. `MenuBarExtra` produces
/// no visible status item on this Mac (macOS 26): an app whose entire body is
/// `MenuBarExtra { Text("test") } label: { Image(systemName: "hourglass") }` shows nothing
/// either and leaves the same four offscreen menu-bar-sized windows behind, so it was never
/// anything our label was doing. HANDOFF step 3 has the trace. An `NSStatusItem` is in keeping
/// anyway: the shield is already an `NSPanel` and the watchdog already `SMAppService`.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: MacModel
    private var item: NSStatusItem?
    private var timer: Timer?

    init(model: MacModel) {
        self.model = model
        super.init()
    }

    /// Puts the item in the menu bar. Idempotent, so a second call cannot leave two hourglasses.
    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        self.item = item
        refresh()
        // Worth a line, because this failure is silent: on some Macs — this one, 2026-09-08 —
        // macOS shows no third-party menu bar item at all, and the log is then the only way to
        // tell "Furlough never added it" from "macOS did not draw it".
        SharedStore.log("menu bar: item added, visible=\(item.isVisible)")
        // The same shape as the enforcer's tick: built by hand and added to the common mode,
        // so the countdown keeps moving while a menu is open or a window is being dragged.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The hourglass, plus the countdown when something is open. Drawn from `Policy.summary`,
    /// the same source the widget and the phone's hero read, so the three cannot disagree.
    private func refresh() {
        guard let button = item?.button else { return }
        let now = model.clock.now
        let summary = Policy.summary(state: model.state, now: now)
        let isOpen = summary.openUntil != nil || !summary.allDayNames.isEmpty
        let symbol = isOpen ? "hourglass.bottomhalf.filled" : "hourglass"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Furlough")
        if let until = summary.openUntil {
            // Monospaced digits, or the item resizes on every tick and the whole right-hand
            // side of the menu bar shuffles with it.
            button.attributedTitle = NSAttributedString(
                string: " \(TimeFormat.countdown(from: now, to: until))",
                attributes: [.font: NSFont.monospacedDigitSystemFont(
                    ofSize: NSFont.systemFontSize, weight: .regular
                )]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    /// Rebuilt every time it opens, so the statuses are current rather than as of install.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = model.clock.now
        let targets = model.state.config.targets
        if targets.isEmpty {
            menu.addItem(disabled("Nothing in Furlough yet"))
        }
        for target in targets {
            let status = Policy.status(
                of: target, config: model.state.config, runtime: model.state.runtime, now: now
            )
            menu.addItem(disabled("\(target.displayName): \(TimeFormat.status(status))"))
        }
        menu.addItem(.separator())
        let open = NSMenuItem(
            title: "Open Furlough", action: #selector(openFurlough), keyEquivalent: "o"
        )
        open.target = self
        menu.addItem(open)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// The way to the window from the menu bar, where Furlough otherwise sits with none.
    @objc private func openFurlough() {
        MacAppDelegate.showWindow()
    }
}
