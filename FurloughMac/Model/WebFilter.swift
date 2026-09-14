import AppKit
import Foundation
import Security
import NetworkExtension
import Observation
import SystemExtensions

/// The app's side of the web filter: installs the system extension, keeps its filter
/// configuration on, pushes it the hosts to block, and listens for what it drops.
///
/// macOS can switch the extension off in System Settings without telling anyone; this is the
/// one place the app finds out whether it's actually running.
@MainActor
@Observable
final class WebFilter {
    enum Status: Equatable {
        /// A system extension only loads from an app inside /Applications.
        case notInApplications
        case notInstalled
        case installing
        /// macOS is waiting for the person to allow the extension in System Settings.
        case awaitingApproval
        /// Installed once, and since switched off in System Settings.
        case disabledInSettings
        /// The extension is enabled but its filter configuration is off or gone, so it sees
        /// nothing. Turning it on again asks macOS's "filter network content" question again.
        case filterOff
        case on
        /// The extension is on, but macOS refused the *second* question — the one that lets it
        /// see traffic. Distinct from `failed`: the toggle shows on in System Settings here.
        case filterDenied(String, prompted: Bool)
        case failed(String)

        var label: String {
            switch self {
            case .notInApplications: "Needs the Applications folder"
            case .notInstalled: "Not installed"
            case .installing: "Installing…"
            case .awaitingApproval: "Waiting for approval"
            case .disabledInSettings: "Off in System Settings"
            case .filterOff: "Installed, not filtering"
            case .filterDenied: "Not allowed to filter"
            case .on: "On"
            case .failed: "Failed"
            }
        }

        var isOn: Bool { self == .on }

        /// What to do next: one action at a time, in the order it has to be done.
        ///
        /// Network Extensions exists only under System Settings' By Category view — under By
        /// App (which may open by default) there is only a plain Furlough entry that leads
        /// nowhere. See step 4 below.
        var guidance: Guidance {
            switch self {
            case .notInApplications:
                Guidance(
                    lead: "macOS loads a system extension only from an app in the Applications folder.",
                    steps: [
                        Guidance.Step(text: "Quit Furlough."),
                        Guidance.Step(text: "Move Furlough into your Applications folder."),
                        Guidance.Step(text: "Open it again, then install the filter from Settings > Web."),
                    ]
                )
            case .notInstalled:
                Guidance(
                    lead: "Installing asks you for two things: the extension itself, in System Settings, and then permission to filter. Both are yours to give, and Settings > Web takes it back out whenever you like."
                )
            case .installing:
                Guidance(lead: "Asking macOS. This takes a moment.")
            case .awaitingApproval:
                Guidance(
                    lead: "macOS is waiting for you in System Settings. Nothing is filtered until this is done.",
                    steps: Self.approvalSteps(verb: "Switch on")
                )
            case .disabledInSettings:
                Guidance(
                    lead: "The extension is installed and switched off, so websites are enforced by the tab reader alone.",
                    steps: Self.approvalSteps(verb: "Switch back on")
                )
            case .filterOff:
                Guidance(
                    lead: "macOS has the extension but is sending it nothing to look at.",
                    steps: [
                        Guidance.Step(text: "Turn the filter on.", action: .turnFilterOn),
                        Guidance.Step(text: "Click Allow.", figure: .allowDialog),
                    ]
                )
            case .on:
                Guidance(
                    lead: "The web filter is on. Firefox, a site saved to the Dock, and anything else that opens a blocked address are refused the connection.\n\nWhile something is blocked, connections that cannot be named are refused over QUIC and the browser falls back to the ordinary kind, where the name can be read. That is invisible, and only while a rule is in force."
                )
            case .filterDenied(let reason, let prompted) where prompted:
                Guidance(
                    lead: "The extension is installed and switched on. What was refused is the second permission, the one that lets it look at traffic: \u{201C}\(reason)\u{201D}.",
                    steps: [
                        Guidance.Step(text: "Turn the filter on. macOS asks again.", action: .turnFilterOn),
                        Guidance.Step(text: "Click Allow.", figure: .allowDialog),
                    ],
                    caution: "Login Items & Extensions is already right \u{2014} the switch you turned on there is the extension, and it is on. Nothing on that page needs another visit."
                )
            case .filterDenied(let reason, _):
                Guidance(
                    lead: "The extension is installed and switched on, but macOS refused to let it filter without asking you anything: \u{201C}\(reason)\u{201D}. It came back too fast for a question to have been put up, so there is no prompt you missed.",
                    steps: [
                        Guidance.Step(text: "Open System Settings, then Network.", action: .openSystemSettings),
                        Guidance.Step(
                            text: "Look for a Furlough filter left there by an earlier attempt, and remove it.",
                            note: "A configuration left behind is the usual reason macOS refuses on its own. While one is there the question is never asked again."
                        ),
                        Guidance.Step(text: "Come back and turn the filter on.", action: .turnFilterOn),
                    ],
                    caution: "Login Items & Extensions is already right \u{2014} the switch you turned on there is the extension, and it is on. If this keeps happening, Copy diagnostics below says what the extension and the permission each look like from in here."
                )
            case .failed(let reason):
                Guidance(
                    lead: reason,
                    caution: "This failed before macOS put any question up, so there is nothing waiting in System Settings to allow. Copy diagnostics under Settings > Web says what the extension and the filter each look like from here."
                )
            }
        }

