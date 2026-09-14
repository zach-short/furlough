import SwiftUI

struct MacOnboardingView: View {
    @Environment(MacModel.self) private var model
    @State private var requesting = false
    @State private var pane = Pane.promise
    @State private var chosen: Half = .anchor
    @State private var wantsBoth = false

    private enum Pane { case promise, start }

    var body: some View {
        ZStack {
            EmberWall()
            HStack(spacing: 40) {
                mark
                    .frame(width: 170, height: 200)
                ScrollView(.vertical) {
                    Group {
                        switch pane {
                        case .promise: promise
                        case .start: start
                        }
                    }
                    .frame(maxWidth: 460, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: 460)
            }
            .padding(40)
        }
    }

    @ViewBuilder private var mark: some View {
        if pane == .start {
            HStack(spacing: 16) {
                AnchorShape()
                    .fill(chosen == .anchor ? Ember.ember : Ember.faint)
                    .frame(width: 78, height: 100)
                    .shadow(color: Ember.ember.opacity(chosen == .anchor ? 0.5 : 0), radius: 24)
                LivingHourglass(state: .open(level: 0.62, warned: false))
                    .compositingGroup()
                    .frame(width: 82, height: 108)
                    .shadow(color: Ember.amber.opacity(chosen == .rules ? 0.45 : 0), radius: 24)
                    .opacity(chosen == .rules ? 1 : 0.45)
            }
            .animation(.snappy(duration: 0.25), value: chosen)
        } else {
            LivingHourglass(state: .open(level: 0.62, warned: false))
                .compositingGroup()
                .frame(width: 150, height: 200)
                .shadow(color: Ember.amber.opacity(0.45), radius: 32)
        }
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Furlough for Mac", color: Ember.amber)
            Text("No unblock button.")
                .emberDisplay(36)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Two ways to put an app out of reach. Neither of them has a button that hands it back.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            VStack(spacing: 0) {
                MacHalfRow(
                    title: "The Anchor",
                    detail: "One click locks a list, or every app on this Mac. The only thing that lifts it is the tag you paired on your iPhone."
                ) {
                    AnchorGlyph(isAnchored: false)
                }
                CardDivider()
                MacHalfRow(
                    title: "Rules",
                    detail: "Allowed windows and a daily budget for the apps and websites that eat your time. Tightening one applies at once; anything that gives you back time waits."
                ) {
                    HelpTile(symbol: "hourglass")
                }
            }
            .emberCard()
            .padding(.top, 18)
            Footnote(text: "Use either on its own. Neither one needs the other.")
                .padding(.top, 10)
            Text("The Mac has no Screen Time API for apps like this, so Furlough quits blocked apps itself and macOS will ask once per browser whether it may read the address bar. Furlough opens at login and refuses to quit while something is blocked; Force Quit is the one escape.")
                .emberBody(12.5)
                .foregroundStyle(Ember.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            HStack(spacing: 10) {
                Button(requesting ? "Asking…" : "Start") {
                    Task {
                        requesting = true
                        await model.requestNotifications()
                        requesting = false
                        withAnimation(.snappy(duration: 0.25)) { pane = .start }
                    }
                }
                .emberGlassButton(prominent: true, tint: Ember.ember)
                .controlSize(.large)
                .disabled(requesting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Two halves", color: Ember.amber)
            Text("Where do you want to start?")
                .emberDisplay(36)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Furlough opens on the half you pick and walks you through setting it up. The other one is one click away, whenever you want it.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            VStack(spacing: 0) {
                MacStartRow(
                    title: "The Anchor",
                    detail: "Lock a list, or every app on this Mac, in one click. Your iPhone's tag is the only way back.",
                    isOn: chosen == .anchor && !wantsBoth
                ) {
                    AnchorGlyph(isAnchored: false)
                } action: {
                    chosen = .anchor
                    wantsBoth = false
                }
                CardDivider()
                MacStartRow(
                    title: "Rules",
                    detail: "Give the apps and websites that eat your time allowed windows and a daily budget.",
                    isOn: chosen == .rules && !wantsBoth
                ) {
                    HelpTile(symbol: "hourglass")
                } action: {
                    chosen = .rules
                    wantsBoth = false
                }
            }
            .emberCard()
            .padding(.top, 18)
            Button {
                chosen = .anchor
                wantsBoth = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: wantsBoth ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Both, the Anchor first")
                        .emberBody(13, .semibold)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(wantsBoth ? Ember.ember : Ember.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityAddTraits(wantsBoth ? .isSelected : [])
            Footnote(text: "Nothing is decided here. Both halves are one click apart afterwards, whichever you pick.")
                .padding(.top, 10)
            HStack(spacing: 10) {
                Button(wantsBoth ? "Start with the Anchor" : "Start with \(chosen == .anchor ? "the Anchor" : "Rules")") {
                    model.chooseStart(half: chosen, both: wantsBoth)
                    model.finishOnboarding()
                }
                .emberGlassButton(prominent: true, tint: Ember.ember)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Button("Back") {
                    withAnimation(.snappy(duration: 0.25)) { pane = .promise }
                }
                .emberGlassButton()
                .controlSize(.large)
            }
            .padding(.top, 24)
        }
        .animation(.snappy(duration: 0.25), value: chosen)
        .animation(.snappy(duration: 0.25), value: wantsBoth)
    }
}


private struct MacHalfRow<Icon: View>: View {
    let title: String
    let detail: String
    let icon: Icon

    init(title: String, detail: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.detail = detail
        self.icon = icon()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct MacStartRow<Icon: View>: View {
    let title: String
    let detail: String
    let isOn: Bool
    let icon: Icon
    let action: () -> Void

    init(
        title: String,
        detail: String,
        isOn: Bool,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.icon = icon()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .emberDisplaySmall(14)
                        .foregroundStyle(Ember.cream)
                    Text(detail)
                        .emberBody(12)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? Ember.ember : Ember.cream.opacity(0.22))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(isOn ? Ember.ember.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
