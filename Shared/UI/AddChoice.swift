import SwiftUI

/// What the + button asks before anything is picked: an app or a website.
enum AddChoice: Hashable, CaseIterable {
    case application
    case website
}

/// A trip to Apple's picker, and what to do with what it comes back with.
///
/// The two callers want opposite things from the same picker. The + button shows the whole
/// selection and reads the answer as the whole truth, so anything unpicked is a removal. The
/// companion nudge shows an empty one and asks a single question — "which app is this?" — so
/// nothing may be removed on the strength of it, and what comes back is added beside the
/// target that asked, wearing that target's rule.
struct AddRequest: Hashable {
    var choice: AddChoice
    /// Set when the nudge on a target asked, rather than the + button.
    var companion: Companion?

    struct Companion: Hashable {
        /// The target whose other half this is: the one whose rule the new one inherits.
        var targetID: UUID
        /// What the companions table calls the app, so it can be named before iOS ever names
        /// it. Empty when several were picked and no single name fits.
        var title: String
    }

    static func plain(_ choice: AddChoice) -> AddRequest { AddRequest(choice: choice) }

    static func companion(_ choice: AddChoice, of targetID: UUID, titled title: String) -> AddRequest {
        AddRequest(choice: choice, companion: Companion(targetID: targetID, title: title))
    }
}

/// The little popover under the + button: Application or Website, each with one line saying
/// what it means on this platform. Whoever shows it decides what happens next: on the phone
/// both open Apple's picker, on the Mac they open different sheets.
struct AddChoicePopover: View {
    let applicationCaption: String
    let websiteCaption: String
    let onPick: (AddChoice) -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(.application, symbol: "square.grid.2x2.fill", title: "Application", caption: applicationCaption)
            Rectangle()
                .fill(Ember.cardBorder)
                .frame(height: 1)
                .padding(.horizontal, 14)
            row(.website, symbol: "globe", title: "Website", caption: websiteCaption)
        }
        .padding(.vertical, 6)
        .frame(width: 268)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ choice: AddChoice, symbol: String, title: String, caption: String) -> some View {
        Button {
            onPick(choice)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ember.amber)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Ember.tileRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Ember.tileRadius, style: .continuous).strokeBorder(Ember.cardBorder, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .emberDisplaySmall(14)
                        .foregroundStyle(Ember.cream)
                    Text(caption)
                        .emberBody(11.5)
                        .foregroundStyle(Ember.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ember.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(AddChoiceRowStyle())
        .accessibilityLabel(title)
        .accessibilityHint(caption)
    }
}

/// A row that lights up faintly while pressed, and under the pointer on the Mac.
private struct AddChoiceRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.white.opacity(configuration.isPressed ? 0.1 : hovering ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.horizontal, 6)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
