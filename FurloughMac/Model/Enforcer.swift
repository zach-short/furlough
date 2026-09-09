import AppKit
import CoreGraphics
import Foundation
import UserNotifications

/// Enforces the rules on the Mac, where there is no Screen Time API to do it. Once a second
/// it re-derives everything from persisted state: a blocked app that is running is asked to
/// quit and force-quit when its grace runs out (`QuitGrace`), every window of every running
/// browser showing a blocked site is sent to the shield page, the same list of blocked hosts
/// goes to the web filter (`WebFilter`) so a connection to one fails everywhere the browsers
/// cannot be read, and time spent in an open app or site counts against its daily budget. The
/// 5-minute warning and "Time's up" arrive as notifications, as on the phone.
@MainActor
final class Enforcer {
    static let shared = Enforcer()

    private(set) var lastDecision = Decision()
    let browsers = Browsers()
    let webFilter = WebFilter()
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var ledger = UsageLedger.load()
    private var lastTick = Date.now
    /// Apps asked to quit, and how long each has left before it is forced.
    private var grace = QuitGrace()
    /// When each target's shield was last shown, so a relaunch loop does not flash it.
    private var lastShield: [UUID: Date] = [:]
    /// Window ends already warned about today, per target.
    private var windowWarned: [UUID: Int] = [:]
    /// Whether the device's clock disagreed at the last tick, so the log gets one line per
    /// crossing rather than one a second.
    private var clockOff = false
    /// How far the device's clock is from Furlough's at the last tick. The web filter runs on
    /// the device's clock, so every date handed to it is moved by this.
    private var drift: TimeInterval = 0
    /// Furlough's own time as of the last tick, for the parts of the UI that ask outside one.
    private(set) var now = Date.now
    private let shield = ShieldPanel()
    private static let idleAfter: TimeInterval = 120

