import ActivityKit
import Foundation

/// Live Activity shown while at least one target's window is open.
struct FurloughActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var openNames: [String]
        var note: String
    }

    var windowStart: Date
    var windowEnd: Date
}