        /// One step at a time: the row is easy to miss below a list that looks complete, then
        /// behind a segmented control that may default to the wrong half.
        private static func approvalSteps(verb: String) -> [Guidance.Step] {
            [
                Guidance.Step(text: "Open System Settings.", figure: .systemSettings, action: .openSystemSettings),
                Guidance.Step(text: "Click General, then Login Items & Extensions.", figure: .general),
                Guidance.Step(
                    text: "Scroll all the way down, to Extensions.",
                    note: "Furlough appears twice on the way down, under Open at Login and under App Background Activity. Those are the app and its watchdog. Keep going past both.",
                    figure: .scrollDown
                ),
                Guidance.Step(
                    text: "Click By Category.",
                    note: "This is the one everybody misses. Under By App there is no Network Extensions row at all \u{2014} just a Furlough entry, which is a different thing and leads nowhere.",
                    figure: .byCategory
                ),
                Guidance.Step(text: "Click the \u{24D8} beside Network Extensions.", figure: .networkExtensionsRow),
                Guidance.Step(text: "\(verb) Furlough Web Filter. macOS asks for your password.", figure: .furloughToggle),
                Guidance.Step(text: "Come back here.", action: .checkAgain),
            ]
        }
    }

    struct Guidance: Equatable {
        var lead: String
        var steps: [Step] = []
        var caution: String?

        struct Step: Equatable {
            var text: String
            /// Shown inline at the step, not in a block read after the mistake.
            var note: String?
            /// Drawn, not screenshotted: screenshots go stale with each System Settings redesign.
            var figure: Figure?
            var action: Action?
        }

        enum Figure: Equatable {
            case systemSettings
            case general
            case scrollDown
            /// The segmented control that hides Network Extensions under By App.
            case byCategory
            case networkExtensionsRow
            case furloughToggle
            case allowDialog
        }

        /// An enum, not a closure, so onboarding and Settings share the same meaning per step.
        enum Action: Equatable {
            case openSystemSettings, checkAgain, turnFilterOn

            var title: String {
                switch self {
                case .openSystemSettings: "Open System Settings"
                case .checkAgain: "Check again"
                case .turnFilterOn: "Turn the filter on"
                }
            }
        }
    }

    // MARK: Diagnostics