    func start() {
        guard timer == nil else { return }
        webFilter.onBlocked = { [weak self] host, app in self?.noteFiltered(host: host, app: app) }
        webFilter.start()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(reason: "app event") }
            })
        }
        // Moving the date forward is the obvious way to try to buy time, so react at once
        // rather than on the next tick; Policy holds the loosening changes either way.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(reason: "clock changed") }
        })
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(reason: nil) }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Logs and applies everything. Call it after any edit.
    @discardableResult
    func reconcile(now requested: Date? = nil, reason: String) -> Decision {
        var state = SharedStore.load()
        let now = requested ?? readClock(state)
        if Policy.applyDuePending(&state, now: now) {
            SharedStore.log("applied due pending changes during reconcile")
        }
        let decision = apply(&state, now: now, elapsed: 0)
        state.runtime.lastReconcile = now
        SharedStore.save(state)
        SharedStore.log(
            "reconcile (\(reason)): blocked apps=\(decision.blockedApps.count) sites=\(decision.blockedHosts.count)"
        )
        onChange?()
        return decision
    }

    /// Furlough's own time, logging the first tick on each side of the line so the log shows
    /// both when the device's clock went wrong and when it came back.
    @discardableResult
    private func readClock(_ state: SharedState) -> Date {
        let clock = state.clock()
        if !clock.isTrusted {
            if !clockOff {
                clockOff = true
                let direction = clock.drift > 0 ? "ahead" : "behind"
                SharedStore.log("device clock is \(Clock.describe(clock.drift)) \(direction); running on Furlough's own time")
            }
        } else if clockOff {
            clockOff = false
            SharedStore.log("device clock agrees again")
        }
        now = clock.now
        drift = clock.drift
        return clock.now
    }

    func usedSeconds(for id: UUID) -> Int {
        ledger.dayKey == Policy.dayKey(now) ? Int(ledger.seconds[id] ?? 0) : 0
    }

    #if DEBUG || TESTING_TOOLS
    /// Forgets today's counted usage and warnings, for Settings > Testing > Reset everything.
    func resetUsage() {
        ledger = UsageLedger(dayKey: Policy.dayKey(now))
        ledger.save()
        windowWarned = [:]
        lastShield = [:]
        grace.forgetAll()
    }
    #endif

    // MARK: The tick

    private func tick(reason: String?) {
        var state = SharedStore.load()
        let now = readClock(state)
        let elapsed = reason == nil ? min(max(0, now.timeIntervalSince(lastTick)), 5) : 0
        if reason == nil { lastTick = now }
        let before = state
        if Policy.applyDuePending(&state, now: now) {
            SharedStore.log("applied due pending changes")
        }
        if Policy.liftExpiredAnchor(&state.config, now: now) {
            SharedStore.log("a timed anchor's time had passed; lifted it")
        }
        apply(&state, now: now, elapsed: elapsed)
        if state != before {
            SharedStore.save(state)
            onChange?()
        }
    }

    /// Counts usage, marks warnings and exhaustion, then quits and redirects. Returns the
    /// decision it enforced.
    @discardableResult
    private func apply(_ state: inout SharedState, now: Date, elapsed: TimeInterval) -> Decision {
        let dayKey = Policy.dayKey(now)
        // The Mac is awake every second, so this counts a minute at a time; the phone counts
        // the same minutes in bigger pieces at its reconciles. See `Record.accumulate`.
        Record.accumulate(&state, now: now)
        if ledger.dayKey != dayKey {
            ledger = UsageLedger(dayKey: dayKey)
            ledger.save()
            windowWarned = [:]
        }
        var decision = Policy.decide(config: state.config, runtime: state.runtime, now: now)
        let front = Front.current(browsers: browsers, readsAddress: state.config.targets.contains { $0.kind.isHost })

        if elapsed > 0, !Self.isIdle(), let used = front.target(in: state.config),
           let rule = used.rule, decision.statuses[used.id]?.isAllowed == true {
            let seconds = (ledger.seconds[used.id] ?? 0) + elapsed
            ledger.seconds[used.id] = seconds
            ledger.save()
            let budget = rule.budget(on: Policy.weekday(now))
            if seconds >= Double(budget * 60), !state.runtime.isExhausted(used.id, dayKey: dayKey) {
                state.runtime.exhausted[used.id.uuidString] = dayKey
                Record.markSpent(used.id, in: &state, now: now)
                SharedStore.log("budget spent: \(used.displayName)")
                let next = Policy.nextOpen(in: rule, afterWeekday: Policy.weekday(now)).map { "Opens \(TimeFormat.nextOpen($0))." } ?? ""
                Notifier.post(
                    id: "exhausted-\(used.id.uuidString)",
                    title: "Time's up",
                    body: "You used your \(TimeFormat.budget(budget)) for \(used.displayName). \(next)"
                )
                decision = Policy.decide(config: state.config, runtime: state.runtime, now: now)
            } else if budget > Furlough.warningMinutes,
                      seconds >= Double((budget - Furlough.warningMinutes) * 60),
                      !state.runtime.wasWarned(used.id, dayKey: dayKey) {
                state.runtime.warned[used.id.uuidString] = dayKey
                Record.markWarned(used.id, in: &state, now: now)
                SharedStore.log("5 minutes of budget left: \(used.displayName)")
                Notifier.post(
                    id: "warning-\(used.id.uuidString)",
                    title: "5 minutes left",
                    body: "\(used.displayName) has \(Furlough.warningMinutes) minutes of budget left today."
                )
            }
        }

        // A window closing soon. A rule without windows has no closing time, only a budget, and
        // neither has the evening half of a night: its `until` is a time on the next morning,
        // which no minute of today is five minutes short of, so the warning waits for the
        // morning half and the hour the night really ends.
        let minute = Policy.minuteOfDay(now)
        for target in state.config.targets where target.rule?.isAllDay == false {
            guard case .open(let until) = decision.statuses[target.id], until - minute == Furlough.warningMinutes,
                  windowWarned[target.id] != until else { continue }
            windowWarned[target.id] = until
            Notifier.post(
                id: "closing-\(target.id.uuidString)-\(until)",
                title: "5 minutes left",
                body: "\(target.displayName) closes at \(TimeFormat.until(until))."
            )
        }

        enforceApps(decision: decision, config: state.config, runtime: state.runtime, now: now)
        enforceBrowser(decision: decision, config: state.config, runtime: state.runtime, now: now)
        // The web filter gets the same list, on the device's clock, together with the moment
        // Policy next allows a status to change: past that the extension blocks nothing on its
        // own, so a list left behind by a force quit cannot outlive the window it was true for.
        webFilter.sync(
            hosts: decision.blockedHosts,
            until: Policy.nextTransition(config: state.config, after: now).addingTimeInterval(drift)
        )
        lastDecision = decision
        return decision
    }

    /// The web filter dropped a connection to `host` from `app`. A browser the tab reader covers
    /// is already on its way to the shield page and gets no card; everything else — Firefox, a
    /// site saved to the Dock, an app loading a blocked site — gets the floating card, which is
    /// the only explanation it will see.
    private func noteFiltered(host: String, app: String) {
        let state = SharedStore.load()
        let appName = AppInfo.name(for: app) ?? (app.isEmpty ? "an app" : app)
        guard let target = state.config.target(host: host) else {
            SharedStore.log("web filter dropped \(host) for \(appName)")
            return
        }
        SharedStore.log("blocked \(host) in \(appName) (web filter)")
        guard browsers.kind(of: app) == nil,
              now.timeIntervalSince(lastShield[target.id] ?? .distantPast) > 8 else { return }
        lastShield[target.id] = now
        let status = lastDecision.statuses[target.id]
        let text = ShieldText.text(name: target.displayName, status: status, rule: target.rule)
        shield.show(
            name: target.displayName, title: text.title, subtitle: text.subtitle,
            icon: AppInfo.icon(for: app),
            glass: HourglassState.of(target, status: status ?? .blockedAllDay, runtime: state.runtime, now: now)
        )
    }

    private func enforceApps(decision: Decision, config: Config, runtime: RuntimeState, now: Date) {
        let running = NSWorkspace.shared.runningApplications
        grace.forget(except: Set(running.map(\.processIdentifier)))
        for app in running {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                  decision.blocks(app: bundleID) else { continue }
            // Over everything, only what a person could have opened: an app with a Dock
            // presence, and never one the Mac cannot do without. A listed app is a listed app.
            if !decision.blockedApps.contains(bundleID),
               app.activationPolicy != .regular || AppCatalog.excluded.contains(bundleID) {
                continue
            }
            let target = config.target(bundleID: bundleID)
            let name = target?.displayName ?? app.localizedName ?? bundleID
            let age = now.timeIntervalSince(app.launchDate ?? now)
            switch grace.step(pid: app.processIdentifier, age: age, now: now) {
            case .ask(let deadline):
                app.terminate()
                let status = target.flatMap { decision.statuses[$0.id] }
                SharedStore.log("asked \(name) to quit: \(status.map { TimeFormat.status($0) } ?? "in the anchor")")
                if let target, now.timeIntervalSince(lastShield[target.id] ?? .distantPast) > 8 {
                    lastShield[target.id] = now
                    let text = ShieldText.text(name: name, status: status, rule: target.rule)
                    shield.show(
                        name: name, title: text.title, subtitle: text.subtitle,
                        icon: AppInfo.icon(for: bundleID),
                        glass: HourglassState.of(target, status: status ?? .blockedAllDay, runtime: runtime, now: now),
                        grace: deadline.timeIntervalSince(now)
                    )
                }
            case .wait:
                // Inside its grace: the save dialog is the user's to answer.
                continue
            case .force(let first):
                app.forceTerminate()
                if first { SharedStore.log("force quit \(name)") }
            }
        }
    }

    /// Sends every window showing a blocked site to the shield page, in every running browser —
    /// not only the browser in front, and not only its front window. A blocked site left playing
    /// behind the window you are looking at is still a blocked site.
    private func enforceBrowser(decision: Decision, config: Config, runtime: RuntimeState, now: Date) {
        // `hasHost` rather than `kind.isHost`: an imported setup can carry a website as the
        // linked half of an app's row, and that site still needs the browser swept for it.
        guard config.targets.contains(where: \.hasHost) || decision.shieldsEverything else { return }
        for browser in browsers.snapshots() {
            for tab in browser.tabs {
                guard let host = tab.url.host()?.lowercased() else { continue }
                let text: (title: String, subtitle: String)
                let glass: HourglassState
                if let target = config.target(host: host) {
                    let status = decision.statuses[target.id]
                    let blocked = status.map { !$0.isAllowed } ?? target.hosts.contains { decision.blockedHosts.contains($0) }
                    guard blocked else { continue }
                    text = ShieldText.text(name: target.displayName, status: status, rule: target.rule)
                    glass = HourglassState.of(target, status: status ?? .blockedAllDay, runtime: runtime, now: now)
                } else {
                    // Not a site Furlough knows: only the anchor over everything blocks it, and
                    // then it wears the anchored shield under its own name.
                    guard decision.blocks(host: host) else { continue }
                    text = ShieldText.text(name: host, status: .anchored, rule: nil)
                    glass = .anchored
                }
                browsers.redirect(
                    browser.bundleID, kind: browser.kind, window: tab.window,
                    to: ShieldPage.url(title: text.title, subtitle: text.subtitle, glass: glass)
                )
                SharedStore.log("blocked \(host) in \(AppInfo.name(for: browser.bundleID) ?? browser.bundleID)")
            }
        }
    }

    /// No keyboard or mouse for two minutes: nothing is being used, whatever is in front.
    private static func isIdle() -> Bool {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .flagsChanged]
        let idle = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
        return idle > idleAfter
    }
}

