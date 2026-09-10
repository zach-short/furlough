import FamilyControls
import SwiftUI

/// The first run: four panes, then the ask.
///
/// It is four rather than one because Furlough is two things and used to introduce only one of
/// them. Rules — hours, budgets, the delay — are the everyday half, and the Anchor is the other:
/// one tap, the whole phone if you want it, and a physical tag as the only key. Someone who came
/// for a tag-and-lock app used to meet three paragraphs about minute budgets and had to find the
/// Anchor on their own, from a card on Home. Now each half gets a pane and its own mark, and the
/// promise that covers both — no unblock button — is what opens.
///
/// The ask is last and on its own, because both halves are enforced by Screen Time and because
/// the gentler first week starts the moment access is granted, which is a thing to be told
/// immediately before granting it rather than three screens earlier.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var requesting = false
    @State private var pane: Pane = .promise

    /// The panes in order. `access` carries the button; the other three carry Continue.
    private enum Pane: Int, CaseIterable {
        case promise, rules, anchor, access

        var next: Pane? { Pane(rawValue: rawValue + 1) }
        var previous: Pane? { Pane(rawValue: rawValue - 1) }

        /// Every pane has one, so the button sits at the same height on all four.
        var footnote: String {
            switch self {
            case .promise: "Screen Time access is asked for at the end, once you know what for."
            case .rules: "Adding an app enforces nothing on its own. Saving its first rule is what starts it."
            case .anchor: "The Anchor is optional, and nothing else in Furlough depends on it."
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
    }

    // MARK: The mark

    /// The glass for the three panes it belongs to, the anchor for the one it does not. The
    /// Anchor's pane wearing the app's hourglass would be the same demotion in a picture.
    @ViewBuilder private func mark(for pane: Pane) -> some View {
        if pane == .anchor {
            // The bare mark rather than the row tile it wears elsewhere, so it stands here the
            // way the hourglass stands on the other three: one glowing object, no furniture.
            AnchorShape()
                .fill(Ember.ember)
                .frame(width: 100, height: 128)
                .shadow(color: Ember.ember.opacity(0.5), radius: 24)
                .frame(width: 106, height: 140)
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
        case .rules: rules
        case .anchor: anchor
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
            VStack(spacing: 0) {
                HalfRow(
                    title: "Rules",
                    detail: "Allowed hours and a daily budget for the apps that eat your day. Tightening one applies at once; anything that gives you back time waits."
                ) {
                    HelpTile(symbol: "hourglass")
                }
                CardDivider()
                HalfRow(
                    title: "The Anchor",
                    detail: "One tap locks a list, or the whole phone. The only thing that lifts it is an NFC tag you paired and left somewhere else."
                ) {
                    AnchorGlyph(isAnchored: false)
                }
            }
            .emberCard()
            .padding(.top, 18)
            Footnote(text: "Use either on its own. Neither one needs the other.")
                .padding(.top, 10)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "The everyday half", color: Ember.amber)
                .padding(.top, 30)
            Text("By the clock.")
                .emberDisplay(34)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Pick the apps and websites that eat your time. Give each one a minute budget, and allowed windows if you want them, the same every day or different on weekends. Once the budget is spent, or outside the windows, iOS shields the app.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text("Tightening a rule applies instantly. Loosening one waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)), and you can cancel it while it does.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text("The shield says which app is closed and when it opens next. There is nothing else on it.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private var anchor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "The other half", color: Ember.ember)
                .padding(.top, 30)
            Text("One tap. Then the tag.")
                .emberDisplay(34)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("The Anchor is a separate list you lock in one tap, from anywhere — or turn inside out, so every app on the phone is shielded and the list is what stays open. No delay applies, because anchoring only ever takes things away.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text("What lifts it is holding your phone to an NFC tag you paired. Any NTAG sticker works, and so does the tag that came with another blocking product. Leave it at home and the phone stays anchored until you are back.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text("It can also drop on a schedule you set, and it carries to Furlough on your Mac.")
                .emberBody(15)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
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