    /// Everything this Mac can say about the filter, in one block of text.
    ///
    /// macOS owns the extension and `NEFilterManager` owns the permission separately; this
    /// reports both, since a failure in one can look identical to a failure in the other from
    /// the one-line status alone.
    func diagnostics() async -> String {
        var lines: [String] = []
        lines.append("Furlough web filter diagnostics")
        lines.append("status: \(status.label)")
        if case .failed(let reason) = status { lines.append("  reason: \(reason)") }
        if case .filterDenied(let reason, let prompted) = status {
            lines.append("  reason: \(reason)")
            lines.append("  a dialog was put up: \(prompted)")
        }
        lines.append("asked for (isWanted): \(isWanted)")
        lines.append("app: \(Bundle.main.bundleURL.path)")
        lines.append("in /Applications: \(Self.isInApplications)")
        lines.append("extension bundled with this build: \(Self.bundledVersion ?? "none found")")
        // "installed" disagreeing with "in this build" is the signature of a filter left
        // behind by an earlier copy — an app replacement doesn't touch what macOS has loaded.
        lines.append("this build's extension: \(Self.bundledIdentity ?? "could not be read")")
        lines.append("extension this app installed: \(installedIdentity ?? "none recorded")")
        lines.append("last asked for by a launch: \(attemptedIdentity ?? "none")")
        lines.append("extension id: \(FilterXPC.extensionID)")

        lines.append("")
        lines.append("What macOS says about the extension:")
        if let found = await ExtensionRequest.properties() {
            if found.isEmpty { lines.append("  none installed") }
            for info in found {
                lines.append("  version \(info.bundleVersion): enabled=\(info.isEnabled) awaitingApproval=\(info.isAwaitingUserApproval)")
            }
        } else {
            lines.append("  NO ANSWER \u{2014} macOS was asked and did not reply (the service is stuck; a restart clears it)")
        }

        lines.append("")
        lines.append("What macOS says about the filter permission:")
        let configuration = await readConfiguration()
        if !configuration.answered {
            lines.append("  NO ANSWER \u{2014} loadFromPreferences did not reply")
        } else if let error = configuration.error {
            lines.append("  could not load: \(error)")
        } else {
            lines.append("  enabled: \(configuration.isEnabled)")
            lines.append("  configuration: \(configuration.hasConfiguration ? "present" : "none")")
            if configuration.hasConfiguration {
                lines.append("  provider: \(configuration.provider ?? "unset")")
                lines.append("  sockets: \(configuration.filtersSockets)")
                lines.append("  rules: \(configuration.rulesReadable ? "readable" : "unreadable")")
            }
        }

        lines.append("")
        lines.append("Entitlement Furlough is signed with:")
        lines.append("  \(Self.networkExtensionEntitlement)")

        lines.append("")
        lines.append("Read at \(Date.now.formatted(date: .numeric, time: .standard))")
        return lines.joined(separator: "\n")
    }

    /// The `com.apple.developer.networking.networkextension` values this copy is signed with.
    ///
    /// Distinguishes "refused" from "never allowed to ask": a development-signed build only
    /// gets the plain `content-filter-provider` entitlement, not
    /// `content-filter-provider-systemextension`, which a Mac Team Provisioning Profile can't grant.
    static var networkExtensionEntitlement: String {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.networking.networkextension" as CFString, nil)
        else { return "could not be read" }
        if let values = value as? [String] { return values.joined(separator: ", ") }
        return String(describing: value)
    }

    /// Logged too, so a failure leaves evidence even if nobody presses Copy diagnostics.
    func logDiagnostics(because reason: String) async {
        let report = await diagnostics()
        SharedStore.log("web filter diagnostics (\(reason)):")
        for line in report.split(separator: "\n") where !line.isEmpty {
            SharedStore.log("  \(line)")
        }
    }

    func perform(_ action: Guidance.Action) {
        switch action {
        case .openSystemSettings: Self.openSystemSettings()
        case .checkAgain: Task { await refresh() }
        case .turnFilterOn: Task { await enableFilter() }
        }
    }

    static let explainer = "The web filter is a system extension that sees every connection this Mac opens and refuses the ones to a blocked site, whatever opened it. Those get the floating card rather than the shield page.\n\nWithout it a site is held only in the browsers Furlough recognises, by reading the address bar: Safari, Chrome, Arc, Brave, Edge and the other Chromium ones. Anything off that list goes through — Firefox, a browser Furlough has not met, a site saved to the Dock, or an app that loads a page on its own."

    private(set) var status: Status = .notInstalled
    var isWanted: Bool {
        get { SharedStore.defaults.bool(forKey: Self.wantedKey) }
        set { SharedStore.defaults.set(newValue, forKey: Self.wantedKey) }
    }
    var onBlocked: ((String, String) -> Void)?

