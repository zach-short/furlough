import AppKit
import CoreGraphics
import Foundation
import UserNotifications

/// Enforces rules on the Mac, where there is no Screen Time API; re-derives everything from
/// persisted state once a second.
@MainActor
final class Enforcer {
    static let shared = Enforcer()

    private(set) var lastDecision = Decision()
    let browsers = Browsers()
    let webFilter = WebFilter()
    var onChange: (() -> Void)?
    /// No midnight DeviceActivity callback on Mac; the ledger's day-boundary check stands in
    /// for it. See `MacModel.start()`.
    var onDayRollover: ((SharedState) -> Void)?

    private var timer: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var ledger = UsageLedger.load()
    /// The days before today, kept so the Mac stops throwing away the only measurement of used
    /// time either half of Furlough has. Filed and pruned at the day boundary below.
    private var history = UsageHistory.load()
    private var lastTick = Date.now
    /// No DeviceActivity callback on Mac to fire exactly at a drop minute; each tick instead
    /// checks whether a scheduled drop fell between this mark and now, which also catches one
    /// missed while the Mac was asleep.
    private var lastScheduleCheck = Date.now
    private var grace = QuitGrace()
    /// Debounces repeated shield flashes from a relaunch loop.
    private var lastShield: [UUID: Date] = [:]
    private var windowWarned: [UUID: Int] = [:]
    /// Logs once per clock-trust crossing, not every tick.
    private var clockOff = false
    /// The web filter runs on the device's clock; dates handed to it are shifted by this.
    private var drift: TimeInterval = 0
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
        // React to clock changes immediately (a way to try to buy time); Policy still gates loosening.
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

    /// Logs only at each clock-trust transition, not every tick.
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

    /// What has been measured, today included — today's seconds are still in the live ledger,
    /// which is only filed into the history when the day turns over.
    var measured: UsageHistory {
        var combined = history
        combined.record(ledger.seconds, on: ledger.dayKey)
        return combined
    }

    #if DEBUG || TESTING_TOOLS
    func resetUsage() {
        ledger = UsageLedger(dayKey: Policy.dayKey(now))
        ledger.save()
        history = UsageHistory()
        history.save()
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
        checkScheduledDrop(&state, now: now)
        if Policy.liftExpiredAnchor(&state.config, now: now) {
            SharedStore.log("a timed anchor's time had passed; lifted it")
        }
        apply(&state, now: now, elapsed: elapsed)
        if state != before {
            SharedStore.save(state)
            onChange?()
        }
    }

    /// Applies a schedule's drop, if one fell in the window since the last tick.
    /// `Policy.scheduledDrop` is idempotent, matching the phone's monitor extension behavior.
    private func checkScheduledDrop(_ state: inout SharedState, now: Date) {
        defer { lastScheduleCheck = now }
        guard let due = state.config.anchor.schedules.nextDrop(after: lastScheduleCheck), due <= now,
              Policy.scheduledDrop(&state.config, minute: Policy.minuteOfDay(due), now: now) != nil
        else { return }
        let dropped = state.config.anchor
        let lift = dropped.until.map { " until \(TimeFormat.clock($0))" } ?? " until you scan your tag"
        SharedStore.log("dropped anchor on schedule: \(dropped.heldDescription)\(lift)")
        Notifier.post(id: "anchor-dropped", kind: .anchorDropped, title: "Anchor dropped", body: "\(dropped.heldDescription) locked\(lift).")
        AnchorSync.publish(dropped, origin: .drop, now: now)
    }

