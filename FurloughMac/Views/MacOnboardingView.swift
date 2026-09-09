import SwiftUI

/// Two panes. The first is the promise; the second offers the web filter, which is the one
/// thing on the Mac that needs the person's hand in System Settings, so it is asked for here
/// rather than found later.
struct MacOnboardingView: View {
    @Environment(MacModel.self) private var model
    @State private var requesting = false
    @State private var step = Step.promise

    private enum Step { case promise, filter }

    var body: some View {
        ZStack {
            EmberWall()
            HStack(spacing: 40) {
                LivingHourglass(state: .open(level: 0.62, warned: false))
                    .compositingGroup()
                    .frame(width: 150, height: 200)
                    .shadow(color: Ember.amber.opacity(0.45), radius: 32)
                // Scrolls because the filter pane grows: six numbered steps and a caution is a
                // taller column than the promise, and a step that falls off the bottom of a
                // fixed window is a step nobody follows.
                ScrollView(.vertical) {
                    Group {
                        switch step {
                        case .promise: promise
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

    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Furlough for Mac", color: Ember.amber)
            Text("No unblock button.")
                .emberDisplay(36)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Pick the apps and websites that eat your time. Give each one allowed windows, the same every day or different on weekends, and a minute budget. Outside the windows, or once the budget is spent, Furlough quits the app and sends the tab to a shield page.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .padding(.top, 14)
            Text("Tightening a rule applies instantly. Loosening one waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)).")
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
                        withAnimation(.snappy(duration: 0.25)) { step = .filter }
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
                case .awaitingApproval, .disabledInSettings, .filterOff:
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