    /// The extension macOS last told us it had accepted, as `bundledIdentity` writes it.
    ///
    /// Stored outside `SharedState` (like `isWanted`): it describes macOS's Mac, not
    /// Furlough's setup, so Testing > Reset everything leaves it alone.
    private var installedIdentity: String? {
        get { SharedStore.defaults.string(forKey: Self.installedKey) }
        set { SharedStore.defaults.set(newValue, forKey: Self.installedKey) }
    }
    /// One request per build, so a Mac that won't take this copy isn't asked again every launch.
    private var attemptedIdentity: String? {
        get { SharedStore.defaults.string(forKey: Self.attemptedKey) }
        set { SharedStore.defaults.set(newValue, forKey: Self.attemptedKey) }
    }
    /// Set by `refresh()` when the extension service doesn't answer at all — a different case
    /// from a refusal, needing a different repair, though `Status.failed` covers both.
    private var queryWentUnanswered = false

    private static let wantedKey = "furlough.mac.filter.wanted"
    private static let installedKey = "furlough.mac.filter.installed"
    private static let attemptedKey = "furlough.mac.filter.attempted"
    private let link = FilterLink()
    private var lastPushed: FilterRules?
    private var pushing = false
    private var pushAgain: FilterRules?

    /// macOS refuses activation from anywhere but /Applications, reporting only an error code.
    static var isInApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    private static var extensionURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Library/SystemExtensions/\(FilterXPC.extensionID).systemextension")
    }

    private static var bundledVersion: String? {
        Bundle(url: extensionURL)?.infoDictionary?["CFBundleVersion"] as? String
    }

    /// Version plus the first bytes of the code directory hash (the same hash macOS identifies
    /// a binary by). The version alone can't tell builds apart — `CURRENT_PROJECT_VERSION` sat
    /// at `1` for every Mac build — but the hash moves with every build regardless.
    private static var bundledIdentity: String? {
        let url = extensionURL
        guard let bundle = Bundle(url: url) else { return nil }
        let version = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        guard let stamp = codeHash(of: url) else { return nil }
        return "\(version)+\(stamp)"
    }

    /// Nil, not a guess, when the signature can't be read: `FilterRepair` then skips the
    /// replacement rules rather than reinstalling on every launch.
    private static func codeHash(of url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let hash = dictionary[kSecCodeInfoUnique as String] as? Data,
              !hash.isEmpty else { return nil }
        return hash.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private var presence: FilterRepair.Presence {
        switch status {
        case .notInApplications: .elsewhere
        case .notInstalled: .notInstalled
        case .installing: .installing
        case .awaitingApproval: .awaitingApproval
        case .disabledInSettings: .disabledInSettings
        case .on: .running
        case .filterOff: .notFiltering
        case .filterDenied(_, let prompted): prompted ? .declined : .refused
        case .failed: queryWentUnanswered ? .unanswered : .refused
        }
    }

    // MARK: Lifecycle

    /// `FilterRepair` decides whether to reactivate (the case it exists for: an app just
    /// replaced). A copy switched off in System Settings, or declined, is only reported.
    func start() {
        link.onBlocked = { [weak self] host, app in self?.onBlocked?(host, app) }
        Task {
            // Logged on both sides of the ask so a "nothing is wrong" answer can be told from
            // macOS never answering at all.
            SharedStore.log("web filter: asking macOS for its state")
            await refresh()
            SharedStore.log("web filter: macOS says \(status.label)")
            switch status {
            case .disabledInSettings where isWanted:
                SharedStore.log("web filter is switched off in System Settings > General > Login Items & Extensions; sites are enforced by the tab reader alone")
            case .awaitingApproval where isWanted:
                SharedStore.log("web filter: still waiting for approval in System Settings")
            default:
                break
            }
            await repair()
            guard isWanted else { return }
            // Worth recording now: the filter's state lives in macOS, not here, so evidence of
            // a bad launch is gone unless it's written down at the time.
            if !status.isOn {
                await logDiagnostics(because: "the filter is asked for and is not running")
            }
        }
    }

    /// Every app replacement leaves macOS holding the extension the old bundle staged;
    /// `systemextensionsctl` still lists it and a properties request from the new bundle can
    /// come back empty or never answer. This re-activates in that case rather than reporting
    /// *Not installed*. A filter switched off in System Settings, or declined, is left as is.
    private func repair() async {
        let bundled = Self.bundledIdentity
        let action = FilterRepair.decide(
            wanted: isWanted,
            presence: presence,
            bundled: bundled,
            activated: installedIdentity,
            attempted: attemptedIdentity
        )
        guard case .activate(let reason) = action else { return }
        SharedStore.log("web filter: \(reason.sentence)")
        // Written before the request, not after: a hung request or a quit mid-activation must
        // not buy another attempt on every subsequent launch.
        attemptedIdentity = bundled
        await activate()
    }

    /// Reads the extension's state and the filter configuration's, and returns the version of
    /// the extension macOS has enabled, if any.
    @discardableResult
    func refresh() async -> String? {
        guard Self.isInApplications else {
            status = .notInApplications
            return nil
        }
        queryWentUnanswered = false
        guard let found = await ExtensionRequest.properties() else {
            queryWentUnanswered = true
            // Not a refusal: the service that answers this can get stuck (e.g. replacing the
            // app while it holds a reference). Install again submits a fresh request, which
            // often clears it; a restart clears it when that doesn't.
            status = .failed("macOS did not answer when it was asked about the extension. That is not a refusal — the service that answers is stuck. Install again below; if it still will not turn on, restart the Mac and install again.")
            return nil
        }
        if let enabled = found.first(where: \.isEnabled) {
            let configuration = await readConfiguration()
            status = configuration.isOn ? .on : .filterOff
            if status.isOn { link.connect() } else { link.disconnect() }
            return enabled.bundleVersion
        }
        link.disconnect()
        if found.contains(where: \.isAwaitingUserApproval) {
            status = .awaitingApproval
        } else if found.isEmpty {
            status = .notInstalled
        } else {
            status = .disabledInSettings
        }
        return nil
    }

    // MARK: Installing and removing

    func install() {
        guard Self.isInApplications else {
            status = .notInApplications
            return
        }
        isWanted = true
        status = .installing
        Task { await activate() }
    }

    private func activate() async {
        do {
            let outcome = try await ExtensionRequest.activate { [weak self] in
                Task { @MainActor in
                    self?.status = .awaitingApproval
                    SharedStore.log("web filter: waiting for approval in System Settings > General > Login Items & Extensions > Network Extensions")
                }
            }
            switch outcome {
            case .completed:
                SharedStore.log("web filter extension is active")
                installedIdentity = Self.bundledIdentity
                await enableFilter()
            case .afterReboot:
                status = .failed("Restart the Mac to finish installing the web filter.")
                SharedStore.log("web filter: macOS wants a restart before the extension can run")
            }
        } catch {
            status = .failed(error.localizedDescription)
            SharedStore.log("web filter: \(error.localizedDescription)")
            await logDiagnostics(because: "the extension would not activate")
        }
    }

    func enableFilter() async {
        let manager = NEFilterManager.shared()
        // Outside the `do` so the catch can read it; see the note where it is set.
        var asked = Date.now
        do {
            try await manager.loadFromPreferences()
            let configuration = manager.providerConfiguration ?? NEFilterProviderConfiguration()
            configuration.filterSockets = true
            configuration.filterPackets = false
            configuration.filterDataProviderBundleIdentifier = FilterXPC.extensionID
            if FilterRules(vendorConfiguration: configuration.vendorConfiguration) == nil {
                configuration.vendorConfiguration = FilterRules.empty.vendorConfiguration
            }
            manager.providerConfiguration = configuration
            manager.localizedDescription = "Furlough"
            manager.isEnabled = true
            // Timed: a refusal faster than a person could read a dialog means macOS said no on
            // its own, with no prompt shown — telling them to click Allow then would send them
            // hunting for a dialog that never existed.
            asked = Date.now
            try await manager.saveToPreferences()
            status = .on
            lastPushed = nil
            link.connect()
            SharedStore.log("web filter on")
        } catch {
            // Not `.failed`: the extension activated fine, it's the filter permission refused.
            let prompted = Date.now.timeIntervalSince(asked) >= 1.5
            status = .filterDenied(error.localizedDescription, prompted: prompted)
            SharedStore.log("web filter: not allowed to filter: \(error.localizedDescription) (macOS \(prompted ? "asked and was refused" : "refused without asking"))")
            await logDiagnostics(because: "the filter permission was refused")
        }
    }

    /// Not held behind the loosening delay, like the watchdog toggle: System Settings can
    /// switch the extension off regardless. The tab reader keeps enforcing either way.
    func remove() {
        isWanted = false
        installedIdentity = nil
        attemptedIdentity = nil
        link.disconnect()
        lastPushed = nil
        Task {
            let manager = NEFilterManager.shared()
            do {
                try await manager.loadFromPreferences()
                try await manager.removeFromPreferences()
            } catch {
                SharedStore.log("web filter: could not remove the configuration: \(error.localizedDescription)")
            }
            do {
                _ = try await ExtensionRequest.deactivate()
            } catch {
                SharedStore.log("web filter: could not remove the extension: \(error.localizedDescription)")
            }
            SharedStore.log("web filter removed")
            await refresh()
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: The rules

    /// `until` is the next moment `Policy` allows a status to change; past it the extension
    /// blocks nothing, which is what makes a stale list harmless.
    func sync(hosts: Set<String>, until: Date) {
        guard status.isOn else { return }
        let rules = FilterRules(hosts: hosts.sorted(), until: until, version: 0)
        if let last = lastPushed, last.hosts == rules.hosts, rules.hosts.isEmpty || last.until == rules.until { return }
        push(rules)
    }

    private func push(_ rules: FilterRules) {
        guard !pushing else {
            pushAgain = rules
            return
        }
        pushing = true
        Task {
            await save(rules)
            pushing = false
            if let next = pushAgain {
                pushAgain = nil
                push(next)
            }
        }
    }

    private func save(_ rules: FilterRules) async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            guard let configuration = manager.providerConfiguration, manager.isEnabled else {
                status = .filterOff
                SharedStore.log("web filter: the configuration is gone; Settings > Web can turn it on again")
                return
            }
            var rules = rules
            rules.version = (FilterRules(vendorConfiguration: configuration.vendorConfiguration)?.version ?? 0) + 1
            configuration.vendorConfiguration = rules.vendorConfiguration
            manager.providerConfiguration = configuration
            try await manager.saveToPreferences()
            lastPushed = rules
            SharedStore.log("web filter: \(rules.hosts.count) host(s) blocked until \(rules.until.formatted(date: .omitted, time: .shortened))")
        } catch {
            // Remembered as pushed so a persistent failure logs once, not once a second.
            lastPushed = rules
            SharedStore.log("web filter: could not save the rules: \(error.localizedDescription)")
        }
    }

    /// Raced like the extension query: this call has been seen hanging indefinitely, which
    /// would otherwise take `refresh()` and Copy diagnostics down with it.
    struct ConfigurationReport: Sendable {
        var answered = true
        var error: String?
        var isEnabled = false
        var hasConfiguration = false
        var provider: String?
        var filtersSockets = false
        var rulesReadable = false

        var isOn: Bool { answered && isEnabled && hasConfiguration }
    }

    private func readConfiguration() async -> ConfigurationReport {
        await firstOf(8, work: {
            let manager = NEFilterManager.shared()
            do {
                try await manager.loadFromPreferences()
            } catch {
                return ConfigurationReport(error: error.localizedDescription)
            }
            let configuration = manager.providerConfiguration
            return ConfigurationReport(
                isEnabled: manager.isEnabled,
                hasConfiguration: configuration != nil,
                provider: configuration?.filterDataProviderBundleIdentifier,
                filtersSockets: configuration?.filterSockets ?? false,
                rulesReadable: configuration.map { FilterRules(vendorConfiguration: $0.vendorConfiguration) != nil } ?? false
            )
        }, timedOut: ConfigurationReport(answered: false))
    }
}

