import DeviceActivity
import ExtensionKit
import SwiftUI

// The contexts these scenes answer to, `.rank(n)` and `.focus`, live in Shared/Usage: the app
// names one when it hosts a DeviceActivityReport, and the scene here with the same context
// draws it.

/// What a rank slot draws: the recommendation at that position, or nothing, and enough about
/// the rest to say why nothing.
struct RankSlot: Sendable {
    var position: Int
    var item: Recommendation?
    /// How many positions have something.
    var count: Int
    var days: Int
}

/// One row of the ranking. Five of these exist (`UsageAnalysis.rankLimit`), each its own
/// report, so the app can give every row a fixed height and nothing is squeezed or clipped:
/// a report cannot tell its host how tall it wants to be.
///
/// `nonisolated`: `AppExtensionScene` is a main-actor protocol, so a scene would otherwise be
/// inferred onto the main actor, and the extension's `body`, which is not, could not build it.
/// Off the main actor is also where the walk over a fortnight of segments belongs.
nonisolated struct RankReport: DeviceActivityReportScene {
    let position: Int
    let content: (RankSlot) -> RankView

    var context: DeviceActivityReport.Context { .rank(position) }

    init(_ position: Int, content: @escaping (RankSlot) -> RankView) {
        self.position = position
        self.content = content
    }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> RankSlot {
        let summary = await UsageCollector.summary(of: data)
        let advice = summary.recommendations
        return RankSlot(
            position: position,
            item: position <= advice.count ? advice[position - 1] : nil,
            count: advice.count,
            days: summary.totalDays
        )
    }
}

/// Draws one app's or site's week by the hour. The app passes a filter with a single token, so
/// the heaviest entry in the data is the one asked about. `nonisolated` as above.
nonisolated struct FocusReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .focus
    let content: (UsageSummary) -> FocusView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        await UsageCollector.summary(of: data)
    }
}

extension UsageCollector {
    /// The report's results never fail, so a walk that somehow throws is simply empty.
    static func summary(of data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        (try? await collect(data)) ?? UsageSummary()
    }
}
