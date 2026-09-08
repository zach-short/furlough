import DeviceActivity
import ExtensionKit
import SwiftUI

// The context these scenes answer to, `.rank(n)`, lives in Shared/Usage: the app names one
// when it hosts a DeviceActivityReport, and the scene here with the same context draws it.

/// What a rank slot draws: the recommendation at that position with the entry behind it (for
/// its token, so the card can show the real icon), or nothing, and enough about the rest to
/// say why nothing.
struct RankSlot: Sendable {
    var position: Int
    var item: Recommendation?
    var entry: UsageEntry?
    /// How many positions have something.
    var count: Int
    var days: Int
}

/// One card of the ranking. Five of these exist (`UsageAnalysis.rankLimit`), each its own
/// report, so the app can give every card a fixed height and show them one at a time: a report
/// cannot tell its host how tall it wants to be, and mounting five at once is what made the
/// old page stutter.
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
        let item = position <= advice.count ? advice[position - 1] : nil
        return RankSlot(
            position: position,
            item: item,
            entry: item.flatMap { summary.entry(for: $0) },
            count: advice.count,
            days: summary.totalDays
        )
    }
}

extension UsageCollector {
    /// The report's results never fail, so a walk that somehow throws is simply empty.
    static func summary(of data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        (try? await collect(data)) ?? UsageSummary()
    }
}
