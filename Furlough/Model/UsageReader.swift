import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// What the app asks Screen Time for, and — on iOS 26.4 with data access — the numbers in its
/// own hands. Data access needs the Family Controls App & Website Usage capability, which
/// makes the authorization prompt all-or-nothing; Apple grants it to App Store customers only
/// in the EU, dev builds anywhere (`FamilyActivityData`). Without it, `hasDataAccess` stays
/// false and the report extension is the only window — the app hosts its cards but never sees
/// a number.
enum UsageReader {
    /// Two weeks holds two of every weekday, so a weekday and a weekend peak each rest on more
    /// than one day.
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
            // DeviceActivity works in tokens; a filter naming none would report the whole
            // device. UsageView never asks for a report on a typed host, so this never fires.
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

    /// Timeout for a Screen Time query: the installed-apps round trip usually answers in a
    /// second or two but can hang indefinitely, which used to leave "Asking Screen Time…" on
    /// screen for minutes.
    static let patience: Duration = .seconds(12)

    /// Screen Time did not answer within `patience`.
    struct Unanswered: LocalizedError {
        var errorDescription: String? { "Screen Time did not answer." }
    }

    /// `fillingTokens(in:)`, given up on after `limit`.
    @available(iOS 26.4, *)
    static func fillingTokens(in summary: UsageSummary, within limit: Duration) async throws -> Naming {
        try await within(limit) { try await fillingTokens(in: summary) }
    }

    /// `kind(forKey:)`, given up on after `limit`. Nil means "not installed" (an answer, not a
    /// failure) — only silence throws.
    @available(iOS 26.4, *)
    static func kind(forKey key: String, within limit: Duration) async throws -> TargetKind? {
        guard let encoded = try await within(limit, { try await encodedKinds()[key] }) else { return nil }
        return try JSONDecoder().decode(TargetKind.self, from: encoded)
    }

    /// The tokens behind `keys`, from one walk of the installed list, given up on after
    /// `limit`. Uninstalled keys are simply absent.
    @available(iOS 26.4, *)
    static func kinds(forKeys keys: [String], within limit: Duration) async throws -> [String: TargetKind] {
        let encoded = try await within(limit) { try await encodedKinds() }
        let decoder = JSONDecoder()
        var found: [String: TargetKind] = [:]
        for key in keys {
            guard let data = encoded[key] else { continue }
            found[key] = try decoder.decode(TargetKind.self, from: data)
        }
        return found
    }

    /// `ask`, or `Unanswered` when it has not come back within `limit`. Races a detached task
    /// against a timer rather than cancelling `ask`: `installedApplications` sometimes never
    /// returns and does not honor cancellation, so a real timeout has to abandon it rather than
    /// wait for it to acknowledge cancellation. The straggler isn't cancelled either — it's left
    /// to complete and fill `Enumeration`'s cache, so asking again later costs nothing.
    private static func within<Answer: Sendable>(
        _ limit: Duration,
        _ ask: @escaping @Sendable () async throws -> Answer
    ) async throws -> Answer {
        let race = Race<Answer>()
        Task.detached(priority: .userInitiated) {
            do { await race.settle(.answered(try await ask())) }
            catch { await race.settle(.refused(error.localizedDescription)) }
        }
        // Detached so a caller going away can't leave the race with nobody to end it.
        let timer = Task.detached(priority: .utility) {
            try? await Task.sleep(for: limit)
            await race.settle(.unanswered)
        }
        defer { timer.cancel() }
        let outcome = await withTaskCancellationHandler {
            await race.first()
        } onCancel: {
            Task { await race.settle(.unanswered) }
        }
        switch outcome {
        case .answered(let answer): return answer
        case .unanswered: throw Unanswered()
        case .refused(let reason): throw Refused(reason)
        }
    }

    /// Screen Time answered with a complaint. Carried as its message rather than the error
    /// itself, which can't cross out of the task that caught it.
    struct Refused: LocalizedError {
        var errorDescription: String?
        init(_ reason: String) { errorDescription = reason }
    }

    /// Which of the two came first.
    private enum Outcome<Answer: Sendable>: Sendable {
        case answered(Answer)
        case refused(String)
        case unanswered
    }

    /// First settle wins; a later one is silently dropped, so an answer arriving after the
    /// deadline never resumes anybody twice.
    private actor Race<Answer: Sendable> {
        private var outcome: Outcome<Answer>?
        private var waiting: CheckedContinuation<Outcome<Answer>, Never>?

        func settle(_ result: Outcome<Answer>) {
            guard outcome == nil else { return }
            outcome = result
            if let waiting {
                self.waiting = nil
                waiting.resume(returning: result)
            }
        }

        /// Awaited once, by `within`.
        func first() async -> Outcome<Answer> {
            if let outcome { return outcome }
            return await withCheckedContinuation { waiting = $0 }
        }
    }

    /// What one pass at naming found.
    struct Naming: Sendable {
        var summary: UsageSummary
        /// An empty answer means a failed query (worth retrying), not a phone with no apps.
        var answered: Bool
    }

