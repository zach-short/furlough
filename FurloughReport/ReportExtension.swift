import DeviceActivity
import ExtensionKit
import SwiftUI

/// Screen Time's window into Furlough. iOS renders these scenes in a process of their own,
/// where the usage history is readable and nothing else is: no network, and no App Group write
/// that ever reaches the app. So everything Furlough can do with the numbers happens in here,
/// with the same arithmetic as everywhere else (`UsageAnalysis`), and the person carries a
/// suggestion into the editor by hand. Where iOS 26.4 lets the app read the numbers itself
/// (`UsageReader.hasDataAccess`), the app draws its own suggestions with an Apply button and
/// these cards become the illustration.
@main
struct FurloughReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // One scene per rank slot: as many as UsageAnalysis.rankLimit. A result builder
        // cannot loop, so they are spelled out.
        RankReport(1) { RankView(slot: $0) }
        RankReport(2) { RankView(slot: $0) }
        RankReport(3) { RankView(slot: $0) }
        RankReport(4) { RankView(slot: $0) }
        RankReport(5) { RankView(slot: $0) }
    }
}