    @discardableResult
    private func apply(_ state: inout SharedState, now: Date, elapsed: TimeInterval) -> Decision {
        let dayKey = Policy.dayKey(now)
        // Mac counts a second at a time; the phone batches at its reconciles. See `Record.accumulate`.
        Record.accumulate(&state, now: now)
        if ledger.dayKey != dayKey {
            // The day that just ended is the only complete measurement the Mac ever has, so it
            // is filed before the ledger is replaced. This is the once-a-day moment that
            // happens whether or not anyone opens Furlough, so the prune belongs here too
            // rather than on a second timer of its own.
            history.record(ledger.seconds, on: ledger.dayKey)
            history.prune(on: now)
            history.save()
            ledger = UsageLedger(dayKey: dayKey)
            ledger.save()
            windowWarned = [:]
            onDayRollover?(state)
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
                    kind: .budgetSpent,
                    title: "Time's up",
                    body: "You used your \(TimeFormat.budget(budget)) for \(used.displayName). \(next)"
                )
                decision = Policy.decide(config: state.config, runtime: state.runtime, now: now)
            } else if budget > Furlough.warningMinutes,
                      seconds >= Double((budget - Furlough.warningMinutes) * 60),
                      !state.runtime.wasWarned(used.id, dayKey: dayKey) {
                state.runtime.warned[used.id.uuidString] = dayKey
                // Keep in sync with `warned`; a half-set pair goes unnoticed until much later.
                state.runtime.warnedAt[used.id.uuidString] = now
                Record.markWarned(used.id, in: &state, now: now)
                SharedStore.log("5 minutes of budget left: \(used.displayName)")
                Notifier.post(
                    id: "warning-\(used.id.uuidString)",
                    kind: .budgetWarning,
                    title: "5 minutes left",
                    body: "\(used.displayName) has \(Furlough.warningMinutes) minutes of budget left today."
                )
            }
        }

        // Overnight rules: `until` falls on the next morning, so this warning only fires
        // for the morning half.
        let minute = Policy.minuteOfDay(now)
        for target in state.config.targets where target.rule?.isAllDay == false {
            guard case .open(let until) = decision.statuses[target.id], until - minute == Furlough.warningMinutes,
                  windowWarned[target.id] != until else { continue }
            windowWarned[target.id] = until
            Notifier.post(
                id: "closing-\(target.id.uuidString)-\(until)",
                kind: .windowClosing,
                title: "5 minutes left",
                body: "\(target.displayName) closes at \(TimeFormat.until(until))."
            )
        }

        enforceApps(decision: decision, config: state.config, runtime: state.runtime, now: now)
        enforceBrowser(decision: decision, config: state.config, runtime: state.runtime, now: now)
        // `until` is the next policy transition; past it the extension blocks nothing, so a
        // list left behind by a force quit can't outlive its window.
        webFilter.sync(
            hosts: decision.blockedHosts,
            until: Policy.nextTransition(config: state.config, after: now).addingTimeInterval(drift)
        )
        lastDecision = decision
        return decision
    }

    /// Browsers the tab reader covers already redirect to the shield page; only other apps
    /// (Firefox, a Dock-saved site, etc.) get this floating card.
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
            // Skip background/non-Dock apps unless explicitly listed.
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

    /// Sweeps every window of every running browser, not just the front one.
    private func enforceBrowser(decision: Decision, config: Config, runtime: RuntimeState, now: Date) {
        // `hasHost`, not `kind.isHost`: a website linked to an app's row still needs sweeping.
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
                    // Unknown site: only an all-blocking anchor covers it.
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

    private static func isIdle() -> Bool {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .flagsChanged]
        let idle = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
        return idle > idleAfter
    }
}

enum Front {
    case app(bundleID: String)
    case browser(bundleID: String, kind: Browsers.Kind, url: URL?)
    case nothing

    /// Reads the address bar only when a host rule exists, so app-only setups never trigger
    /// the Automation permission prompt.
    @MainActor
    static func current(browsers: Browsers, readsAddress: Bool) -> Front {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return .nothing }
        if let kind = browsers.kind(of: bundleID) {
            let url = readsAddress ? browsers.currentURL(of: bundleID, kind: kind) : nil
            return .browser(bundleID: bundleID, kind: kind, url: url)
        }
        return .app(bundleID: bundleID)
    }

    func target(in config: Config) -> Target? {
        switch self {
        case .app(let bundleID): config.target(bundleID: bundleID)
        case .browser(_, _, let url): url?.host().flatMap { config.target(host: $0) }
        case .nothing: nil
        }
    }
}

/// Kept out of `RuntimeState` so the shared model matches iOS, where iOS does the counting.
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

/// The store side of `UsageHistory`, beside `UsageLedger`'s and for the same reason: the pure
/// type in `Shared/Core` knows nothing about defaults. Fourteen days of `[UUID: Double]` for a
/// couple of dozen targets is a few kilobytes — measured at 2.8 KB for 25 targets × 14 days.
extension UsageHistory {
    static func load() -> UsageHistory {
        guard let data = SharedStore.defaults.data(forKey: storeKey),
              let history = try? JSONDecoder().decode(UsageHistory.self, from: data)
        else { return UsageHistory() }
        return history
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            SharedStore.defaults.set(data, forKey: Self.storeKey)
        }
    }
}

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

/// `k` (status) and `d` (lone grain) are query params read by Shield.html's hourglass drawing.
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

    /// No draining state here: a blocked site is never inside its window.
    static func key(for glass: HourglassState) -> String {
        if glass == .usedUp { return "spent" }
        if glass == .alwaysBlocked { return "blocked" }
        if glass == .unconfigured { return "unset" }
        if glass == .doneForToday { return "done" }
        return glass.sandLevel > 0.5 ? "soon" : "done"
    }
}
