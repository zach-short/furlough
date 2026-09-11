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

    /// How long one question to Screen Time is given before it is treated as unanswered. The
    /// installed-apps query behind `fillingTokens` and `kind(forKey:)` is one round trip to
    /// Screen Time's own process that usually answers in a second or two and sometimes never
    /// does, and a caller with nothing else to do about it kept "Asking Screen Time…" on the
    /// screen for minutes at a time. Generous rather than tight, because the page no longer waits
    /// on the answer: the cost of giving up on a slow answer is an icon, and the cost of not
    /// giving up was the page.
    static let patience: Duration = .seconds(12)

    /// Screen Time did not answer within `patience`.
    struct Unanswered: LocalizedError {
        var errorDescription: String? { "Screen Time did not answer." }
    }

    /// `fillingTokens(in:)`, given up on after `limit` — see `patience`.
    @available(iOS 26.4, *)
    static func fillingTokens(in summary: UsageSummary, within limit: Duration) async throws -> Naming {
        try await within(limit) { try await fillingTokens(in: summary) }
    }

    /// `kind(forKey:)`, given up on after `limit` — see `patience`. Nil where the key is not
    /// installed, which is an answer and not a failure: only silence throws.
    @available(iOS 26.4, *)
    static func kind(forKey key: String, within limit: Duration) async throws -> TargetKind? {
        guard let encoded = try await within(limit, { try await encodedKinds()[key] }) else { return nil }
        return try JSONDecoder().decode(TargetKind.self, from: encoded)
    }

    /// The tokens behind `keys`, out of one walk of the installed list, given up on after
    /// `limit`. Keys that are not installed are simply absent.
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

    /// `ask`, or `Unanswered` when it has not come back within `limit`.
    ///
    /// The question is left behind at the deadline rather than waited on, and that distinction
    /// is the whole of this. A task group may not be left while a child of it is still running,
    /// so `cancelAll` inside one only *asks* the child to stop — and the question this exists
    /// for, `installedApplications`, is exactly the one that sometimes never comes back and does
    /// not answer the asking. A timeout that still had to wait for it was no timeout at all: it
    /// is what left "Applying…" on a usage card with nothing that could ever take it off.
    ///
    /// The straggler is not even cancelled. `Enumeration` holds one query for everyone who asks,
    /// so a question that answers late still fills the cache and still answers the next caller —
    /// which is what makes asking again a second later cost nothing.
    private static func within<Answer: Sendable>(
        _ limit: Duration,
        _ ask: @escaping @Sendable () async throws -> Answer
    ) async throws -> Answer {
        let race = Race<Answer>()
        Task.detached(priority: .userInitiated) {
            do { await race.settle(.answered(try await ask())) }
            catch { await race.settle(.refused(error.localizedDescription)) }
        }
        // Detached, so a caller that goes away cannot leave the race with nobody to end it.
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

    /// Screen Time answered with a complaint. Carried as what it said rather than as the error
    /// itself, which cannot cross out of the task that caught it.
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

    /// The first answer in, and no way for the second to matter. Whoever settles first wins and
    /// the loser's `settle` does nothing, so a question that comes back after the deadline is
    /// dropped on the floor rather than resuming anybody twice.
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
        /// Screen Time answered at all. An answer holding nothing is a failed query, not a
        /// phone with no apps on it, and is worth asking again; an answer that named some but
        /// not others is Screen Time working, and the rest are simply not installed under
        /// those identifiers any more, so asking again would only take longer to say so.
        var answered: Bool
    }

    /// The fortnight with its tokens filled in, out of a fresh answer from Screen Time.
    ///
    /// Data access hands over minutes and a bundle identifier and nothing else: no
    /// `localizedDisplayName`, and no token either. A token is the only thing that names an app
    /// on screen (`Label(token)` draws Apple's own name and icon) and the only thing a rule can
    /// be written on, so without this every card says "This app" over a blank tile and Apply
    /// has nothing to write on. Matching each key against what is installed puts both back.
    ///
    /// One walk of the installed list for the whole summary, not one per entry. The query is
    /// always made, even where every entry already has a token: since the cache
    /// (`TokenCache`) fills them before the first frame, a summary that looks complete is
    /// exactly the one whose tokens most need checking against what is installed now.
    @available(iOS 26.4, *)
    static func fillingTokens(in summary: UsageSummary) async throws -> Naming {
        let kinds = try await encodedKinds()
        // An empty answer is a failed query, not a phone with no apps on it, so nothing is
        // resolved against it — resolving would take away every token the cache just supplied.
        guard !kinds.isEmpty else { return Naming(summary: summary, answered: false) }
        return Naming(summary: try fillingTokens(in: summary, from: kinds), answered: true)
    }

    /// The same fold against a map already in hand — the cache, on the way to the first frame —
    /// with no query at all, and so nothing to wait for and nothing to fail.
    ///
    /// Every entry is resolved, not only the tokenless ones. A token here came from a map, and
    /// the map is the whole truth about what is installed: an entry the map does not name has no
    /// token, which is what lets a cached token for an app deleted since the last visit be taken
    /// away again the moment Screen Time answers.
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
            // Nothing else is keyed the way a usage entry is, so nothing else can match.
            default: break
            }
            return found
        }
        return filled
    }

    /// The last answer Screen Time gave, or nil where it has never answered — see `TokenCache`
    /// for why it is kept. Costs a read of the App Group defaults and nothing else.
    static func cachedKinds() -> [String: Data]? {
        guard let cache = SharedStore.tokenCache(), !cache.entries.isEmpty else { return nil }
        return cache.entries
    }

    /// Everything installed and everything visited, keyed the way `UsageCollector` keys an
    /// entry, as encoded `TargetKind`s — and written down on the way past, so the next visit
    /// opens on it rather than on this query.
    ///
    /// One question at a time, through `Enumeration`: the usage page asks on every visit, an
    /// activation asks for the names it is missing, an arrival asks for the token behind a
    /// bundle identifier, and each one of those is a walk of every app on the phone. Asked at
    /// once they queue up inside Screen Time and every caller pays for all of them, which is how
    /// a page that had given up waiting could still be waiting.
    @available(iOS 26.4, *)
    private static func encodedKinds() async throws -> [String: Data] {
        try await Enumeration.shared.kinds()
    }

    /// The one walk of the installed list, shared. A caller arriving while a question is in
    /// flight waits on that one rather than adding another — including the caller whose own
    /// patience ran out a moment ago and is asking again (`within`).
    private actor Enumeration {
        static let shared = Enumeration()
        private var asking: Task<[String: Data], any Error>?

        @available(iOS 26.4, *)
        func kinds() async throws -> [String: Data] {
            if let asking { return try await asking.value }
            let question = Task<[String: Data], any Error> {
                let kinds = try await UsageReader.queryKinds()
                // Only an answer worth keeping: `refreshed` says no to an empty one, so a query
                // that failed cannot wipe a good cache. Written here rather than by each caller,
                // so that joining a question in flight costs nothing.
                if let fresh = TokenCache.refreshed(with: kinds) { SharedStore.save(fresh) }
                return kinds
            }
            asking = question
            defer { asking = nil }
            return try await question.value
        }
    }

    /// The query itself. Off the main actor and answering in bytes for the same reason
    /// `encodedKind` is: `FamilyActivityData` and the arrays it hands back are not Sendable, so
    /// they may neither be reached from an actor nor returned to one.
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

    /// Every installed app and visited site, as the key `UsageCollector` would give it against
    /// the `TargetKind` it is. The inverse of what a target holds: a target has an opaque token
    /// and wants an identity, and this is the only thing on the device that knows both.
    ///
    /// Data access only, so it answers on a development build anywhere and for a customer only in
    /// the EU (`FamilyActivityData`). Everything that reads it must work without it — see
    /// `AppModel.nameFromTables`, where the fallback is the name the shield teaches instead.
    ///
    /// The cache first, and the query only where there is no cache at all: this runs on every
    /// activation (`AppModel.nameUnnamedTargets`), and enumerating every app on the phone is not
    /// what an activation should cost. A cache that has gone stale costs nothing here either —
    /// the worst it can do is name a target after an app that has since been deleted, which is
    /// still what that target is.
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

    /// The target for a usage entry Screen Time named but handed no token for: its key is a
    /// bundle identifier, or "web:" and a domain, looked up among the apps installed and the
    /// domains visited. Nil when it is not there.
    ///
    /// Out of the same shared walk everything else uses (`encodedKinds`) rather than a walk of
    /// its own: finding one app costs the whole list either way, so a lookup per key was a
    /// whole enumeration per key. The answer crosses as bytes and is decoded here, on the
    /// caller's side: `FamilyActivityData` and the tokens it hands back are not Sendable.
    @available(iOS 26.4, *)
    static func kind(forKey key: String) async throws -> TargetKind? {
        guard let encoded = try await encodedKinds()[key] else { return nil }
        return try JSONDecoder().decode(TargetKind.self, from: encoded)
    }
}
