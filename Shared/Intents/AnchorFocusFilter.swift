import AppIntents
import Foundation
import WidgetKit

/// A system Focus drops the Anchor. Configured once under Settings > Focus > (a Focus) >
/// Focus Filters > Furlough — System Settings > Focus on the Mac; turning that Focus on locks
/// whatever the Anchor holds, and only the tag lifts it again. A Focus syncs across a person's
/// devices, so one Work Focus reaches the phone and the Mac, and each drops its own anchor.
///
/// **Turning the Focus off does nothing.** The system calls `perform()` twice per Focus Filter
/// — once when the Focus turns on with the configured parameters, once when it turns off with
/// every parameter back at default — so `dropsAnchor` is how the two calls are told apart, and
/// the off-case must write nothing. Wiring it to a release would turn "a Focus controls the
/// anchor" into an unblock button with a schedule, which unanchoring never is.
///
/// Deliberately has no parameter for *what* the anchor holds (Zach's call, 2026-09-12) — the
/// Anchor screen owns that. On the phone a fourth caller of `AnchorDrop.drop` alongside the
/// app, the Control Center control, and `DropAnchorIntent`; on the Mac a caller of
/// `MacModel.dropAnchor`, which is the one drop the Mac has and refuses with no iPhone on the
/// link or no iCloud, since only an iPhone's tag can release an anchor dropped there. Runs in
/// the app (the system launches Furlough in the background to perform it).
struct AnchorFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Drop the Anchor"
    static let description = IntentDescription(
        "Locks everything the Anchor holds while this Focus is on. Turning the Focus off does not unlock it — only your paired tag does.",
        categoryName: "Anchor"
    )

    /// Has to be a real parameter — with nothing to configure there'd be no way to tell the
    /// on-call from the off-call in `perform()`.
    @Parameter(
        title: "Drop the Anchor",
        description: "Off means this Focus changes nothing. Only your paired tag ever lifts an anchor.",
        default: false
    )
    var dropsAnchor: Bool

    /// The confirmation sheet the Anchor button shows can't appear when a Focus silently turns
    /// on, so the warning is shown here instead, at setup time (Zach's call, 2026-09-12) — worded
    /// via `Config.anchorWarning` so the Filter and the app never disagree. On the Mac the row
    /// also says when the drop would be refused, in the refusal's own words, because a Filter
    /// fires with no UI and this row is the one place a person reads before turning it on.
    var displayRepresentation: DisplayRepresentation {
        guard dropsAnchor else {
            return DisplayRepresentation(title: "Nothing", subtitle: "This Focus will not touch the Anchor.")
        }
        let config = SharedStore.load().config
        let held = LocalizedStringResource(stringLiteral: "Anchors \(config.anchor.heldDescription)")
        #if !os(iOS)
        if let refusal = Self.macRefusalAhead {
            return DisplayRepresentation(title: held, subtitle: LocalizedStringResource(stringLiteral: refusal.message))
        }
        #endif
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

    #if !os(iOS)
    /// What `MacModel.dropAnchor` would refuse right now, read the way it reads it. Offered and
    /// refused rather than hidden: a Focus Filter cannot be withheld from the list per device,
    /// and a row that says why is honest where a missing one would only be quiet.
    private static var macRefusalAhead: Policy.DropRefusal? {
        guard AnchorCloud.isAvailable else { return .noCloud }
        guard DeviceLink.isEnrolled, DeviceLink.roster().hasKey(besides: AnchorSync.deviceID) else { return .noPhone }
        return nil
    }
    #endif

    /// Suggested already switched on — a filter whose default does nothing would look configured
    /// and not be.
    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [Self] {
        // `let`, not a slip: `@Parameter` holds its value in its own reference, so this doesn't
        // mutate the intent.
        let filter = AnchorFocusFilter()
        filter.dropsAnchor = true
        return [filter]
    }

    func perform() async throws -> some IntentResult {
        // Off-case: the Focus turned off, or was configured to do nothing. Either way, no write.
        guard dropsAnchor else { return .result() }
        #if os(iOS)
        switch AnchorDrop.drop(reason: "focus filter") {
        case .anchored(let anchor):
            SharedStore.log("focus filter dropped the anchor: \(anchor.heldDescription)")
            // iOS launches Furlough in the background to perform this, so the request may be
            // refused; the Lock Screen then catches up at the next `enforce`.
            LiveActivityManager.sync(state: SharedStore.load())
        case .refused(let why):
            // No app on screen to show this to, so it goes in the log instead.
            SharedStore.log("focus filter refused: \(why.message)")
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: Furlough.anchorControlKind)
        #else
        // The Mac's drop, refusals and all — `.noPhone` and `.noCloud` still say no.
        let refusal = await MainActor.run { MacModel.shared.dropAnchor() }
        if let refusal {
            SharedStore.log("focus filter refused: \(refusal)")
            // A Filter fires with no UI. Silence here would be a Focus a person believes is
            // locking their Mac and is not, so the refusal is posted where they will see it.
            Notifier.reply(id: "focus-refused", title: "Anchor not dropped", body: refusal)
        } else {
            SharedStore.log("focus filter dropped the anchor")
        }
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}