/// One value, delivered once, to whichever of two racers gets there first.
private final class OneShot<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }

    func resume(_ value: T) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}

/// `work`, or `timedOut` if it has not answered in `seconds`, abandoning whichever loses.
///
/// Deliberately **not** a task group: a group waits for every child, so racing a hung call
/// against `Task.sleep` inside one still hangs. Cancellation doesn't help either, since the
/// calls that hang here (the extension properties request, `loadFromPreferences`) belong to
/// macOS and don't honour it — so the loser is left running unobserved instead.
private func firstOf<T: Sendable>(
    _ seconds: Double,
    work: @escaping @Sendable () async -> T,
    timedOut: T
) async -> T {
    await withCheckedContinuation { continuation in
        let once = OneShot(continuation)
        Task { once.resume(await work()) }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            once.resume(timedOut)
        }
    }
}

/// One `OSSystemExtensionRequest` as an async call. The caller's local keeps it alive until it
/// finishes; the delegate is called on the main queue.
private final class ExtensionRequest: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    struct Info: Sendable {
        var isEnabled: Bool
        var isAwaitingUserApproval: Bool
        var bundleVersion: String
    }

    enum Outcome: Sendable {
        case completed
        case afterReboot
    }

    private enum Answer: Sendable {
        case finished(Outcome)
        case found([Info])
    }

    private var continuation: CheckedContinuation<Answer, Error>?
    private var found: [Info] = []
    private let onNeedsApproval: @Sendable () -> Void
    private let isPropertiesRequest: Bool

    private init(properties: Bool = false, onNeedsApproval: @escaping @Sendable () -> Void = {}) {
        self.isPropertiesRequest = properties
        self.onNeedsApproval = onNeedsApproval
    }

    static func activate(onNeedsApproval: @escaping @Sendable () -> Void) async throws -> Outcome {
        let request = ExtensionRequest(onNeedsApproval: onNeedsApproval)
        let answer = try await request.submit(.activationRequest(forExtensionWithIdentifier: FilterXPC.extensionID, queue: .main))
        guard case .finished(let outcome) = answer else { return .completed }
        return outcome
    }

    static func deactivate() async throws -> Outcome {
        let request = ExtensionRequest()
        let answer = try await request.submit(.deactivationRequest(forExtensionWithIdentifier: FilterXPC.extensionID, queue: .main))
        guard case .finished(let outcome) = answer else { return .completed }
        return outcome
    }

    /// Nil is a distinct answer from an empty array: nil means macOS never answered, not that
    /// no extension is installed — they need opposite handling.
    static func properties() async -> [Info]? {
        await firstOf(10, work: {
            let request = ExtensionRequest(properties: true)
            do {
                let answer = try await request.submit(.propertiesRequest(forExtensionWithIdentifier: FilterXPC.extensionID, queue: .main))
                guard case .found(let infos) = answer else { return [] }
                return infos
            } catch let error as OSSystemExtensionError where error.code == .extensionNotFound {
                return []
            } catch {
                return nil
            }
        }, timedOut: nil)
    }


    private func submit(_ request: OSSystemExtensionRequest) async throws -> Answer {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        onNeedsApproval()
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let answer: Answer = isPropertiesRequest
            ? .found(found)
            : .finished(result == .willCompleteAfterReboot ? .afterReboot : .completed)
        continuation?.resume(returning: answer)
        continuation = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        found = properties.map {
            Info(isEnabled: $0.isEnabled, isAwaitingUserApproval: $0.isAwaitingUserApproval, bundleVersion: $0.bundleVersion)
        }
    }
}

