import DeviceActivity
import FamilyControls
import SwiftUI

/// An app-by-app judgement on the last fortnight. One card an app, heaviest first, each one
/// answering three questions in order — what it is and how much of the day it takes, where that
/// time falls, and what Furlough would do about it — and then offering Apply or Skip. Two doors
/// lead here: the step after Screen Time access, and "Where the time goes" in Settings, which
/// runs the whole thing again whenever it is wanted.
///
/// Two paths, chosen at runtime by `UsageReader.hasDataAccess`. With data access (iOS 26.4) the
/// app reads the fortnight itself and draws every card natively, hosting no `DeviceActivityReport`
/// at all — which is what makes the page scroll. Without it, only the report extension ever sees
/// a number, so the cards are remote views: one at a time, stepped through by hand, and "Apply"
/// becomes a hand-off to the picker and the editor, because nothing can come back out of that
/// sandbox — not which app qualified, not the rule, not even that a button was pressed.
struct UsageView: View {
    /// How the screen was reached. The step brings its own navigation and its own way out; from
    /// Settings it is already inside a stack, and the back button is the way out.
    enum Role { case onboarding, settings }
    var role: Role = .settings

    @Environment(AppModel.self) private var model
    @State private var summary: UsageSummary?
    /// Ranked once, when the fortnight is read: `UsageSummary.recommendations` walks every
    /// entry and searches every hour of it, which is not work to redo on each pass through
    /// `body`. This page has to scroll.
    @State private var advice: [Recommendation] = []
    @State private var failure: String?
    /// Keyed by `Recommendation.key`, which is stable across a reload, so an applied card keeps
    /// its mark even if the fortnight is fetched again underneath it.
    @State private var states: [String: UsageCardState] = [:]
    /// Applied cards asked to open back up, by `Recommendation.key`. Applying folds a card, so
    /// this is the set that overrides that — empty is the ordinary case.
    @State private var expanded: Set<String> = []
    @State private var busy: String?
    /// Where Path A has got to; see `Phase`.
    @State private var phase = Phase.reading
    /// Screen Time is still being asked for the tokens (`nameApps`). While this is true a card
    /// whose app the tables did not know is held back, because there is nothing to call it yet,
    /// and Apply waits for the answer rather than asking the same slow question a second time —
    /// over a token out of the cache too, while `fromCache` says so.
    @State private var naming = false
    /// The tokens on the page came out of `TokenCache` and Screen Time has not confirmed them
    /// yet. True from the moment the cache is folded in until the first answered pass of
    /// `nameApps`; it is what holds Apply back over a token that may name an app deleted since
    /// the last visit — see `apply`.
    @State private var fromCache = false
    /// How many times to ask Screen Time for the tokens before giving up on them, each ask given
    /// `UsageReader.patience`. Three, a second apart: long enough to ride out a query that simply
    /// did not answer, short enough that the icons stop changing under the reader within the
    /// minute. Nothing on the page waits on this; see `nameApps`.
    private static let namingAttempts = 3

    /// What the page is doing where the app reads the numbers itself. Nothing is shown until the
    /// hours are in; the cards are drawn the moment they are, named from the tables (`Brand`),
    /// and Apple's own names and icons arrive behind them as Screen Time hands the tokens over.
    private enum Phase: Equatable {
        /// Reading the fortnight out of Screen Time.
        case reading
        /// Cards.
        case ready
        /// Screen Time would not hand the hours over at all.
        case failed(String)
        /// The hours came and the names never did, so there is nothing worth drawing.
        case nameless
    }
    /// Path B: which card the tour is showing, 1…`UsageAnalysis.rankLimit`.
    @State private var position = 1
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var editing: EditingTarget?

    /// The target the picker just added, on its way to the rule editor.
    private struct EditingTarget: Identifiable, Hashable { let id: UUID }

    private var hasDataAccess: Bool { UsageReader.hasDataAccess(model.authorization) }

