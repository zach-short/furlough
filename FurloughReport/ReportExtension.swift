import DeviceActivity
import ExtensionKit
import SwiftUI

/// Runs in its own sandboxed process — usage history readable, but no network and no App Group
/// write reaching the app — so the person carries a suggestion into the editor by hand.
/// Superseded by in-app suggestions where iOS 26.4's `UsageReader.hasDataAccess` applies.
@main
struct FurloughReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // One scene per rank slot (UsageAnalysis.rankLimit); a result builder can't loop.
        RankReport(1) { RankView(slot: $0) }
        RankReport(2) { RankView(slot: $0) }
        RankReport(3) { RankView(slot: $0) }
        RankReport(4) { RankView(slot: $0) }
        RankReport(5) { RankView(slot: $0) }
    }
}
