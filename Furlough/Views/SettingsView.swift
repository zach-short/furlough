import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var delayHours = Furlough.defaultLoosenDelayHours
    @State private var result: ProposalResult?
    @State private var confirmReset = false
    @State private var setupFile: SetupDocument?
    @State private var setupName = ""
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var chosenSetup: ChosenSetup?
    @State private var importError: String?
    #if DEBUG || TESTING_TOOLS
    @State private var showTesting = TestingTools.isShown
    #endif

    /// A file that has been read and not yet acted on. `ConfigExport` is a value, not an
    /// identity, so the sheet needs one of its own to be presented by.
    private struct ChosenSetup: Identifiable {
        let id = UUID()
        let export: ConfigExport
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    delayCard

                    enforcementCard

                    setupCard

                    SectionLabel(text: "If something gets stuck")
                    Text("Furlough has no unblock button by design. If a shield ever refuses to lift when it should, open Settings > Screen Time > Apps with Screen Time Access, turn off Furlough, and all shields and the delete-protection flag are cleared by iOS. Reopen Furlough to re-enable.")
                        .emberBody(12)
                        .foregroundStyle(Ember.muted)
                        .padding(.horizontal, 8)

                    aboutCard

                    #if DEBUG || TESTING_TOOLS
                    if showTesting {
                        SectionLabel(text: "Testing")
                        VStack(spacing: 0) {
                            action("Reset everything") { confirmReset = true }
                            CardDivider()
                            action("Hide these buttons") {
                                TestingTools.isShown = false
                                showTesting = false
                            }
                        }
                        .emberCard()
                        Footnote(text: "Not in the App Store build. Reset everything forgets every app, rule, pending change and the Anchor, and lifts all shields.\n\nHide these buttons puts this section away; five taps on Version above brings it back.")
                            .padding(.top, 8)
                    }
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
            .fileExporter(
                isPresented: Binding(get: { setupFile != nil }, set: { if !$0 { setupFile = nil } }),
                document: setupFile,
                contentType: .json,
                defaultFilename: setupName
            ) { outcome in
                setupFile = nil
                if case .failure(let error) = outcome {
                    exportError = error.localizedDescription
                    SharedStore.log("export failed: \(error)")
                } else {
                    SharedStore.log("exported setup")
                }
            }
            .alert("Download my setup", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }), presenting: exportError) { _ in
                Button("OK") { exportError = nil }
            } message: { error in
                Text(error)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { outcome in
                switch outcome {
                case .success(let url):
                    switch model.openSetup(fileAt: url) {
                    case .success(let export): chosenSetup = ChosenSetup(export: export)
                    case .failure(let refusal): importError = refusal.message
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .sheet(item: $chosenSetup) { chosen in
                ImportSetupView(export: chosen.export, config: model.state.config)
            }
            .alert("Restore from a file", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }), presenting: importError) { _ in
                Button("OK") { importError = nil }
            } message: { error in
                Text(error)
            }
            #if DEBUG || TESTING_TOOLS
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

    @ViewBuilder
    private var delayCard: some View {
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
    }

    @ViewBuilder
    private var enforcementCard: some View {
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
            NavigationLink { UsageView() } label: {
                HStack {
                    Text("Where the time goes")
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
    }

    /// The export and the import, which are the same card: one writes the file and the other
    /// reads it back. Its own property because the settings body is one long `VStack` and the
    /// type checker gives up on it.
    @ViewBuilder
    private var setupCard: some View {
        SectionLabel(text: "Your setup")
        VStack(spacing: 0) {
            action("Download my setup") { exportSetup() }
            CardDivider()
            action("Restore from a file") { showImporter = true }
        }
        .emberCard()
        Footnote(text: "Saves your rules, budgets, tiers and delay as a JSON file you can keep or send to another device. Screen Time names an app with a token that means nothing off this iPhone, so the file records what each app is called rather than the app itself. The Anchor is not included.")
            .padding(.top, 8)
        Footnote(text: "Restoring asks which app each rule was, since the file cannot say. It is a proposal, not a rewind: every rule goes through the same delay the rule editor does, so anything in the file that loosens your rules waits.")
            .padding(.top, 6)
    }

    /// The version, and the way to the rest of About. The number is the one thing the site
    /// cannot print: only the running copy knows which build it is, and it is the first thing
    /// a support mail needs. Everything else — what Furlough keeps, what it is built on — is a
    /// page rather than a screen, so it can be corrected without shipping a build.
    @ViewBuilder
    private var aboutCard: some View {
        SectionLabel(text: "About")
        VStack(spacing: 0) {
            row("Version", Self.version)
                .contentShape(Rectangle())
                .onTapGesture { noteVersionTap() }
            CardDivider()
            action("About Furlough") {
                if let url = Furlough.helpURL("about") { openURL(url) }
            }
        }
        .emberCard()
        Footnote(text: "Opens furloughapp.com, where what stays on this phone and what Furlough is built on are written out in full.")
            .padding(.top, 8)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
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

    /// Five taps on the Version row ask for the Testing section back. Nothing at all in a build
    /// that does not carry it — see `TestingTools` for why the section hides itself even when it
    /// is there.
    private func noteVersionTap() {
        #if DEBUG || TESTING_TOOLS
        if TestingTools.noteVersionClick() { showTesting = true }
        #endif
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

    /// Builds the file and opens the save panel. Reading the store is the whole of it: an
    /// export changes nothing, so alone among the buttons on this screen it needs no delay,
    /// no confirmation and no enforcement pass afterwards.
    private func exportSetup() {
        do {
            let export = ConfigExport.current()
            setupFile = SetupDocument(data: try export.json())
            setupName = export.suggestedFilename
        } catch {
            exportError = error.localizedDescription
            SharedStore.log("export failed: \(error)")
        }
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
