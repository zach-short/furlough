import Foundation

/// Which half of Furlough: Rules (allowed hours, a daily budget, delay on loosening) or the
/// Anchor (one tap, a physical tag as the only key).
///
/// A named pair rather than an `isAnchor` Bool — a Bool would quietly make one half the default
/// and the other the exception, which is what this whole pass exists to undo.
enum Half: String, CaseIterable, Codable, Sendable {
    case rules
    case anchor

    /// Short, since it shares a title-width control with the other one.
    var title: String {
        switch self {
        case .rules: "Rules"
        case .anchor: "Anchor"
        }
    }

    /// The other one.
    var other: Half { self == .rules ? .anchor : .rules }
}
