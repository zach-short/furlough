import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var requesting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "hourglass")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.tint)
                Text("Furlough")
                    .font(.largeTitle.bold())
                Text("Pick the apps that eat your time. Give each one daily windows and a minute budget. Outside the windows, or once the budget is spent, iOS shields the app.")
                Text("There is no unblock button. Tightening a rule applies instantly. Loosening one waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)).")
                    .foregroundStyle(.secondary)
                if model.authorization == .denied {
                    Text("Screen Time access was denied. Turn it on in Settings > Screen Time > Apps with Screen Time Access > Furlough.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !model.isAppGroupAvailable {
                    Text("The App Group entitlement is missing, so the extensions cannot share state. Check signing in Xcode.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button {
                    Task {
                        requesting = true
                        await model.requestAuthorization()
                        await model.requestNotifications()
                        requesting = false
                    }
                } label: {
                    Text(requesting ? "Waiting for iOS…" : "Allow Screen Time access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(requesting)
            }
            .padding()
        }
    }
}
