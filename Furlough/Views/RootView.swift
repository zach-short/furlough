import FamilyControls
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var revealed = false
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
                UsageView(role: .onboarding)
                    .transition(.opacity)
            } else {
                // Read once: Home owns `half` from then on, so a swipe isn't undone by rebuild.
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
        // Separate from `lastError`: this covers App Intent outcomes, not failures.
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
        // Raised from the root (not from either pairing screen) since one of them is pushed
        // onto Home's own nav stack, which a root-level sheet covers either way.
        .sheet(
            isPresented: Binding(
                get: { model.placingTagID != nil },
                set: { if !$0 { model.placingTagID = nil } }
            )
        ) {
            TagPlacementView(tagName: model.placingTagName)
        }
    }

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
