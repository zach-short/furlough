import FamilyControls
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    /// The launch screen has had its time. Only ever set when one was shown.
    @State private var revealed = false
    /// The wall fades up under the launch screen; every screen draws its own wall over it.
    @State private var lit = false

    private var holdsLaunch: Bool { model.wasAuthorized && !revealed }

    var body: some View {
        @Bindable var model = model
        ZStack {
            Ember.ground.ignoresSafeArea()
            EmberWall()
                .opacity(lit ? 1 : 0)
            if holdsLaunch {
                LaunchView()
                    .transition(.opacity)
                    .zIndex(1)
            } else if model.showsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else if model.showsUsageStep {
                // The step between access and the first rule: a fortnight of use, app by app,
                // with the rule each one would take. Skippable, and Settings opens the same
                // screen again whenever it is wanted.
                UsageView(role: .onboarding)
                    .transition(.opacity)
            } else {
                // The half the intro was told to start on. Read once, here, so Home's own state
                // owns it from then on and a swipe is not undone by the next rebuild.
                HomeView(start: model.startHalf)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Launch.dissolve), value: model.showsOnboarding)
        .animation(.easeInOut(duration: Launch.dissolve), value: model.showsUsageStep)
        .preferredColorScheme(.dark)
        .tint(Ember.ember)
        .task { await model.observeAuthorization() }
        .task { await holdLaunch() }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        // What an App Intent has to say, once it is back in an app that can say it. Its own
        // alert rather than `lastError`: none of these is a thing going wrong, and the wrong
        // tag least of all — that is the anchor working.
        .alert(
            "Furlough",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            )
        ) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    /// Keeps the launch screen up for its fixed time, and a little longer only if iOS has not
    /// yet said whether Screen Time access still stands, then dissolves it into the app.
    private func holdLaunch() async {
        guard holdsLaunch else {
            lit = true
            return
        }
        withAnimation(.easeOut(duration: Launch.rise)) { lit = true }
        let started = ContinuousClock.now
        try? await Task.sleep(for: Launch.hold)
        while model.authorization == .notDetermined, ContinuousClock.now - started < Launch.hold + Launch.patience {
            try? await Task.sleep(for: .milliseconds(50))
        }
        withAnimation(.easeInOut(duration: Launch.dissolve)) { revealed = true }
    }
}
