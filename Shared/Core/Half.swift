import Foundation

/// Which half of Furlough. Rules are the everyday half — allowed hours, a daily budget, and a
/// delay on anything that hands time back. The Anchor is the other — one tap, as much of the
/// phone as you want, and a physical tag as the only key.
///
/// A named pair rather than a flag, because neither one is the feature and neither is the
/// extra. Everywhere the app tells the two apart — the page it opens on, the guide still
/// running, where a + is adding — it has to name both; an `isAnchor` Bool would quietly make
/// one of them the default case and the other the exception, which is the thing this whole
/// pass exists to undo.
enum Half: String, CaseIterable, Codable, Sendable {
    case rules
    case anchor

    /// What the segment calls it. Short, because it shares a title-width control with the
    /// other one — the intro and Help have the room for "The Anchor" and use it.
    var title: String {
        switch self {
        case .rules: "Rules"
        case .anchor: "Anchor"
        }
    }

    /// The other one.
    var other: Half { self == .rules ? .anchor : .rules }
}
