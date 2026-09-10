import FamilyControls
import SwiftUI

/// The first run: the promise, the question, the ask.
///
/// Three panes, and the middle one is the point. Furlough is two things — Rules, which are hours
/// and budgets and a delay on anything that hands time back, and the Anchor, which is one tap and
/// a physical tag as the only key. The intro used to name both and then hand everyone the same
/// app, built around Rules, with the Anchor a card someone had to find. So the second pane asks
/// which half you came for, and the answer is what the app opens on and which guide runs. The
/// two panes that used to explain a half each are gone: every sentence on them now lands inside
/// the guide step it describes, where it can be acted on rather than read and forgotten.
///
/// The ask is last and on its own, because both halves are enforced by Screen Time and because
/// the gentler first week starts the moment access is granted, which is a thing to be told
/// immediately before granting it rather than two screens earlier.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var requesting = false
    @State private var pane: Pane = .promise
    /// The start pane's answer, held until Continue. The Anchor leads: it is the half nobody
    /// was being offered, and a preselected first row asks the question without putting a dead
    /// button under it.
    @State private var chosen: Half = .anchor
    @State private var wantsBoth = false

    /// The panes in order. `access` carries the button; the other two carry Continue.
    private enum Pane: Int, CaseIterable {
        case promise, start, access

        var next: Pane? { Pane(rawValue: rawValue + 1) }
        var previous: Pane? { Pane(rawValue: rawValue - 1) }

        /// Every pane has one, so the button sits at the same height on all three.
        var footnote: String {
            switch self {
            case .promise: "Screen Time access is asked for at the end, once you know what for."
            case .start: "Nothing is decided here. Both halves are a swipe apart afterwards, whichever you pick."
            case .access: "You can turn this off any time in Settings > Screen Time."
            }
        }
    }

    var body: some View {
        ZStack {
            EmberWall()
            VStack(alignment: .leading, spacing: 0) {
                // A pager rather than a switch, so the panes can be swiped as well as stepped
                // through. Selection is the same `pane` the dots and the buttons read, so the
                // two ways of moving cannot disagree. The mark rides inside each page, which is
                // what makes a swipe carry the whole screen rather than slide the words out
                // from under a mark that stayed put.
                TabView(selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { pane in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                mark(for: pane)
                                    .padding(.top, 8)
                                content(for: pane)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(pane)
                    }
                }
                // The pager's own dots would sit over the button and count in the wrong style,
                // so they are off and `PaneDots` below draws them beside Back.
                .tabViewStyle(.page(indexDisplayMode: .never))
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    // Only the footer animates on the pane changing; the pager runs its own
                    // transition, and a second one over the top of it stutters.
                    .animation(.snappy(duration: 0.28), value: pane)
            }
        }
        // A phone that has already been through the panes and had access refused comes back to
        // the ask rather than to page one. The intro is not the thing it is stuck on.
        .onAppear { if model.authorization == .denied { pane = .access } }
        // The answer is committed on the way forward off the start pane, which is the one place
        // both ways of leaving it meet: Continue sets `pane` and so does a swipe. Going Back
        // does not commit, so a finger on its way somewhere else changes nothing.
        .onChange(of: pane) { old, new in
            guard old == .start, new.rawValue > Pane.start.rawValue else { return }
            model.chooseStart(half: chosen, both: wantsBoth)
        }
    }

    // MARK: The mark

    /// The glass on the panes about the whole app, and both marks together on the one that asks
    /// you to choose between them — the picture of the question, in the order the rows are in.
    /// Bare marks rather than the row tiles they wear elsewhere: glowing objects, no furniture.
    @ViewBuilder private func mark(for pane: Pane) -> some View {
        if pane == .start {
            HStack(spacing: 16) {
                AnchorShape()
                    .fill(chosen == .anchor ? Ember.ember : Ember.faint)
                    .frame(width: 72, height: 92)
                    .shadow(color: Ember.ember.opacity(chosen == .anchor ? 0.5 : 0), radius: 20)
                LivingHourglass(state: .open(level: 0.62, warned: false))
                    .compositingGroup()
                    .frame(width: 76, height: 100)
                    .shadow(color: Ember.amber.opacity(chosen == .rules ? 0.45 : 0), radius: 20)
                    .opacity(chosen == .rules ? 1 : 0.45)
            }
            .frame(height: 140)
            .animation(.snappy(duration: 0.25), value: chosen)
        } else {
            LivingHourglass(state: .open(level: 0.62, warned: false))
                .compositingGroup()
                .frame(width: 106, height: 140)
                .shadow(color: Ember.amber.opacity(0.45), radius: 24)
        }
    }

    // MARK: The panes

    @ViewBuilder private func content(for pane: Pane) -> some View {
        switch pane {
        case .promise: promise
        case .start: start
        case .access: access
        }
    }

    /// Both halves on one screen, named, with a row each. Whatever else is skipped, this is the
    /// screen that has to leave behind the fact that there are two of them.
    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Furlough", color: Ember.amber)
                .padding(.top, 30)
            Text("No unblock button.")
                .emberDisplay(34)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Two ways to put an app out of reach. Neither of them has a button that hands it back.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            // The Anchor first here and on the next pane, so the intro lists the two halves in
            // one order throughout and the row you read first is the row you land on.
            VStack(spacing: 0) {
                HalfRow(
                    title: "The Anchor",
                    detail: "One tap locks a list, or the whole phone. The only thing that lifts it is an NFC tag you paired and left somewhere else."
                ) {
                    AnchorGlyph(isAnchored: false)
                }
                CardDivider()
                HalfRow(
                    title: "Rules",
                    detail: "Allowed hours and a daily budget for the apps that eat your day. Tightening one applies at once; anything that gives you back time waits."
                ) {
                    HelpTile(symbol: "hourglass")
                }
            }
            .emberCard()
            .padding(.top, 18)
            Footnote(text: "Use either on its own. Neither one needs the other.")
                .padding(.top, 10)
        }
    }

    /// The question the app never asked. Two rows and a quieter third line; the answer sets the
    /// page Furlough opens on and the guide that runs on it. Tapping a row only selects it —
    /// Continue is what commits, and it is live from the moment the pane arrives, because a
    /// disabled button under a question is the thing this pass is removing from Home.
    private var start: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Two halves", color: Ember.amber)
                .padding(.top, 30)
            Text("Where do you want to start?")
                .emberDisplay(34)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Furlough opens on the half you pick and walks you through setting it up. The other one is one swipe away, whenever you want it.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            VStack(spacing: 0) {
                StartRow(
                    title: "The Anchor",
                    detail: "Lock a list, or the whole phone, in one tap. A tag you paired is the only way back.",
                    isOn: chosen == .anchor && !wantsBoth
                ) {
                    AnchorGlyph(isAnchored: false)
                } action: {
                    chosen = .anchor
                    wantsBoth = false
                }
                CardDivider()
                StartRow(
                    title: "Rules",
                    detail: "Give the apps that eat your day allowed hours and a daily budget.",
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
        }
        .animation(.snappy(duration: 0.25), value: chosen)
        .animation(.snappy(duration: 0.25), value: wantsBoth)
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "One thing to allow", color: Ember.amber)
                .padding(.top, 30)
            Text("Both run on Screen Time.")
                .emberDisplay(34)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Rules and the Anchor are both enforced by iOS rather than by Furlough. Allowing Screen Time access is what lets either of them shield an app. Furlough is never told which apps you picked.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text("Your first \(Furlough.trialDays) days are gentler: a loosening waits \(TimeFormat.delay(hours: Furlough.trialDelayHours)) instead, so nothing you try out can cost you a day. The week starts when you allow access, and it cannot be extended.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if model.authorization == .denied {
                Text("Screen Time access was denied. Turn it on in Settings > Screen Time > Apps with Screen Time Access > Furlough.")
                    .emberBody(12)
                    .foregroundStyle(Ember.ember)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            if !model.isAppGroupAvailable {
                Text("The App Group entitlement is missing, so the extensions cannot share state. Check signing in Xcode.")
                    .emberBody(12)
                    .foregroundStyle(Ember.ember)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: The footer

    private var footer: some View {
        VStack(spacing: 0) {
            PaneDots(count: Pane.allCases.count, index: pane.rawValue)
                .overlay(alignment: .leading) {
                    if let previous = pane.previous {
                        // withAnimation, because a page-style TabView slides for a gesture but
                        // jumps for a plain assignment, and the two ways forward should look
                        // like the same movement.
                        Button("Back") { withAnimation(.snappy(duration: 0.28)) { pane = previous } }
                            .emberBody(13, .semibold)
                            .foregroundStyle(Ember.muted)
                            .buttonStyle(.plain)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 14)
            if pane == .access {
                ProminentButton(
                    title: requesting ? "Waiting for iOS…" : "Allow Screen Time access",
                    isBusy: requesting
                ) {
                    Task {
                        requesting = true
                        await model.requestAuthorization()
                        await model.requestNotifications()
                        requesting = false
                    }
                }
                .disabled(requesting)
            } else {
                ProminentButton(title: "Continue") {
                    if let next = pane.next {
                        withAnimation(.snappy(duration: 0.28)) { pane = next }
                    }
                }
            }
            Footnote(text: pane.footnote, alignment: .center)
                .padding(.top, 12)
        }
    }
}

/// One half of the app on the promise pane: its mark, its name, and what it is in two lines.
private struct HalfRow<Icon: View>: View {
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

/// One half offered on the start pane: `HalfRow` with a tap and a chosen state. The mark keeps
/// its own colour when the row is not chosen — an anchor greyed out is a different anchor — and
/// the row says which it is with its border and its check.
private struct StartRow<Icon: View>: View {
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

/// Where you are in the intro. Ember for the pane you are on.
private struct PaneDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Ember.ember : Ember.cream.opacity(0.22))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}
