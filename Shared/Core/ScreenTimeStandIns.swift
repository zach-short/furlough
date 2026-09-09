// Stand-ins for the three ManagedSettings token types, for a target that must not link the
// Screen Time frameworks.
//
// App Review's automated pass rejected build 202609090423 on 2026-09-09 under guideline 2.5.1:
// "the app uses one or more Screen Time APIs but has not been submitted with the Family
// Controls entitlement". Every bundle that links FamilyControls, ManagedSettings or
// DeviceActivity must carry `com.apple.developer.family-controls`, and the widget was linking
// ManagedSettings — not for any API call, only because `Models.swift` and `Policy.swift` import
// it for `ApplicationToken`, `WebDomainToken` and `ActivityCategoryToken`, which sit inside
// the state the widget decodes from the App Group. The widget carried no such entitlement, and
// its App ID has no distribution grant; that one bundle failed the whole submission.
//
// A widget has no business with the Screen Time API, so rather than entitle it, the
// FurloughWidgets target builds with `NO_SCREEN_TIME` set (see project.yml), those two
// imports fall away, and these three types take the tokens' names. They decode whatever JSON
// the real token wrote and would encode it back unchanged, so the store round-trips; equality
// is structural, which is all a `Set` of them needs. Nothing in the widget ever opens a token.
//
// Only ever compiled with the condition set: everywhere else the real types exist and these
// must not.
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

/// Any JSON value, kept as it was found. The real tokens' wire format is Apple's to change,
/// so this preserves a subtree of whatever shape rather than assuming one.
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