@MainActor
final class FilterLink {
    var onBlocked: ((String, String) -> Void)?
    private var connection: NSXPCConnection?
    private var wanted = false
    private let receiver = FilterReceiver()
    private static let retryAfter: Duration = .seconds(5)

    func connect() {
        wanted = true
        guard connection == nil else { return }
        receiver.onBlocked = { [weak self] host, app in
            Task { @MainActor in self?.onBlocked?(host, app) }
        }
        let connection = NSXPCConnection(machServiceName: FilterXPC.serviceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: FilterControl.self)
        connection.exportedInterface = NSXPCInterface(with: FilterListening.self)
        connection.exportedObject = receiver
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.dropped() }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.dropped() }
        }
        connection.resume()
        self.connection = connection
        let control = connection.remoteObjectProxyWithErrorHandler { error in
            SharedStore.log("web filter link: \(error.localizedDescription)")
        } as? FilterControl
        control?.hello { _ in
            SharedStore.log("web filter link up")
        }
    }

    func disconnect() {
        wanted = false
        connection?.invalidate()
        connection = nil
    }

    /// Retries while the filter is still meant to be on.
    private func dropped() {
        connection?.invalidate()
        connection = nil
        guard wanted else { return }
        Task {
            try? await Task.sleep(for: Self.retryAfter)
            if wanted, connection == nil { connect() }
        }
    }
}

/// Not on the main actor: XPC calls this on a queue of its own, so it hops over in the closure.
final class FilterReceiver: NSObject, FilterListening, @unchecked Sendable {
    var onBlocked: (@Sendable (String, String) -> Void)?

    func blocked(host: String, in app: String) {
        onBlocked?(host, app)
    }
}