/// What is in front of the user right now.
enum Front {
    case app(bundleID: String)
    case browser(bundleID: String, kind: Browsers.Kind, url: URL?)
    case nothing

    /// The address bar is only read when some website has a rule, so an app-only setup never
    /// asks macOS for browser access.
    @MainActor
    static func current(browsers: Browsers, readsAddress: Bool) -> Front {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return .nothing }
        if let kind = browsers.kind(of: bundleID) {
            let url = readsAddress ? browsers.currentURL(of: bundleID, kind: kind) : nil
            return .browser(bundleID: bundleID, kind: kind, url: url)
        }
        return .app(bundleID: bundleID)
    }

    /// The target being used: the front app, or the site in the front browser.
    func target(in config: Config) -> Target? {
        switch self {
        case .app(let bundleID): config.target(bundleID: bundleID)
        case .browser(_, _, let url): url?.host().flatMap { config.target(host: $0) }
        case .nothing: nil
        }
    }
}

/// Seconds of use per target for one day. Kept out of `RuntimeState` so the shared model
/// stays as it is on the phone, where iOS does the counting.
struct UsageLedger: Codable {
    var dayKey: String
    var seconds: [UUID: Double] = [:]

    private static let key = "furlough.mac.usage.v1"

    static func load() -> UsageLedger {
        if let data = SharedStore.defaults.data(forKey: key),
           let ledger = try? JSONDecoder().decode(UsageLedger.self, from: data) {
            return ledger
        }
        return UsageLedger(dayKey: Policy.dayKey(.now))
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            SharedStore.defaults.set(data, forKey: Self.key)
        }
    }
}

