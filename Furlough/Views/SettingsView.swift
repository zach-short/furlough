import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var delayHours = Furlough.defaultLoosenDelayHours
    @State private var result: ProposalResult?
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Loosening delay")
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Delay")
                                .emberBody(13)
                                .foregroundStyle(Ember.cream)
                            Spacer()
                            Text(TimeFormat.delay(hours: delayHours))
                                .emberBody(13, .semibold)
                                .monospacedDigit()
                                .foregroundStyle(Ember.cream)
                            Stepper("Loosening delay", value: $delayHours, in: 1...168, step: delayHours >= 24 ? 24 : 1)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        CardDivider()
                        GhostButton(title: "Save delay") { result = model.setDelay(hours: delayHours) }
                            .disabled(delayHours == model.state.config.loosenDelayHours)
                            .opacity(delayHours == model.state.config.loosenDelayHours ? 0.4 : 1)
                    }
                    .emberCard()
                    Footnote(text: "Raising the delay applies immediately. Lowering it waits out the current delay.")
                        .padding(.top, 8)

                    SectionLabel(text: "Enforcement")
                    VStack(spacing: 0) {
                        row("Screen Time access", model.isAuthorized ? "Allowed" : "Not allowed")
                        CardDivider()
                        row("Notifications", model.notificationsGranted == true ? "Allowed" : "Off")
                        CardDivider()
                        row("App Group", model.isAppGroupAvailable ? "OK" : "Missing")
                        CardDivider()
                        row("Last shield update", stamp(model.state.runtime.lastReconcile))
                        CardDivider()
                        row("Last schedule update", stamp(model.state.runtime.lastRegistration))
                        if let error = model.state.runtime.registrationError {
                            CardDivider()
                            Text(error)
                                .emberBody(12)
                                .foregroundStyle(Ember.ember)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        CardDivider()
                        action("Re-apply enforcement now") { model.enforce(reason: "manual") }
                        if model.notificationsGranted != true {
                            CardDivider()
                            action("Allow notifications") { Task { await model.requestNotifications() } }
                        }
                        CardDivider()
                        NavigationLink { LogView() } label: {
                            HStack {
                                Text("Activity log")
                                    .emberBody(13)
                                    .foregroundStyle(Ember.cream)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Ember.faint)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .emberCard()

                    SectionLabel(text: "If something gets stuck")
                    Text("Furlough has no unblock button by design. If a shield ever refuses to lift when it should, open Settings > Screen Time > Apps with Screen Time Access, turn off Furlough, and all shields and the delete-protection flag are cleared by iOS. Reopen Furlough to re-enable.")
                        .emberBody(12)
                        .foregroundStyle(Ember.muted)
                        .padding(.horizontal, 8)

                    #if DEBUG
                    SectionLabel(text: "Testing")
                    VStack(spacing: 0) {
                        action("Reset everything") { confirmReset = true }
                    }
                    .emberCard()
                    Footnote(text: "Debug builds only. Forgets every app, rule, pending change and the Anchor, and lifts all shields.")
                        .padding(.top, 8)
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Ember.cream)
                }
            }
            .onAppear { delayHours = model.state.config.loosenDelayHours }
            .alert("Delay", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }), presenting: result) { _ in
                Button("OK") { result = nil }
            } message: { result in
                Text(result.message)
            }
            #if DEBUG
            .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) {
                    model.resetEverything()
                    dismiss()
                }
            } message: {
                Text("Every app, rule, pending change and the Anchor are forgotten and all shields lift. Screen Time access is kept.")
            }
            #endif
        }
        .presentationBackground(Ember.ground)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            Spacer()
            Text(value)
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .emberBody(13, .semibold)
                .foregroundStyle(Ember.ember)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }
}

struct LogView: View {
    @State private var entries = SharedStore.logEntries()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    Text("Nothing logged yet.")
                        .emberBody(13)
                        .foregroundStyle(Ember.muted)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(Array(entries.reversed().enumerated()), id: \.offset) { index, entry in
                        if index > 0 { CardDivider() }
                        Text(entry)
                            .font(EmberFont.mono(11))
                            .foregroundStyle(Ember.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
            }
            .emberCard()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(EmberWall())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Activity log")
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") { entries = SharedStore.logEntries() }
                    .tint(Ember.cream)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", systemImage: "trash") {
                    SharedStore.clearLog()
                    entries = []
                }
                .tint(Ember.cream)
            }
        }
    }
}
