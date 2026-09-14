import FamilyControls
import SwiftUI

/// A phone can't resolve a Screen Time target from an exported bundle identifier or host — it's
/// an opaque token Apple scopes to one device and app install — so each row must be remapped to
/// an app through the picker here, except website rows (a plain host string), which
/// `ConfigImport.preresolved` resolves automatically before the screen draws. Rows left alone
/// are left out.
struct ImportSetupView: View {
    let export: ConfigExport
    /// Read once at the call site since `init` needs it and the environment isn't readable there.
    let config: Config
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// One per row of the file, in order; starts unanswered until Import is pressed.
    @State private var resolutions: [ImportResolution]
    @State private var picking: Int?
    @State private var selection = FamilyActivitySelection()
    @State private var review: ImportPlan?
    @State private var problem: String?
    /// The sheet stays up behind this alert and closes on OK, since part of an import may not
    /// take effect for a day and a screen that just vanished would look like nothing happened.
    @State private var applied: String?

    init(export: ConfigExport, config: Config) {
        self.export = export
        self.config = config
        _resolutions = State(
            initialValue: ConfigImport.preresolved(for: export, config: config, unresolved: Self.unanswered)
        )
    }

    private static let unanswered = "You did not say which app this is, so it was left out."

    private var matches: [ImportMatch] {
        zip(export.targets, resolutions).map { ImportMatch(exported: $0, resolution: $1) }
    }

    private var answered: Int {
        resolutions.filter { if case .skipped = $0 { return false }; return true }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let review {
                    VStack(alignment: .leading, spacing: 0) {
                        ImportReviewList(plan: review)
                        ProminentButton(title: "Apply this setup") {
                            applied = model.applyImport(review)
                        }
                        .disabled(!review.canApply)
                        .opacity(review.canApply ? 1 : 0.4)
                        .padding(.top, 16)
                        GhostButton(title: "Back") { self.review = nil }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
                } else {
                    chooser
                }
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(review == nil ? "Restore from a file" : "What this will do")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Ember.cream)
                }
            }
        }
        .presentationBackground(Ember.ground)
        .familyActivityPicker(
            headerText: picking.map { "Which app is \(matches[$0].name)?" } ?? "Which app is this?",
            footerText: "Its schedule, budget and tier come from the file. Only which app it is is yours to say.",
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            selection: $selection
        )
        .onChange(of: picking) { was, now in
            // No single-select mode in Apple's picker, so the answer is read on the way out.
            guard was != nil, now == nil else { return }
            if let index = was { answer(index) }
            selection = FamilyActivitySelection()
        }
        .alert("Restore from a file", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }), presenting: problem) { _ in
            Button("OK") { problem = nil }
        } message: { problem in
            Text(problem)
        }
        .alert("Restored", isPresented: Binding(get: { applied != nil }, set: { if !$0 { applied = nil } }), presenting: applied) { _ in
            Button("OK") {
                applied = nil
                dismiss()
            }
        } message: { message in
            Text(message)
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This file has \(export.targets.count == 1 ? "1 rule" : "\(export.targets.count) rules") in it, and knows what each one was called. Screen Time will not tell it which app that was, so say here.")
                .emberBody(13)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SectionLabel(text: "From the file")
            VStack(spacing: 0) {
                ForEach(Array(export.targets.enumerated()), id: \.offset) { index, exported in
                    if index > 0 { CardDivider() }
                    row(index, exported)
                }
            }
            .emberCard()
            Footnote(text: "Nothing is written until you have seen what it would do. A rule you map onto an app you already manage is judged against the rule that app has today, so anything that loosens it still waits out the delay.")
                .padding(.top, 8)

            ProminentButton(title: answered == 0 ? "Nothing chosen yet" : "See what this will do") {
                review = model.plan(export, matches: matches)
            }
            .disabled(answered == 0)
            .opacity(answered == 0 ? 0.4 : 1)
            .padding(.top, 16)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 48)
    }

    private func row(_ index: Int, _ exported: ExportedTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(matches[index].name)
                    .emberDisplaySmall(14)
                    .foregroundStyle(Ember.cream)
                Text(TimeFormat.rule(exported.rule))
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                if let tier = exported.utility?.utility {
                    Text(tier.label)
                        .emberBody(11)
                        .foregroundStyle(Ember.faint)
                }
            }
            HStack(spacing: 10) {
                if let kind = kind(of: resolutions[index]) {
                    TokenTile(kind: kind, size: 26)
                    TokenName(kind: kind)
                    Spacer(minLength: 0)
                    Button("Leave out") { resolutions[index] = .skipped(Self.unanswered) }
                        .buttonStyle(.plain)
                        .emberBody(12, .semibold)
                        .foregroundStyle(Ember.muted)
                } else {
                    Button(exported.kind == .website ? "Choose the website" : "Choose the app") { picking = index }
                        .buttonStyle(.plain)
                        .emberBody(12.5, .bold)
                        .foregroundStyle(Ember.ember)
                    Spacer(minLength: 0)
                    Text("Left out")
                        .emberBody(11.5)
                        .foregroundStyle(Ember.faint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func kind(of resolution: ImportResolution) -> TargetKind? {
        switch resolution {
        case .existing(let id): model.state.config.target(id: id)?.kind
        case .create(let kind): kind
        case .skipped: nil
        }
    }

    private func answer(_ index: Int) {
        var kinds: [TargetKind] = []
        kinds += selection.applicationTokens.map(TargetKind.application)
        kinds += selection.webDomainTokens.map(TargetKind.webDomain)
        kinds += selection.categoryTokens.map(TargetKind.category)
        guard let chosen = kinds.first else { return }
        guard kinds.count == 1 else {
            problem = "Choose one app for \(matches[index].name). Each rule in the file belongs to one."
            return
        }
        // Two rows can't map to the same app: the second would be judged against whatever the
        // first just did.
        for (other, resolution) in resolutions.enumerated() where other != index {
            guard kind(of: resolution) == chosen else { continue }
            problem = "\(matches[other].name) is already mapped onto that one. Leave that row out first if you meant this one."
            return
        }
        if let existing = model.state.config.target(kind: chosen) {
            resolutions[index] = .existing(existing.id)
        } else {
            resolutions[index] = .create(chosen)
        }
    }
}
