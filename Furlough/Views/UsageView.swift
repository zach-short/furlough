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
    /// Cards answered before Screen Time had the last word on their token, by
    /// `Recommendation.key`. See `Optimistic`, `confirm` and `land`.
    @State private var optimistic: [String: Optimistic] = [:]
    /// What this run could not finish, in the order it gave up on them. The toast's whole
    /// content; emptied by Dismiss or by Try again.
    @State private var trouble: [Trouble] = []
    /// The Done button is settling the last of `optimistic` before it lets the step close.
    @State private var finishing = false
    /// Where Path A has got to; see `Phase`.
    @State private var phase = Phase.reading
    /// Screen Time is still being asked for the tokens (`nameApps`). While this is true a card
    /// whose app the tables did not know is held back, because there is nothing to call it yet,
    /// and a card answered before its token arrived waits on this answer rather than asking the
    /// same slow question a second time — see `land`.
    @State private var naming = false
    /// The tokens on the page came out of `TokenCache` and Screen Time has not confirmed them
    /// yet. True from the moment the cache is folded in until the first answered pass of
    /// `nameApps`; it is what makes an Apply over one of those tokens worth checking afterwards
    /// — see `apply` and `confirm`.
    @State private var fromCache = false
    /// How many times to ask Screen Time for the tokens before giving up on them, each ask given
    /// `UsageReader.patience`. Three, a second apart: long enough to ride out a query that simply
    /// did not answer, short enough that the icons stop changing under the reader within the
    /// minute. Nothing on the page waits on this; see `nameApps`.
    private static let namingAttempts = 3
    /// How long the Done button will settle outstanding work before it closes the step anyway.
    /// Short, because by the time a screenful of cards has been read the naming answered long
    /// ago and this is nearly always zero — and because a card still owed at the end keeps
    /// finishing on its own after the step closes; the only thing given up on is the toast.
    private static let finishPatience: Duration = .seconds(3)

    /// A card answered before Screen Time had the last word on its token.
    ///
    /// Two cases, one shape. `done` set: the work is written, on a token the cache supplied and
    /// Screen Time has not confirmed — `confirm` reads the answer back against it. `done` nil:
    /// there was no token at all, so nothing could be written yet and `land` is waiting for one.
    /// Either way the name is kept here, because a card whose app Screen Time ends up disowning
    /// is gone from `advice` by the time there is anything to say about it, and the toast has to
    /// be able to say which app.
    private struct Optimistic {
        var name: String
        var done: UsageCardState.Applied?
    }

    /// Why the work could not be done, in the words the card says back. A type of its own
    /// because `Result` wants an `Error` on the losing side and the reason is a sentence.
    private struct Refusal: Error {
        var reason: String
        init(_ reason: String) { self.reason = reason }
    }

    /// One app this run could not finish, and the card to put back as a question.
    private struct Trouble: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

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
    /// Where an answer lands, while both halves are on offer. Held for the page rather than the
    /// card, so answering once answers for the run: most people want the same thing for every
    /// app on the list, and the ones who do not change it on the card that is the exception.
    @State private var destination = UsageDestination.both
    /// Path B: which card the tour is showing, 1…`UsageAnalysis.rankLimit`.
    @State private var position = 1
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var editing: EditingTarget?

    /// The target the picker just added, on its way to the rule editor.
    private struct EditingTarget: Identifiable, Hashable { let id: UUID }

    private var hasDataAccess: Bool { UsageReader.hasDataAccess(model.authorization) }

    /// Which half the cards offer. The page itself is the same page for everybody — a fortnight,
    /// heaviest app first, which is worth reading whichever half you came for — so the start
    /// pane's answer only decides what a card proposes at the end of it.
    ///
    /// The Anchor drops out where it has nothing to take in: while it is down its list cannot
    /// change at all, and under the everything-except scope the list is what stays open, so
    /// "hold this too" would mean letting it through. Neither can happen on the way out of the
    /// intro; both can from Settings, which opens the same screen months later.
    private var offer: UsageOffer {
        let anchor = model.state.config.anchor
        guard !anchor.isAnchored, !anchor.anchorsEverything else { return .rules }
        if model.wantsBothHalves { return .both }
        return model.startHalf == .anchor ? .anchor : .rules
    }

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
            // Room for the toast while there is one, so the last thing on the page — which on
            // the way out of the intro is the Done button — never ends up underneath it.
            .padding(.bottom, trouble.isEmpty ? 40 : 190)
            .animation(.easeInOut(duration: 0.2), value: trouble.isEmpty)
        }
        .background(EmberWall())
        // Over the page rather than in it: what could not be finished is news about a card that
        // has already been folded and scrolled past, and a line appearing somewhere up the list
        // is a line nobody reads.
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

    /// The page's second line, in the shape of the half on offer.
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

    /// The same, on a phone where only the report extension ever sees a number.
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
            ProminentButton(title: offer == .anchor ? "Hold this app" : "Manage this app", action: openPicker)
            Footnote(text: offer == .anchor
                ? "Apple's picker opens on its own list of apps. Pick the one the card names, and it goes on the Anchor's list — out of reach the moment you drop it."
                : "Apple's picker opens on its own list of apps. Pick the one the card names, and the rule editor opens next so you can write what the card showed.")
        }
    }

    /// Apple's picker, seeded with whatever the half on offer already has: both ways in replace
    /// a whole list rather than add to one, so what is already there has to go in with it.
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

    /// What the picker left behind. `applyPicker` schedules a removal for anything it does not
    /// see, so the selection was seeded with everything already managed; whatever is new is the
    /// app this card was about, and the editor opens on it.
    private func addPicked() {
        // The anchor's list is replaced whole, the way its own screen replaces it, and there is
        // no editor to go to afterwards: a held app has no hours to write.
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
            // The check Zach asked for, at the one place there is a step after this one: the
            // flow has been applying optimistically all the way down the page, and this is
            // where anything still owed is settled before the step can close on it.
            ProminentButton(title: finishTitle, isBusy: finishing) { Task { await finish() } }
                .padding(.top, 4)
            Footnote(
                text: "You can run this again any time from Settings › Where the time goes.",
                alignment: .center
            )
        }
    }

    private var finishTitle: String {
        if finishing { return "Finishing up…" }
        return applied.isEmpty ? "Skip for now" : "Done"
    }

    /// The suggestions taken this run, in the order they were offered. A card whose work is
    /// still on its way in is not one of them: the closing count says what was done, and a
    /// pending card has had nothing written for it yet.
    private var applied: [Recommendation] {
        advice.filter {
            if case .applied(let done) = states[$0.key] { return !done.pending }
            return false
        }
    }

    /// What each of them did, for the closing count.
    private func done(_ item: Recommendation) -> UsageCardState.Applied? {
        guard case .applied(let done) = states[item.key] else { return nil }
        return done
    }

    /// "3 apps managed, about 2 h 10 min a day taken back. 2 on the Anchor's list." The time is
    /// what each average is over its new budget, rounded down to five minutes — an estimate, and
    /// said as one. The two halves are counted separately because a card can land on both, and
    /// one number covering them would be a number of nothing.
    private var closingLine: String {
        var lines: [String] = []
        let ruled = applied.filter { done($0)?.targetID != nil }
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
        // Nothing on the old page is owed a check any more: the cards it was about are gone,
        // and whatever those tasks were waiting on will find no card to finish.
        optimistic = [:]
        trouble = []
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
        // Screen Time has had its say, so anything answered on the cache's word before it can be
        // checked against it. Last, because it reads `advice` and `summary` as they now stand.
        confirm()
    }

    /// Suggestions the tables had no name for.
    private var unnamed: Int { advice.count - shown.count }

    /// Suggestions Screen Time has still handed no token for.
    private var tokenless: Int {
        guard let summary else { return 0 }
        return advice.filter { summary.entry(for: $0)?.targetKind == nil }.count
    }

    /// Do what the card offered, wherever the card said it lands: write the suggested rule,
    /// adding the app to Rules first when Furlough does not manage it yet; put it on the
    /// Anchor's list; or both.
    ///
    /// Nothing here waits. Every line of the work itself is a write to the App Group and a
    /// redraw (`write`), so the card can be answered in the frame the button was pressed in —
    /// and until 2026-09-13 it was not, because Apply asked Screen Time a question first and
    /// Screen Time is the slowest thing on the phone. That wait bought one guarantee: a token
    /// out of the cache names what was installed at the *last* visit, and an app deleted since
    /// is the case where it is wrong. The guarantee is worth having; paying for it in front of
    /// the button was not. So the work goes in now on the token in hand, and the check moves
    /// behind it — `confirm` reads Screen Time's answer back the moment `nameApps` has it, and
    /// anything it disowns is taken off again and named in the toast.
    ///
    /// The one case with nothing to go on is a card Screen Time has handed no token for at all,
    /// which is the first visit before the first answer. There the card is still answered on the
    /// spot and marked `pending`, and `land` finishes it when the token arrives.
    private func apply(_ item: Recommendation, _ entry: UsageEntry) {
        guard #available(iOS 26.4, *) else { return }
        // Answering a card again takes it out of the toast: whatever it says about this app is
        // about the previous answer, and there is a new one now.
        withAnimation(.easeInOut(duration: 0.2)) { trouble.removeAll { $0.key == item.key } }

        guard let kind = entry.targetKind else {
            var done = UsageCardState.Applied(message: "")
            done.pending = true
            settle(item, done)
            optimistic[item.key] = Optimistic(name: entry.plainName, done: nil)
            Task { await land(item, entry) }
            return
        }
        switch write(item, entry, on: kind) {
        case .success(let done):
            settle(item, done)
            // Cached, so it says what was installed last visit and Screen Time has not been
            // heard from since. `confirm` is where that is read back.
            if fromCache { optimistic[item.key] = Optimistic(name: entry.plainName, done: done) }
        case .failure(let refusal):
            states[item.key] = .failed(refusal.reason)
        }
    }

    /// The work itself, on a token already in hand: the rule, the place on the anchor's list, or
    /// both. Every line is a write to the App Group and an enforce — no query and no await — so
    /// this is what makes an instant Apply honest rather than optimistic.
    ///
    /// Adding to Rules goes through the picker path with everything already chosen kept in the
    /// selection, because `applyPicker` schedules a removal for whatever it does not see.
    private func write(
        _ item: Recommendation,
        _ entry: UsageEntry,
        on kind: TargetKind
    ) -> Result<UsageCardState.Applied, Refusal> {
        let landing = landing()
        var done = UsageCardState.Applied(message: "")

        if landing.writesRule {
            var fresh = false
            // `target(kind:)` rather than a match on `kind` alone: this app may already be the
            // linked half of a row — YouTube beside youtube.com — and adding it again would split
            // the pair back into the two rows linking exists to join.
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
                return .failure(Refusal("Could not add \(entry.plainName)."))
            }
            let outcome = model.apply(rule: item.rule, nickname: target.nickname, for: target.id, andTo: [])
            done.targetID = target.id
            done.fresh = fresh
            done.waiting = outcome.scheduled > 0
            done.message = outcome.message
        }

        if landing.holds {
            // Every door of the row where there is one — a linked app and site are two ways into
            // one habit and should not need two picks to close — and the one the card names where
            // there is not. An anchor-only person gets no rules row out of this at all.
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

    /// Marks a card answered and folds it. Folded whatever it was doing before: this is the
    /// answer to the question the card was asking, and the rest of it has been read by the time
    /// Apply is pressed.
    private func settle(_ item: Recommendation, _ done: UsageCardState.Applied) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expanded.remove(item.key)
            states[item.key] = .applied(done)
        }
    }

    /// Finishes a card answered before Screen Time had handed a token over.
    ///
    /// It waits on `nameApps` rather than asking anything itself, because `nameApps` is putting
    /// that very question to Screen Time for every card on the page at once, and a second walk
    /// of every app on the phone would only queue up behind the first (`UsageReader.Enumeration`).
    /// Its own ask is the fallback for a naming that came back with nothing at all.
    ///
    /// Nothing on screen is held up by any of this: the card was folded and marked the moment
    /// the button was pressed, and the page below it is still a page.
    private func land(_ item: Recommendation, _ entry: UsageEntry) async {
        guard #available(iOS 26.4, *) else { return }
        while naming, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard !Task.isCancelled else { return }
        // The card may have been answered again, skipped, or taken back while this was waiting.
        // Whatever it says now is a later answer than the one this task is carrying.
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

    /// Reads Screen Time's answer back against every card applied before it arrived.
    ///
    /// By the time this runs, `fillingTokens` has resolved every entry on the page against what
    /// is installed *now* — it clears each token before it looks one up — so an entry that has
    /// lost its token is an app that is no longer there. A card applied on the cache's word
    /// about it was applied on a token nothing will ever name or shield, and the honest thing is
    /// to take it back off and say which app it was.
    ///
    /// Cards still waiting for a first token are not this function's business: `land` is holding
    /// them and is about to be let go.
    private func confirm() {
        guard let read = summary else { return }
        let alive = Set(read.entries.compactMap { $0.targetKind != nil ? $0.key : nil })
        for (key, pending) in optimistic {
            guard let done = pending.done else { continue }
            optimistic[key] = nil
            guard !alive.contains(key) else { continue }
            // Undone by hand, skipped, or answered again since: whatever the card says now is a
            // later answer than the one being checked, and it is not this pass's to overrule.
            guard isApplied(key) else { continue }
            guard let item = advice.first(where: { $0.key == key }) else {
                // The card is gone from the page with the app; take the work back all the same.
                takeBack(done)
                trouble.append(Trouble(key: key, name: pending.name))
                continue
            }
            SharedStore.log("usage: took \(key) back — the cache's token named an app Screen Time no longer has")
            giveUp(item, name: pending.name, done: done)
        }
    }

    /// Undoes an optimistic answer and puts the card back as a question, with the app named in
    /// the toast. Only what this flow made itself comes off: a rule written on a row that was
    /// already there is a loosening like any other and belongs in the editor.
    /// What a card says now, for the two passes that come back to a page which has moved on
    /// without them. `land` carries an answer that is only still wanted while the card is
    /// pending; `confirm` may only take back an answer the card is still standing on.
    private func isPending(_ item: Recommendation) -> Bool {
        guard case .applied(let done) = states[item.key] else { return false }
        return done.pending
    }

    private func isApplied(_ key: String) -> Bool {
        guard case .applied(let done) = states[key] else { return false }
        return !done.pending
    }

    private func takeBack(_ done: UsageCardState.Applied) {
        if done.holds { model.stopHolding(done.heldKinds) }
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

    /// The toast's own button: offer every one of them again, on whatever Screen Time knows now.
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

    /// The Done button. Settles whatever is still on its way in before the step closes, which is
    /// the check the optimistic Apply owes: anything that could not be finished is named here,
    /// on the last screen that can still do something about it, rather than silently not being
    /// there afterwards. Bounded by `finishPatience`, because a card left owing keeps finishing
    /// on its own after the step closes and only the toast is given up on.
    private func finish() async {
        let known = Set(trouble.map(\.key))
        if !optimistic.isEmpty {
            finishing = true
            let deadline = ContinuousClock.now.advanced(by: Self.finishPatience)
            while !optimistic.isEmpty, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(150))
            }
            finishing = false
        }
        // Trouble the settle turned up is news, and the step stays open on it. Trouble that was
        // already on the page has been read, and pressing Done over it means Done.
        guard trouble.allSatisfy({ known.contains($0.key) }) else { return }
        model.finishUsageStep()
    }

    /// Where this card's answer lands: the half on offer, or the segment's answer when both are.
    private func landing() -> UsageDestination {
        switch offer {
        case .rules: .rules
        case .anchor: .anchor
        case .both: destination
        }
    }

    /// Takes back what this run did: the place on the anchor's list, which has no delay and
    /// always comes straight off, and a rule this run wrote on an app this run added. A rule on
    /// a row that was already there is a loosening like any other, and belongs in the rule
    /// editor where the delay is explained — `Applied.canUndo` is what keeps the button off
    /// those cards.
    private func undo(_ item: Recommendation) {
        guard case .applied(let done) = states[item.key], done.canUndo else { return }
        if done.holds { model.stopHolding(done.heldKinds) }
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
