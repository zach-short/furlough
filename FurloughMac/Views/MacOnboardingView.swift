import SwiftUI

/// Three panes. The first is the promise, the second is the Anchor, and the third offers the
/// web filter, which is the one thing on the Mac that needs the person's hand in System
/// Settings, so it is asked for here rather than found later.
///
/// The Anchor has a pane of its own because Furlough is two things and this screen used to
/// introduce one of them. Someone who came for a tag-and-lock app met three paragraphs about
/// minute budgets and had to find the Anchor in a sheet on their own.
struct MacOnboardingView: View {
    @Environment(MacModel.self) private var model
    @State private var requesting = false
    @State private var step = Step.promise

    private enum Step { case promise, anchor, filter }

    var body: some View {
        ZStack {
            EmberWall()
            HStack(spacing: 40) {
                // The Anchor's pane wears the anchor. The app's own hourglass standing over a
                // screen about the Anchor would be the same demotion in a picture.
                mark
                    .frame(width: 150, height: 200)
                // Scrolls because the filter pane grows: six numbered steps and a caution is a
                // taller column than the promise, and a step that falls off the bottom of a
                // fixed window is a step nobody follows.
                ScrollView(.vertical) {
                    Group {
                        switch step {
                        case .promise: promise
                        case .anchor: anchor
                        case .filter: filter
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
        if step == .anchor {
            AnchorShape()
                .fill(Ember.ember)
                .frame(width: 120, height: 150)
                .shadow(color: Ember.ember.opacity(0.45), radius: 32)
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
            Text("Two ways to put an app out of reach, and neither of them has a button that hands it back.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .padding(.top, 14)
            Text("Rules are the everyday half. Pick the apps and websites that eat your time and give each one allowed windows, the same every day or different on weekends, and a minute budget. Outside the windows, or once the budget is spent, Furlough quits the app and sends the tab to a shield page. Tightening a rule applies instantly; loosening one waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)).")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .padding(.top, 10)
            Text("The Anchor is the other half, and it is next.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .padding(.top, 10)
            Text("The Mac has no Screen Time API for apps like this, so macOS will ask once per browser whether Furlough may read the address bar. Furlough opens at login and refuses to quit while something is blocked; Force Quit is the one escape.")
                .emberBody(12.5)
                .foregroundStyle(Ember.faint)
                .padding(.top, 14)
            HStack(spacing: 10) {
                Button(requesting ? "Asking…" : "Start") {
                    Task {
                        requesting = true
                        await model.requestNotifications()
                        requesting = false
                        withAnimation(.snappy(duration: 0.25)) { step = .anchor }
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

    /// The Anchor, in the terms this device is in: it can drop one, and it cannot lift one.
    /// Nothing here needs setting up, so the pane is told rather than asked — the point is that
    /// a person who came to Furlough for a one-tap lock finds out on the first run that the Mac
    /// is in it, rather than a week later from a sheet.
    private var anchor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "The other half", color: Ember.ember)
            Text("One tap. Then the tag.")
                .emberDisplay(36)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("The Anchor is a separate list you lock in one tap — or turn inside out, so every app on this Mac is closed and the list is what stays open. No delay applies, because anchoring only ever takes things away.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .padding(.top, 14)
            Text("This Mac has no NFC reader, so the key is your iPhone's: an anchor lifts when you hold the phone to a tag you paired beforehand. One Anchor covers both devices, and either one can drop it.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .padding(.top, 10)
            Text("There is nothing to pair here and nothing to switch on: both devices signed into your Apple Account is the whole of the link. This Mac has to have heard from the phone once before it will drop an anchor of its own, so that it never holds a lock with no key anywhere.")
                .emberBody(12.5)
                .foregroundStyle(Ember.faint)
                .padding(.top, 14)
            HStack(spacing: 10) {
                Button("Continue") {
                    withAnimation(.snappy(duration: 0.25)) { step = .filter }
                }
                .buttonStyle(.glassProminent)
                .tint(Ember.ember)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Button("Back") {
                    withAnimation(.snappy(duration: 0.25)) { step = .promise }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.top, 24)
        }
    }

    /// The web filter, offered once. Whatever is chosen here, Settings > Web has the same
    /// buttons later.
    private var filter: some View {
        let filter = model.enforcer.webFilter
        let status = filter.status
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "One more thing", color: Ember.amber)
            Text("The web filter.")
                .emberDisplay(36)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            if status == .notInstalled {
                Text("Furlough reads the tabs of Safari and the Chromium browsers and sends a blocked one to its shield page. It cannot read Firefox, a site saved to the Dock as an app, or an app that loads a site on its own. The web filter closes those: a system extension that refuses the connection instead, from any app.")
                    .emberBody(14.5)
                    .foregroundStyle(Ember.muted)
                    .padding(.top, 14)
            } else {
                // Once Install has been pressed, what the filter is matters less than what is
                // being waited on, and the steps need the room the paragraph was using.
                Text(status.label)
                    .emberBody(13, .semibold)
                    .foregroundStyle(status.isOn ? Ember.moss : Ember.pending)
                    .padding(.top, 14)
            }
            FilterDirections(guidance: status.guidance, perform: filter.perform)
                .padding(.top, 14)
            HStack(spacing: 10) {
                switch status {
                case .notInstalled, .failed:
                    Button("Install the web filter") { filter.install() }
                        .buttonStyle(.glassProminent)
                        .tint(Ember.ember)
                        .keyboardShortcut(.defaultAction)
                    Button("Not now") { model.finishOnboarding() }
                        .buttonStyle(.glass)
                case .awaitingApproval, .disabledInSettings, .filterOff, .filterDenied:
                    // No Open System Settings or Check again here: the walkthrough puts each of
                    // them on the step that calls for it, and a second copy down here would be
                    // a button to press at the wrong time.
                    Button("Continue") { model.finishOnboarding() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.defaultAction)
                case .installing:
                    Button("Continue") { model.finishOnboarding() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.defaultAction)
                case .on, .notInApplications:
                    Button("Continue") { model.finishOnboarding() }
                        .buttonStyle(.glassProminent)
                        .tint(Ember.ember)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.top, 24)
        }
        .task { await filter.refresh() }
    }
}
