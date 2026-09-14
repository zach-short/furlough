import DeviceActivity
import FamilyControls
import SwiftUI

// Two paths chosen at runtime by `UsageReader.hasDataAccess`. With data access (iOS 26.4+) the
// app reads the fortnight itself and draws every card natively, with no `DeviceActivityReport`
// hosted at all. Without it, only the report extension ever sees a number, so cards are remote
// views stepped through one at a time, and Apply hands off to the picker + editor instead —
// nothing (not the app, not the rule, not even a tap) can come back out of that sandbox.
struct UsageView: View {
    enum Role { case onboarding, settings }
    var role: Role = .settings

    @Environment(AppModel.self) private var model
    @State private var summary: UsageSummary?
    // Ranked once, on read — `UsageSummary.recommendations` walks every entry/hour, too costly
    // to redo on each `body` pass.
    @State private var advice: [Recommendation] = []
    @State private var failure: String?
    // Keyed by `Recommendation.key` (stable across reload) so an applied card keeps its mark
    // even if the fortnight is refetched underneath it.
    @State private var states: [String: UsageCardState] = [:]
    // Applied cards reopened by hand; applying folds a card, so this overrides that.
    @State private var expanded: Set<String> = []
    // Cards answered before Screen Time confirmed their token. See `Optimistic`, `confirm`, `land`.
    @State private var optimistic: [String: Optimistic] = [:]
    @State private var trouble: [Trouble] = []
    // Settling the last of `optimistic` before the Done button lets the step close.
    @State private var finishing = false
    @State private var phase = Phase.reading
    // True while Screen Time is being asked for tokens (`nameApps`); a card the tables didn't
    // know is held back until this resolves, rather than re-asking the same slow query — see `land`.
    @State private var naming = false
    // True from when tokens are filled from `TokenCache` until the first answered `nameApps`
    // pass — marks tokens worth double-checking after an Apply. See `apply`, `confirm`.
    @State private var fromCache = false
    // Retries for Screen Time's token query: 3, a second apart — enough to ride out a query
    // that just didn't answer, short enough not to stall. See `nameApps`.
    private static let namingAttempts = 3
    // Long enough to outlast `nameApps` (every attempt, plus the ask `land` makes after them):
    // a card says Applied from the press, so the Done button is where the wait for Screen Time
    // is spent. Only a ceiling — `land` settles every card well inside it.
    private static let finishPatience: Duration = .seconds(60)

    // `done` set: written on a cache-supplied token Screen Time hasn't confirmed — `confirm`
    // checks it. `done` nil: no token yet, `land` is waiting for one. The name is kept either
    // way since a disowned app's card is gone from `advice` by the time the toast needs it.
    private struct Optimistic {
        var name: String
        var done: UsageCardState.Applied?
    }

    // Wraps a String as Error since `Result` needs one and the reason is just a sentence.
    private struct Refusal: Error {
        var reason: String
        init(_ reason: String) { self.reason = reason }
    }

    private struct Trouble: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    private enum Phase: Equatable {
        case reading
        case ready
        case failed(String)
        // Hours came back but nothing could be named, by tables or Screen Time.
        case nameless
    }
    // Held for the page rather than the card: answering once answers for the whole run, since
    // most people want the same destination for every app.
    @State private var destination = UsageDestination.both
    @State private var position = 1
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var editing: EditingTarget?

    private struct EditingTarget: Identifiable, Hashable { let id: UUID }

    private var hasDataAccess: Bool { UsageReader.hasDataAccess(model.authorization) }

    // The Anchor drops out of the offer when it has nothing to take in: while anchored its list
    // can't change, and under everything-except scope the list is what stays open, so "hold
    // this too" would mean letting it through.
    private var offer: UsageOffer {
        let anchor = model.state.config.anchor
        guard !anchor.isAnchored, !anchor.anchorsEverything else { return .rules }
        if model.wantsBothHalves { return .both }
        return model.startHalf == .anchor ? .anchor : .rules
    }

