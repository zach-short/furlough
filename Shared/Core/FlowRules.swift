import Foundation

/// What the Mac's web filter enforces. Pure, and the system extension in `FurloughMacFilter` is
/// a thin shell around it, so everything the filter decides is tested from here.
///
/// The filter is the second half of website blocking on the Mac. The first, `Browsers`, reads
/// the tabs of Safari and the Chromium browsers and sends a blocked one to the shield page. It
/// cannot see Firefox, a site saved to the Dock as an app, or an app that loads a blocked host
/// outside a browser. The filter sees every connection the Mac opens and drops the ones to a
/// blocked host, so those holes close — with a failed connection rather than a shield page, and
/// the floating card to say why.
struct FilterRules: Equatable, Sendable {
    /// Hosts blocked right now, exactly as `Decision.blockedHosts` names them: a host and every
    /// subdomain of it, matched with `Hosts.matches`.
    var hosts: [String]
    /// When these rules stop being trusted, on the device's clock: the next moment `Policy` says
    /// a status could change. Past it the filter blocks nothing until fresh rules arrive. That is
    /// what keeps a dropped connection derived from `Policy.decide` rather than from a list the
    /// app left behind — with Furlough force-quit, a site stays blocked only until its next
    /// window edge, and the watchdog has it back long before that.
    var until: Date
    /// Bumped by the app on every push, so the extension can tell a new list from the old one
    /// without comparing every host.
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

    /// Whether the rules still stand at `now`.
    func isCurrent(at now: Date) -> Bool { now < until }

    /// The hosts to block at `now`: none once the rules have lapsed.
    func activeHosts(at now: Date) -> [String] { isCurrent(at: now) ? hosts : [] }

    /// The dictionary that carries the rules to the extension, as
    /// `NEFilterProviderConfiguration.vendorConfiguration`. Strings, a date and a number, because
    /// every value in it has to be one the system can archive.
    var vendorConfiguration: [String: Any] {
        [Key.hosts: hosts, Key.until: until, Key.version: version]
    }

    /// The rules as they come back out of that dictionary. Nil for a dictionary that is not one
    /// of ours, which the extension reads as "block nothing".
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
        /// The name the app connected by, when the system knows it. macOS knows it only for apps
        /// that connect by name — Safari, Firefox, anything on URLSession. A browser that resolves
        /// the name itself and connects to the address, as the Chromium family does, shows up
        /// nameless, and so does anything connecting to a bare address.
        var hostname: String?
        var port: Int
        var isUDP: Bool

        /// A name the system hands over is lowercased, and an address literal is no name at all:
        /// nothing in a rule can match `142.250.72.14`, and treating it as a name would skip the
        /// look at the first bytes that would have found the real one.
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
        /// Not decidable yet: the first outbound bytes carry the name the client is asking for.
        case inspect
        case drop(host: String, rule: String)
        /// A nameless connection over UDP 443. That is QUIC, whose first bytes cannot be read the
        /// way TLS's can, so while anything is blocked it is refused and the browser falls back
        /// to TCP, where the name can be read. The fallback is the browsers' own and invisible.
        case dropQUIC
    }

    /// What to do with a connection after looking at some of its outbound bytes.
    enum Inspection: Equatable, Sendable {
        case allow
        /// The name has not arrived yet: look at more.
        case more
        case drop(host: String, rule: String)
    }

    /// How many outbound bytes to ask for at a time. A TLS ClientHello is a kilobyte or two, more
    /// with post-quantum key shares, and an HTTP request line and headers are less.
    static let peekBytes = 8 * 1024
    /// Past this much with no name found, the connection is let through: whatever it is, it is
    /// not carrying a name the filter can read.
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

    /// `bytes` is everything sent so far, from the first byte.
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

    /// What reading a name out of the first bytes found.
    enum Parse: Equatable, Sendable {
        case found(String)
        /// The bytes are complete and there is no name in them, or they are not what was expected
        /// on this port at all. Either way there is nothing to wait for.
        case absent
        /// More bytes would settle it.
        case incomplete
    }

    /// The name a TLS client asks for, from the ClientHello that opens every HTTPS connection.
    /// Encrypted Client Hello hides it, and then there is nothing here to read.
    enum TLS {
        private static let handshakeRecord: UInt8 = 0x16
        private static let clientHello: UInt8 = 0x01
        private static let serverNameExtension = 0
        private static let hostNameType: UInt8 = 0

        static func serverName(in data: Data) -> Parse {
            let bytes = [UInt8](data)
            // The ClientHello is one handshake message, usually in one record and occasionally
            // split across two. The records are unwrapped first, so the parse below never has to
            // know where a record boundary fell.
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
            // Version, random, then three length-prefixed fields before the extensions.
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
                    // A list of names, of which there is only ever one: a host name.
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
                // No whole line yet. Worth waiting for only if what is here could still turn
                // into a request line.
                let couldBeMethod = methods.contains { method in
                    (method + " ").hasPrefix(text) || text.hasPrefix(method + " ")
                }
                return couldBeMethod ? .incomplete : .absent
            }
            let requestLine = text[..<lineEnd.lowerBound].split(separator: " ", omittingEmptySubsequences: false)
            guard requestLine.count == 3, methods.contains(String(requestLine[0])),
                  requestLine[2].hasPrefix("HTTP/1.") else { return .absent }
            // The blank line that ends the headers can be the request line's own line break
            // doubled, which is a request with no headers at all.
            guard let end = text.range(of: headerEnd, range: lineEnd.lowerBound..<text.endIndex) else { return .incomplete }
            let headers = text[lineEnd.upperBound..<max(lineEnd.upperBound, end.lowerBound)]
            for line in headers.components(separatedBy: "\r\n") {
                guard let colon = line.firstIndex(of: ":"),
                      line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "host" else { continue }
                var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
                // A port is not part of the name. An IPv6 literal keeps its brackets and its
                // colons, and matches no rule anyway.
                if !value.hasPrefix("["), let portColon = value.lastIndex(of: ":") {
                    value = String(value[..<portColon])
                }
                return value.isEmpty ? .absent : .found(value)
            }
            return .absent
        }
    }

    /// Walks bytes with bounds checks, so a malformed hello ends in `.absent` rather than a trap.
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
