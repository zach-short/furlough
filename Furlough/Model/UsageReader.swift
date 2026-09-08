import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// What the app asks Screen Time for, and — on iOS 26.4 with data access — the numbers in
/// its own hands. Data access needs the Family Controls App & Website Usage capability (on
/// the Furlough target since 2026-09-08), which turns the authorisation prompt all-or-nothing,
/// and Apple honours it for App Store customers only in the EU (`FamilyActivityData`).
/// Development builds work anywhere. Without it `hasDataAccess` stays false and the report
/// extension is the only window: the app hosts its cards and never sees a number.
enum UsageReader {
    /// How far back every report and fetch looks. Two weeks holds two of every weekday, so a
    /// weekday and a weekend peak each rest on more than one day.
    static let days = 14

    /// The last `days` whole days and today so far.
    static func interval(calendar: Calendar = .current, now: Date = .now) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        return DateInterval(start: start, end: now)
    }

    /// Hour by hour, everyone on the account, this phone and any iPad beside it.
    static func filter(calendar: Calendar = .current) -> DeviceActivityFilter {
        DeviceActivityFilter(segment: .hourly(during: interval(calendar: calendar)), users: .all, devices: .init([.iPhone, .iPad]))
    }

    /// The same stretch, narrowed to one target: what the focus report is shown.
    static func filter(for kind: TargetKind, calendar: Calendar = .current) -> DeviceActivityFilter {
        let segment = DeviceActivityFilter.SegmentInterval.hourly(during: interval(calendar: calendar))
        let devices = DeviceActivityFilter.Devices([.iPhone, .iPad])
        switch kind {
        case .application(let token):
            return DeviceActivityFilter(segment: segment, users: .all, devices: devices, applications: [token])
        case .webDomain(let token):
            return DeviceActivityFilter(segment: segment, users: .all, devices: devices, webDomains: [token])
        case .category(let token):
            return DeviceActivityFilter(segment: segment, users: .all, devices: devices, categories: [token])
        case .host:
            // Nothing counts a typed host: DeviceActivity works in tokens, and a filter that
            // named no application, web domain or category would report the whole device.
            // `UsageView` does not offer a report for one, so this is never asked for.
            return DeviceActivityFilter(segment: segment, users: .all, devices: devices, applications: [])
        }
    }

    /// True when `status` lets the app read the numbers itself.
    static func hasDataAccess(_ status: AuthorizationStatus) -> Bool {
        guard #available(iOS 26.4, *) else { return false }
        return status == .approvedWithDataAccess
    }

    /// True when this phone lets the app read the numbers itself, right now.
    static var hasDataAccess: Bool { hasDataAccess(AuthorizationCenter.shared.authorizationStatus) }

    /// The fortnight, fetched by the app and folded the same way the report folds it. Throws
    /// where iOS will not hand the data over: check `hasDataAccess` first.
    @available(iOS 26.4, *)
    static func summary(calendar: Calendar = .current) async throws -> UsageSummary {
        try await UsageCollector.collect(
            DeviceActivityData.activityData(filteredBy: filter(calendar: calendar), using: .cached),
            calendar: calendar
        )
    }

    /// The target for a usage entry Screen Time named but handed no token for: its key is a
    /// bundle identifier, or "web:" and a domain, looked up among the apps installed and the
    /// domains visited. Nil when it is not there.
    @available(iOS 26.4, *)
    static func kind(forKey key: String) async throws -> TargetKind? {
        try await encodedKind(forKey: key).map { try JSONDecoder().decode(TargetKind.self, from: $0) }
    }

    /// The lookup itself, off the main actor: `FamilyActivityData` and what it returns are not
    /// Sendable, so they may neither be reached from an actor nor handed back to one. The
    /// answer crosses as bytes instead; `TargetKind` is Codable for the store anyway.
    @available(iOS 26.4, *)
    @concurrent
    private static func encodedKind(forKey key: String) async throws -> Data? {
        let kind: TargetKind?
        if key.hasPrefix("web:") {
            let domain = String(key.dropFirst(4))
            kind = try await FamilyActivityData.shared.visitedWebDomains
                .first { $0.domain == domain }?.token.map(TargetKind.webDomain)
        } else {
            kind = try await FamilyActivityData.shared.installedApplications
                .first { $0.bundleIdentifier == key }?.token.map(TargetKind.application)
        }
        return try kind.map { try JSONEncoder().encode($0) }
    }
}
