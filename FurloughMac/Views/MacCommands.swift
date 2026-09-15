import SwiftUI

/// What the menu bar asked the window to do.
///
/// Menu commands are built in the `App`, which has no access to the window's own state, so every
/// item here sets a request and the window performs it through the path its toolbar already
/// uses — never a second path of its own. `HelpRoute` is the same idea, one menu older.
@MainActor
@Observable
final class MacMenuRoute {
    enum Request: Equatable {
        case addApplication
        case addWebsite
        case visualizeWindows
        case dropAnchor
    }

    /// Cleared by the window as soon as it has acted, so the same item works twice.
    var request: Request?
    /// Which half the window is showing. Mirrored both ways: the View menu writes it, and the
    /// segment and the swipe write it back so the checkmark is never a guess.
    var half: Half = .rules
    /// Whether a rule is open in the detail pane. Visualizing windows is a thing you do *to* a
    /// rule, so with none open the item is disabled rather than quietly doing nothing.
    var hasRuleOpen = false
}

/// The menus themselves. A View per group rather than raw `Button`s: `@Bindable` and
/// `@Environment` are only readable inside a View, and menu commands inherit no window's
/// environment.
struct AnchorMenuItems: View {
    let route: MacMenuRoute
    /// Handed over rather than read from the environment: menu commands inherit no window's
    /// environment, so an `@Environment` lookup here would find nothing.
    let model: MacModel

    var body: some View {
        let refusal = model.dropRefusal
        Button("Drop Anchor") { route.request = .dropAnchor }
            .keyboardShortcut("d")
            .disabled(refusal != nil)
            .help(refusal?.message ?? "Locks everything the Anchor holds. Only your iPhone's tag lifts it.")
        // No Weigh Anchor item, and there must never be one: there is no tag reader on a Mac,
        // and a greyed-out release would imply one could exist.
        if let refusal {
            Text(firstSentence(of: refusal.message))
        }
    }

    /// A menu row is one line, and `.noPhone`'s full paragraph is three. The whole of it stays
    /// on the disabled item's own tooltip.
    private func firstSentence(of message: String) -> String {
        guard let end = message.firstIndex(of: ".") else { return message }
        return String(message[...end])
    }
}

struct RulesMenuItems: View {
    let route: MacMenuRoute

    var body: some View {
        Button("Add Application…") { route.request = .addApplication }
            .keyboardShortcut("n")
        Button("Add Website…") { route.request = .addWebsite }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        Divider()
        Button("Visualize Windows…") { route.request = .visualizeWindows }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(!route.hasRuleOpen)
            .help(route.hasRuleOpen ? "The week as a grid." : "Open a rule first.")
    }
}

/// Two checkable items rather than a picker: a picker in a menu carries no key equivalents, and
/// ⌘1 / ⌘2 for the two halves is what a View menu is for.
struct HalfMenuItems: View {
    let route: MacMenuRoute

    var body: some View {
        Toggle("Rules", isOn: showing(.rules))
            .keyboardShortcut("1", modifiers: .command)
        Toggle("The Anchor", isOn: showing(.anchor))
            .keyboardShortcut("2", modifiers: .command)
    }

    /// Turning one on is choosing it; turning the current one off would leave the window
    /// showing neither, so it does nothing.
    private func showing(_ half: Half) -> Binding<Bool> {
        Binding(get: { route.half == half }, set: { if $0 { route.half = half } })
    }
}
