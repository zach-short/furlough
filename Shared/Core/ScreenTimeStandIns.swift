// Stand-ins for the three ManagedSettings token types, so the widget need not link Screen Time
// frameworks at all.
//
// App Review rejected build 202609090423 (2026-09-09, guideline 2.5.1) because the widget
// linked ManagedSettings — only for `ApplicationToken`/`WebDomainToken`/`ActivityCategoryToken`
// used by decoded state — without the Family Controls entitlement the widget's App ID lacks.
//
// The `NO_SCREEN_TIME` build flag (project.yml) drops those imports for FurloughWidgets and
// substitutes these types, which decode/re-encode the same JSON unchanged (structural equality
// is all a `Set` needs) without ever opening a token. Only ever compiled with that flag set —
// elsewhere the real types must be used.
#if os(iOS) && NO_SCREEN_TIME
import Foundation

/// A token as the bytes Apple wrote, never looked inside.
struct ApplicationToken: Codable, Hashable, Sendable {
    let raw: OpaqueJSON
    init(from decoder: Decoder) throws { raw = try OpaqueJSON(from: decoder) }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}

struct WebDomainToken: Codable, Hashable, Sendable {
    let raw: OpaqueJSON
    init(from decoder: Decoder) throws { raw = try OpaqueJSON(from: decoder) }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}

struct ActivityCategoryToken: Codable, Hashable, Sendable {
    let raw: OpaqueJSON
    init(from decoder: Decoder) throws { raw = try OpaqueJSON(from: decoder) }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}

/// Any JSON value, kept as found — preserves whatever shape Apple's token wire format has,
/// without assuming one.
indirect enum OpaqueJSON: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([OpaqueJSON])
    case object([String: OpaqueJSON])

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: Key.self) {
            var object: [String: OpaqueJSON] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(OpaqueJSON.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [OpaqueJSON] = []
            while !unkeyed.isAtEnd { array.append(try unkeyed.decode(OpaqueJSON.self)) }
            self = .array(array)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let bool = try? single.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? single.decode(Int.self) {
            self = .int(int)
        } else if let number = try? single.decode(Double.self) {
            self = .number(number)
        } else if let string = try? single.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(in: single, debugDescription: "Not a JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let bool):
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case .int(let int):
            var container = encoder.singleValueContainer()
            try container.encode(int)
        case .number(let number):
            var container = encoder.singleValueContainer()
            try container.encode(number)
        case .string(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array { try container.encode(value) }
        case .object(let object):
            var container = encoder.container(keyedBy: Key.self)
            for (name, value) in object { try container.encode(value, forKey: Key(name)) }
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
#endif
