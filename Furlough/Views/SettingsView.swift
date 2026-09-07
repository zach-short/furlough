import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var delayHours = Furlough.defaultLoosenDelayHours
    @State private var result: ProposalResult?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $delayHours, in: 1...168, step: delayHours >= 24 ? 24 : 1) {
                        Text("Loosening delay: \(TimeFormat.delay(hours: delayHours))")
                    }
                    Button("Save delay") { result = model.setDelay(hours: delayHours) }
                        .disabled(delayHours == model.state.config.loosenDelayHours)
                } footer: {
                    Text("Raising the delay applies immediately. Lowering it waits out the current delay.")
                }

                Section("Enforcement") {
                    row("Screen Time access", model.isAuthorized ? "Allowed" : "Not allowed")
                    row("Notifications", model.notificationsGranted == true ? "Allowed" : "Off")
                    row("App Group", model.isAppGroupAvailable ? "OK" : "Missing")
                    row("Last shield update", model.state.runtime.lastReconcile?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    row("Last schedule update", model.state.runtime.lastRegistration?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    if let error = model.state.runtime.registrationError {
                        Text(error).foregroundStyle(.red)
                    }
                    Button("Re-apply enforcement now") { model.enforce(reason: "manual") }
                    if model.notificationsGranted != true {
                        Button("Allow notifications") { Task { await model.requestNotifications() } }
                    }
                    NavigationLink("Activity log") { LogView() }
                }

                Section("If something gets stuck") {
                    Text("Furlough has no unblock button by design. If a shield ever refuses to lift when it should, open Settings > Screen Time > Apps with Screen Time Access, turn off Furlough, and all shields and the delete-protection flag are cleared by iOS. Reopen Furlough to re-enable.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { delayHours = model.state.config.loosenDelayHours }
            .alert("Delay", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }), presenting: result) { _ in
                Button("OK") { result = nil }
            } message: { result in
                Text(result.message)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}

struct LogView: View {
    @State private var entries = SharedStore.logEntries()

    var body: some View {
        List(entries.reversed(), id: \.self) { entry in
            Text(entry).font(.caption.monospaced())
        }
        .navigationTitle("Activity log")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") { entries = SharedStore.logEntries() }
                Button("Clear", systemImage: "trash") {
                    SharedStore.clearLog()
                    entries = []
                }
            }
        }
    }
}
