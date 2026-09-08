import DeviceActivity
import FamilyControls
import SwiftUI

/// Where the time goes, and the rule that would take it back. The ranking is drawn by the
/// report extension over the last fortnight, one report per position so each row has a height
/// the app knows: Screen Time's numbers never reach the app through those cards. Under it, one
/// chart per app or site Furlough manages, from the same extension. With data access
/// (`UsageReader.hasDataAccess`, iOS 26.4) the app reads the numbers itself and draws its own
/// suggestions, each with an Apply button that writes the rule; authorised the old way on a
/// phone that could grant it, it asks.
struct UsageView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: UsageSummary?
    @State private var failure: String?
    @State private var outcome: String?

    /// Categories have no hours of their own worth a card.
    private var targets: [Target] { model.state.config.targets.filter { !$0.kind.isCategory } }

    private var hasDataAccess: Bool { UsageReader.hasDataAccess(model.authorization) }

    /// Allowed the old way, on a phone that knows the new one.
    private var couldHaveDataAccess: Bool {
        guard #available(iOS 26.4, *) else { return false }
        return model.isAuthorized && !hasDataAccess
    }

    /// A report cannot tell the app how tall it is, so every slot gets a height the row was
    /// designed for: name, two lines of where, three lines of rule, and the card's padding.
    private let rankHeight: CGFloat = 176
    private let focusHeight: CGFloat = 176

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if hasDataAccess {
                    applySection
                } else if couldHaveDataAccess {
                    dataAccessCard
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow(text: "Where the time goes")
                        Spacer()
                        Eyebrow(text: "Last \(UsageReader.days) days")
                    }
                    .padding(.horizontal, 4)
                    ForEach(1...UsageAnalysis.rankLimit, id: \.self) { position in
                        DeviceActivityReport(.rank(position), filter: UsageReader.filter())
                            .frame(height: rankHeight)
                    }
                }
                if !targets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "What Furlough manages")
                            .padding(.horizontal, 4)
                        ForEach(targets) { target in
                            focusCard(target)
                        }
                    }
                }
                Text("Screen Time draws these cards in a sandbox of its own. A suggestion closes the hours that hold most of the use and keeps half the time.")
                    .emberBody(11)
                    .foregroundStyle(Ember.faint)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
        .background(EmberWall())
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.authorization) { await load() }
        .alert("Applied", isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })) {
            Button("OK") { outcome = nil }
        } message: {
            Text(outcome ?? "")
        }
    }

    /// The app's own reading of the fortnight, with the button the report cards cannot have.
    @ViewBuilder
    private var applySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Suggested rules")
            if let failure {
                Text(failure).emberBody(13).foregroundStyle(Ember.ember)
            } else if let summary {
                let advice = summary.recommendations
                if advice.isEmpty {
                    Text("Nothing passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day.")
                        .emberBody(13)
                        .foregroundStyle(Ember.muted)
                }
                ForEach(advice) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).emberDisplaySmall(15).foregroundStyle(Ember.cream)
                            Text(TimeFormat.rule(item.rule)).emberBody(12).foregroundStyle(Ember.muted)
                        }
                        Spacer(minLength: 12)
                        Button("Apply") { Task { await apply(item) } }
                            .emberBody(13)
                            .foregroundStyle(Ember.amber)
                    }
                }
            } else {
                Text("Reading Screen Time…").emberBody(13).foregroundStyle(Ember.muted)
            }
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
            Text("With data access, Furlough reads these numbers itself and every suggestion gets an Apply button. Nothing leaves the phone.")
                .emberBody(13)
                .foregroundStyle(Ember.muted)
            GhostButton(title: "Allow data access") { Task { await model.requestAuthorization() } }
            Text("If no prompt appears, turn Furlough off and back on under Settings › Screen Time › Apps with Screen Time Access, then come back here.")
                .emberBody(11)
                .foregroundStyle(Ember.faint)
        }
        .padding(16)
        .emberCard()
    }

    private func focusCard(_ target: Target) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(target.displayName)
                    .emberDisplaySmall(15)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Spacer()
                NavigationLink { RuleEditorView(targetID: target.id) } label: {
                    HStack(spacing: 4) {
                        Text("Edit rule").emberBody(12)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Ember.amber)
                }
            }
            DeviceActivityReport(.focus, filter: UsageReader.filter(for: target.kind))
                .frame(height: focusHeight)
        }
    }

    private func load() async {
        guard #available(iOS 26.4, *), hasDataAccess else { return }
        do {
            summary = try await UsageReader.summary()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Write the suggested rule, adding the target first when Furlough does not manage it yet.
    /// A usage entry may come without a token; then the token is looked up among what is
    /// installed. Adding goes through the picker path with everything already chosen kept in
    /// the selection, because `applyPicker` schedules a removal for whatever it does not see.
    private func apply(_ item: Recommendation) async {
        guard #available(iOS 26.4, *), let entry = summary?.entry(for: item) else { return }
        var kind: TargetKind?
        do {
            if let token = entry.applicationToken {
                kind = .application(token)
            } else if let token = entry.webDomainToken {
                kind = .webDomain(token)
            } else {
                kind = try await UsageReader.kind(forKey: entry.key)
            }
        } catch {
            failure = error.localizedDescription
            return
        }
        guard let kind else {
            failure = "Screen Time gave no token for \(item.name)."
            return
        }

        if model.state.config.targets.first(where: { $0.kind == kind }) == nil {
            var selection = FamilyActivitySelection()
            for target in model.state.config.targets {
                switch target.kind {
                case .application(let token): selection.applicationTokens.insert(token)
                case .webDomain(let token): selection.webDomainTokens.insert(token)
                case .category(let token): selection.categoryTokens.insert(token)
                // Not in any selection, and `applyPicker` leaves typed hosts alone rather
                // than reading their absence as an unpick.
                case .host: break
                }
            }
            switch kind {
            case .application(let token): selection.applicationTokens.insert(token)
            case .webDomain(let token): selection.webDomainTokens.insert(token)
            case .category: break
            // A report names things Screen Time counted, and it never counts a typed host.
            case .host: break
            }
            _ = model.applyPicker(selection)
            model.reload()
        }
        guard let target = model.state.config.targets.first(where: { $0.kind == kind }) else {
            failure = "Could not add \(item.name)."
            return
        }
        outcome = model.apply(rule: item.rule, nickname: target.nickname, for: target.id, andTo: []).message
    }
}
