import SwiftUI

/// What Website means on the phone. iOS mints a web domain only inside Apple's picker, never
/// from an address typed here, and the sites sit below the apps in every category — three
/// levels down, where nobody finds them by accident. This says where to look before the
/// picker opens; the picker's own footer says it again once you are in there.
struct AddWebsiteGuideView: View {
    /// Hand over to Apple's picker. The sheet dismisses itself; the caller opens the picker
    /// once this one is fully gone.
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// The sheet hugs its content. Seeded near the real height so it does not resize on open.
    @State private var contentHeight: CGFloat = 470

    private static let steps: [(title: String, detail: String)] = [
        ("Open a category", "Social, Entertainment, whichever one the site belongs to."),
        ("Scroll past its apps", "Websites are the last section, under the whole app list."),
        ("Tap Add Website", "Type the address. It lands on Home with its own windows and budget."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "globe")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Ember.amber)
                    .frame(width: 56, height: 56)
                    .background(
                        Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: Ember.tileRadiusLarge, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Ember.tileRadiusLarge, style: .continuous)
                            .strokeBorder(Ember.cardBorder, lineWidth: 1)
                    )
                Text("Websites live inside Apple's picker")
                    .emberDisplay(26)
                    .foregroundStyle(Ember.cream)
                    .padding(.top, 18)
                Text("iOS hands out a website only through the same picker as the apps, so Furlough cannot take an address of its own. It is three steps in.")
                    .emberBody(14.5)
                    .foregroundStyle(Ember.muted)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        if index > 0 { CardDivider() }
                        StepRow(number: index + 1, title: step.title, detail: step.detail)
                    }
                }
                .emberCard()
                .padding(.top, 20)
                ProminentButton(title: "Open the picker") {
                    onContinue()
                    dismiss()
                }
                .padding(.top, 22)
                Footnote(text: "The picker repeats this in its footer.", alignment: .center)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(EmberWall())
        .presentationBackground(Ember.ground)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }
}

/// One numbered step: an amber numeral, the move to make and what to look for.
private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(EmberFont.numerals(13))
                .monospacedDigit()
                .foregroundStyle(Ember.amber)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().strokeBorder(Ember.cardBorder, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .emberDisplaySmall(14)
                    .foregroundStyle(Ember.cream)
                Text(detail)
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }
}
