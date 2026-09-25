import SwiftUI
import UniformTypeIdentifiers

/// Settings, as a menu: each row opens a screen and shows the one fact worth knowing without
/// opening it. Shares its chrome (`AnchorSettingScreen`) with the Anchor page's own settings.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The two halves' own settings, and the devices they cross to.
                    VStack(spacing: 0) {
                        sectionRow("Start", detail: startSummary) { StartSettingsScreen() }
                        CardDivider()
                        sectionRow("Rules", detail: rulesSummary) { RulesSettingsScreen() }
                        CardDivider()
                        sectionRow("Devices", detail: devicesSummary, dot: devicesDot) {
                            AnchorSettingScreen(title: "Devices", lead: devicesLead) { DevicesScreen() }
                        }
                    }
                    .emberCard()
                    // Refresh on open so the Devices row reflects now, not the last heartbeat.
                    .task { model.refreshLink() }

                    VStack(spacing: 0) {
                        if let record = recordSummary {
                            sectionRow("The record", detail: record) { RecordScreen() }
                            CardDivider()
                        }
                        sectionRow("Where the time goes", detail: "The last fortnight, app by app") {
                            UsageView()
                        }
                        CardDivider()
                        sectionRow("Notifications", detail: notificationsSummary) {
                            NotificationsScreen()
                        }
                    }
                    .emberCard()
                    .padding(.top, 12)

                    VStack(spacing: 0) {
                        sectionRow("Your setup", detail: "Download it, or restore from a file") {
                            SetupScreen()
                        }
                        CardDivider()
                        sectionRow("Diagnostics", detail: diagnostics.line, dot: dot(for: diagnostics.level)) {
                            DiagnosticsView()
                        }
                        CardDivider()
                        // resetEverything() is compiled out here too, so the symbol stays out of
                        // a Release binary — scripts/archive.sh refuses to ship one that has it.
                        sectionRow("About", detail: appVersion) {
                            AboutScreen(onReset: {
                                #if DEBUG || TESTING_TOOLS
                                model.resetEverything()
                                #endif
                                dismiss()
                            })
                        }
                    }
                    .emberCard()
                    .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
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
            }
        }
        .presentationBackground(Ember.ground)
    }

    // MARK: What each row says without being opened

    private var startSummary: String {
        "Opens on \(model.startHalf.title)"
    }

    /// During the first-week trial, shows the capped delay rather than the configured one,
    /// since that's the one a loosening would actually wait.
    private var rulesSummary: String {
        if Forgiveness.trialDaysLeft(model.state.config, at: model.clock.now) != nil {
            return "First week: a loosening waits \(TimeFormat.delay(hours: Furlough.trialDelayHours))"
        }
        return "A loosening waits \(TimeFormat.delay(hours: model.state.config.loosenDelayHours))"
    }

    private var devicesSummary: String {
        guard model.cloudAvailable else { return "Not linked · iCloud Drive is off" }
        guard model.isEnrolled else { return "Off the link. Link this iPhone to share the Anchor and what you add." }
        let others = model.devices.count
        return others == 0 ? "On the link · nothing else on it yet" : "On the link with \(others) other\(others == 1 ? "" : "s")"
    }

    private var devicesDot: Color {
        guard model.cloudAvailable else { return Ember.ember }
        return model.isEnrolled && !model.devices.isEmpty ? Ember.moss : Ember.amber
    }

    private var devicesLead: String {
        guard model.cloudAvailable else { return AnchorSync.cutOffWarning }
        return model.isEnrolled
            ? "This iPhone is on the link. The Anchor crosses to every device here, and what you add can too."
            : "Furlough on your other devices can share the Anchor with this iPhone, and be told what you add here. Nothing crosses until you link it."
    }

    /// Nil until there is a record, so a fresh install isn't offered a row into an empty screen.
    private var recordSummary: String? {
        let card = Record.card(model.state, now: model.state.now)
        guard !card.isEmpty else { return nil }
        return "No budget spent: \(Record.streakLine(card))"
    }

    /// The count, not a list: nine names would not fit, and the one fact worth knowing without
    /// opening the screen is whether anything is switched off at all.
    private var notificationsSummary: String {
        let muted = model.mutedNotifications.count
        if muted == 0 { return "Every one arrives" }
        if muted == NotificationKind.allCases.count { return "All of them muted" }
        return "\(muted) muted"
    }

    private var diagnostics: Diagnostics { model.diagnostics }

    private func dot(for level: Diagnostics.Level) -> Color {
        switch level {
        case .well: Ember.moss
        case .warn: Ember.amber
        case .bad: Ember.ember
        }
    }
}

// MARK: - Start

