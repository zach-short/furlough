import SwiftUI

/// What an import would do, laid out before it does it.
///
/// One view for both platforms, for the same reason `PendingDeltaView` is one: an import is
/// the largest single change Furlough can make to itself, half of it may be invisible for a
/// day, and the phone and the Mac must not tell that story in two different vocabularies.
/// It is also the vocabulary the pending cards already use — Now/Becomes, and a date in the
/// Pending colour — because a queued import change *is* a pending change, and reading the
/// review should teach nothing that has to be unlearned on the Pending screen.
///
/// Self-contained on purpose: this file is compiled into the widgets along with the rest of
/// `Shared/UI`, where the two apps' cards and section labels do not exist.
struct ImportReviewList: View {
    let plan: ImportPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.headline)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

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
                // A row's name is the app; what part of it this line is about is the label,
                // and a target being added needs no second word for it.
                if item.subject != .target {
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