/// Names and icons for Mac apps, looked up by bundle identifier and cached.
@MainActor
enum AppInfo {
    private static var cache: [String: (name: String, icon: NSImage)?] = [:]

    static func lookup(_ bundleID: String) -> (name: String, icon: NSImage)? {
        if let cached = cache[bundleID] { return cached }
        var result: (name: String, icon: NSImage)?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            result = (Self.name(at: url), NSWorkspace.shared.icon(forFile: url.path))
        }
        cache[bundleID] = result
        return result
    }

    static func name(for bundleID: String) -> String? { lookup(bundleID)?.name }
    static func icon(for bundleID: String) -> NSImage? { lookup(bundleID)?.icon }

    static func name(at url: URL) -> String {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }
}

/// The page a blocked tab is sent to, bundled with the app. It draws Furlough's own hourglass
/// in the status the site is in, as the phone's shield does since it started rendering the real
/// drawing into its icon slot; `k` names the status and `d` asks for the lone grain.
enum ShieldPage {
    static func url(title: String, subtitle: String, glass: HourglassState = .doneForToday) -> URL {
        guard let file = Bundle.main.url(forResource: "Shield", withExtension: "html"),
              var components = URLComponents(url: file, resolvingAgainstBaseURL: false) else {
            return URL(string: "about:blank")!
        }
        components.queryItems = [
            URLQueryItem(name: "t", value: title),
            URLQueryItem(name: "s", value: subtitle),
            URLQueryItem(name: "k", value: key(for: glass)),
        ]
        if glass.dropsGrain { components.queryItems?.append(URLQueryItem(name: "d", value: "1")) }
        return components.url ?? file
    }

    /// Which of the page's five glasses to draw. A blocked site is never inside its window, so
    /// there is no draining state here; anything unrecognised falls back to a settled glass.
    static func key(for glass: HourglassState) -> String {
        if glass == .usedUp { return "spent" }
        if glass == .alwaysBlocked { return "blocked" }
        if glass == .unconfigured { return "unset" }
        if glass == .doneForToday { return "done" }
        return glass.sandLevel > 0.5 ? "soon" : "done"
    }
}
