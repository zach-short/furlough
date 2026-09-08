import DeviceActivity
import FamilyControls
import Foundation

/// What the app asks Screen Time for, and — on iOS 26.4 with data access — the numbers in
/// its own hands. Apple limits customer installs of data access to devices in the EU on EU
/// accounts (`FamilyActivityData`), and it needs the Family Controls App & Website Usage
/// capability, which also turns the authorisation prompt all-or-nothing. Development builds
/// work anywhere. Without it `hasDataAccess` stays false and the report extension is the only
/// window: the app hosts its cards and never sees a number.
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
        }
    }

    /// True when this phone lets the app read the numbers itself.
    static var hasDataAccess: Bool {
        guard #available(iOS 26.4, *) else { return false }
        return AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess
    }

    /// The fortnight, fetched by the app and folded the same way the report folds it. Throws
    /// where iOS will not hand the data over: check `hasDataAccess` first.
    @available(iOS 26.4, *)
    static func summary(calendar: Calendar = .current) async throws -> UsageSummary {
        try await UsageCollector.collect(
            DeviceActivityData.activityData(filteredBy: filter(calendar: calendar), using: .cached),
            calendar: calendar
        )
    }
}
