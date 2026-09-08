import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var requesting = false

    var body: some View {
        ZStack {
            EmberWall()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)
                LivingHourglass(state: .open(level: 0.62, warned: false))
                    .compositingGroup()
                    .frame(width: 106, height: 140)
                    .shadow(color: Ember.amber.opacity(0.45), radius: 24)
                Eyebrow(text: "Furlough", color: Ember.amber)
                    .padding(.top, 30)
                Text("No unblock button.")
                    .emberDisplay(34)
                    .foregroundStyle(Ember.cream)
                    .padding(.top, 6)
                Text("Pick the apps that eat your time. Give each one allowed windows, the same every day or different on weekends, and a minute budget. Outside the windows, or once the budget is spent, iOS shields the app.")
                    .emberBody(15)
                    .foregroundStyle(Ember.muted)
                    .padding(.top, 14)
                Text("Tightening a rule applies instantly. Loosening one waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)).")
                    .emberBody(15)
                    .foregroundStyle(Ember.muted)
                    .padding(.top, 10)
                if model.authorization == .denied {
                    Text("Screen Time access was denied. Turn it on in Settings > Screen Time > Apps with Screen Time Access > Furlough.")
                        .emberBody(12)
                        .foregroundStyle(Ember.ember)
                        .padding(.top, 14)
                }
                if !model.isAppGroupAvailable {
                    Text("The App Group entitlement is missing, so the extensions cannot share state. Check signing in Xcode.")
                        .emberBody(12)
                        .foregroundStyle(Ember.ember)
                        .padding(.top, 14)
                }
                Spacer()
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
                Footnote(text: "You can turn this off any time in Settings > Screen Time.", alignment: .center)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
}
