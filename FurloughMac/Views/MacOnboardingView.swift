import SwiftUI

struct MacOnboardingView: View {
    @Environment(MacModel.self) private var model
    @State private var requesting = false

    var body: some View {
        ZStack {
            EmberWall()
            HStack(spacing: 40) {
                LivingHourglass(state: .open(level: 0.62, warned: false))
                    .compositingGroup()
                    .frame(width: 150, height: 200)
                    .shadow(color: Ember.amber.opacity(0.45), radius: 32)
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
                                model.finishOnboarding()
                                requesting = false
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
                .frame(maxWidth: 460, alignment: .leading)
            }
            .padding(40)
        }
    }
}
