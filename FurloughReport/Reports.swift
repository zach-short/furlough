import DeviceActivity
import ExtensionKit
import SwiftUI

// `.rank(n)` context lives in Shared/Usage: the app names it when hosting a
// DeviceActivityReport; the scene here with the same context draws it.

/// The recommendation at this position plus its entry (for the icon token), or nothing plus
/// enough to say why.
struct RankSlot: Sendable {
    var position: Int
    var item: Recommendation?
    var entry: UsageEntry?
    /// How many positions have something.
    var count: Int
    var days: Int
}

/// One of 5 fixed-height cards (`UsageAnalysis.rankLimit`) — a report can't tell its host how
/// tall it wants to be, and mounting all 5 at once caused the old page to stutter.
///
/// `nonisolated` because `AppExtensionScene` is main-actor but the extension's `body` isn't.
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