    /// The fortnight with its tokens filled in, out of a fresh answer from Screen Time. Data
    /// access hands over minutes and a bundle identifier only — no token, so without this every
    /// card says "This app" over a blank tile with nothing for Apply to write a rule on.
    /// Always re-walks the installed list even for entries that already have a cached token,
    /// since those are exactly the ones most worth re-checking against what's installed now.
    @available(iOS 26.4, *)
    static func fillingTokens(in summary: UsageSummary) async throws -> Naming {
        let kinds = try await encodedKinds()
        // An empty answer means the query failed — resolving against it would strip every
        // token the cache just supplied.
        guard !kinds.isEmpty else { return Naming(summary: summary, answered: false) }
        return Naming(summary: try fillingTokens(in: summary, from: kinds), answered: true)
    }

    /// Same fold against a map already in hand (e.g. the cache), with no query and nothing to
    /// fail. Resolves every entry, not just tokenless ones, so a token for an app since deleted
    /// gets dropped once the map no longer names it.
    static func fillingTokens(in summary: UsageSummary, from kinds: [String: Data]) throws -> UsageSummary {
        let decoder = JSONDecoder()
        var filled = summary
        filled.entries = try summary.entries.map { entry in
            var found = entry
            found.applicationToken = nil
            found.webDomainToken = nil
            guard let encoded = kinds[entry.key] else { return found }
            switch try decoder.decode(TargetKind.self, from: encoded) {
            case .application(let token): found.applicationToken = token
            case .webDomain(let token): found.webDomainToken = token
            default: break
            }
            return found
        }
        return filled
    }

    /// The last answer Screen Time gave, or nil if it never has — see `TokenCache`.
    static func cachedKinds() -> [String: Data]? {
        guard let cache = SharedStore.tokenCache(), !cache.entries.isEmpty else { return nil }
        return cache.entries
    }

    /// Everything installed and visited, keyed like `UsageCollector` keys an entry, as encoded
    /// `TargetKind`s — cached on the way past so the next visit skips the query. Deduplicated
    /// through `Enumeration`: several callers (usage page, activation, arrivals) each walk
    /// every app on the phone, and firing them concurrently would queue up inside Screen Time
    /// and make every caller pay for all of them.
    @available(iOS 26.4, *)
    private static func encodedKinds() async throws -> [String: Data] {
        try await Enumeration.shared.kinds()
    }

    /// The one walk of the installed list, shared. A caller arriving mid-flight joins the
    /// existing one rather than starting another.
    private actor Enumeration {
        static let shared = Enumeration()
        private var asking: Task<[String: Data], any Error>?

        @available(iOS 26.4, *)
        func kinds() async throws -> [String: Data] {
            if let asking { return try await asking.value }
            let question = Task<[String: Data], any Error> {
                let kinds = try await UsageReader.queryKinds()
                // `refreshed` rejects an empty result, so a failed query can't wipe a good
                // cache. Written here (not per-caller) so joining an in-flight query is free.
                if let fresh = TokenCache.refreshed(with: kinds) { SharedStore.save(fresh) }
                return kinds
            }
            asking = question
            defer { asking = nil }
            return try await question.value
        }
    }

    /// Off the main actor and answering in bytes: `FamilyActivityData` and its return arrays
    /// aren't Sendable, so they can't cross into or out of an actor directly.
    @available(iOS 26.4, *)
    @concurrent
    private static func queryKinds() async throws -> [String: Data] {
        let encoder = JSONEncoder()
        var kinds: [String: Data] = [:]
        for app in try await FamilyActivityData.shared.installedApplications {
            guard let identifier = app.bundleIdentifier, let token = app.token else { continue }
            kinds[identifier] = try encoder.encode(TargetKind.application(token))
        }
        for site in try await FamilyActivityData.shared.visitedWebDomains {
            guard let domain = site.domain, let token = site.token else { continue }
            kinds["web:\(domain)"] = try encoder.encode(TargetKind.webDomain(token))
        }
        return kinds
    }

    /// Every installed app and visited site, keyed by `TargetKind` — the inverse of a target,
    /// which holds an opaque token and wants an identity. Data access only (EU customers, dev
    /// builds anywhere); everything reading it must work without it too — see
    /// `AppModel.nameFromTables`. Prefers the cache over a fresh query so an activation
    /// (`AppModel.nameUnnamedTargets`) doesn't pay to enumerate every app on the phone.
    @available(iOS 26.4, *)
    static func identities() async throws -> [TargetKind: String] {
        let kinds: [String: Data]
        if let cached = cachedKinds() {
            kinds = cached
        } else {
            kinds = try await encodedKinds()
        }
        var identities: [TargetKind: String] = [:]
        let decoder = JSONDecoder()
        for (key, encoded) in kinds {
            identities[try decoder.decode(TargetKind.self, from: encoded)] = key
        }
        return identities
    }

    /// The token for a usage entry Screen Time named but gave no token for, looked up by bundle
    /// ID / "web:"+domain among installed apps and visited domains. Uses the shared
    /// `encodedKinds` walk rather than one of its own, since a single lookup costs the whole
    /// list anyway.
    @available(iOS 26.4, *)
    static func kind(forKey key: String) async throws -> TargetKind? {
        guard let encoded = try await encodedKinds()[key] else { return nil }
        return try JSONDecoder().decode(TargetKind.self, from: encoded)
    }
}
