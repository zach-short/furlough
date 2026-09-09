import AppKit
import Foundation
import NetworkExtension
import Observation
import SystemExtensions

/// The app's side of the web filter: installs the system extension, keeps its filter
/// configuration on, pushes it the hosts to block, and listens for what it drops.
///
/// The extension itself is `FurloughMacFilter`, and every decision it makes is `FlowRules`,
/// which is pure and tested. This file is the plumbing between the two, and the one place the
/// app finds out whether the filter is actually running — macOS can switch it off in System
/// Settings without telling anyone, and Settings > Web is where that has to show.
@MainActor
@Observable
final class WebFilter {
    enum Status: Equatable {
        /// A system extension only loads from an app inside /Applications, so a build run from
        /// anywhere else cannot install it.
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
        /// The extension is installed and switched on, and macOS refused the *second* question
        /// — the one that lets it see traffic. A different failure from `failed` and the one
        /// that reads most like a lie if they are conflated: System Settings shows the toggle
        /// on, so telling somebody nothing was ever asked of them is plainly false.
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
        /// Onboarding and Settings > Web both draw these rather than wording it twice, because
        /// this is the copy that had to be right and was not. Two rounds of it on 2026-09-09:
        /// first a single sentence — "allow it under System Settings > General > Login Items &
        /// Extensions > Network Extensions" — which sent Zach to a page listing Furlough twice
        /// under *other* headings; then a six-line list that still missed the step that actually
        /// hid the row. **Network Extensions exists only under By Category.** Under By App, the
        /// segment macOS may well open on, there is no such row at all — there is a Furlough
        /// entry, which is not the same thing and leads nowhere. That is step 4, and it is the
        /// whole reason this walkthrough shows one step at a time instead of a list to skim.
        ///
        /// `failed` says the opposite of all of it on purpose: when the activation is refused
        /// nothing was ever asked of the person, and sending them into System Settings to hunt
        /// for a prompt that was never made is the worst thing this screen can do.
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

        /// The walk through System Settings. One action each, because every one of them is a
        /// place to go wrong: the row is below a list that looks like the end of the page, and
        /// then it is behind a segmented control that may not be on the half you are looking at.
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

    /// One state's directions: a line saying where you stand, the steps out of it taken one at a
    /// time, and the trap it has when it has no steps at all.
    struct Guidance: Equatable {
        var lead: String
        var steps: [Step] = []
        var caution: String?

        /// One thing to do, at most one thing to press, and a picture of what to look for.
        struct Step: Equatable {
            var text: String
            /// The trap in this particular step, said where it is met rather than in a block at
            /// the bottom that is read after the mistake.
            var note: String?
            /// What this step looks like on screen. Drawn by `StepFigure` in Furlough's own
            /// tokens rather than shipped as screenshots of macOS: a screenshot goes stale with
            /// every System Settings redesign, and a drawing can point at the one control that
            /// matters instead of showing a whole window to search.
            var figure: Figure?
            var action: Action?
        }

        /// The part of System Settings a step is about.
        enum Figure: Equatable {
            case systemSettings
            case general
            case scrollDown
            /// The segmented control that hid Network Extensions. The reason for all of this.
            case byCategory
            case networkExtensionsRow
            case furloughToggle
            case allowDialog
        }

        /// What a step's button does. An enum rather than a closure so the directions stay a
        /// value the model owns, and so a step cannot mean one thing in onboarding and another
        /// in Settings.
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
    /// The web filter is the one part of Furlough whose state lives almost entirely outside the
    /// app — macOS owns the extension, and `NEFilterManager` owns the permission — so when it
    /// goes wrong the app's one-line status is not enough to work from. Twice on 2026-09-09 the
    /// status said one thing and System Settings showed another: first an activation refused for
    /// a missing Info.plist key, then "Failed" over an extension that was plainly switched on,
    /// because the *filter permission* had been refused and both landed in the same case.
    /// This says which half is which.
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
        lines.append("extension id: \(FilterXPC.extensionID)")

        lines.append("")
        lines.append("What macOS says about the extension:")
        do {
            let found = try await ExtensionRequest.properties()
            if found.isEmpty {
                lines.append("  none installed")
            }
            for info in found {
                lines.append("  version \(info.bundleVersion): enabled=\(info.isEnabled) awaitingApproval=\(info.isAwaitingUserApproval)")
            }
        } catch let error as OSSystemExtensionError where error.code == .extensionNotFound {
            lines.append("  none installed (extensionNotFound)")
        } catch {
            lines.append("  could not ask: \(error.localizedDescription)")
        }