private struct StartSettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AnchorSettingScreen(title: "Start", lead: "Over the Rules page + always makes a rule.") {
            VStack(spacing: 0) {
                halfRow(title: "Opens on", selection: model.startHalf) { model.setStartHalf($0) }
                CardDivider()
                addRow
                CardDivider()
                actionRow(
                    "Run the setup guide again",
                    detail: guideDetail,
                    isEnabled: !model.finishedGuides.isEmpty
                ) {
                    model.restartGuides()
                }
            }
            .emberCard()
        }
    }

    /// Only meaningful over the Anchor page — over Rules, + has no second reading to choose.
    private var addRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On the Anchor page, + adds")
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            HStack(spacing: 6) {
                chip("To the anchor", isOn: model.anchorPageAdds == .anchor, isWide: true) {
                    model.setAnchorPageAdds(.anchor)
                }
                chip("A new rule", isOn: model.anchorPageAdds == .rules, isWide: true) {
                    model.setAnchorPageAdds(.rules)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var guideDetail: String {
        let finished = model.finishedGuides
        guard !finished.isEmpty else { return "Both checklists are showing on Home." }
        if finished.count == 1, let only = finished.first {
            return "Puts the three steps back on the \(only.title) page."
        }
        return "Puts the three steps back on both pages."
    }

    private func halfRow(title: String, selection: Half, onPick: @escaping (Half) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(Half.allCases, id: \.self) { half in
                    chip(half.title, isOn: half == selection) { onPick(half) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: - Rules

private struct RulesSettingsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var delayHours = Furlough.defaultLoosenDelayHours
    @State private var result: ProposalResult?

    var body: some View {
        AnchorSettingScreen(
            title: "Rules",
            lead: "Raising the delay applies immediately. Lowering it waits out the current delay."
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Loosening delay")
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
            if let left = Forgiveness.trialDaysLeft(model.state.config, at: model.clock.now),
               let ends = model.state.config.trialEndsAt {
                // Without this, the capped trial delay above reads as if it's being ignored.
                CautionBanner(
                    text: "First week: \(left == 1 ? "1 day" : "\(left) days") left. Until \(TimeFormat.day(ends)) a loosening waits \(TimeFormat.delay(hours: Furlough.trialDelayHours)), whatever this says. After that the full delay applies and cannot be put off.",
                    isSevere: false
                )
                .padding(.top, 8)
            }
        }
        .onAppear { delayHours = model.state.config.loosenDelayHours }
        .alert("Delay", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }), presenting: result) { _ in
            Button("OK") { result = nil }
        } message: { result in
            Text(result.message)
        }
    }
}

// MARK: - Your setup

private struct SetupScreen: View {
    @Environment(AppModel.self) private var model
    @State private var setupFile: SetupDocument?
    @State private var setupName = ""
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var chosenSetup: ChosenSetup?
    @State private var importError: String?

    /// `ConfigExport` is a value type with no identity, so wrap it for `sheet(item:)`.
    private struct ChosenSetup: Identifiable {
        let id = UUID()
        let export: ConfigExport
    }

    var body: some View {
        AnchorSettingScreen(
            title: "Your setup",
            lead: "Rules, budgets, tiers and delay, as a file. The Anchor stays on this phone. Restoring goes through the same delay as editing."
        ) {
            VStack(spacing: 0) {
                actionRow("Download my setup") { exportSetup() }
                CardDivider()
                actionRow("Restore from a file") { showImporter = true }
            }
            .emberCard()
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
    }

    /// Read-only, so unlike the other buttons here it needs no delay or confirmation.
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

// MARK: - About

private struct AboutScreen: View {
    /// Closes Settings after a testing reset so the app lands on onboarding, not an empty screen.
    let onReset: () -> Void
    #if DEBUG || TESTING_TOOLS
    @State private var showTesting = TestingTools.isShown
    @State private var confirmReset = false
    #endif

    var body: some View {
        AnchorSettingScreen(title: "About") {
            VStack(spacing: 0) {
                statusRow("Version", appVersion)
                    .contentShape(Rectangle())
                    .onTapGesture { noteVersionTap() }
                CardDivider()
                navRow("About Furlough") { AboutHelp() }
                CardDivider()
                navRow("What's new") { WhatsNewView() }
                CardDivider()
                navRow("If something gets stuck") { StuckHelp() }
            }
            .emberCard()

            #if DEBUG || TESTING_TOOLS
            if showTesting {
                SectionLabel(text: "Testing")
                VStack(spacing: 0) {
                    actionRow("Reset everything") { confirmReset = true }
                    CardDivider()
                    actionRow("Hide these buttons") {
                        TestingTools.isShown = false
                        showTesting = false
                    }
                }
                .emberCard()
                Footnote(text: "Not in the App Store build. Reset everything forgets every app, rule, pending change and the Anchor, lifts all shields, hands Screen Time access back and returns to onboarding — a fresh install, apart from the notification permission, which iOS only asks about once.\n\nHide these buttons puts this section away. Show testing buttons, or five taps on Version above, brings it back.")
                    .padding(.top, 8)
            } else {
                GhostButton(title: "Show testing buttons", color: Ember.muted) {
                    TestingTools.isShown = true
                    showTesting = true
                }
                .padding(.top, 4)
            }
            #endif
        }
        #if DEBUG || TESTING_TOOLS
        .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) { onReset() }
        } message: {
            Text("Every app, rule, pending change and the Anchor are forgotten, all shields lift, and Screen Time access is handed back, so Furlough starts again at onboarding.")
        }
        #endif
    }

    /// Five taps on Version brings the Testing section back; see `TestingTools`.
    private func noteVersionTap() {
        #if DEBUG || TESTING_TOOLS
        if TestingTools.noteVersionClick() { showTesting = true }
        #endif
    }
}

private var appVersion: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return "\(short) (\(build))"
}

// MARK: - The rows these screens are built from

/// Shared with the Anchor page's own settings card.
@MainActor
private func sectionRow<Screen: View>(
    _ title: String,
    detail: String,
    dot: Color? = nil,
    @ViewBuilder screen: @escaping () -> Screen
) -> some View {
    NavigationLink { screen() } label: {
        HStack(spacing: 10) {
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .emberDisplaySmall(13.5)
                    .foregroundStyle(Ember.cream)
                Text(detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ember.faint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

/// Read-only, unlike `actionRow`/`navRow`.
@MainActor
private func statusRow(_ title: String, _ value: String) -> some View {
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

/// Acts in place rather than opening a screen.
@MainActor
private func actionRow(
    _ title: String,
    detail: String? = nil,
    isEnabled: Bool = true,
    _ perform: @escaping () -> Void
) -> some View {
    Button(action: perform) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .emberBody(13, .semibold)
                .foregroundStyle(isEnabled ? Ember.ember : Ember.faint)
            if let detail {
                Text(detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
}

/// For screens nested inside a section (Help pages, the log); the menu's own rows are `sectionRow`.
@MainActor
private func navRow<Screen: View>(
    _ title: String,
    @ViewBuilder screen: @escaping () -> Screen
) -> some View {
    NavigationLink { screen() } label: {
        HStack(spacing: 10) {
            Text(title)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
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

/// Not a `Picker`: both choices need to stay readable at once, unlike a wheel showing one at a time.
@MainActor
private func chip(
    _ title: String,
    isOn: Bool,
    isWide: Bool = false,
    _ perform: @escaping () -> Void
) -> some View {
    Button(action: perform) {
        Text(title)
            .emberBody(12, .semibold)
            .foregroundStyle(isOn ? Ember.ground : Ember.muted)
            .frame(maxWidth: isWide ? .infinity : nil)
            .padding(.horizontal, isWide ? 8 : 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Ember.amber : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? .clear : Ember.cardBorder, lineWidth: 1)
            )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : [])
}

private func stamp(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
}

// MARK: - Diagnostics

/// Nothing here is a setting; it's what Furlough can see about itself. Linked from Help's
/// *If something gets stuck* by name.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AnchorSettingScreen(title: "Diagnostics") {
            VStack(spacing: 0) {
                statusRow("Screen Time access", model.isAuthorized ? "Allowed" : "Not allowed")
                CardDivider()
                statusRow("Notifications", model.notificationsGranted == true ? "Allowed" : "Off")
                CardDivider()
                statusRow("App Group", model.isAppGroupAvailable ? "OK" : "Missing")
                CardDivider()
                statusRow("Last shield update", stamp(model.state.runtime.lastReconcile))
                CardDivider()
                statusRow("Last schedule update", stamp(model.state.runtime.lastRegistration))
                if let error = model.state.runtime.registrationError {
                    CardDivider()
                    Text(error)
                        .emberBody(12)
                        .foregroundStyle(Ember.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
            .emberCard()

            SectionLabel(text: "If something looks wrong")
            VStack(spacing: 0) {
                actionRow("Re-apply enforcement now") { model.enforce(reason: "manual") }
                if model.notificationsGranted != true {
                    CardDivider()
                    actionRow("Allow notifications") { Task { await model.requestNotifications() } }
                }
                CardDivider()
                navRow("Activity log") { LogView() }
            }
            .emberCard()
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
