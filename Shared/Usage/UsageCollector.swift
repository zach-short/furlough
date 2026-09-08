import DeviceActivity
import ManagedSettings
import SwiftUI

/// The two reports the app hosts and the extension draws. The app names one when it makes a
/// `DeviceActivityReport`; the scene in FurloughReport with the same context answers it.
extension DeviceActivityReport.Context {
    /// The whole phone: the heaviest apps and sites and the rule each one would take.
    static let cutback = Self("cutback")
    /// One thing, which the app filters to its token: its hours, and the rule for it.
    static let focus = Self("focus")
}

/// One app or website as Screen Time reported it, folded onto the week. The token rides along
/// so the app, where iOS lets it read the numbers itself, can write a rule without a picker;
/// the report extension has no use for it. A token is an immutable value Apple has not marked
/// Sendable, hence the unchecked.
struct UsageEntry: Hashable, @unchecked Sendable {
    /// The bundle identifier, "web:" and the domain, or a stand-in for a token with no name.
    var key: String
    var name: String
    var histogram: UsageHistogram
    var applicationToken: ApplicationToken?
    var webDomainToken: WebDomainToken?

    /// The shape `UsageAnalysis.rank` reads.
    var ranked: (key: String, name: String, histogram: UsageHistogram) { (key, name, histogram) }
}

/// Everything one walk of the data found.
struct UsageSummary: Sendable {
    var entries: [UsageEntry] = []
    /// First hour seen to last, or nil when there was nothing.
    var interval: DateInterval?
    var daysObserved = UsageHistogram.oneWeek

    var totalDays: Int { daysObserved.reduce(0, +) }
    var totalMinutesPerDay: Double {
        totalDays == 0 ? 0 : entries.reduce(0) { $0 + $1.histogram.totalMinutes } / Double(totalDays)
    }
    var recommendations: [Recommendation] { UsageAnalysis.rank(entries.map(\.ranked)) }
    func entry(for recommendation: Recommendation) -> UsageEntry? {
        entries.first { $0.key == recommendation.key }
    }
}

enum UsageCollector {
    /// Walk `data` — every person, every device, every segment — and fold each app's and
    /// website's minutes onto the week by the hour each segment starts in. Ask for hourly
    /// segments; a daily one lands whole on midnight. The days observed are read off the data,
    /// first segment to last, because a report scene is never told what stretch the app asked
    /// for. The same walk serves the report's results and the app's own fetch.
    static func collect<Data: AsyncSequence>(
        _ data: Data,
        calendar: Calendar = .current
    ) async throws -> UsageSummary where Data.Element == DeviceActivityData {
        var entries: [String: UsageEntry] = [:]
        var earliest: Date?
        var latest: Date?

        for try await datum in data {
            for await segment in datum.activitySegments {
                let start = segment.dateInterval.start
                earliest = min(earliest ?? start, start)
                latest = max(latest ?? segment.dateInterval.end, segment.dateInterval.end)
                let weekday = calendar.component(.weekday, from: start)
                let hour = calendar.component(.hour, from: start)

                for await category in segment.categories {
                    for await activity in category.applications {
                        let app = activity.application
                        guard let key = app.bundleIdentifier ?? app.token.map({ "app:\($0.hashValue)" }) else { continue }
                        var entry = entries[key] ?? UsageEntry(
                            key: key,
                            name: app.localizedDisplayName ?? app.bundleIdentifier ?? "This app",
                            histogram: UsageHistogram(),
                            applicationToken: app.token
                        )
                        entry.histogram.add(
                            weekday: weekday,
                            hour: hour,
                            minutes: activity.totalActivityDuration / 60,
                            pickups: activity.numberOfPickups
                        )
                        entries[key] = entry
                    }
                    for await activity in category.webDomains {
                        let site = activity.webDomain
                        guard let key = site.domain.map({ "web:\($0)" }) ?? site.token.map({ "web:\($0.hashValue)" }) else { continue }
                        var entry = entries[key] ?? UsageEntry(
                            key: key,
                            name: site.domain ?? "This website",
                            histogram: UsageHistogram(),
                            webDomainToken: site.token
                        )
                        entry.histogram.add(weekday: weekday, hour: hour, minutes: activity.totalActivityDuration / 60)
                        entries[key] = entry
                    }
                }
            }
        }

        var summary = UsageSummary()
        if let earliest, let latest, earliest < latest {
            let interval = DateInterval(start: earliest, end: latest)
            summary.interval = interval
            summary.daysObserved = UsageHistogram.daysObserved(in: interval, calendar: calendar)
        }
        summary.entries = entries.values
            .map { entry in
                var dated = entry
                dated.histogram.daysObserved = summary.daysObserved
                return dated
            }
            .sorted { $0.key < $1.key }
        return summary
    }
}