        lines.append("")
        lines.append("What macOS says about the filter permission:")
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            lines.append("  enabled: \(manager.isEnabled)")
            lines.append("  configuration: \(manager.providerConfiguration == nil ? "none" : "present")")
            if let configuration = manager.providerConfiguration {
                lines.append("  provider: \(configuration.filterDataProviderBundleIdentifier ?? "unset")")
                lines.append("  sockets: \(configuration.filterSockets)")
                lines.append("  rules: \(FilterRules(vendorConfiguration: configuration.vendorConfiguration) == nil ? "unreadable" : "readable")")
            }
        } catch {
            lines.append("  could not load: \(error.localizedDescription)")
        }

        lines.append("")
        lines.append("Read at \(Date.now.formatted(date: .numeric, time: .standard))")
        return lines.joined(separator: "\n")
    }

    /// Puts the same block in the activity log, so a failure leaves its evidence behind whether
    /// or not anybody thought to press Copy diagnostics.
    func logDiagnostics(because reason: String) async {
        let report = await diagnostics()
        SharedStore.log("web filter diagnostics (\(reason)):")
        for line in report.split(separator: "\n") where !line.isEmpty {
            SharedStore.log("  \(line)")
        }
    }

    /// Runs what a step's button says it does, so both screens wire the same step to the same
    /// thing.
    func perform(_ action: Guidance.Action) {
        switch action {
        case .openSystemSettings: Self.openSystemSettings()
        case .checkAgain: Task { await refresh() }
        case .turnFilterOn: Task { await enableFilter() }
        }
    }

    /// What the filter is, for the two screens that offer it. Separate from `Guidance`, which
    /// only ever says what to do next.
    static let explainer = "The web filter is a system extension that sees every connection this Mac opens and refuses the ones to a blocked site, from any app: Firefox, a site saved to the Dock, anything that loads a site outside a browser. Those get the floating card rather than the shield page."

    private(set) var status: Status = .notInstalled
    /// Set once Install is pressed and cleared by Remove, so a launch that finds the extension
    /// gone or switched off can say so rather than silently going without.
    var isWanted: Bool {
        get { SharedStore.defaults.bool(forKey: Self.wantedKey) }
        set { SharedStore.defaults.set(newValue, forKey: Self.wantedKey) }
    }
    /// Called with the host and the bundle identifier of the app whose connection was dropped.
    var onBlocked: ((String, String) -> Void)?

    private static let wantedKey = "furlough.mac.filter.wanted"
    private let link = FilterLink()
    private var lastPushed: FilterRules?
    private var pushing = false
    private var pushAgain: FilterRules?

