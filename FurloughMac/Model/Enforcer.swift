import AppKit
import CoreGraphics
import Foundation
import UserNotifications

/// Enforces the rules on the Mac, where there is no Screen Time API to do it. Once a second
/// it re-derives everything from persisted state: a blocked app that is running is asked to
/// quit (and force-quit if it lingers), a blocked website in the front browser is sent to the
/// shield page, and time spent in an open app or site counts against its daily budget. The
/// 5-minute warning and "Time's up" arrive as notifications, as on the phone.
@MainActor
final class Enforcer {
    static let shared = Enforcer()

    private(set) var lastDecision = Decision()
    let browsers = Browsers()
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var ledger = UsageLedger.load()
    private var lastTick = Date.now
    /// Apps asked to quit and when, so a lingering one is force-quit a moment later.
    private var quitting: [pid_t: Date] = [:]
    /// When each target's shield was last shown, so a relaunch loop does not flash it.
    private var lastShield: [UUID: Date] = [:]
    /// Window ends already warned about today, per target.
    private var windowWarned: [UUID: Int] = [:]
    /// Whether the wall clock was ahead at the last tick, so the log gets one line per change.
    private var clockAhead = false
    private let shield = ShieldPanel()
    private static let forceQuitAfter: TimeInterval = 2
    private static let idleAfter: TimeInterval = 120

    func start() {
        guard timer == nil else { return }
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
    func reconcile(now: Date = .now, reason: String) -> Decision {
        var state = SharedStore.load()
        if Policy.applyDuePending(&state, now: now, trust: clockTrust(state, now: now)) {
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

    /// Reads the clock and logs the first tick on each side of the line, so the log shows both
    /// when the wall clock moved forward and when it came back.
    private func clockTrust(_ state: SharedState, now: Date) -> Clock.Trust {
        let trust = state.clockTrust(now: now)
        if case .movedForward(let drift) = trust {
            if !clockAhead {
                clockAhead = true
                SharedStore.log("clock is \(Clock.describe(drift)) ahead: loosening changes are held")
            }
        } else if clockAhead {
            clockAhead = false
            SharedStore.log("clock is back: pending changes can land again")
        }
        return trust
    }

    func usedSeconds(for id: UUID) -> Int {
        ledger.dayKey == Policy.dayKey(.now) ? Int(ledger.seconds[id] ?? 0) : 0
    }

    #if DEBUG
    /// Forgets today's counted usage and warnings, for Settings > Testing > Reset everything.
    func resetUsage() {
        ledger = UsageLedger(dayKey: Policy.dayKey(.now))
        ledger.save()
        windowWarned = [:]
        lastShield = [:]
    }
    #endif

    // MARK: The tick

    private func tick(reason: String?) {
        let now = Date.now
        let elapsed = reason == nil ? min(max(0, now.timeIntervalSince(lastTick)), 5) : 0
        if reason == nil { lastTick = now }
        var state = SharedStore.load()
        let before = state
        if Policy.applyDuePending(&state, now: now, trust: clockTrust(state, now: now)) {
            SharedStore.log("applied due pending changes")
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
            let budget = rule.dailyBudgetMinutes
            if seconds >= Double(budget * 60), !state.runtime.isExhausted(used.id, dayKey: dayKey) {
                state.runtime.exhausted[used.id.uuidString] = dayKey
                SharedStore.log("budget spent: \(used.displayName)")
                let next = Policy.nextOpen(in: rule, afterWeekday: Policy.weekday(now)).map { "Opens \(TimeFormat.nextOpen($0))." } ?? ""
                Notifier.post(title: "Time's up", body: "You used your \(TimeFormat.budget(budget)) for \(used.displayName). \(next)")
                decision = Policy.decide(config: state.config, runtime: state.runtime, now: now)
            } else if budget > Furlough.warningMinutes,
                      seconds >= Double((budget - Furlough.warningMinutes) * 60),
                      !state.runtime.wasWarned(used.id, dayKey: dayKey) {
                state.runtime.warned[used.id.uuidString] = dayKey
                SharedStore.log("5 minutes of budget left: \(used.displayName)")
                Notifier.post(title: "5 minutes left", body: "\(used.displayName) has \(Furlough.warningMinutes) minutes of budget left today.")
            }
        }

        // A window closing soon. A rule without windows has no closing time, only a budget.
        let minute = Policy.minuteOfDay(now)
        for target in state.config.targets where target.rule?.isAllDay == false {
            guard case .open(let until) = decision.statuses[target.id], until - minute == Furlough.warningMinutes,
                  windowWarned[target.id] != until else { continue }
            windowWarned[target.id] = until
            Notifier.post(title: "5 minutes left", body: "\(target.displayName) closes at \(TimeFormat.minute(until)).")
        }

        enforceApps(decision: decision, config: state.config, now: now)
        enforceBrowser(front: front, decision: decision, config: state.config, now: now)
        lastDecision = decision
        return decision
    }

    private func enforceApps(decision: Decision, config: Config, now: Date) {
        let running = NSWorkspace.shared.runningApplications
        let alive = Set(running.map(\.processIdentifier))
        quitting = quitting.filter { alive.contains($0.key) }
        for app in running {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                  decision.blockedApps.contains(bundleID) else { continue }
            let pid = app.processIdentifier
            if let asked = quitting[pid] {
                if now.timeIntervalSince(asked) >= Self.forceQuitAfter {
                    app.forceTerminate()
                    quitting[pid] = nil
                    SharedStore.log("force quit \(app.localizedName ?? bundleID)")
                }
                continue
            }
            quitting[pid] = now
            app.terminate()
            let target = config.target(bundleID: bundleID)
            let name = target?.displayName ?? app.localizedName ?? bundleID
            let status = target.flatMap { decision.statuses[$0.id] }
            SharedStore.log("quit \(name): \(status.map { TimeFormat.status($0) } ?? "in the anchor")")
            if let target, now.timeIntervalSince(lastShield[target.id] ?? .distantPast) > 8 {
                lastShield[target.id] = now
                let text = ShieldText.text(name: name, status: status, rule: target.rule)
                shield.show(name: name, title: text.title, subtitle: text.subtitle, icon: AppInfo.icon(for: bundleID))
            }
        }
    }

    private func enforceBrowser(front: Front, decision: Decision, config: Config, now: Date) {
        guard case .browser(let bundleID, let kind, let url) = front, let url,
              let host = url.host()?.lowercased(), let target = config.target(host: host) else { return }
        let status = decision.statuses[target.id]
        let blocked = status.map { !$0.isAllowed } ?? decision.blockedHosts.contains(target.host)
        guard blocked else { return }
        let text = ShieldText.text(name: target.displayName, status: status, rule: target.rule)
        browsers.redirect(bundleID, kind: kind, to: ShieldPage.url(title: text.title, subtitle: text.subtitle))
        SharedStore.log("blocked \(host) in \(AppInfo.name(for: bundleID) ?? bundleID)")
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

enum Notifier {
    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { SharedStore.log("notification failed: \(error.localizedDescription)") }
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

/// The page a blocked tab is sent to, bundled with the app.
enum ShieldPage {
    static func url(title: String, subtitle: String) -> URL {
        guard let file = Bundle.main.url(forResource: "Shield", withExtension: "html"),
              var components = URLComponents(url: file, resolvingAgainstBaseURL: false) else {
            return URL(string: "about:blank")!
        }
        components.queryItems = [URLQueryItem(name: "t", value: title), URLQueryItem(name: "s", value: subtitle)]
        return components.url ?? file
    }
}
