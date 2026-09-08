import DeviceActivity
import ExtensionKit
import SwiftUI

// The contexts these scenes answer to, `.cutback` and `.focus`, live in Shared/Usage: the app
// names one when it hosts a DeviceActivityReport, and this extension matches it here.

/// Ranks everything Screen Time hands over and suggests a rule for the heaviest few.
///
/// `nonisolated`: `AppExtensionScene` is a main-actor protocol, so a scene would otherwise be
/// inferred onto the main actor, and the extension's `body`, which is not, could not build it.
/// Off the main actor is also where the walk over a fortnight of segments belongs.
nonisolated struct CutbackReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .cutback
    let content: (UsageSummary) -> CutbackView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        await UsageCollector.summary(of: data)
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
