import FamilyControls
import SwiftUI

/// The card for this rank, or (in the first empty slot) a line saying the list ended.
struct RankView: View {
    let slot: RankSlot

    var body: some View {
        Group {
            if let item = slot.item, let entry = slot.entry {
                UsageReportCard(item: item, entry: entry, days: slot.days)
            } else if slot.position == slot.count + 1 {
                Text(slot.count == 0
                    ? "Nothing on this phone passes \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day in the last \(slot.days) days."
                    : "That is everything over \(Int(UsageAnalysis.minimumDailyMinutes)) minutes a day.")
                    .emberBody(12)
                    .foregroundStyle(Ember.faint)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Same card the app draws for itself when it can read the numbers; here Screen Time draws it
/// and the person carries the rule into the editor by hand, since nothing can leave this sandbox.
struct UsageReportCard: View {
    let item: Recommendation
    let entry: UsageEntry
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            VStack(alignment: .leading, spacing: 8) {
                UsageHours(histogram: entry.histogram, item: item)
                Text(item.whereLine())
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Ember.cardBorder).frame(height: 1)
            VStack(alignment: .leading, spacing: 9) {
                Eyebrow(text: "What Furlough would do", color: Ember.amber)
                RuleDrawing(item: item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reportCard()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ReportTile(entry: entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .emberDisplaySmall(17)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Text(subtitle)
                    .emberBody(11)
                    .foregroundStyle(Ember.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(TimeFormat.budget(Int(item.averageDailyMinutes.rounded())))
                    .emberNumerals(15)
                Text("a day")
                    .emberBody(11)
                    .foregroundStyle(Ember.faint)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    private var subtitle: String {
        let pickups = Int(item.pickupsPerDay.rounded())
        guard pickups >= 1 else { return "Last \(days) days" }
        return "\(pickups) pickups a day · last \(days) days"
    }
}

/// Apple's `Label(token)` is a fixed 32pt with artwork filling ~2/3 of that, so this measures
/// and scales past the padding. Duplicates `TokenTile` from the app since `Furlough/Views`
/// isn't in this extension's sources; move it to `Shared/UI` if the two need to agree on more.
private struct ReportTile: View {
    let entry: UsageEntry
    var size: CGFloat = 34
    @State private var natural = CGSize.zero
    /// App icon fills 0.655 of Apple's 32pt view; everything else runs edge to edge. Measured
    /// value mirrored from `TokenTile.artworkFraction` in the app.
    private var artworkFraction: CGFloat { entry.applicationToken != nil ? 0.655 : 1 }

    private var hasToken: Bool { entry.applicationToken != nil || entry.webDomainToken != nil }

    var body: some View {
        if hasToken {
            let longest = max(natural.width, natural.height)
            let scale = longest > 0 ? size / (longest * artworkFraction) : 1
            icon
                .labelStyle(.iconOnly)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
                .scaleEffect(scale)
                .frame(width: size, height: size)
        } else {
            // Screen Time counted it but handed over no token, so there is no artwork to draw.
            Image(systemName: entry.key.hasPrefix("web:") ? "globe" : "square.dashed")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(Ember.amber)
                .frame(width: size, height: size)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                )
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let token = entry.applicationToken {
            Label(token)
        } else if let token = entry.webDomainToken {
            Label(token)
        }
    }
}

extension View {
    /// Furlough's own ground behind the card, so text reads regardless of what the host paints.
    func reportCard() -> some View {
        background(Ember.ground.opacity(0.92), in: RoundedRectangle(cornerRadius: Ember.cardRadius, style: .continuous))
            .emberCard()
    }
}