    private var couldHaveDataAccess: Bool {
        guard #available(iOS 26.4, *) else { return false }
        return model.isAuthorized && !hasDataAccess
    }

    var body: some View {
        switch role {
        case .onboarding: NavigationStack { page }
        case .settings: page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                if hasDataAccess {
                    suggestions
                } else {
                    if couldHaveDataAccess { dataAccessCard }
                    tour
                }
                closing
            }
            .padding(.horizontal, 16)
            .padding(.top, role == .onboarding ? 8 : 0)
            // Extra bottom padding when the toast is up, so it doesn't cover the Done button.
            .padding(.bottom, trouble.isEmpty ? 40 : 190)
            .animation(.easeInOut(duration: 0.2), value: trouble.isEmpty)
        }
        .background(EmberWall())
        // Overlay rather than inline: the card it's about may already be folded and scrolled
        // past, so a message placed inline could go unseen.
        .overlay(alignment: .bottom) {
            if !trouble.isEmpty {
                UsageTroubleToast(
                    names: trouble.map(\.name),
                    retry: retryTrouble,
                    dismiss: { withAnimation(.easeInOut(duration: 0.2)) { trouble = [] } }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(role == .onboarding ? "" : "Usage")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { RuleEditorView(targetID: $0.id) }
        .task(id: model.authorization) { await load() }
        .familyActivityPicker(
            headerText: "Choose the app this card is about",
            footerText: offer == .anchor
                ? "Pick the one the card names. It goes on the Anchor's list."
                : "Pick the one the card names. The next screen is where its rule is written.",
            isPresented: $showPicker,
            selection: $selection
        )
        .onChange(of: showPicker) { _, presented in
            guard !presented else { return }
            addPicked()
        }
    }

    // MARK: The page's own words

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Last \(UsageReader.days) days", color: Ember.amber)
            Text(role == .onboarding ? "Where your time went" : "Where the time goes")
                .emberDisplay(30)
                .foregroundStyle(Ember.cream)
            Text(hasDataAccess ? lead : sandboxLead)
                .emberBody(14)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lead: String {
        switch offer {
        case .rules:
            "One card an app, heaviest first. Each suggestion closes the hours the time actually falls in and keeps half of what you spend."
        case .anchor:
            "One card an app, heaviest first. Take in the ones you want out of reach, and the Anchor holds them the moment you drop it."
        case .both:
            "One card an app, heaviest first. Each suggestion closes the hours the time actually falls in and keeps half of what you spend — and you say whether it lands on Rules, the Anchor, or both."
        }
    }

    private var sandboxLead: String {
        offer == .anchor
            ? "Screen Time draws these cards inside a sandbox of its own. Furlough cannot read a number off one or press a button for you, so read the card, then choose the app to put on the Anchor's list."
            : "Screen Time draws these cards inside a sandbox of its own. Furlough cannot read a number off one or press a button for you, so read the card, then add the app and write the rule it shows."
    }

    // MARK: Path A — the app has the numbers

    @ViewBuilder
    private var suggestions: some View {
        switch phase {
        case .reading:
            waiting("Reading the last \(UsageReader.days) days…")
        case .failed(let reason):
            problem(
                eyebrow: "Screen Time said no",
                body: reason,
                hint: "Nothing was read, so nothing has changed."
            )
        case .nameless:
            problem(
                eyebrow: "Could not read your Screen Time",
                body: "Furlough got the hours but Screen Time would not say what the apps are called, and a card that cannot name the app is not one anybody can judge.",
                hint: offer == .anchor
                    ? "Choose the apps you want held by hand instead."
                    : "Choose the apps you want to manage by hand instead."
            )
        case .ready:
            if advice.isEmpty {
                Text("Nothing on this phone passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day. There is nothing here worth \(offer == .anchor ? "holding" : "a rule").")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .padding(16)
                    .emberCard()
            } else if let summary {
                ForEach(shown) { item in
                    if let entry = summary.entry(for: item) {
                        card(item, entry, days: summary.totalDays)
                    }
                }
                if naming, shown.count < advice.count {
                    heldBack(advice.count - shown.count)
                }
            }
        }
    }

    // While naming is in progress, only the tables' own apps are shown, so nothing gets drawn
    // as "This app" over a dashed square and then renamed under the reader's eyes.
    private var shown: [Recommendation] {
        guard let summary else { return [] }
        return advice.filter { summary.entry(for: $0)?.isNamed == true }
    }

    private func heldBack(_ count: Int) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Ember.amber).controlSize(.small)
            Text(count == 1
                ? "Asking Screen Time about one more app…"
                : "Asking Screen Time about \(count) more apps…")
                .emberBody(12)
                .foregroundStyle(Ember.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func waiting(_ line: String) -> some View {
        VStack(spacing: 16) {
            LivingHourglass(state: .open(level: 0.55, warned: false))
                .compositingGroup()
                .frame(width: 52, height: 70)
                .shadow(color: Ember.amber.opacity(0.4), radius: 18)
            Text(line)
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .emberCard()
    }

    private func problem(eyebrow: String, body: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: eyebrow, color: Ember.ember)
            Text(body)
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(hint)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
            ProminentButton(title: "Choose apps by hand", action: openPicker)
            GhostButton(title: "Try again", color: Ember.amber) { Task { await restart() } }
        }
        .padding(16)
        .emberCard()
    }

    @ViewBuilder
    private func card(_ item: Recommendation, _ entry: UsageEntry, days: Int) -> some View {
        let state = states[item.key] ?? .offered
        switch state {
        case .skipped:
            UsageSkippedLine(item: item, entry: entry, offer: offer) {
                withAnimation(.easeInOut(duration: 0.2)) { states[item.key] = .offered }
            }
        case .applied(let done) where !expanded.contains(item.key):
            UsageAppliedLine(
                item: item,
                entry: entry,
                done: done,
                undo: { undo(item) },
                expand: { withAnimation(.easeInOut(duration: 0.2)) { _ = expanded.insert(item.key) } }
            )
        default:
            UsageSuggestionCard(
                item: item,
                entry: entry,
                days: days,
                state: state,
                offer: offer,
                destination: $destination,
                apply: { apply(item, entry) },
                skip: { withAnimation(.easeInOut(duration: 0.2)) { states[item.key] = .skipped } },
                undo: { undo(item) },
                collapse: { withAnimation(.easeInOut(duration: 0.2)) { _ = expanded.remove(item.key) } }
            )
        }
    }

    // Where iOS won't show the new prompt directly, toggling Furlough off/on under Screen Time
    // makes the next `requestAuthorization` call fresh.
    private var dataAccessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Apply with one tap")
            Text("With data access, Furlough reads these numbers itself: the cards come back inside the app and every suggestion gets an Apply button. Nothing leaves the phone.")
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            GhostButton(title: "Allow data access") { Task { await model.requestAuthorization() } }
            Text("If no prompt appears, turn Furlough off and back on under Settings › Screen Time › Apps with Screen Time Access, then come back here.")
                .emberBody(11)
                .foregroundStyle(Ember.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .emberCard()
    }

    // MARK: Path B — Screen Time has the numbers, and keeps them

    // Fixed frame, one card at a time: a DeviceActivityReport can't report its own height, and
    // rendering several at once made the old page stutter.
    private var tour: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeviceActivityReport(.rank(position), filter: UsageReader.filter())
                .frame(height: UsageReportFrame.height)
                .id(position)
            HStack {
                step("Previous", systemImage: "chevron.left", enabled: position > 1) { position -= 1 }
                Spacer()
                Eyebrow(text: "\(position) of \(UsageAnalysis.rankLimit)")
                Spacer()
                step("Next", systemImage: "chevron.right", trailing: true, enabled: position < UsageAnalysis.rankLimit) {
                    position += 1
                }
            }
            ProminentButton(title: offer == .anchor ? "Hold this app" : "Manage this app", action: openPicker)
            Footnote(text: offer == .anchor
                ? "Apple's picker opens on its own list of apps. Pick the one the card names, and it goes on the Anchor's list — out of reach the moment you drop it."
                : "Apple's picker opens on its own list of apps. Pick the one the card names, and the rule editor opens next so you can write what the card showed.")
        }
    }

    // Seeded with the existing selection: both destinations replace the whole list rather than add to it.
    private func openPicker() {
        selection = offer == .anchor ? model.anchorSelection : model.pickerSelection
        showPicker = true
    }

    private func step(
        _ title: String,
        systemImage: String,
        trailing: Bool = false,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if !trailing { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
                Text(title).emberBody(13, .semibold)
                if trailing { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(enabled ? Ember.amber : Ember.faint)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func addPicked() {
        // No editor afterwards for the anchor case: a held app has no hours to write.
        guard offer != .anchor else {
            model.setAnchorSelection(selection)
            return
        }
        let before = Set(model.state.config.targets.map(\.id))
        let result = model.applyPicker(selection)
        guard result.added > 0 else { return }
        model.reload()
        editing = model.state.config.targets.first { !before.contains($0.id) }.map { EditingTarget(id: $0.id) }
    }

    // MARK: Closing

    @ViewBuilder
    private var closing: some View {
        if !applied.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "So far", color: Ember.moss)
                Text(closingLine)
                    .emberBody(14)
                    .foregroundStyle(Ember.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .emberCard()
        }
        if role == .onboarding {
            // Settles anything still owed from optimistic applies before the step can close;
            // the button itself is the wait while it does.
            UsageFinishButton(title: finishTitle, finishing: finishing) { Task { await finish() } }
                .padding(.top, 4)
            Footnote(
                text: "You can run this again any time from Settings › Where the time goes.",
                alignment: .center
            )
        }
    }

    private var finishTitle: String { applied.isEmpty ? "Skip for now" : "Done" }

    // Counts cards still owed to Screen Time too: they say Applied, so the closing line and the
    // Done button have to agree with them. `finish` is what waits for the writes themselves.
    private var applied: [Recommendation] {
        advice.filter {
            if case .applied = states[$0.key] { return true }
            return false
        }
    }

    private func done(_ item: Recommendation) -> UsageCardState.Applied? {
        guard case .applied(let done) = states[item.key] else { return nil }
        return done
    }

    // Time saved is rounded down to five minutes as an estimate. Rules and Anchor counts are
    // kept separate since a card can land on both.
    private var closingLine: String {
        var lines: [String] = []
        let ruled = applied.filter { done($0)?.rules == true }
        if !ruled.isEmpty {
            let apps = ruled.count == 1 ? "1 app" : "\(ruled.count) apps"
            let saved = ruled.reduce(0) { total, item in
                total + max(0, Int(item.averageDailyMinutes.rounded()) - item.rule.dailyBudgetMinutes)
            } / 5 * 5
            lines.append(saved >= 5
                ? "\(apps) managed, about \(TimeFormat.budget(saved)) a day taken back."
                : "\(apps) managed.")
        }
        let held = applied.filter { done($0)?.holds == true }
        if !held.isEmpty {
            lines.append(held.count == 1
                ? "1 app on the Anchor's list, out of reach when you drop it."
                : "\(held.count) apps on the Anchor's list, out of reach when you drop it.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: Doing it

    private func load() async {
        guard #available(iOS 26.4, *), hasDataAccess, summary == nil else { return }
        phase = .reading
        // Asked now, alongside the read, rather than after it: the token walk is what an Apply
        // without a token waits on, so the earlier it starts the likelier the first press finds
        // its token in hand. `nameApps` joins this same walk if it is still going.
        UsageReader.warmTokens()
        do {
            // Folded now for pairs a key alone can join (a typed site beside its app's row);
            // folded again in `nameApps` once tokens confirm which entry is which app.
            let read = try await UsageReader.summary().folded(in: model.state.config)
            advice = read.recommendations
            summary = read
            SharedStore.log("usage: \(read.entries.count) entries, \(advice.count) worth a rule, \(unnamed) not in the tables")
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        fillFromCache()
        phase = .ready
        await nameApps()
    }

    // Reads last visit's tokens from the App Group defaults (`TokenCache`) so the first frame
    // shows Apple's icons instead of letters; nothing is asked of Screen Time here. Re-folds and
    // re-ranks since folding an app onto its site needs the token to know which entry is which.
    private func fillFromCache() {
        guard let read = summary, let cache = SharedStore.tokenCache(), !cache.entries.isEmpty else { return }
        guard let filled = try? UsageReader.fillingTokens(in: read, from: cache.entries) else { return }
        let folded = filled.folded(in: model.state.config)
        summary = folded
        advice = folded.recommendations
        fromCache = true
        let have = advice.filter { folded.entry(for: $0)?.targetKind != nil }.count
        SharedStore.log("usage: \(have) of \(advice.count) tokens from the cache, written \(cache.age()) ago")
    }

    private func restart() async {
        summary = nil
        advice = []
        fromCache = false
        // Clears pending work from the old page — its cards are gone, so nothing is left to finish.
        optimistic = [:]
        trouble = []
        await load()
    }

    // `UsageReader.fillingTokens` (Screen Time's own store) is the only way to a token, and it's
    // unreliable — it can answer, come back empty, throw, or hang — so it's retried a few times.
    // A fresh answer resolves every entry, so a cache token for an app since deleted is dropped
    // along with its card, which would otherwise have no name and no token to write a rule on.
    private func nameApps() async {
        guard #available(iOS 26.4, *) else { return }
        naming = true
        defer { naming = false }
        for attempt in 1...Self.namingAttempts {
            guard let read = summary else { return }
            do {
                let pass = try await UsageReader.fillingTokens(in: read, within: UsageReader.patience)
                summary = pass.summary
                SharedStore.log("usage: naming attempt \(attempt) \(pass.answered ? "answered" : "came back empty"), \(tokenless) of \(advice.count) still without a token")
                if pass.answered {
                    // All tokens (cache-supplied included) are now confirmed against what's installed.
                    fromCache = false
                    break
                }
            } catch is UsageReader.Unanswered {
                SharedStore.log("usage: naming attempt \(attempt) unanswered after \(UsageReader.patience.components.seconds) s")
            } catch {
                SharedStore.log("usage: naming attempt \(attempt) failed: \(error.localizedDescription)")
            }
            guard !Task.isCancelled, attempt < Self.namingAttempts else { break }
            try? await Task.sleep(for: .seconds(1))
        }
        guard !Task.isCancelled else { return }
        // Re-fold/re-rank now that tokens have arrived: folding an app onto its site needs the
        // token, and a folded pair's combined minutes may rank higher than either half alone.
        if let read = summary {
            let folded = read.folded(in: model.state.config)
            if folded.entries.count != read.entries.count {
                SharedStore.log("usage: folded \(read.entries.count - folded.entries.count) linked half/halves into their rows")
            }
            summary = folded
            advice = folded.recommendations
        }
        let named = shown
        // Distinguishes an honestly empty fortnight from one where nothing could be named.
        phase = (!advice.isEmpty && named.isEmpty) ? .nameless : .ready
        advice = named
        confirm()
    }

    private var unnamed: Int { advice.count - shown.count }

    private var tokenless: Int {
        guard let summary else { return 0 }
        return advice.filter { summary.entry(for: $0)?.targetKind == nil }.count
    }

    // Applies instantly on whatever token is in hand (no wait on Screen Time), then verifies
    // afterwards: `confirm` reads Screen Time's actual answer back once `nameApps` has it, and
    // undoes anything built on a token for an app since deleted. If there's no token at all yet
    // (first visit, before the first answer), the card still says Applied — the press has to
    // answer at once — and `land` writes it the moment Screen Time names the app. Only a name
    // that never comes takes the card back, with the toast saying so.
    private func apply(_ item: Recommendation, _ entry: UsageEntry) {
        guard #available(iOS 26.4, *) else { return }
        // Re-answering clears any toast entry — it was about the previous answer.
        withAnimation(.easeInOut(duration: 0.2)) { trouble.removeAll { $0.key == item.key } }

        guard let kind = entry.targetKind else {
            var done = UsageCardState.Applied(message: "")
            done.owed = landing()
            settle(item, done)
            optimistic[item.key] = Optimistic(name: entry.plainName, done: nil)
            Task { await land(item, entry) }
            return
        }
        switch write(item, entry, on: kind) {
        case .success(let done):
            settle(item, done)
            // Flagged for `confirm` to double-check, since this token came from the cache.
            if fromCache { optimistic[item.key] = Optimistic(name: entry.plainName, done: done) }
        case .failure(let refusal):
            states[item.key] = .failed(refusal.reason)
        }
    }

    // No query or await anywhere in here — every line is a synchronous write + enforce — which
    // is what makes an instant Apply honest rather than optimistic.
    private func write(
        _ item: Recommendation,
        _ entry: UsageEntry,
        on kind: TargetKind
    ) -> Result<UsageCardState.Applied, Refusal> {
        let landing = landing()
        var done = UsageCardState.Applied(message: "")

        if landing.writesRule {
            var fresh = false
            // target(kind:) rather than matching `kind` alone: this app may already be the linked
            // half of a row (YouTube beside youtube.com), and adding it again would split that pair.
            if model.state.config.target(kind: kind) == nil {
                var picked = model.pickerSelection
                switch kind {
                case .application(let token): picked.applicationTokens.insert(token)
                case .webDomain(let token): picked.webDomainTokens.insert(token)
                // Screen Time counts neither a whole category nor a hand-typed site.
                case .category, .host: break
                }
                _ = model.applyPicker(picked)
                model.reload()
                fresh = true
            }
            guard let target = model.state.config.targets.first(where: { $0.kind == kind }) else {
                return .failure(Refusal("Could not add \(entry.plainName)."))
            }
            let outcome = model.apply(rule: item.rule, nickname: target.nickname, for: target.id, andTo: [])
            done.targetID = target.id
            done.fresh = fresh
            done.waiting = outcome.scheduled > 0
            done.message = outcome.message
        }

        if landing.holds {
            // Holds every door of a linked row (app + site) together, so one pick closes both.
            let doors = model.state.config.target(kind: kind)?.kinds ?? [kind]
            guard model.hold(doors) else {
                return .failure(Refusal("The Anchor cannot take anything in while it is down."))
            }
            done.heldKinds = doors
            let held = "On the Anchor's list: out of reach the moment you drop it."
            done.message = done.message.isEmpty ? held : "\(done.message)\n\n\(held)"
        }
        return .success(done)
    }

    private func settle(_ item: Recommendation, _ done: UsageCardState.Applied) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expanded.remove(item.key)
            states[item.key] = .applied(done)
        }
    }

    // Waits on `nameApps` rather than querying itself, since `nameApps` is already asking Screen
    // Time the same question for every card at once — a second enumeration would just queue
    // behind it. Falls back to its own ask only if naming came back with nothing.
    private func land(_ item: Recommendation, _ entry: UsageEntry) async {
        guard #available(iOS 26.4, *) else { return }
        while naming, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard !Task.isCancelled else { return }
        // The card may have been re-answered, skipped, or taken back while this was waiting.
        guard isPending(item) else {
            optimistic[item.key] = nil
            return
        }
        var found = summary?.entry(for: item)?.targetKind
        if found == nil {
            found = try? await UsageReader.kind(forKey: entry.key, within: UsageReader.patience)
        }
        optimistic[item.key] = nil
        guard isPending(item) else { return }
        guard let kind = found else {
            SharedStore.log("usage: \(entry.key) was applied optimistically and Screen Time never named it")
            giveUp(item, name: entry.plainName, done: nil)
            return
        }
        switch write(item, summary?.entry(for: item) ?? entry, on: kind) {
        case .success(let done): settle(item, done)
        case .failure(let refusal): states[item.key] = .failed(refusal.reason)
        }
    }

    // `fillingTokens` clears each entry's token before re-resolving it, so a card that lost its
    // token belongs to an app no longer installed — take that work back off.
    private func confirm() {
        guard let read = summary else { return }
        let alive = Set(read.entries.compactMap { $0.targetKind != nil ? $0.key : nil })
        for (key, pending) in optimistic {
            guard let done = pending.done else { continue }
            optimistic[key] = nil
            guard !alive.contains(key) else { continue }
            // Skip if the card has moved on since (undone, skipped, re-answered).
            guard isApplied(key) else { continue }
            guard let item = advice.first(where: { $0.key == key }) else {
                takeBack(done)
                trouble.append(Trouble(key: key, name: pending.name))
                continue
            }
            SharedStore.log("usage: took \(key) back — the cache's token named an app Screen Time no longer has")
            giveUp(item, name: pending.name, done: done)
        }
    }

    private func isPending(_ item: Recommendation) -> Bool {
        guard case .applied(let done) = states[item.key] else { return false }
        return done.pending
    }

    private func isApplied(_ key: String) -> Bool {
        guard case .applied(let done) = states[key] else { return false }
        return !done.pending
    }

    // Reads what was written, not what `holds` promises: a card still owed has written nothing.
    private func takeBack(_ done: UsageCardState.Applied) {
        if !done.heldKinds.isEmpty { model.stopHolding(done.heldKinds) }
        if let targetID = done.targetID, done.fresh { _ = model.undoFreshTarget(targetID) }
    }

    private func giveUp(_ item: Recommendation, name: String, done: UsageCardState.Applied?) {
        if let done { takeBack(done) }
        withAnimation(.easeInOut(duration: 0.2)) {
            states[item.key] = .offered
            trouble.removeAll { $0.key == item.key }
            trouble.append(Trouble(key: item.key, name: name))
        }
    }

    private func retryTrouble() {
        let again = trouble
        withAnimation(.easeInOut(duration: 0.2)) { trouble = [] }
        for one in again {
            guard let item = advice.first(where: { $0.key == one.key }),
                  let entry = summary?.entry(for: item)
            else { continue }
            apply(item, entry)
        }
    }

    // Waits out every card still owed to Screen Time (`finishPatience` is only the ceiling): a
    // card says Applied from the press, so this is the one place the write itself is waited
    // for, and a write that fails here keeps the step open with the toast naming the app.
    private func finish() async {
        // A second press while the first is still waiting would run this twice over.
        guard !finishing else { return }
        let known = Set(trouble.map(\.key))
        if !optimistic.isEmpty {
            finishing = true
            let deadline = ContinuousClock.now.advanced(by: Self.finishPatience)
            while !optimistic.isEmpty, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(150))
            }
            finishing = false
        }
        // Only new trouble (not already shown before Done was pressed) keeps the step open.
        guard trouble.allSatisfy({ known.contains($0.key) }) else { return }
        model.finishUsageStep()
    }

    private func landing() -> UsageDestination {
        switch offer {
        case .rules: .rules
        case .anchor: .anchor
        case .both: destination
        }
    }

    // Only undoes what this run itself did — a rule on a pre-existing row is a loosening like
    // any other and belongs in the rule editor; `Applied.canUndo` keeps the button off those cards.
    // A card still owed has written nothing: dropping it from `optimistic` is the whole undo,
    // and `land` finds the card no longer pending and lets it go.
    private func undo(_ item: Recommendation) {
        guard case .applied(let done) = states[item.key], done.canUndo else { return }
        if done.pending { optimistic[item.key] = nil }
        if !done.heldKinds.isEmpty { model.stopHolding(done.heldKinds) }
        if let targetID = done.targetID, !model.undoFreshTarget(targetID) {
            states[item.key] = .failed("Furlough has held this rule too long to take it straight back. Loosen it from the rule editor instead.")
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            expanded.remove(item.key)
            states[item.key] = .offered
        }
    }
}
