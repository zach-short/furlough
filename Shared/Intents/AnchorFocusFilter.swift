#if os(iOS)
import AppIntents
import Foundation
import WidgetKit

/// A system Focus drops the Anchor. Configured once under Settings > Focus > (a Focus) >
/// Focus Filters > Furlough; from then on, turning that Focus on locks whatever the Anchor
/// holds, and only the tag lifts it again.
///
/// **Turning the Focus off does nothing at all.** That is the whole of the care this file
/// needs. The system performs a Focus Filter twice — once when the Focus turns on with the
/// parameters as configured, and once when it turns off with every parameter back at its
/// default (Apple's own sample documents exactly that: `alwaysUseDarkMode: false`,
/// `status: nil`). So `dropsAnchor` is both what the person switched on and how this tells
/// the two calls apart, and the off-case returns without writing anything. Wiring the off-case
/// to a release is the one thing that would turn "a Focus controls the anchor" into an unblock
/// button with a schedule: unanchoring is the tag, unconditionally, and nothing added here or
/// anywhere else changes that.
///
/// A fourth caller of `AnchorDrop.drop`, beside the app, the Control Center control and
/// `DropAnchorIntent` — not new anchor logic. There is deliberately no parameter for *what*
/// the anchor holds: the Anchor screen owns the list and the scope, and a Filter that could
/// set the scope could narrow the hold as easily as widen it (Zach's call, 2026-09-12). What
/// this can do is show what the anchor holds, and warn about it, at the moment it is being
/// configured — see `displayRepresentation`.
///
/// It runs in the app: iOS launches Furlough in the background to perform it. An App Intents
/// extension would be the next step if that ever proves unreliable, and `AnchorDrop` already
/// works from any process, so it would be a target membership and nothing else.
struct AnchorFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Drop the Anchor"
    static let description = IntentDescription(
        "Locks everything the Anchor holds while this Focus is on. Turning the Focus off does not unlock it — only your paired tag does.",
        categoryName: "Anchor"
    )

    /// The switch, and the only parameter. It has to be a parameter rather than an assumption:
    /// a Filter with nothing to configure could not tell a Focus turning on from one turning
    /// off, because both arrive here as one call to `perform()`.
    @Parameter(
        title: "Drop the Anchor",
        description: "Off means this Focus changes nothing. Only your paired tag ever lifts an anchor.",
        default: false
    )
    var dropsAnchor: Bool

    /// What the Filter's own row says, read live from the anchor it would drop.
    ///
    /// This is where the warning goes (Zach's call, 2026-09-12). The confirmation sheet the
    /// Anchor button shows cannot appear at the moment a Focus turns on — there is no Furlough
    /// on screen and no system Focus Filter has room for one — so the honest place for it is
    /// the screen where this is being set up, naming the essential apps the anchor actually
    /// holds rather than a sentence about apps in general. Read at configuration time, not at
    /// every activation, and said again in `Config.anchorWarning`'s own words so the Filter and
    /// the app cannot warn differently.
    var displayRepresentation: DisplayRepresentation {
        guard dropsAnchor else {
            return DisplayRepresentation(title: "Nothing", subtitle: "This Focus will not touch the Anchor.")
        }
        let config = SharedStore.load().config
        let held = LocalizedStringResource(stringLiteral: "Anchors \(config.anchor.heldDescription)")
        guard let warning = config.anchorWarning,
              let text = UtilityText.anchoring(
                names: warning.names, utility: warning.utility, detail: warning.detail
              )
        else {
            return DisplayRepresentation(
                title: held,
                subtitle: "Only your paired tag lifts it. Turning this Focus off will not."
            )
        }
        return DisplayRepresentation(title: held, subtitle: LocalizedStringResource(stringLiteral: text))
    }

    /// Offered when the Filter is first added, already switched on: a Filter whose suggested
    /// setting does nothing would be a screen that looks configured and is not.
    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [Self] {
        // `let`, and not a slip: `@Parameter` keeps its value in a reference of its own, so
        // setting one through it does not mutate the intent.
        let filter = AnchorFocusFilter()
        filter.dropsAnchor = true
        return [filter]
    }

    func perform() async throws -> some IntentResult {
        // The off-case. `dropsAnchor` is false either because the Focus is turning off — the
        // system hands back the default — or because the Filter was configured to do nothing.
        // Both mean the same thing here, and the same thing is nothing: no drop, no release,
        // no write of any kind.
        guard dropsAnchor else { return .result() }
        switch AnchorDrop.drop(reason: "focus filter") {
        case .anchored(let anchor):
            SharedStore.log("focus filter dropped the anchor: \(anchor.heldDescription)")
        case .refused(let why):
            // Nothing to show it to — a Focus turning on has no app in front — so it goes in
            // the log, where "why did my Focus not anchor anything" is answered.
            SharedStore.log("focus filter refused: \(why.message)")
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: Furlough.anchorControlKind)
        return .result()
    }
}
#endif
