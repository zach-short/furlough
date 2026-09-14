import SwiftUI

/// One view for both platforms — vocabulary matches `PendingDeltaView`'s pending cards
/// (Now/Becomes, Pending colour) since a queued import change is a pending change.
/// Self-contained: compiled into widgets too, where each app's own components don't exist.
struct ImportReviewList: View {
    let plan: ImportPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provenance disambiguates files that look identical in Downloads.
            if let provenance {
                Text(provenance)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }

            Text(plan.headline)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            // Hard refusal, not a warning: an import iOS won't register is worse than one that
            // never happens (rules land, registration throws, nothing enforces them). Buttons
            // on both platforms gate on `plan.canApply`.
            if let limitReason = plan.limitReason {
                Text(limitReason)
                    .emberBody(12)
                    .foregroundStyle(Ember.ember)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .emberCard()
                    .padding(.top, 10)
            }

            section("New here", plan.added, caption: "Added as soon as you apply this. Nothing was managing them before, so their first rule is in force at once.")
            section("Applies now", plan.immediate, caption: "These tighten your rules, so they take effect immediately.")
            section("Waits out the delay", plan.queued, caption: "These loosen your rules. They are queued, and you can cancel any of them from Pending before they land.")
            section("Not used", plan.skipped, caption: "In the file, and left out. Furlough will not guess at what these were meant to say.")

            if !plan.untouched.isEmpty {
                header("Left alone")
                Text("\(UtilityText.list(plan.untouched)) \(plan.untouched.count == 1 ? "is" : "are") managed here and not in the file. An import only ever adds, so \(plan.untouched.count == 1 ? "it stays" : "they stay") exactly as \(plan.untouched.count == 1 ? "it is" : "they are").")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }
        }
    }

    /// Drops the build name when the file predates `appVersion`, so old exports still open.
    private var provenance: String? {
        guard let exportedAt = plan.exportedAt else { return nil }
        let when = exportedAt.formatted(date: .abbreviated, time: .shortened)
        guard let appVersion = plan.appVersion, !appVersion.isEmpty else {
            return "This file was saved \(when)."
        }
        return "This file was saved \(when), by Furlough \(appVersion)."
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ImportPlan.Item], caption: String) -> some View {
        if !items.isEmpty {
            header(title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Ember.cardBorder)
                            .frame(height: 1)
                            .padding(.leading, 12)
                    }
                    row(item)
                }
            }
            .emberCard()
            Text(caption)
                .emberBody(11.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .emberBody(10.5, .semibold)
            .tracking(0.8)
            .foregroundStyle(Ember.faint)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func row(_ item: ImportPlan.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.name)
                    .emberDisplaySmall(13.5)
                    .foregroundStyle(Ember.cream)
                // Row name is the app; label only shown when it adds info beyond that.
                if item.subject.isWorthNaming {
                    Text(item.subject.label)
                        .emberBody(11)
                        .foregroundStyle(Ember.faint)
                }
                Spacer(minLength: 0)
            }
            if let delta = item.delta {
                PendingDeltaView(delta: delta)
            }
            switch item.outcome {
            case .queued(let date):
                Text("Takes effect \(date.formatted(date: .abbreviated, time: .shortened))")
                    .emberBody(11, .semibold)
                    .foregroundStyle(Ember.pending)
            case .skipped(let why):
                Text(why)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
            case .now:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
