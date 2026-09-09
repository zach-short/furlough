import DeviceActivity
import ManagedSettings
import SwiftUI

/// The reports the app hosts and the extension draws. The app names one when it makes a
/// `DeviceActivityReport`; the scene in FurloughReport with the same context answers it.
/// A report cannot tell the app how tall its content is, so each one is shaped to fit a
/// height the app already knows.
extension DeviceActivityReport.Context {
    /// The `position`-th heaviest app or site on the phone, 1 the heaviest, with the rule it
    /// would take: one card, one report. The slot after the last worthwhile one says so; slots
    /// past that draw nothing. `UsageAnalysis.rankLimit` says how many there are. The app shows
    /// one at a time, so at most one or two of these remote views ever exist together.
    static func rank(_ position: Int) -> Self { Self("rank-\(position)") }
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

    /// The target this entry is, when Screen Time handed a token over with the numbers: what a
    /// rule is written on, and what draws the real icon. Nil for something it counted but
    /// named no token for; `UsageReader.kind(forKey:)` goes looking for those.
    var targetKind: TargetKind? {
        if let applicationToken { return .application(applicationToken) }
        if let webDomainToken { return .webDomain(webDomainToken) }
        return nil
    }

    /// What to call this where there is no token to draw Apple's own name from. With data
    /// access `localizedDisplayName` is nil and `name` falls back to the bundle identifier,
    /// which is not a name anybody should be shown: a site names itself, an app does not.
    var plainName: String {
        if let domain = UsageAnalysis.domain(inKey: key) { return domain }
        return name == key ? "This app" : name
    }
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

    /// The same fortnight with the halves of each linked target added together.
    ///
    /// Screen Time hands out an app and a website as two entries, because on the phone they are
    /// two things. Linked, they are one row on one rule and one shared budget, so ranking them
    /// apart would put YouTube on the page twice and suggest a budget for each half of one that is
    /// already shared. `UsageAnalysis.folding` decides which entries belong together and which of
    /// them carries the pair; the carrier keeps its own key and token, so the card still draws
    /// Apple's icon and name for the app and `entry(for:)` still finds it.
    ///
    /// `UsageHistogram.merge` adds minutes and pickups and leaves `daysObserved` alone, which is
    /// what makes the merged average right: both halves were observed over the very same days, so
    /// the sum is divided by those days once rather than twice.
    func folded(in config: Config) -> UsageSummary {
        let folding = UsageAnalysis.folding(
            entries.map { ($0.key, $0.targetKind, $0.histogram.totalMinutes) },
            in: config
        )
        guard !folding.isEmpty else { return self }
        var byKey = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for (from, into) in folding where from != into {
            guard let half = byKey.removeValue(forKey: from), var carrier = byKey[into] else { continue }
            carrier.histogram.merge(half.histogram)
            byKey[into] = carrier
        }
        var folded = self
        folded.entries = byKey.values.sorted { $0.key < $1.key }
        return folded
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
                        guard let key = site.domain.map(UsageAnalysis.webKey) ?? site.token.map({ UsageAnalysis.webKey("\($0.hashValue)") }) else { continue }
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
