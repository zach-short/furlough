import SwiftUI

/// A typed site gets only its hours enforced — no daily limit, and iOS shows its own "Website
/// Not Allowed" page instead of Furlough's shield. A site picked via Apple's picker gets both.
struct AddSiteSheet: View {
    /// Dismisses the sheet; the caller opens the picker guide once it's fully gone.
    let onUsePicker: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    @State private var text = ""
    @State private var outcome: AppModel.AddHostOutcome?
    /// Seeded near the real content height so the sheet doesn't resize on open.
    @State private var contentHeight: CGFloat = 430

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
                        // Return submits, so a separate Done button is needed to dismiss the keyboard.
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { typing = false }
                            }
                        }
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
        // Cleared only on success; a rejected entry stays in the field for correction.
        if case .added = result {
            text = ""
            typing = true
        }
    }
}
