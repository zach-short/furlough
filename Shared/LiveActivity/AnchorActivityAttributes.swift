import ActivityKit
import Foundation

/// Live Activity shown while the Anchor holds — the half a person feels most, and the one that
/// had nothing on the Lock Screen until now.
///
/// A second type rather than a flag on `FurloughActivityAttributes`: `ActivityAttributes` is a
/// *type*, so a second kind of activity is a second lifecycle, not a field.
///
/// The attributes carry nothing. There is only ever one anchor, so the single activity of this
/// type is the hold — which is what lets one scheduled ahead with `Activity.request(start:)`
/// simply become the live one when its moment arrives, updated in place by the monitor rather
/// than ended and re-requested by a process that may not request anything.
///
/// **It carries no App Intent, and must never gain one.** Every button on a Live Activity runs
/// an intent, and the only intent that could belong here is a release — which lives behind a
/// tag scan in the app, and nowhere else.
struct AnchorActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// `AnchorText.headline`: "Everything anchored", "3 anchored".
        var headline: String
        /// `AnchorProfile.heldDescription`: "3 items", "Everything except 2".
        var held: String
        /// When the hold began — in the state, not the attributes, because a scheduled drop
        /// promises a minute and the callback that performs it can arrive a little after it.
        var droppedAt: Date
        /// When it lifts by itself; nil when the tag is the only way back.
        var until: Date?
        var anchorsEverything = false

        init(
            headline: String,
            held: String,
            droppedAt: Date,
            until: Date? = nil,
            anchorsEverything: Bool = false
        ) {
            self.headline = headline
            self.held = held
            self.droppedAt = droppedAt
            self.until = until
            self.anchorsEverything = anchorsEverything
        }
    }
}
