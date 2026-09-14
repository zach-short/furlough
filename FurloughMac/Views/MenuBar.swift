import AppKit
import Foundation
import SwiftUI

// NSStatusItem, not SwiftUI's MenuBarExtra — MenuBarExtra shows no visible status item on
// macOS 26 (see HANDOFF step 3).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: MacModel
    private var item: NSStatusItem?
    private var timer: Timer?
    // Cached so an unchanged tick skips redraw.
    private var lastGlass: HourglassState?
    private var lastDark = true
    private var lastImage: NSImage?
    // Under 40pt draws the bolder chip form (same as the 12pt row chips).
    private static let glassSize = NSSize(width: 13.5, height: 18)
    private static let trendSize = NSSize(width: 210, height: 64)
    private static let placementAttempts = 20
    private static let placementRetry: TimeInterval = 0.1

    init(model: MacModel) {
        self.model = model
        super.init()
    }

    // Idempotent — guards against a second status item.
    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        self.item = item
        refresh()
        // Deferred: a status item's button frame is (0,0,w,0) until macOS lays it out.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.reportPlacement() } }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // Icon only — a wider item (with countdown) gets pushed under the notch on a full menu
    // bar and is invisible. The countdown lives at the top of the menu instead.
    private func refresh() {
        guard let button = item?.button else { return }
        let now = model.clock.now
        let summary = Policy.summary(state: model.state, now: now)
        var state = HourglassState.of(summary, now: now)
        // Rounded to 1/40 — finer than a pixel at this size, avoids per-second redraws while
        // still animating.
        state.sandLevel = (state.sandLevel * 40).rounded() / 40
        state.moundLevel = (state.moundLevel * 40).rounded() / 40
        // Menu bar theme follows the desktop picture, not just system appearance — draw in
        // ink on light so the glass isn't a smudge.
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if state != lastGlass || isDark != lastDark || lastImage == nil {
            lastGlass = state
            lastDark = isDark
            let isOpen = summary.openUntil != nil || !summary.allDayNames.isEmpty
            lastImage = Self.still(
                state, onDark: isDark,
                label: isOpen ? "Furlough, something is open" : "Furlough"
            )
            lastImage = lastImage ?? NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Furlough")
        }
        button.image = lastImage
    }

    // Never isTemplate: AppKit would flatten the colored sand/glow to one tint.
    private static func still(_ state: HourglassState, onDark: Bool = true, label: String = "Furlough") -> NSImage? {
        var state = state
        if !onDark {
            state.glass = .ink
            // Glow reads as a smudge on a light background.
            state.glow = nil
        }
        let renderer = ImageRenderer(
            content: HourglassView(state: state, phase: 0, motion: false)
                .frame(width: glassSize.width, height: glassSize.height)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.isOpaque = false
        let image = renderer.nsImage
        image?.isTemplate = false
        image?.accessibilityDescription = label
        return image
    }

    // A full menu bar pushes overflow items under the notch — isVisible true, frame real, but
    // invisible. The frame also stays (0,0,w,0) for a few run-loop turns after creation, so
    // this polls until it's actually laid out before judging visibility.
    private func reportPlacement(attempt: Int = 0) {
        let frame = item?.button?.window?.frame ?? .zero
        guard frame.height > 0, frame.origin.y > 0 else {
            guard attempt < Self.placementAttempts else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.placementRetry) {
                MainActor.assumeIsolated { self.reportPlacement(attempt: attempt + 1) }
            }
            return
        }
        // Use the screen the item landed on, not NSScreen.main — an external display's menu
        // bar has no notch.
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        else { return }
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = model.clock.now
        // Built once per opening — NSMenu content doesn't tick live once shown.
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
            let row = disabled("\(target.displayName): \(TimeFormat.status(status))")
            // A menu draws in the system's appearance, not the bar's — ask NSApp, not the button.
            let onDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            row.image = Self.still(
                HourglassState.of(target, status: status, runtime: model.state.runtime, now: now),
                onDark: onDark, label: target.displayName
            )
            menu.addItem(row)
        }
        if let trend = trendItem(now: now) {
            menu.addItem(.separator())
            menu.addItem(disabled("Held shut, last seven days"))
            menu.addItem(trend)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(
            title: "Open Furlough", action: #selector(openFurlough), keyEquivalent: "o"
        )
        open.target = self
        menu.addItem(open)
    }

    // NSMenuItem can host a view directly (unlike NSStatusItem's button, which needs an image).
    private func trendItem(now: Date) -> NSMenuItem? {
        let bars = Record.week(model.state.runtime.days, upTo: now)
        guard bars.contains(where: { $0.shieldedMinutes > 0 }) else { return nil }
        let item = NSMenuItem()
        let view = NSHostingView(rootView: MenuTrend(bars: bars))
        view.frame = NSRect(x: 0, y: 0, width: Self.trendSize.width, height: Self.trendSize.height)
        item.view = view
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openFurlough() {
        MacAppDelegate.showWindow()
    }
}

// Hand-rolled rather than Swift Charts — seven rects don't need a framework dependency.
// Uses system label/secondary colors, not Furlough's cream: menus follow system appearance,
// not the bar's.
struct MenuTrend: View {
    var bars: [Record.DayBar]
    private var letters: [String] { Calendar.current.veryShortWeekdaySymbols }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(bars) { bar in
                    VStack(spacing: 4) {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.09))
                            .frame(width: 12, height: 30)
                            .overlay(alignment: .bottom) {
                                Capsule(style: .continuous)
                                    .fill(bar.isToday ? Ember.amber : Ember.ember)
                                    .frame(height: max(bar.fraction * 30, bar.shieldedMinutes > 0 ? 3 : 0))
                            }
                        Text(letter(bar.weekday))
                            .font(.system(size: 9, weight: bar.isToday ? .bold : .regular))
                            .foregroundStyle(bar.isToday ? Color.primary : Color.secondary)
                    }
                }
            }
            Text(total)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func letter(_ weekday: Int) -> String {
        let index = weekday - 1
        return letters.indices.contains(index) ? letters[index] : ""
    }

    private var total: String {
        let minutes = bars.reduce(0) { $0 + $1.shieldedMinutes }
        return minutes > 0 ? "\(TimeFormat.budget(minutes)) in seven days" : "Nothing held shut"
    }
}
