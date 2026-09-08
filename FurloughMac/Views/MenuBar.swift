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
        // Deferred, because a status item's button frame is (0, 0, w, 0) until macOS lays it
        // out — measuring at creation is what made this take a session to diagnose.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.reportPlacement() } }
        // The same shape as the enforcer's tick. Nothing counts down in the bar any more, but
        // the glass still has to fill and empty as windows open and close.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The hourglass alone, filled while something is open. Drawn from `Policy.summary`, the
    /// same source the widget and the phone's hero read, so the three cannot disagree.
    ///
    /// Icon only, and that is the point: with the countdown beside it the item was about 85
    /// points wide, and on a notched Mac whose menu bar is full macOS pushes an item that big
    /// under the notch, where it cannot be seen at all. At 27 points it takes one slot. The
    /// countdown moved to the top of the menu, one click away.
    private func refresh() {
        guard let button = item?.button else { return }
        let summary = Policy.summary(state: model.state, now: model.clock.now)
        let isOpen = summary.openUntil != nil || !summary.allDayNames.isEmpty
        button.image = NSImage(
            systemSymbolName: isOpen ? "hourglass.bottomhalf.filled" : "hourglass",
            accessibilityDescription: isOpen ? "Furlough, something is open" : "Furlough"
        )
    }

    /// Says where macOS actually put the item, because not being able to see it is otherwise
    /// a silent failure with no error anywhere.
    ///
    /// A full menu bar on a notched Mac does not drop the overflow, it places it *under the
    /// camera housing*, where `isVisible` is `true`, the frame is real, and nothing is on
    /// screen. The screen's two auxiliary areas are the usable strips either side of the notch,
    /// so an item intersecting neither is behind it.
    private func reportPlacement() {
        guard let frame = item?.button?.window?.frame, let screen = NSScreen.main else { return }
        let beside = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
        guard !beside.isEmpty else {
            SharedStore.log("menu bar: item added")
            return
        }
        if beside.contains(where: { $0.intersects(frame) }) {
            SharedStore.log("menu bar: item added")
        } else {
            SharedStore.log(
                "menu bar: item is behind the notch and cannot be seen — the menu bar is full."
                + " Remove an item (⌘-drag it out, or System Settings > Control Center)."
            )
        }
    }

    /// Rebuilt every time it opens, so the statuses are current rather than as of install.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = model.clock.now
        // The countdown the item used to carry. It does not tick — a menu is built when it
        // opens and then stands still — but it is right at the moment it is read.
        if let until = Policy.summary(state: model.state, now: now).openUntil {
            menu.addItem(disabled("\(TimeFormat.countdown(from: now, to: until)) left"))
            menu.addItem(.separator())
        }
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