    /// Allowed the old way, on a phone that knows the new one.
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
            .padding(.bottom, 40)
        }
        .background(EmberWall())
        .navigationTitle(role == .onboarding ? "" : "Usage")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { RuleEditorView(targetID: $0.id) }
        .task(id: model.authorization) { await load() }
        .familyActivityPicker(
            headerText: "Choose the app this card is about",
            footerText: "Pick the one the card names. The next screen is where its rule is written.",
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
            Text(hasDataAccess
                ? "One card an app, heaviest first. Each suggestion closes the hours the time actually falls in and keeps half of what you spend."
                : "Screen Time draws these cards inside a sandbox of its own. Furlough cannot read a number off one or press a button for you, so read the card, then add the app and write the rule it shows.")
                .emberBody(14)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                hint: "Choose the apps you want to manage by hand instead."
            )
        case .ready:
            if advice.isEmpty {
                Text("Nothing on this phone passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day. There is nothing here worth a rule.")
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

    /// The suggestions with something to be called. Everything, once naming is over, because
    /// `nameApps` drops the rest then; while Screen Time is still being asked, the ones the tables
    /// knew, so that an app they did not is not drawn as "This app" over a dashed square and then
    /// renamed under the reader's eyes.
    private var shown: [Recommendation] {
        guard let summary else { return [] }
        return advice.filter { summary.entry(for: $0)?.isNamed == true }
    }

    /// The line under the cards for the ones held back: why the list is short, and that it may
    /// yet grow — without an hourglass over the whole page.
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

    /// The hourglass, running, while Screen Time is being asked something.
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

    /// Screen Time would not do its half. Says so plainly, then offers the way round it: the
    /// picker, which needs nothing from Screen Time's history at all.
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
            ProminentButton(title: "Choose apps by hand") {
                selection = model.pickerSelection
                showPicker = true
            }
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
            UsageSkippedLine(item: item, entry: entry) {
                withAnimation(.easeInOut(duration: 0.2)) { states[item.key] = .offered }
            }
        case .applied(let targetID, let fresh, let message, let waiting) where !expanded.contains(item.key):
            UsageAppliedLine(
                item: item,
                entry: entry,
                targetID: targetID,
                fresh: fresh,
                message: message,
                waiting: waiting,
                undo: { undo(item) },
                expand: { withAnimation(.easeInOut(duration: 0.2)) { _ = expanded.insert(item.key) } }
            )
        default:
            UsageSuggestionCard(
                item: item,
                entry: entry,
                days: days,
                state: state,
                isBusy: busy == item.key,
                apply: { Task { await apply(item, entry) } },
                skip: { withAnimation(.easeInOut(duration: 0.2)) { states[item.key] = .skipped } },
                undo: { undo(item) },
                collapse: { withAnimation(.easeInOut(duration: 0.2)) { _ = expanded.remove(item.key) } }
            )
        }
    }

    /// The ask, for a phone allowed the old way. `requestAuthorization` shows the new prompt
    /// where iOS lets it; where it does not, turning Furlough off and on under Screen Time
    /// makes the next request a fresh one.
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

    /// One card at a time in a frame the app fixed, because a report cannot say how tall it
    /// wants to be and five of them at once is what made the old page stutter.
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
            ProminentButton(title: "Manage this app") {
                selection = model.pickerSelection
                showPicker = true
            }
            Footnote(text: "Apple's picker opens on its own list of apps. Pick the one the card names, and the rule editor opens next so you can write what the card showed.")
        }
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

    /// What the picker left behind. `applyPicker` schedules a removal for anything it does not
    /// see, so the selection was seeded with everything already managed; whatever is new is the
    /// app this card was about, and the editor opens on it.
    private func addPicked() {
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
            ProminentButton(title: applied.isEmpty ? "Skip for now" : "Done") { model.finishUsageStep() }
                .padding(.top, 4)
            Footnote(
                text: "You can run this again any time from Settings › Where the time goes.",
                alignment: .center
            )
        }
    }

    /// The suggestions taken this run, in the order they were offered.
    private var applied: [Recommendation] {
        advice.filter {
            if case .applied = states[$0.key] { return true }
            return false
        }
    }

    /// "3 apps managed, about 2 h 10 min a day taken back." The time is what each average is
    /// over its new budget, rounded down to five minutes — an estimate, and said as one.
    private var closingLine: String {
        let apps = applied.count == 1 ? "1 app" : "\(applied.count) apps"
        let saved = applied.reduce(0) { total, item in
            total + max(0, Int(item.averageDailyMinutes.rounded()) - item.rule.dailyBudgetMinutes)
        } / 5 * 5
        guard saved >= 5 else { return "\(apps) managed." }
        return "\(apps) managed, about \(TimeFormat.budget(saved)) a day taken back."
    }

    // MARK: Doing it

    private func load() async {
        guard #available(iOS 26.4, *), hasDataAccess, summary == nil else { return }
        phase = .reading
        do {
            // Folded now for the halves a key alone can pair — a typed site beside its app's
            // row — and again in `nameApps`, once the tokens say which entry is which app.
            let read = try await UsageReader.summary().folded(in: model.state.config)
            advice = read.recommendations
            summary = read
            SharedStore.log("usage: \(read.entries.count) entries, \(advice.count) worth a rule, \(unnamed) not in the tables")
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        // Apple's icons out of the cache, before anything is drawn — on every visit but the
        // first, this is where they come from, and Screen Time only corrects them afterwards.
        fillFromCache()
        // Cards, now. Anything the cache did not know is named from the tables with a letter for
        // an icon until Screen Time hands the token over, which is the slow, unreliable half and
        // no longer the gate.
        phase = .ready
        await nameApps()
    }

    /// Puts last visit's tokens on the summary, so the first frame has Apple's own icons rather
    /// than letters. Nothing is asked of Screen Time here and nothing can fail: the map is a read
    /// of the App Group defaults, and a phone that has never answered simply has none.
    ///
    /// Folded a second time, because folding an app's half onto its site's needs to know which
    /// entry is which target, and for an app that is the token — which is what has just arrived.
    /// Then ranked again, because a folded pair carries both halves' minutes.
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

    /// Throws the fortnight away and reads it again, for the button on a failure.
    private func restart() async {
        summary = nil
        advice = []
        fromCache = false
        await load()
    }

    /// Puts Apple's names and icons on the suggestions — behind them, not before them.
    ///
    /// Data access names an app by its bundle identifier alone, so Apple's own name and icon
    /// come from a token, and the only way to a token is a query into Screen Time's own store
    /// (`UsageReader.fillingTokens`). That query is not reliable: it answers, it comes back with
    /// nothing, it throws, or it never comes back at all, and the app cannot tell which in
    /// advance. So each ask is given `UsageReader.patience`, and it is asked again, a second
    /// apart, until Screen Time answers — an answer holding nothing is a failed query worth
    /// repeating, while an answer that named only some is Screen Time working, and asking twice
    /// more would only take longer to say the same thing.
    ///
    /// The cards are on the page throughout — with last visit's icons already on them where
    /// there was a cache (`fillFromCache`), and drawn from the tables (`Brand`) where there was
    /// not — and every token that lands confirms one or swaps Apple's artwork in for a letter.
    /// A token the cache supplied for an app since deleted is taken away here, because a fresh
    /// answer resolves every entry rather than only the tokenless ones, and the card goes with
    /// it. Whatever the tables did not know and Screen Time never named is dropped at the end
    /// rather than drawn: it has no name to show and no token to write a rule on, so its card
    /// would be furniture. An app used in the last fortnight and since deleted is exactly that,
    /// and it must not be able to wedge the page.
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
                    // Every token on the page has now been checked against what is installed,
                    // including the ones the cache supplied, so Apply need not wait on anything.
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
        // Only now can an app's half of a linked pair be added to its site's, and only now is it
        // worth ranking again. Folding needs to know which entry is which target, and for an app
        // that is the token — which is exactly what the loop above has just been waiting for.
        // Ranked again because a folded pair carries both halves' minutes and so may place
        // higher than either half did alone.
        if let read = summary {
            let folded = read.folded(in: model.state.config)
            if folded.entries.count != read.entries.count {
                SharedStore.log("usage: folded \(read.entries.count - folded.entries.count) linked half/halves into their rows")
            }
            summary = folded
            advice = folded.recommendations
        }
        let named = shown
        // Suggestions existed and not one of them could be named, by the tables or by Screen
        // Time: there is nothing to show. An honestly empty fortnight is not this.
        phase = (!advice.isEmpty && named.isEmpty) ? .nameless : .ready
        advice = named
    }

    /// Suggestions the tables had no name for.
    private var unnamed: Int { advice.count - shown.count }

    /// Suggestions Screen Time has still handed no token for.
    private var tokenless: Int {
        guard let summary else { return 0 }
        return advice.filter { summary.entry(for: $0)?.targetKind == nil }.count
    }

    /// Write the suggested rule, adding the app first when Furlough does not manage it yet. A
    /// usage entry may arrive without a token; then the token is looked up among what is
    /// installed. Adding goes through the picker path with everything already chosen kept in
    /// the selection, because `applyPicker` schedules a removal for whatever it does not see.
    private func apply(_ item: Recommendation, _ entry: UsageEntry) async {
        guard #available(iOS 26.4, *) else { return }
        busy = item.key
        defer { busy = nil }

        var entry = entry
        if naming, entry.targetKind == nil || fromCache {
            // `nameApps` is asking Screen Time this very question for every card at once, and
            // asking it again for this one would be a second slow query racing the first. Wait
            // for that answer instead; the button reads "Applying…" meanwhile.
            //
            // A token out of the cache waits too, even though it is right here. It says what was
            // installed at the last visit, and an app deleted since is exactly the case where it
            // is wrong — writing a rule on it would leave a target nothing can name and no shield
            // will ever cover, past the half hour `undoFreshTarget` allows. So the one place the
            // cache is not trusted is the place where being wrong outlives the screen.
            while naming, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }
            entry = summary?.entry(for: item) ?? entry
        }
        var kind = entry.targetKind
        if kind == nil {
            do {
                kind = try await UsageReader.kind(forKey: entry.key, within: UsageReader.patience)
            } catch {
                states[item.key] = .failed(error.localizedDescription)
                return
            }
        }
        guard let kind else {
            states[item.key] = .failed("Screen Time counted \(entry.plainName) but gave no token for it, so there is nothing to write a rule on.")
            return
        }

        var fresh = false
        // `target(kind:)` rather than a match on `kind` alone: this app may already be the linked
        // half of a row — YouTube beside youtube.com — and adding it again would split the pair
        // back into the two rows linking exists to join.
        if model.state.config.target(kind: kind) == nil {
            var picked = model.pickerSelection
            switch kind {
            case .application(let token): picked.applicationTokens.insert(token)
            case .webDomain(let token): picked.webDomainTokens.insert(token)
            // A report names what Screen Time counted, and it counts neither a whole category
            // nor a site typed by hand.
            case .category, .host: break
            }
            _ = model.applyPicker(picked)
            model.reload()
            fresh = true
        }
        guard let target = model.state.config.targets.first(where: { $0.kind == kind }) else {
            states[item.key] = .failed("Could not add \(entry.plainName).")
            return
        }
        let outcome = model.apply(rule: item.rule, nickname: target.nickname, for: target.id, andTo: [])
        withAnimation(.easeInOut(duration: 0.2)) {
            // Folded, whatever the card was doing before: this is the answer to the question the
            // card was asking, and the rest of it has been read by the time Apply is pressed.
            expanded.remove(item.key)
            states[item.key] = .applied(
                targetID: target.id,
                fresh: fresh,
                message: outcome.message,
                waiting: outcome.scheduled > 0
            )
        }
    }

    /// Takes back a rule this run wrote on an app this run added. Anything else is a loosening
    /// like any other, and belongs in the rule editor where the delay is explained.
    private func undo(_ item: Recommendation) {
        guard case .applied(let targetID, true, _, _) = states[item.key] else { return }
        if model.undoFreshTarget(targetID) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.remove(item.key)
                states[item.key] = .offered
            }
        } else {
            states[item.key] = .failed("Furlough has held this rule too long to take it straight back. Loosen it from the rule editor instead.")
        }
    }
}
