import SwiftUI

/// The first run: the promise, and the question.
///
/// Two panes, and the second one is the point. Furlough is two things — Rules, which are hours
/// and budgets and a delay on anything that hands time back, and the Anchor, which is one click
/// and your phone's tag as the only key. This screen used to name both and then hand everyone
/// the same window, built around Rules, with the Anchor a padlock somebody had to find. So the
/// second pane asks which half you came for, and the answer is what the window opens on and
/// which guide runs. The pane that used to explain the Anchor is gone: every sentence on it now
/// lands inside the guide step it describes, where it can be acted on rather than read once.
///
/// The web filter used to be a third pane here, and it is gone. It does nothing until some
/// website is blocked, so asking for a trip to System Settings before there is a single rule
/// charged everybody up front for something most people would never need — and anyone who only
/// blocks applications was answering for a feature that could not do anything for them. It is
/// offered at the first website instead; see `WebFilterOfferSheet`.
struct MacOnboardingView: View {
    @Environment(MacModel.self) private var model
    @State private var requesting = false
    @State private var pane = Pane.promise
    /// The start pane's answer, held until Continue. The Anchor leads: it is the half nobody was
    /// being offered, and a preselected first row asks the question without putting a dead button
    /// under it.
    @State private var chosen: Half = .anchor
    @State private var wantsBoth = false

    private enum Pane { case promise, start }

    var body: some View {
        ZStack {
            EmberWall()
            HStack(spacing: 40) {
                mark
                    .frame(width: 170, height: 200)
                // Scrolls so a pane taller than a short window is still reachable rather than
                // cut off at the bottom.
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

    /// The glass on the panes about the whole app, and both marks together on the one that asks
    /// you to choose between them — the picture of the question, in the order the rows are in.
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

    /// Both halves on one screen, named, with a row each. Whatever else is skipped, this is the
    /// screen that has to leave behind the fact that there are two of them.
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
            // The Anchor first here and on the next pane, so the intro lists the two halves in
            // one order throughout and the row you read first is the row you land on.
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
            // The one thing about this Mac that has to be said before anything is agreed to: it
            // enforces by hand because there is no Screen Time API here, which is why it has to
            // keep running and why Force Quit is the way out.
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
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .controlSize(.large)
                .disabled(requesting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)
        }
    }

    /// The question the app never asked. Two rows and a quieter third line; the answer sets the
    /// half the window opens on and the guide that runs in it. Clicking a row only selects it —
    /// Continue is what commits, and it is live from the moment the pane arrives.
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
            // Quieter and outside the card, because it is not a third thing to be — it is the
            // two above, in the order they are in.
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
                // The last button of the first run now that the filter pane has gone, so it says
                // where it lands rather than "Continue", which promised another pane.
                Button(wantsBoth ? "Start with the Anchor" : "Start with \(chosen == .anchor ? "the Anchor" : "Rules")") {
                    // Committed on the way forward rather than on each click, so backing out and
                    // coming at it again does not leave a half chosen by a mouse on its way
                    // somewhere else.
                    model.chooseStart(half: chosen, both: wantsBoth)
                    model.finishOnboarding()
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Button("Back") {
                    withAnimation(.snappy(duration: 0.25)) { pane = .promise }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.top, 24)
        }
        .animation(.snappy(duration: 0.25), value: chosen)
        .animation(.snappy(duration: 0.25), value: wantsBoth)
    }
}


/// One half of the app on the promise pane: its mark, its name, and what it is in two lines.
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

/// One half offered on the start pane: `MacHalfRow` with a click and a chosen state. The mark
/// keeps its own colour when the row is not chosen — an anchor greyed out is a different anchor
/// — and the row says which it is with its tint and its check.
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
