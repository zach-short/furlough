import SwiftUI

/// Screen Time tokens don't transfer across devices, so unlike the phone's import
/// (`ImportSetupView`) there's no setup step before the review here.
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
                    .emberGlassButton(tint: Ember.muted)
                Button(plan.isEmpty ? "Nothing to apply" : "Apply this setup") { onApply() }
                    .emberGlassButton(prominent: true, tint: Ember.ember)
                    .disabled(!plan.canApply)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
