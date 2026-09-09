import FamilyControls
import SwiftUI

enum AnchorRoute: Hashable {
    case editor
}

/// The Anchor profile: apps locked behind a physical tag. Anchor from here or from the home
/// card; weigh anchor only by scanning one of the paired tags.
struct AnchorView: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var message: String?
    @State private var forgetting: PairedTag?
    @State private var renaming: PairedTag?
    @State private var draftName = ""

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var anchorCaution: (text: String, isSevere: Bool)? { model.anchorCaution }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                stateCard
                SectionLabel(text: "Apps")
                appsCard
                if let caution = anchorCaution {
                    CautionBanner(text: caution.text, isSevere: caution.isSevere)
                        .padding(.top, 12)
                }
                Footnote(text: anchor.isAnchored
                    ? "Unanchor with your tag to change the list."
                    : "Anything here is blocked while anchored. Windows and budgets still apply the rest of the time.")
                    .padding(.top, 8)
                SectionLabel(text: "Tags")
                tagCard
                Footnote(text: tagFootnote)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
        .background(EmberWall())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Anchor")
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
        }
        .familyActivityPicker(
            headerText: "Choose what the anchor holds",
            footerText: "Picking a category locks every app in it.",
            isPresented: $showPicker,
            selection: $selection
        )
        .onChange(of: showPicker) { _, presented in
            guard !presented else { return }
            model.setAnchorSelection(selection)
        }
        .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Forget this tag?",
            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget \(forgetting?.name ?? "tag")", role: .destructive) {
                if let tag = forgetting { model.unpairTag(id: tag.id) }
                forgetting = nil
            }
            Button("Keep it", role: .cancel) { forgetting = nil }
        } message: {
            Text(anchor.tags.count == 1
                ? "This is the last key. Anchoring is refused until you pair another."
                : "The other tags still release the anchor.")
        }
        .alert(
            "Name this tag",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Home", text: $draftName)
            Button("Save") {
                if let tag = renaming { model.renameTag(id: tag.id, to: draftName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Name it for the place it lives in, so you know which key you are looking for.")
        }
    }

    private var tagFootnote: String {
        let cap = "Up to \(Furlough.maxAnchorTags), so a key can live at each place you do."
        return "Anchoring works without a tag. Weighing anchor needs one, so keep every tag somewhere that makes you think. \(cap)"
    }

    private var header: some View {
        HStack(spacing: 12) {
            AnchorGlyph(isAnchored: anchor.isAnchored, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Anchor")
                    .emberDisplay(19)
                    .foregroundStyle(Ember.cream)
                Text("One tap to lock. The tag to unlock.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var stateCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: anchor.isAnchored ? "Anchored" : "Free", color: anchor.isAnchored ? Ember.ember : Ember.moss)
                Text(stateLine)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
            }
            Spacer(minLength: 8)
            AnchorToggleButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .emberCard()
    }

    private var stateLine: String {
        if anchor.isAnchored, let since = anchor.anchoredAt {
            return "\(count(anchor.count)) since \(since.formatted(date: .omitted, time: .shortened))"
        }
        if anchor.kinds.isEmpty { return "Nothing chosen yet" }
        if !anchor.isPaired { return "\(count(anchor.count)) · pair a tag to enable" }
        return "\(count(anchor.count)) ready"
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if anchor.kinds.isEmpty {
                Text("No apps yet.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Array(anchor.kinds.enumerated()), id: \.offset) { _, kind in
                        TokenTile(kind: kind, size: 44)
                    }
                }
                .padding(12)
            }
            if !anchor.isAnchored {
                CardDivider()
                Button {
                    selection = model.anchorSelection
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(anchor.kinds.isEmpty ? "Choose apps" : "Change apps")
                            .emberBody(13, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .emberCard()
    }

    private var tagCard: some View {
        VStack(spacing: 0) {
            if anchor.tags.isEmpty {
                HStack {
                    Text("None paired")
                        .emberBody(13)
                        .foregroundStyle(Ember.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            } else {
                ForEach(Array(anchor.tags.enumerated()), id: \.element.id) { index, tag in
                    if index > 0 { CardDivider() }
                    tagRow(tag)
                }
            }
            if !anchor.isAnchored {
                CardDivider()
                if anchor.canPairMore {
                    Button {
                        Task { await pair() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wave.3.right")
                                .font(.system(size: 12, weight: .bold))
                            Text(anchor.isPaired ? "Pair another tag" : "Pair a tag")
                                .emberBody(13, .semibold)
                            Spacer(minLength: 8)
                            Text(tagCount)
                                .emberBody(11.5)
                                .monospacedDigit()
                                .foregroundStyle(Ember.muted)
                        }
                        .foregroundStyle(Ember.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text("\(tagCount) · forget one to pair another")
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
            }
        }
        .emberCard()
    }

    /// One key: what it is called, what it is, and the way to change either. Both controls are
    /// gone while anchored, like the app list above them.
    private func tagRow(_ tag: PairedTag) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                    .lineLimit(1)
                Text(tagLabel(tag.id))
                    .emberBody(11)
                    .monospacedDigit()
                    .foregroundStyle(Ember.muted)
            }
            Spacer(minLength: 8)
            if !anchor.isAnchored {
                Button {
                    draftName = tag.name
                    renaming = tag
                } label: {
                    Text("Rename")
                        .emberBody(12, .semibold)
                        .foregroundStyle(Ember.ember)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    forgetting = tag
                } label: {
                    Text("Forget")
                        .emberBody(12, .semibold)
                        .foregroundStyle(Ember.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var tagCount: String { "\(anchor.tags.count) of \(Furlough.maxAnchorTags)" }

    private func pair() async {
        switch await model.pairTag() {
        // Straight into the name: an identifier's last four digits are not a place, and the
        // scan is done, so nothing is waiting on the typing.
        case .paired(let tag):
            draftName = ""
            renaming = tag
        case .failed(let reason): message = reason
        default: break
        }
    }

    private func tagLabel(_ id: Data) -> String {
        let hex = id.map { String(format: "%02X", $0) }.joined()
        return "…\(hex.suffix(4))"
    }

    private func count(_ n: Int) -> String {
        "\(n) \(n == 1 ? "item" : "items")"
    }
}

/// Anchor when free, Unanchor (scan the tag to release it) when anchored. Alerts explain a wrong tag or failure.
struct AnchorToggleButton: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var message: String?
    @State private var confirmAnchor = false

    private var anchor: AnchorProfile { model.state.config.anchor }
    private var caution: (text: String, isSevere: Bool)? { model.anchorCaution }

    var body: some View {
        Group {
            if anchor.isAnchored {
                Button {
                    Task { await unanchor() }
                } label: {
                    Label("Unanchor", systemImage: "wave.3.right")
                        .emberBody(13, .bold)
                        .foregroundStyle(Ember.cream)
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    if caution != nil { confirmAnchor = true } else { drop() }
                } label: {
                    Text("Anchor")
                        .emberBody(13, .bold)
                        .foregroundStyle(Ember.cream)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .disabled(!anchor.canAnchor)
            }
        }
        .disabled(busy)
        .confirmationDialog(
            "Anchor this?",
            isPresented: $confirmAnchor,
            titleVisibility: .visible
        ) {
            Button("Anchor anyway", role: .destructive) { drop() }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text(caution?.text ?? "")
        }
        .alert("Anchor", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func drop() {
        switch model.anchor() {
        case .failed(let reason): message = reason
        default: break
        }
    }

    private func unanchor() async {
        busy = true
        defer { busy = false }
        switch await model.unanchorWithTag() {
        case .wrongTag: message = "That is not a paired tag."
        case .failed(let reason): message = reason
        default: break
        }
    }
}

/// The home-screen entry to the Anchor profile, with its state and the Anchor / Unanchor button.
struct AnchorCard: View {
    let anchor: AnchorProfile

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: AnchorRoute.editor) {
                HStack(spacing: 10) {
                    AnchorGlyph(isAnchored: anchor.isAnchored, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Anchor")
                                .emberDisplaySmall(13.5)
                                .foregroundStyle(Ember.cream)
                            Eyebrow(text: anchor.isAnchored ? "Anchored" : "Free", color: anchor.isAnchored ? Ember.ember : Ember.moss, size: 9)
                        }
                        Text(subtitle)
                            .emberBody(11.5)
                            .foregroundStyle(Ember.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            AnchorToggleButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .emberCard()
    }

    private var subtitle: String {
        let items = "\(anchor.count) \(anchor.count == 1 ? "item" : "items")"
        if anchor.kinds.isEmpty { return "Tap to choose apps and pair a tag" }
        if !anchor.isPaired { return "\(items) · pair a tag to enable" }
        if anchor.isAnchored, let since = anchor.anchoredAt {
            return "\(items) · since \(since.formatted(date: .omitted, time: .shortened))"
        }
        return "\(items) · ready"
    }
}

/// The anchor in a tile, ember while anchored.
struct AnchorGlyph: View {
    let isAnchored: Bool
    var size: CGFloat = 34

    var body: some View {
        let radius = size >= 44 ? Ember.tileRadiusLarge : Ember.tileRadius
        AnchorShape()
            .fill(isAnchored ? Ember.ember : Ember.muted)
            .frame(width: size * 0.52, height: size * 0.52)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: isAnchored ? Ember.ember.opacity(0.35) : .clear, radius: 10)
    }
}
