import DeviceActivity
import ManagedSettings
import SwiftUI

/// The app names a `DeviceActivityReport` context; the matching scene in FurloughReport answers
/// it. A report can't tell the app how tall its content is, so each context is shaped to fit a
/// height the app already knows.
extension DeviceActivityReport.Context {
    /// The `position`-th heaviest app or site, 1 = heaviest, one card per report. Slots past the
    /// last worthwhile one draw nothing; `UsageAnalysis.rankLimit` caps how many exist.
    static func rank(_ position: Int) -> Self { Self("rank-\(position)") }
}

/// One app or website as Screen Time reported it, folded onto the week. The token rides along so
/// the app (where iOS lets it read the numbers itself) can write a rule without a picker; the
/// report extension has no use for it. Token is an immutable value Apple hasn't marked Sendable,
/// hence the unchecked.
struct UsageEntry: Hashable, @unchecked Sendable {
    /// The bundle identifier, "web:" + domain, or a stand-in for a token with no name.
    var key: String
    var name: String
    var histogram: UsageHistogram
    var applicationToken: ApplicationToken?
    var webDomainToken: WebDomainToken?

    var ranked: (key: String, name: String, histogram: UsageHistogram) { (key, name, histogram) }

    /// Nil when Screen Time counted this but handed over no token; `UsageReader.kind(forKey:)`
    /// goes looking for those separately.
    var targetKind: TargetKind? {
        if let applicationToken { return .application(applicationToken) }
        if let webDomainToken { return .webDomain(webDomainToken) }
        return nil
    }

    /// With data access, `name` may just be the bundle identifier — not fit to show, since a
    /// site names itself but an app doesn't.
    var plainName: String {
        if let domain = UsageAnalysis.domain(inKey: key) { return domain }
        return name == key ? "This app" : name
    }

    /// A bare bundle identifier is neither tokened nor named; `UsageView` holds such a card back
    /// while still waiting on Screen Time for the token, and drops it once Screen Time stops answering.
    var isNamed: Bool { targetKind != nil || name != key }
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

    /// The same fortnight with the halves of each linked target (see `UsageAnalysis.folding`)
    /// added together — the carrier keeps its own key and token, so its card still draws
    /// correctly. `UsageHistogram.merge` leaves `daysObserved` alone since both halves were
    /// observed over the same days.
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
    /// Ask for hourly segments — a daily one lands whole on midnight. Days observed are read off
    /// the data itself (first segment to last), since a report scene is never told what date
    /// range the app asked for.
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
                        // Apple's name, then the tables, then the bare identifier as last resort.
                        var entry = entries[key] ?? UsageEntry(
                            key: key,
                            name: app.localizedDisplayName
                                ?? app.bundleIdentifier.flatMap(Brand.name(forKey:))
                                ?? app.bundleIdentifier
                                ?? "This app",
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
