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
        case failed(String)

        var label: String {
            switch self {
            case .notInApplications: "Needs the Applications folder"
            case .notInstalled: "Not installed"
            case .installing: "Installing…"
            case .awaitingApproval: "Waiting for approval"
            case .disabledInSettings: "Off in System Settings"
            case .filterOff: "Installed, not filtering"
            case .on: "On"
            case .failed: "Failed"
            }
        }

        var isOn: Bool { self == .on }
    }

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
            case .notInApplications, .installing, .failed:
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
        }
    }

    /// Turns the filter configuration on. The first time, macOS asks whether Furlough may filter
    /// network content; refusing lands here as an error and the status says so.
    func enableFilter() async {
        let manager = NEFilterManager.shared()
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
            try await manager.saveToPreferences()
            status = .on
            lastPushed = nil
            link.connect()
            SharedStore.log("web filter on")
        } catch {
            status = .failed(error.localizedDescription)
            SharedStore.log("web filter: \(error.localizedDescription)")
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
