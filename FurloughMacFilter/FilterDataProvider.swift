import Foundation
import Network
import NetworkExtension
import os
import Security

/// Runs as root at boot, before login, so it keeps no state of its own; rules come from the
/// saved filter configuration and expire at their own `until`. `@unchecked Sendable`: macOS
/// calls in from multiple queues, guarded by `state`'s lock.
final class FilterDataProvider: NEFilterDataProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: FilterXPC.extensionID, category: "filter")
    /// Guarded by a lock: verdicts, config changes, and XPC arrive on different queues.
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let reporter = FilterReporter()
    private var configurationWatch: NSKeyValueObservation?

    private struct State: Sendable {
        var rules = FilterRules.empty
        var buffers: [UUID: Data] = [:]
        /// Last report time per host, so 20 connections from one page become one card.
        var reported: [String: Date] = [:]
    }

    private static let reportEvery: TimeInterval = 8

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        readRules()
        // Rules arrive by the app re-saving the configuration; readRules is cheap and idempotent.
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

    /// Skips reprocessing when the version is unchanged, rather than diffing host by host.
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
            // `offset` says whether these bytes are the whole connection so far or just what's
            // new; both land as one buffer.
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

    /// Falls back to the endpoint's name when macOS has no `remoteHostname`; an address
    /// endpoint has none, which `Endpoint` also enforces.
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

    /// The signing identifier (an app's bundle identifier) from the audit token macOS attaches to every flow.
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

/// The extension's XPC listener; the app connects and is told about each drop until it disconnects.
final class FilterReporter: NSObject, NSXPCListenerDelegate, FilterControl, @unchecked Sendable {
    private var listener: NSXPCListener?
    /// Guards the connection list: connections come and go on XPC's queues, reports on the filter's.
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

    /// No auth check needed: a connection can only ask to hear about drops, and only Furlough listens.
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
