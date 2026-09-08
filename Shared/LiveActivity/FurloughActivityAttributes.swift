import ActivityKit
import Foundation

/// Live Activity shown while at least one target's window is open.
struct FurloughActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var openNames: [String]
        var note: String
        /// The featured target has had its 5-minute budget warning: the glass turns amber.
        var warned = false

        init(openNames: [String], note: String, warned: Bool = false) {
            self.openNames = openNames
            self.note = note
            self.warned = warned
        }

        /// `warned` arrived after the first activities were started, so its absence must decode.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            openNames = try container.decode([String].self, forKey: .openNames)
            note = try container.decode(String.self, forKey: .note)
            warned = try container.decodeIfPresent(Bool.self, forKey: .warned) ?? false
        }
    }

    /// The real start of the window, so the hourglass can show how much of it is left.
    var windowStart: Date
    var windowEnd: Date
}
