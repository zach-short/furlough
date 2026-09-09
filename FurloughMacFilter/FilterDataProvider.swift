import Foundation
import Network
import NetworkExtension
import os
import Security

/// The web filter: the shell around `FlowRules` that macOS calls with every connection.
///
/// It runs as root, outside any user session, and starts at boot before anyone logs in, so it
/// keeps nothing of its own. The rules arrive in the filter configuration the app saves
/// (`FilterRules.vendorConfiguration`), and they carry their own horizon: past `until` this
/// blocks nothing, so a list the app left behind cannot outlive the moment `Policy` said it
/// could change. What it drops it reports back to the app over XPC, for the floating card.
/// `@unchecked Sendable` because macOS calls it from several queues and everything it mutates
/// is behind `state`'s lock; the observation and the reporter are set up once in `startFilter`.
final class FilterDataProvider: NEFilterDataProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: FilterXPC.extensionID, category: "filter")
    /// The rules as last read, and the bytes seen so far of each connection still being looked
    /// at. Behind a lock because verdicts, configuration changes and XPC arrive on different
    /// queues.
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let reporter = FilterReporter()
    private var configurationWatch: NSKeyValueObservation?

    private struct State: Sendable {
        var rules = FilterRules.empty
        var buffers: [UUID: Data] = [:]
        /// When each host was last reported, so a page that opens twenty connections is one card.
        var reported: [String: Date] = [:]
    }

    private static let reportEvery: TimeInterval = 8

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        readRules()
        // The app pushes new rules by saving the configuration again; the property updates in
        // place and this hears it. `readRules` is cheap and idempotent, so hearing it twice is fine.
        configurationWatch = observe(\.filterConfiguration) { [weak self] _, _ in self?.readRules() }
        reporter.start()
        logger.info("filter started")
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        configurationWatch = nil
        reporter.stop()
        state.withLock { $0.buffers = [:] }
        logger.info("filter stopped: \(reason.rawValue)")
        completionHandler()
    }

    /// Takes the rules out of the configuration. A version the extension already has is skipped
    /// rather than compared host by host.
    private func readRules() {
        let rules = FilterRules(vendorConfiguration: filterConfiguration.vendorConfiguration) ?? .empty
        let changed = state.withLock { state in
            guard state.rules.version != rules.version || state.rules != rules else { return false }
            state.rules = rules
            return true
        }
        if changed {
            logger.info("rules v\(rules.version): \(rules.hosts.count) host(s) until \(rules.until, privacy: .public)")
        }
    }

    // MARK: Verdicts

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socket = flow as? NEFilterSocketFlow else { return .allow() }
        let endpoint = Self.endpoint(of: socket)
        let rules = state.withLock { $0.rules }
        switch FlowRules.newFlow(endpoint, rules: rules, now: .now) {
        case .allow:
            return .allow()
        case .inspect:
            return .filterDataVerdict(withFilterInbound: false, peekInboundBytes: 0, filterOutbound: true, peekOutboundBytes: FlowRules.peekBytes)
        case .drop(let host, _):
            report(host: host, flow: socket)
            return .drop()
        case .dropQUIC:
            return .drop()
        }
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        guard let socket = flow as? NEFilterSocketFlow else { return .allow() }
        let id = flow.identifier
        let port = Int(Self.port(of: socket))
        let (bytes, rules) = state.withLock { state -> (Data, FilterRules) in
            var buffer = state.buffers[id] ?? Data()
            // The bytes may arrive as everything from the start of the connection or as only
            // what is new since the last look; `offset` says which, and both land as one run.
            let alreadyHave = buffer.count - offset
            if alreadyHave >= 0, alreadyHave < readBytes.count {
                buffer.append(readBytes[readBytes.startIndex.advanced(by: alreadyHave)...])
            } else if alreadyHave < 0 {
                buffer = readBytes
            }
            state.buffers[id] = buffer
            return (buffer, state.rules)
        }
        switch FlowRules.inspect(bytes, port: port, rules: rules, now: .now) {
        case .allow:
            forget(id)
            return .allow()
        case .drop(let host, _):
            forget(id)
            report(host: host, flow: socket)
            return .drop()
        case .more:
            return NEFilterDataVerdict(passBytes: 0, peekBytes: bytes.count + FlowRules.peekBytes)
        }
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        .allow()
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        forget(flow.identifier)
        return .allow()
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    private func forget(_ id: UUID) {
        state.withLock { $0.buffers[id] = nil }
    }

    // MARK: Reading a flow

    /// The name comes from `remoteHostname` when macOS has one, else from the endpoint when the
    /// app connected by name; an address endpoint is nameless, which `Endpoint` also enforces.
    private static func endpoint(of flow: NEFilterSocketFlow) -> FlowRules.Endpoint {
        var hostname = flow.remoteHostname
        if hostname == nil, case .hostPort(let host, _) = flow.remoteFlowEndpoint, case .name(let name, _) = host {
            hostname = name
        }
        return FlowRules.Endpoint(hostname: hostname, port: Int(port(of: flow)), isUDP: flow.socketType == SOCK_DGRAM)
    }

    private static func port(of flow: NEFilterSocketFlow) -> UInt16 {
        guard case .hostPort(_, let port) = flow.remoteFlowEndpoint else { return 0 }
        return port.rawValue
    }

    // MARK: Saying what was dropped

    private func report(host: String, flow: NEFilterSocketFlow) {
        let now = Date.now
        let worthSaying = state.withLock { state in
            guard now.timeIntervalSince(state.reported[host] ?? .distantPast) >= Self.reportEvery else { return false }
            state.reported[host] = now
            return true
        }
        guard worthSaying else { return }
        let app = Self.app(of: flow)
        logger.info("dropped \(host, privacy: .public) for \(app, privacy: .public)")
        reporter.blocked(host: host, in: app)
    }

    /// Who opened the connection, from the audit token macOS attaches to every flow: the signing
    /// identifier, which for an app is its bundle identifier.
    private static func app(of flow: NEFilterSocketFlow) -> String {
        guard let token = flow.sourceAppAuditToken else { return "" }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return "" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return "" }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return "" }
        return dictionary[kSecCodeInfoIdentifier as String] as? String ?? ""
    }
}

