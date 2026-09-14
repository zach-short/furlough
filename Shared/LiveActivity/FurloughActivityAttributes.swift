import ActivityKit
import Foundation

/// Live Activity shown while at least one target's window is open.
struct FurloughActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var openNames: [String]
        var note: String
        /// The featured target has had its 5-minute budget warning: the glass turns amber.
        var warned = false
        /// Today's budget for the featured target, in minutes; nil where there is no real limit.
        var budgetMinutes: Int?
        /// Known only once the warning fires (`RuntimeState.warnedAt`); while nil, minutes left
        /// are genuinely unknown, so the activity states the allowance instead of counting it down.
        var budgetDeadline: Date?

        init(
            openNames: [String],
            note: String,
            warned: Bool = false,
            budgetMinutes: Int? = nil,
            budgetDeadline: Date? = nil
        ) {
            self.openNames = openNames
            self.note = note
            self.warned = warned
            self.budgetMinutes = budgetMinutes
            self.budgetDeadline = budgetDeadline
        }

        /// `warned` arrived after the first activities were started, so its absence must decode.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            openNames = try container.decode([String].self, forKey: .openNames)
            note = try container.decode(String.self, forKey: .note)
            warned = try container.decodeIfPresent(Bool.self, forKey: .warned) ?? false
            budgetMinutes = try container.decodeIfPresent(Int.self, forKey: .budgetMinutes)
            budgetDeadline = try container.decodeIfPresent(Date.self, forKey: .budgetDeadline)
        }
    }

    /// The real start of the window, so the hourglass can show how much of it is left.
    var windowStart: Date
    var windowEnd: Date
}
