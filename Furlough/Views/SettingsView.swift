import SwiftUI
import UniformTypeIdentifiers

/// Settings, as a menu.
///
/// It used to be every setting at once, seven cards down one scroll: the delay and which half
/// the app opens on — the two things a person comes here to change — read as two blocks among
/// the record, the export, the diagnostics line and About, and each new setting made the scroll
/// longer for everybody who was not looking for it.
///
/// So each card is a row now, and the footnote that used to sit under it is the first sentence
/// of the screen the row opens. That is the move the Anchor page already made for its own four
/// settings, down to the row and the chrome it opens into (`AnchorSettingScreen`), so the two
/// screens are read the same way. Each row carries the one fact you would have scrolled to
/// read — what the app opens on, how long a loosening waits, whether the devices are linked,
/// whether anything is wrong — and growing now costs a row rather than a screenful.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // What Furlough does: the two halves' own settings, and the devices they
                    // cross to.
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
                    // Asked when the menu opens, so the Devices row is about now rather than
                    // about whenever the app last happened to hear something.
                    .task { model.refreshLink() }

                    // What has happened: the record of the contract, and the fortnight behind it.
                    VStack(spacing: 0) {
                        if let record = recordSummary {
                            sectionRow("The record", detail: record) { RecordScreen() }
                            CardDivider()
                        }
                        sectionRow("Where the time goes", detail: "The last fortnight, app by app") {
                            UsageView()
                        }
                    }
                    .emberCard()
                    .padding(.top, 12)

                    // The app itself.
                    VStack(spacing: 0) {
                        sectionRow("Your setup", detail: "Download it, or restore from a file") {
                            SetupScreen()
                        }
                        CardDivider()
                        sectionRow("Diagnostics", detail: diagnostics.line, dot: dot(for: diagnostics.level)) {
                            DiagnosticsView()
                        }
                        CardDivider()
                        // The version on the row, because it is the one thing about About that
                        // gets asked for by somebody reading a bug report back to you.
                        //
                        // The reset behind it is testing-only: only the Testing section calls
                        // it, and only the builds carrying that section have the method. It is
                        // compiled out of the call here too, so the name stays out of a Release
                        // binary — which is a thing scripts/archive.sh refuses to ship.
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Ember.cream)
                }
            }
        }
        .presentationBackground(Ember.ground)
    }

    // MARK: What each row says without being opened

    /// The half, and nothing about the +. Two facts wrapped the row onto a second line, and the
    /// short true version of the second one — "+ adds to the anchor" — is only true over the
    /// Anchor page, which is the misreading the setting exists to undo. So it is said in full on
    /// the screen or not at all.
    private var startSummary: String {
        "Opens on \(model.startHalf.title)"
    }

    /// The delay, in the words the rest of the app uses for it — and while the first week runs,
    /// the capped number instead, because that is the one a loosening would actually wait.
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

    /// Nil until there is a record, so a fresh install is not offered a row into an empty screen
    /// — the card it replaced drew nothing for the same reason.
    private var recordSummary: String? {
        let card = Record.card(model.state, now: model.state.now)
        guard !card.isEmpty else { return nil }
        return "No budget spent: \(Record.streakLine(card))"
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

/// The three things about how Furlough opens: which half it opens on, what the + means over the
/// Anchor page, and the checklists again.
///
/// First in the menu because these are the settings a person came here to change. The intro asks
/// the first one once, in the pane that says the app is two halves; this is the only other place
/// it can be answered, and the pane is not coming back.
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

    /// What + does over the Anchor page.
    ///
    /// The + acts on the page it is over, which over the Anchor page means its list — and the
    /// one person that reading fails is the one who set the anchor up months ago and has read +
    /// as "give an app hours" ever since. So it is a preference rather than a rule, and only
    /// about the Anchor page: over Rules the button has no second reading to choose between.
    ///
    /// Stacked rather than beside its title, because "To the anchor" and "A new rule" have to say
    /// what they do, and two chips that wide leave a row with nowhere to put the words.
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

    /// Says what pressing it would do, and then what it did — both derived from the same set, so
    /// the row answers for itself rather than raising an alert to say something happened.
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

/// The loosening delay, and the first week counting itself down under it.
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
                // While the week runs, every countdown in the app is already saying the capped
                // number. Without this line that reads like the delay above is not being applied.
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

/// The export and the import, which are the same screen: one writes the file and the other reads
/// it back.
///
/// One lead where there were two paragraphs. Both dropped facts — that restoring has to ask which
/// app each rule was, and that every restored rule goes through the delay — are said on the
/// import screen itself, next to the pickers doing the asking, which is where somebody deciding
/// whether to trust a file is actually standing.
private struct SetupScreen: View {
    @Environment(AppModel.self) private var model
    @State private var setupFile: SetupDocument?
    @State private var setupName = ""
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var chosenSetup: ChosenSetup?
    @State private var importError: String?

    /// A file that has been read and not yet acted on. `ConfigExport` is a value, not an
    /// identity, so the sheet needs one of its own to be presented by.
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

// MARK: - About

/// The version, the About page, and the way out when a shield sticks.
///
/// The stuck paragraph used to be printed in Settings in full, and it is Help's own page of the
/// same name with the same words. One copy, and it is the one with the ordered steps — so this
/// is a link.
///
/// The testing section is here rather than in the menu because the gesture that asks for it is
/// five taps on the Version row above: the thing asked for should appear where it was asked for.
private struct AboutScreen: View {
    /// What follows a testing reset, once the model has forgotten everything: close Settings, so
    /// the app is looking at onboarding rather than at a screen about a phone with nothing on it.
    /// Unused outside the builds that carry the section.
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
                // A way back that does not have to be known about. The five taps still work and
                // are the quieter route, but a hidden gesture is a poor only route to the button
                // that resets the phone during a test pass.
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

    /// Five taps on the Version row ask for the Testing section back. Nothing at all in a build
    /// that does not carry it — see `TestingTools` for why the section hides itself even when it
    /// is there.
    private func noteVersionTap() {
        #if DEBUG || TESTING_TOOLS
        if TestingTools.noteVersionClick() { showTesting = true }
        #endif
    }
}

/// What the About row reads, and the Version row behind it.
private var appVersion: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return "\(short) (\(build))"
}

// MARK: - The rows these screens are built from

/// A row in the menu: the section's name, the one fact about it worth having without opening it,
/// and — where the state can go wrong with nobody having touched anything — a dot. The Anchor
/// page's settings card is built from the same row, and is read the same way.
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

/// A fact and its value. Read-only: everything that can be acted on is an `actionRow` or a
/// `navRow`, so a row that just says a thing looks like one.
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

/// A row that does something here rather than opening a screen: ember, and with a line under it
/// when what it would do is worth saying before it is pressed.
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

/// A row inside one of the screens that opens a further one — Help's pages, the log. The menu's
/// own rows are `sectionRow`s.
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

/// One of a pair: the chosen one is filled, the other is an outline. Not a `Picker`, because both
/// choices have to be readable at once — the question is which of two things this means, and a
/// wheel that shows one answer at a time is a poor way to ask it.
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

/// Everything the Settings screen used to say under Enforcement, one push behind the row that
/// says whether any of it is wrong.
///
/// Nothing here is a setting. It is what Furlough can see about itself — the two permissions, the
/// App Group the extensions read through, when the shields and schedules were last written — and
/// the two things a person can do about it: run the whole pass again, and read what the monitor
/// has been doing. Help's *If something gets stuck* sends people here by name.
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