/// The extension's end of the XPC link to the app. The extension listens; the app connects,
/// exports a `FilterListening`, and is told about each dropped connection until it goes away.
final class FilterReporter: NSObject, NSXPCListenerDelegate, FilterControl, @unchecked Sendable {
    private var listener: NSXPCListener?
    /// Guards the connection list: connections come and go on XPC's queues, and reports arrive
    /// on the filter's.
    private let queue = DispatchQueue(label: "\(FilterXPC.extensionID).reporter")
    private var connections: [NSXPCConnection] = []

    func start() {
        let listener = NSXPCListener(machServiceName: FilterXPC.serviceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
    }

    func stop() {
        listener?.invalidate()
        listener = nil
        queue.sync {
            connections.forEach { $0.invalidate() }
            connections = []
        }
    }

    /// Nothing here is worth guarding: a connection can only ask to be told about dropped
    /// hosts, and only Furlough is listening for that.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FilterControl.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: FilterListening.self)
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in
            self?.queue.sync { self?.connections.removeAll { ObjectIdentifier($0) == id } }
        }
        queue.sync { connections.append(connection) }
        connection.resume()
        return true
    }

    func hello(reply: @escaping @Sendable (Bool) -> Void) {
        reply(true)
    }

    func blocked(host: String, in app: String) {
        let listeners = queue.sync { connections }
        for connection in listeners {
            (connection.remoteObjectProxy as? FilterListening)?.blocked(host: host, in: app)
        }
    }
}
