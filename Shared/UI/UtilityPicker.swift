import SwiftUI

extension Utility {
    /// Green through amber to ember as the tier falls: the colour says how much protecting the
    /// app itself deserves, which is the opposite of how much protecting *from* it does.
    var tint: Color {
        switch self {
        case .essential: Ember.moss
        case .useful: Ember.cream
        case .idle: Ember.pending
        case .hazard: Ember.ember
        }
    }
}

/// The four tiers as a row of chips, with the delay each one buys spelled out underneath.
///
/// One control for both halves of the feature: it sets how long this target's loosenings wait,
/// and it is what decides whether blocking it is questioned first. Shared by the phone and the
/// Mac, so the wording cannot drift between them.
struct UtilityPicker: View {
    @Binding var selection: Utility
    /// The base delay, so each chip can say what it would actually cost.
    let baseDelayHours: Int
    /// What the table would have picked, when it recognises the app and Zach has not chosen yet.
    var suggestion: Utility?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Utility.allCases, id: \.rawValue) { tier in
                    chip(tier)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Text(selection.summary)
                .emberBody(12)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            Text("Loosening this one waits \(TimeFormat.delay(hours: hours(for: selection))).")
                .emberBody(12, .semibold)
                .foregroundStyle(selection.tint)
                .padding(.horizontal, 12)
                .padding(.top, 4)

            if let suggestion, suggestion != selection {
                Button {
                    withAnimation(.snappy) { selection = suggestion }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Furlough would call this \(suggestion.label.lowercased())")
                            .emberBody(11, .semibold)
                    }
                    .foregroundStyle(Ember.faint)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 14)
        .emberCard()
    }

    private func hours(for tier: Utility) -> Int {
        var config = Config()
        config.loosenDelayHours = baseDelayHours
        return config.delayHours(for: tier)
    }

    private func chip(_ tier: Utility) -> some View {
        let isOn = tier == selection
        return Button {
            withAnimation(.snappy) { selection = tier }
        } label: {
            Text(tier.label)
                .emberBody(12, .semibold)
                .foregroundStyle(isOn ? Ember.ground : Ember.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? tier.tint : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isOn ? .clear : Ember.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// The warning shown before a target worth keeping is blocked or anchored. Loud on purpose:
/// Furlough has no emergency unblock, so this is the last point at which the decision is cheap.
struct CautionBanner: View {
    let text: String
    var isSevere: Bool

    private var color: Color { isSevere ? Ember.ember : Ember.pending }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isSevere ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)
            Text(text)
                .emberBody(12, .semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
    }
}
