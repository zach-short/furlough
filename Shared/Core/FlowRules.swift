import Foundation

/// What the Mac's web filter enforces. Pure; the system extension in `FurloughMacFilter` is a
/// thin shell around it.
///
/// The second half of website blocking on the Mac: `Browsers` reads Safari/Chromium tabs but
/// can't see Firefox, a Dock-saved site, or a non-browser app hitting a blocked host directly.
/// This filter sees every connection and drops those instead, closing those holes.
struct FilterRules: Equatable, Sendable {
    /// Exactly as `Decision.blockedHosts` names them: a host and every subdomain, matched with
    /// `Hosts.matches`.
    var hosts: [String]
    /// When these rules expire, on the device's clock — past it the filter blocks nothing until
    /// fresh rules arrive. Keeps a dropped connection tied to `Policy.decide` rather than to a
    /// stale list: if Furlough is force-quit, a site stays blocked only until its next window
    /// edge, well before the watchdog is due.
    var until: Date
    /// Bumped on every push, so the extension can tell a new list from the old without
    /// comparing every host.
    var version: Int

    static let empty = FilterRules(hosts: [], until: .distantPast, version: 0)

    private enum Key {
        static let hosts = "hosts"
        static let until = "until"
        static let version = "version"
    }

    init(hosts: [String], until: Date, version: Int) {
        self.hosts = hosts
        self.until = until
        self.version = version
    }

    func isCurrent(at now: Date) -> Bool { now < until }

    func activeHosts(at now: Date) -> [String] { isCurrent(at: now) ? hosts : [] }

    /// `NEFilterProviderConfiguration.vendorConfiguration` — strings, a date, a number, because
    /// every value must be one the system can archive.
    var vendorConfiguration: [String: Any] {
        [Key.hosts: hosts, Key.until: until, Key.version: version]
    }

    /// Nil for a dictionary that isn't one of ours, which the extension reads as "block nothing".
    init?(vendorConfiguration: [String: Any]?) {
        guard let dictionary = vendorConfiguration,
              let hosts = dictionary[Key.hosts] as? [String],
              let until = dictionary[Key.until] as? Date,
              let version = dictionary[Key.version] as? Int else { return nil }
        self.init(hosts: hosts, until: until, version: version)
    }
}

/// Every decision the filter makes, from the rules and what a connection shows.
enum FlowRules {
    /// A connection as the extension sees it the moment it opens.
    struct Endpoint: Equatable, Sendable {
        /// macOS only knows this for apps that connect by name (Safari, URLSession); browsers
        /// that resolve the name themselves and connect to the address, like Chromium, show up
        /// nameless.
        var hostname: String?
        var port: Int
        var isUDP: Bool

        /// An address literal is treated as no name — nothing in a rule matches `142.250.72.14`,
        /// and treating it as one would skip the byte inspection that finds the real name.
        init(hostname: String?, port: Int, isUDP: Bool) {
            let name = hostname?.lowercased() ?? ""
            self.hostname = name.isEmpty || Self.isAddress(name) ? nil : name
            self.port = port
            self.isUDP = isUDP
        }

        private static func isAddress(_ text: String) -> Bool {
            text.contains(":") || text.allSatisfy { $0.isNumber || $0 == "." }
        }
    }

    /// What to do with a connection before any bytes have crossed it.
    enum NewFlow: Equatable, Sendable {
        case allow
        /// Not decidable yet — the first outbound bytes carry the name being asked for.
        case inspect
        case drop(host: String, rule: String)
        /// QUIC (nameless, UDP 443): its bytes can't be read like TLS's, so while anything is
        /// blocked it's refused outright and the browser silently falls back to TCP.
        case dropQUIC
    }

    /// What to do with a connection after looking at some of its outbound bytes.
    enum Inspection: Equatable, Sendable {
        case allow
        case more
        case drop(host: String, rule: String)
    }

    /// A TLS ClientHello is a kilobyte or two (more with post-quantum key shares).
    static let peekBytes = 8 * 1024
    /// Past this with no name found, let the connection through — it isn't carrying a
    /// readable name.
    static let maxInspectedBytes = 16 * 1024

    static func newFlow(_ endpoint: Endpoint, rules: FilterRules, now: Date) -> NewFlow {
        let hosts = rules.activeHosts(at: now)
        guard !hosts.isEmpty else { return .allow }
        if let hostname = endpoint.hostname {
            guard let rule = match(hostname, in: hosts) else { return .allow }
            return .drop(host: hostname, rule: rule)
        }
        switch (endpoint.isUDP, endpoint.port) {
        case (false, 443), (false, 80): return .inspect
        case (true, 443): return .dropQUIC
        default: return .allow
        }
    }

    /// `bytes` is everything sent so far from the first byte.
    static func inspect(_ bytes: Data, port: Int, rules: FilterRules, now: Date) -> Inspection {
        let hosts = rules.activeHosts(at: now)
        guard !hosts.isEmpty else { return .allow }
        let parsed = port == 443 ? TLS.serverName(in: bytes) : HTTP.host(in: bytes)
        switch parsed {
        case .found(let host):
            guard let rule = match(host, in: hosts) else { return .allow }
            return .drop(host: host, rule: rule)
        case .absent:
            return .allow
        case .incomplete:
            return bytes.count < maxInspectedBytes ? .more : .allow
        }
    }

    /// The rule `host` falls under, if any: the host itself or a parent of it.
    static func match(_ host: String, in hosts: [String]) -> String? {
        let host = host.lowercased()
        return hosts.first { Hosts.matches(host, rule: $0) }
    }

