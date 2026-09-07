import FamilyControls
import SwiftUI

enum BrickRoute: Hashable {
    case editor
}

/// The Brick profile: apps locked behind a physical tag. Brick from here or from the home
/// card; unbrick only by scanning the paired tag.
struct BrickView: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var message: String?
    @State private var confirmForget = false

    private var brick: BrickProfile { model.state.config.brick }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                stateCard
                SectionLabel(text: "Apps")
                appsCard
                Footnote(text: brick.isBricked
                    ? "Unbrick with your tag to change the list."
                    : "Anything here is blocked while bricked. Windows and budgets still apply the rest of the time.")
                    .padding(.top, 8)
                SectionLabel(text: "Tag")
                tagCard
                Footnote(text: "Bricking works without the tag. Unbricking needs it, so keep the tag somewhere that makes you think.")
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
                Text("Brick")
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
        }
        .familyActivityPicker(
            headerText: "Choose what the brick locks",
            footerText: "Picking a category locks every app in it.",
            isPresented: $showPicker,
            selection: $selection
        )
        .onChange(of: showPicker) { _, presented in
            guard !presented else { return }
            model.setBrickSelection(selection)
        }
        .alert("Brick", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("Forget this tag?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget tag", role: .destructive) { model.unpairTag() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrickGlyph(isBricked: brick.isBricked, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Brick")
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
                Eyebrow(text: brick.isBricked ? "Bricked" : "Free", color: brick.isBricked ? Ember.ember : Ember.moss)
                Text(stateLine)
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
            }
            Spacer(minLength: 8)
            BrickToggleButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .emberCard()
    }

    private var stateLine: String {
        if brick.isBricked, let since = brick.brickedAt {
            return "\(count(brick.count)) since \(since.formatted(date: .omitted, time: .shortened))"
        }
        if brick.kinds.isEmpty { return "Nothing chosen yet" }
        if !brick.isPaired { return "\(count(brick.count)) · pair a tag to enable" }
        return "\(count(brick.count)) ready"
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if brick.kinds.isEmpty {
                Text("No apps yet.")
                    .emberBody(13)
                    .foregroundStyle(Ember.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Array(brick.kinds.enumerated()), id: \.offset) { _, kind in
                        TokenTile(kind: kind, size: 44)
                    }
                }
                .padding(12)
            }
            if !brick.isBricked {
                CardDivider()
                Button {
                    selection = model.brickSelection
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(brick.kinds.isEmpty ? "Choose apps" : "Change apps")
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
            HStack {
                Text("Paired tag")
                    .emberBody(13)
                    .foregroundStyle(Ember.cream)
                Spacer()
                Text(brick.tagID.map(tagLabel) ?? "None")
                    .emberBody(13)
                    .monospacedDigit()
                    .foregroundStyle(brick.isPaired ? Ember.moss : Ember.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            if !brick.isBricked {
                CardDivider()
                Button {
                    Task { await pair() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 12, weight: .bold))
                        Text(brick.isPaired ? "Replace tag" : "Pair a tag")
                            .emberBody(13, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if brick.isPaired {
                    CardDivider()
                    GhostButton(title: "Forget tag", color: Ember.muted) { confirmForget = true }
                }
            }
        }
        .emberCard()
    }

    private func pair() async {
        switch await model.pairTag() {
        case .paired: message = "Tag paired. Bricking is ready."
        case .failed(let reason): message = reason
        default: break
        }
    }

    private func tagLabel(_ id: Data) -> String {
        let hex = id.map { String(format: "%02X", $0) }.joined()
        return "Paired · …\(hex.suffix(4))"
    }

    private func count(_ n: Int) -> String {
        "\(n) \(n == 1 ? "item" : "items")"
    }
}

/// Brick when free, Unbrick (scan the tag) when bricked. Alerts explain a wrong tag or failure.
struct BrickToggleButton: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var message: String?

    private var brick: BrickProfile { model.state.config.brick }

    var body: some View {
        Group {
            if brick.isBricked {
                Button {
                    Task { await unbrick() }
                } label: {
                    Label("Unbrick", systemImage: "wave.3.right")
                        .emberBody(13, .bold)
                        .foregroundStyle(Ember.cream)
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    switch model.brick() {
                    case .failed(let reason): message = reason
                    default: break
                    }
                } label: {
                    Text("Brick")
                        .emberBody(13, .bold)
                        .foregroundStyle(Ember.cream)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .disabled(!brick.canBrick)
            }
        }
        .disabled(busy)
        .alert("Brick", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func unbrick() async {
        busy = true
        defer { busy = false }
        switch await model.unbrickWithTag() {
        case .wrongTag: message = "That is not the paired tag."
        case .failed(let reason): message = reason
        default: break
        }
    }
}

/// The home-screen entry to the Brick profile, with its state and the Brick / Unbrick button.
struct BrickCard: View {
    let brick: BrickProfile

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: BrickRoute.editor) {
                HStack(spacing: 10) {
                    BrickGlyph(isBricked: brick.isBricked, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Brick")
                                .emberDisplaySmall(13.5)
                                .foregroundStyle(Ember.cream)
                            Eyebrow(text: brick.isBricked ? "Bricked" : "Free", color: brick.isBricked ? Ember.ember : Ember.moss, size: 9)
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
            BrickToggleButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .emberCard()
    }

    private var subtitle: String {
        let items = "\(brick.count) \(brick.count == 1 ? "item" : "items")"
        if brick.kinds.isEmpty { return "Tap to choose apps and pair a tag" }
        if !brick.isPaired { return "\(items) · pair a tag to enable" }
        if brick.isBricked, let since = brick.brickedAt {
            return "\(items) · since \(since.formatted(date: .omitted, time: .shortened))"
        }
        return "\(items) · ready"
    }
}

/// A cube in a tile, ember while bricked.
struct BrickGlyph: View {
    let isBricked: Bool
    var size: CGFloat = 34

    var body: some View {
        let radius = size >= 44 ? Ember.tileRadiusLarge : Ember.tileRadius
        Image(systemName: "cube.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(isBricked ? Ember.ember : Ember.muted)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: isBricked ? Ember.ember.opacity(0.35) : .clear, radius: 10)
    }
}
