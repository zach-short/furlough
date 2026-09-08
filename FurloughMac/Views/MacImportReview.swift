import SwiftUI

/// The Mac's half of an import: read the file, look at what it would do, then do it.
///
/// A Mac file is a whole setup — a Mac target is a bundle identifier or a host, and this Mac
/// can look both up for itself — so there is nothing to ask before the review. The phone's
/// import has a step in front of this one, because a Screen Time token means nothing off the
/// device that issued it; see `ImportSetupView`.
struct MacImportReview: View {
    let plan: ImportPlan
    let onBack: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { onBack() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text("Settings").emberBody(12.5, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                ImportReviewList(plan: plan)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            Divider().overlay(Ember.cardBorder)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { onBack() }
                    .buttonStyle(.glass)
                    .tint(Ember.muted)
                Button(plan.isEmpty ? "Nothing to apply" : "Apply this setup") { onApply() }
                    .buttonStyle(.glassProminent)
                    .tint(Ember.ember)
                    .disabled(!plan.canApply)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