    enum Parse: Equatable, Sendable {
        case found(String)
        /// Complete with no name, or not the expected shape for this port — nothing to wait for.
        case absent
        case incomplete
    }

    /// The name a TLS client asks for, from the ClientHello. Encrypted Client Hello hides it,
    /// and then there is nothing here to read.
    enum TLS {
        private static let handshakeRecord: UInt8 = 0x16
        private static let clientHello: UInt8 = 0x01
        private static let serverNameExtension = 0
        private static let hostNameType: UInt8 = 0

        static func serverName(in data: Data) -> Parse {
            let bytes = [UInt8](data)
            // Unwrap records first (a ClientHello can span two) so the parse below never has
            // to know where a record boundary fell.
            var handshake: [UInt8] = []
            var index = 0
            var length: Int?
            while length.map({ handshake.count < $0 + 4 }) ?? true {
                guard index + 5 <= bytes.count else { return .incomplete }
                guard bytes[index] == handshakeRecord, bytes[index + 1] == 0x03 else { return .absent }
                let recordLength = Int(bytes[index + 3]) << 8 | Int(bytes[index + 4])
                guard recordLength > 0 else { return .absent }
                let start = index + 5
                let end = start + recordLength
                guard end <= bytes.count else { return .incomplete }
                handshake += bytes[start..<end]
                index = end
                if length == nil, handshake.count >= 4 {
                    guard handshake[0] == clientHello else { return .absent }
                    length = Int(handshake[1]) << 16 | Int(handshake[2]) << 8 | Int(handshake[3])
                }
            }
            guard let length else { return .absent }
            var reader = Reader(handshake, from: 4, to: 4 + length)
            // Version + random, then three length-prefixed fields before the extensions.
            guard reader.skip(2 + 32),
                  let sessionLength = reader.byte(), reader.skip(Int(sessionLength)),
                  let cipherLength = reader.uint16(), reader.skip(cipherLength),
                  let compressionLength = reader.byte(), reader.skip(Int(compressionLength)),
                  let extensionsLength = reader.uint16() else { return .absent }
            let extensionsEnd = min(reader.index + extensionsLength, reader.end)
            while reader.index + 4 <= extensionsEnd {
                guard let type = reader.uint16(), let extensionLength = reader.uint16() else { return .absent }
                let dataEnd = reader.index + extensionLength
                guard dataEnd <= extensionsEnd else { return .absent }
                if type == serverNameExtension {
                    // A list of names, but there is only ever one: the host name.
                    guard reader.skip(2), let nameType = reader.byte(), nameType == hostNameType,
                          let nameLength = reader.uint16(), let name = reader.string(nameLength),
                          !name.isEmpty else { return .absent }
                    return .found(name.lowercased())
                }
                reader.index = dataEnd
            }
            return .absent
        }
    }

    /// The name an HTTP/1 client asks for, from the Host header of its first request. Only plain
    /// HTTP on port 80 arrives this way; everything else is TLS.
    enum HTTP {
        private static let methods = ["GET", "POST", "HEAD", "PUT", "DELETE", "OPTIONS", "PATCH", "TRACE", "CONNECT"]
        private static let headerEnd = "\r\n\r\n"

        static func host(in data: Data) -> Parse {
            guard let text = String(bytes: data, encoding: .isoLatin1) else { return .absent }
            guard let lineEnd = text.range(of: "\r\n") else {
                // No whole line yet; wait only if this could still turn into a request line.
                let couldBeMethod = methods.contains { method in
                    (method + " ").hasPrefix(text) || text.hasPrefix(method + " ")
                }
                return couldBeMethod ? .incomplete : .absent
            }
            let requestLine = text[..<lineEnd.lowerBound].split(separator: " ", omittingEmptySubsequences: false)
            guard requestLine.count == 3, methods.contains(String(requestLine[0])),
                  requestLine[2].hasPrefix("HTTP/1.") else { return .absent }
            // The header-ending blank line can double up with the request line's own break,
            // for a request with no headers at all.
            guard let end = text.range(of: headerEnd, range: lineEnd.lowerBound..<text.endIndex) else { return .incomplete }
            let headers = text[lineEnd.upperBound..<max(lineEnd.upperBound, end.lowerBound)]
            for line in headers.components(separatedBy: "\r\n") {
                guard let colon = line.firstIndex(of: ":"),
                      line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "host" else { continue }
                var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
                // Strip a port; an IPv6 literal keeps its brackets/colons and matches no rule anyway.
                if !value.hasPrefix("["), let portColon = value.lastIndex(of: ":") {
                    value = String(value[..<portColon])
                }
                return value.isEmpty ? .absent : .found(value)
            }
            return .absent
        }
    }

    /// Bounds-checked, so a malformed hello ends in `.absent` rather than a trap.
    private struct Reader {
        let bytes: [UInt8]
        var index: Int
        let end: Int

        init(_ bytes: [UInt8], from start: Int, to end: Int) {
            self.bytes = bytes
            self.index = start
            self.end = min(end, bytes.count)
        }

        mutating func byte() -> UInt8? {
            guard index < end else { return nil }
            defer { index += 1 }
            return bytes[index]
        }

        mutating func uint16() -> Int? {
            guard let high = byte(), let low = byte() else { return nil }
            return Int(high) << 8 | Int(low)
        }

        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, index + count <= end else { return false }
            index += count
            return true
        }

        mutating func string(_ count: Int) -> String? {
            guard count >= 0, index + count <= end else { return nil }
            defer { index += count }
            return String(bytes: bytes[index..<index + count], encoding: .utf8)
        }
    }
}
