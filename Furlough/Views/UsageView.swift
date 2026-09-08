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
    @State private var busy: String?
    /// A naming pass is in flight; see `nameApps`.
    @State private var naming = false
    /// How many times to ask Screen Time for the names before leaving it to a tap. Three, a
    /// second apart, is far less than the time it takes to read the first card.
    private static let namingAttempts = 3
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
        if let failure {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Screen Time said no", color: Ember.ember)
                Text(failure).emberBody(13).foregroundStyle(Ember.muted)
            }
            .padding(16)
            .emberCard()
        } else if let summary {
            if advice.isEmpty {
                Text("Nothing on this phone passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day. There is nothing here worth a rule.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .padding(16)
                    .emberCard()
            }
            ForEach(advice) { item in
                if let entry = summary.entry(for: item) {
                    card(item, entry, days: summary.totalDays)
                }
            }
            if unnamed > 0 { namingFailure }
        } else {
            Text("Reading the last \(UsageReader.days) days…")
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .padding(16)
                .emberCard()
        }
    }

    @ViewBuilder
    private func card(_ item: Recommendation, _ entry: UsageEntry, days: Int) -> some View {
        let state = states[item.key] ?? .offered
        if state == .skipped {
            UsageSkippedLine(item: item, entry: entry) {
                withAnimation(.easeInOut(duration: 0.2)) { states[item.key] = .offered }
            }
        } else {
            UsageSuggestionCard(
                item: item,
                entry: entry,
                days: days,
                state: state,
                isBusy: busy == item.key,
                apply: { Task { await apply(item, entry) } },
                skip: { withAnimation(.easeInOut(duration: 0.2)) { states[item.key] = .skipped } },
                undo: { undo(item) }
            )
        }
    }

    /// Screen Time would not say what these apps are called. Worth saying out loud rather than
    /// leaving a card reading "This app" as though that were the app's name.
    private var namingFailure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unnamed == 1
                ? "Screen Time did not say what one of these apps is called."
                : "Screen Time did not say what \(unnamed) of these apps are called.")
                .emberBody(12)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(naming ? "Asking…" : "Ask again") { Task { await nameApps() } }
                .emberBody(13, .semibold)
                .foregroundStyle(Ember.amber)
                .buttonStyle(.plain)
                .disabled(naming)
        }
        .padding(16)
        .emberCard()
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
        guard #available(iOS 26.4, *), hasDataAccess else { return }
        if summary == nil {
            do {
                let read = try await UsageReader.summary()
                advice = read.recommendations
                summary = read
                failure = nil
                SharedStore.log("usage: \(read.entries.count) entries, \(advice.count) worth a rule")
            } catch {
                failure = error.localizedDescription
                return
            }
        }
        await nameApps()
    }

    /// Puts Apple's names and icons back on the cards, and keeps asking while any of them is
    /// still nameless.
    ///
    /// Data access names an app by its bundle identifier alone, so the only name that exists
    /// comes from a token, and the only way to a token is a query into Screen Time's own store
    /// (`UsageReader.fillingTokens`). That query is not reliable: it answers, or it comes back
    /// with nothing, or it throws, and which one is not something the app can tell in advance.
    /// One attempt is therefore not a design — a single empty answer is what left every card
    /// saying "This app" until the screen was left and opened again. So it is asked again, a
    /// second apart, and only while something it should have named is still unnamed.
    private func nameApps() async {
        guard #available(iOS 26.4, *) else { return }
        naming = true
        defer { naming = false }
        for attempt in 1...Self.namingAttempts {
            guard let read = summary, unnamed > 0 else { return }
            do {
                let named = try await UsageReader.fillingTokens(in: read)
                summary = named
                SharedStore.log("usage: naming attempt \(attempt) left \(unnamed) of \(advice.count) unnamed")
                if unnamed == 0 { return }
            } catch {
                SharedStore.log("usage: naming attempt \(attempt) failed: \(error.localizedDescription)")
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Suggestions Screen Time has still not handed a token for, so the card can only call the
    /// app "This app".
    private var unnamed: Int {
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

        var kind = entry.targetKind
        if kind == nil {
            do {
                kind = try await UsageReader.kind(forKey: entry.key)
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
        if model.state.config.targets.first(where: { $0.kind == kind }) == nil {
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
            states[item.key] = .applied(targetID: target.id, fresh: fresh, message: outcome.message)
        }
    }

    /// Takes back a rule this run wrote on an app this run added. Anything else is a loosening
    /// like any other, and belongs in the rule editor where the delay is explained.
    private func undo(_ item: Recommendation) {
        guard case .applied(let targetID, true, _) = states[item.key] else { return }
        if model.undoFreshTarget(targetID) {
            withAnimation(.easeInOut(duration: 0.2)) { states[item.key] = .offered }
        } else {
            states[item.key] = .failed("Furlough has held this rule too long to take it straight back. Loosen it from the rule editor instead.")
        }
    }
}
