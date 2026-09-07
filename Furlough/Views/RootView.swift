import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isAuthorized {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Ember.ember)
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
    }
}