    /// The extension can only be activated from an app in /Applications; macOS refuses it
    /// anywhere else, and says so only in an error code.
    static var isInApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    /// The version of the extension this build carries, to tell an older installed copy from it.
    private static var bundledVersion: String? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Library/SystemExtensions/\(FilterXPC.extensionID).systemextension")
        return Bundle(url: url)?.infoDictionary?["CFBundleVersion"] as? String
    }

    // MARK: Lifecycle

    /// Called once at launch. Finds out where the filter stands, and if it was asked for and this
    /// build carries a newer extension, activates that one; a copy switched off in System
    /// Settings is only reported, never re-asked for on every launch.
    func start() {
        link.onBlocked = { [weak self] host, app in self?.onBlocked?(host, app) }
        Task {
            let installed = await refresh()
            guard isWanted else { return }
            switch status {
            case .notInstalled:
                SharedStore.log("web filter: asked for but not installed; installing again")
                await activate()
            case .on, .filterOff:
                if let bundled = Self.bundledVersion, installed != bundled {
                    SharedStore.log("web filter: replacing version \(installed ?? "?") with \(bundled)")
                    await activate()
                }
            case .disabledInSettings:
                SharedStore.log("web filter is switched off in System Settings > General > Login Items & Extensions; sites are enforced by the tab reader alone")
            case .awaitingApproval:
                SharedStore.log("web filter: still waiting for approval in System Settings")
            case .notInApplications, .installing, .failed, .filterDenied:
                break
            }
        }
    }

    /// Reads the extension's state and the filter configuration's, and returns the version of
    /// the extension macOS has enabled, if any.
    @discardableResult
    func refresh() async -> String? {
        guard Self.isInApplications else {
            status = .notInApplications
            return nil
        }
        let found: [ExtensionRequest.Info]
        do {
            found = try await ExtensionRequest.properties()
        } catch let error as OSSystemExtensionError where error.code == .extensionNotFound {
            found = []
        } catch {
            status = .failed(error.localizedDescription)
            return nil
        }
        if let enabled = found.first(where: \.isEnabled) {
            status = await filterConfigurationIsOn() ? .on : .filterOff
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

    /// Asks macOS to activate the extension. Two approvals follow, both the person's: the
    /// extension itself in System Settings, then the filter in a dialog of macOS's own.
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

    /// Turns the filter configuration on. The first time, macOS asks whether Furlough may filter
    /// network content; refusing lands here as an error and the status says so.
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
            // Timed, because the two ways this fails need opposite directions and they are
            // otherwise identical. A refusal that comes back faster than a person could read a
            // dialog and click Don't Allow is macOS saying no on its own — no question was put
            // up — and telling somebody to go click Allow in that case sends them hunting for a
            // prompt that never existed. That mistake has already been made twice on this
            // screen; this is the app knowing the difference instead of guessing.
            asked = Date.now
            try await manager.saveToPreferences()
            status = .on
            lastPushed = nil
            link.connect()
            SharedStore.log("web filter on")
        } catch {
            // Not `.failed`: reaching here means the extension activated and it is the filter
            // permission that was refused, which is a different screen and a different fix.
            let prompted = Date.now.timeIntervalSince(asked) >= 1.5
            status = .filterDenied(error.localizedDescription, prompted: prompted)
            SharedStore.log("web filter: not allowed to filter: \(error.localizedDescription) (macOS \(prompted ? "asked and was refused" : "refused without asking"))")
            await logDiagnostics(because: "the filter permission was refused")
        }
    }

    /// Takes the filter away: the configuration first, then the extension. Not held behind the
    /// loosening delay, for the reason the watchdog toggle is not — System Settings can switch
    /// the extension off regardless, and a button that pretended otherwise would be worse. The
    /// tab reader keeps enforcing either way.
    func remove() {
        isWanted = false
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

    /// Where macOS keeps the switch: System Settings > General > Login Items & Extensions.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: The rules

    /// Hands the extension what to block, when it differs from the last push. `until` is on the
    /// device's clock and is the moment `Policy` next allows a status to change; past it the
    /// extension blocks nothing until the next push, which is what makes a stale list harmless.
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
            // Remembered as pushed so a persistent failure logs once, not once a second; the next
            // change tries again.
            lastPushed = rules
            SharedStore.log("web filter: could not save the rules: \(error.localizedDescription)")
        }
    }

    private func filterConfigurationIsOn() async -> Bool {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
        } catch {
            return false
        }
        return manager.isEnabled && manager.providerConfiguration != nil
    }
}

/// One `OSSystemExtensionRequest` as an async call. The caller's local keeps it alive until the
/// request finishes, and the delegate is called on the main queue.
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
    /// A properties request answers with what it found; the other two only with how they ended.
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

    /// Every copy macOS knows about, enabled or not. Throws `.extensionNotFound` on a Mac that
    /// has never had one.
    static func properties() async throws -> [Info] {
        let request = ExtensionRequest(properties: true)
        let answer = try await request.submit(.propertiesRequest(forExtensionWithIdentifier: FilterXPC.extensionID, queue: .main))
        guard case .found(let infos) = answer else { return [] }
        return infos
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

/// The app's end of the XPC link to the extension: connects while the filter is on, reconnects
/// when the extension restarts, and hands each dropped connection to `onBlocked` on the main
/// actor.
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

    /// The extension went away — restarted, or not running yet. Try again in a moment, for as
    /// long as the filter is meant to be on.
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

/// What the extension calls. Not on the main actor, because XPC calls it on a queue of its own;
/// it hops over in the closure it was given.
final class FilterReceiver: NSObject, FilterListening, @unchecked Sendable {
    var onBlocked: (@Sendable (String, String) -> Void)?

    func blocked(host: String, in app: String) {
        onBlocked?(host, app)
    }
}
