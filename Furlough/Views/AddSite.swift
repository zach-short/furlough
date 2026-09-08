import SwiftUI

/// Adding a website by typing it, which since 2026-09-08 is what Website means on the phone.
///
/// It used to mean Apple's picker and nothing else, because a `WebDomainToken` can only be
/// minted in there — three levels down, under every app in a category. But
/// `WebContentSettings.blockedByFilter` takes a plain host string, so Furlough can take one
/// too, and the phone now does what the Mac always has.
///
/// The two are not the same thing and this sheet says so rather than letting them look alike.
/// A typed site gets its hours enforced and nothing else: nothing counts it, so it has no
/// daily limit, and iOS covers it with its own "Website Not Allowed" page instead of
/// Furlough's shield. The picker's version has both. Typing is offered first because it is the
/// thing wanted nine times in ten; the other is one line away.
struct AddSiteSheet: View {
    /// Hand over to Apple's picker instead. The sheet dismisses itself; the caller opens the
    /// guide once this one is fully gone.
    let onUsePicker: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    @State private var text = ""
    @State private var outcome: AppModel.AddHostOutcome?
    /// The sheet hugs its content. Seeded near the real height so it does not resize on open.
    @State private var contentHeight: CGFloat = 430

    /// What Furlough would call it, so the button can say the thing it is about to add rather
    /// than whatever was typed: "https://www.YouTube.com/feed" reads back as "youtube.com".
    private var host: String? { Hosts.normalize(text) }

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
                Text("Add a website")
                    .emberDisplay(26)
                    .foregroundStyle(Ember.cream)
                    .padding(.top, 18)
                Text("Type the address. Furlough blocks it and every subdomain outside its hours, in every browser on this phone.")
                    .emberBody(14.5)
                    .foregroundStyle(Ember.muted)
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    TextField("youtube.com", text: $text)
                        .emberBody(15)
                        .foregroundStyle(Ember.cream)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .focused($typing)
                        .onSubmit(add)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                }
                .emberCard()
                .padding(.top, 20)

                if let message {
                    Text(message)
                        .emberBody(12)
                        .foregroundStyle(tone)
                        .padding(.top, 10)
                        .padding(.horizontal, 2)
                }

                ProminentButton(title: host.map { "Add \($0)" } ?? "Add") { add() }
                    .disabled(host == nil)
                    .opacity(host == nil ? 0.4 : 1)
                    .padding(.top, 18)

                CardDivider()
                    .padding(.top, 22)

                Button {
                    onUsePicker()
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Want a daily time limit on a site?")
                            .emberBody(12.5, .semibold)
                            .foregroundStyle(Ember.ember)
                        Text("Only sites picked from Apple's own list can be counted, and only those get Furlough's shield. It is a few steps further in.")
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
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
        .onAppear { typing = true }
    }

    /// What just happened, or what is wrong with what has been typed so far. Silent while the
    /// field is empty: nothing has gone wrong yet.
    private var message: String? {
        switch outcome {
        case .added(let host): "\(host) added. Give it hours on Home; nothing is blocked until you do."
        case .already(let name): "\(name) is already here. Open it on Home to change its hours."
        case .unreadable: "That is not an address Furlough can read. Try something like youtube.com."
        case nil: nil
        }
    }

    private var tone: Color {
        if case .added = outcome { return Ember.moss }
        return Ember.pending
    }

    private func add() {
        guard host != nil else { return }
        let result = model.addHost(text)
        outcome = result
        // Cleared only on success, so a second site can be typed straight after; a rejected
        // one is left in the field to be corrected rather than retyped.
        if case .added = result {
            text = ""
            typing = true
        }
    }
}
