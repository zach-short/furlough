import FamilyControls
import SwiftUI

// Centralized because the same picker is opened from more than one screen (the + button on
// Home, and the companion nudge in a rule editor).
enum PickerCopy {
    static func header(for choice: AddChoice) -> String {
        switch choice {
        case .application: "Choose apps and categories"
        case .website: "Choose websites"
        }
    }

    static func footer(for choice: AddChoice) -> String {
        switch choice {
        case .application: "Picking a category adds every app in it, each with its own rule."
        case .website: "Open a category, scroll past its apps to Websites and tap Add Website. Each site gets its own rule."
        }
    }

    // The companion nudge asks one question only: nothing is removed by leaving it unpicked,
    // and whatever is picked inherits the hours of the target that offered it.
    static func companionHeader(_ title: String) -> String {
        title.isEmpty ? "Choose the app" : "Choose \(title)"
    }

    static let companionFooter = "It gets the same hours as the site it belongs with. Nothing else here changes."
}

/// Apple's picker in a sheet of Furlough's own, so that it has a Cancel. The system
/// `familyActivityPicker` modifier's sheet has only Done, its binding changes with every tick,
/// and a swipe down ends it the same way Done does — so a picker waved away after a few ticks
/// still went through (Zach, 2026-09-14). Here the picker edits a working copy: Done hands it
/// back, Cancel and a swipe down throw it away.
struct ActivityPickerSheet: View {
    let header: String
    let footer: String
    let done: (FamilyActivitySelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var working: FamilyActivitySelection

    init(
        header: String,
        footer: String,
        initial: FamilyActivitySelection,
        done: @escaping (FamilyActivitySelection) -> Void
    ) {
        self.header = header
        self.footer = footer
        self.done = done
        _working = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(headerText: header, footerText: footer, selection: $working)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .tint(Ember.cream)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            done(working)
                            dismiss()
                        }
                        .tint(Ember.cream)
                    }
                }
        }
    }
}

/// Presents `ActivityPickerSheet` and hands the answer back only once the sheet has fully
/// gone, so what follows it (an editor push, an alert) never races the sheet on its way out.
private struct ActivityPickerPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let header: String
    let footer: String
    let initial: FamilyActivitySelection
    let done: (FamilyActivitySelection) -> Void
    /// Set by Done, read once the sheet is down. Cancel and a swipe down never set it.
    @State private var answer: FamilyActivitySelection?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            guard let picked = answer else { return }
            answer = nil
            done(picked)
        }) {
            ActivityPickerSheet(header: header, footer: footer, initial: initial) { answer = $0 }
        }
    }
}

extension View {
    /// Apple's picker with a real Cancel — see `ActivityPickerSheet`. `done` runs on Done only,
    /// with what was picked, after the sheet is down; `initial` is what the sheet opens showing.
    func activityPicker(
        isPresented: Binding<Bool>,
        header: String,
        footer: String,
        initial: FamilyActivitySelection,
        done: @escaping (FamilyActivitySelection) -> Void
    ) -> some View {
        modifier(ActivityPickerPresentation(
            isPresented: isPresented, header: header, footer: footer, initial: initial, done: done
        ))
    }
}

// Routes by choice and destination: Application goes straight to Apple's picker; Website lands
// on AddSiteSheet (typed address) first, with AddWebsiteGuideView + picker as the path to a
// daily budget. destination == .anchor shows what's already blocked, then the picker, landing
// in setAnchorSelection instead of a target. Set `request` to start it; it resets to nil once
// read. Every presentation is delayed briefly so it doesn't race a sheet/popover still leaving.
struct AddTargetsFlow: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var request: AddRequest?
    // Which of the two the picker was opened for; it wears a matching header and footer.
    @State private var pickerFor: AddChoice = .application
    // Under the anchor's everything-except scope, the same picker chooses what stays open
    // instead of what's held, so this also drives the picker's copy.
    @State private var pickerDestination: Half = .rules
    @State private var showFromRules = false
    @State private var pickerAfterFromRules = false
    // Set when the trip was the companion nudge's, so the answer is added beside that target
    // rather than read as the whole selection.
    @State private var pickerCompanion: AddRequest.Companion?
    @State private var companionOutcome: String?
    @State private var showSiteSheet = false
    // Set by the site sheet's second option, read once that sheet has finished dismissing.
    @State private var siteWantsPicker = false
    @State private var showWebsiteGuide = false
    @State private var guideWantsPicker = false
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var outcome: AppModel.PickerOutcome?

    func body(content: Content) -> some View {
        content
            .activityPicker(
                isPresented: $showPicker,
                header: pickerHeader,
                footer: pickerFooter,
                initial: selection
            ) { picked in
                if pickerDestination == .anchor {
                    model.setAnchorSelection(picked)
                    return
                }
                if let companion = pickerCompanion {
                    pickerCompanion = nil
                    companionOutcome = model.addCompanionApps(picked, for: companion).message
                    return
                }
                let result = model.applyPicker(picked)
                if result.added > 0 || result.removalsScheduled > 0 {
                    outcome = result
                }
            }
            .sheet(isPresented: $showFromRules, onDismiss: {
                guard pickerAfterFromRules else { return }
                pickerAfterFromRules = false
                openAnchorPicker()
            }) {
                AnchorFromRulesSheet(candidates: model.state.config.anchorCandidates) { ids in
                    model.addToAnchor(targetIDs: ids)
                } onPickOthers: {
                    pickerAfterFromRules = true
                }
            }
            .alert(
                "Added",
                isPresented: Binding(get: { companionOutcome != nil }, set: { if !$0 { companionOutcome = nil } }),
                presenting: companionOutcome
            ) { _ in
                Button("OK") { companionOutcome = nil }
            } message: { text in
                Text(text)
            }
            .alert(
                "Selection updated",
                isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } }),
                presenting: outcome
            ) { _ in
                Button("OK") { outcome = nil }
            } message: { outcome in
                Text(outcome.message)
            }
            .sheet(
                isPresented: $showSiteSheet,
                onDismiss: {
                    guard siteWantsPicker else { return }
                    siteWantsPicker = false
                    afterDismissal { showWebsiteGuide = true }
                }
            ) {
                AddSiteSheet { siteWantsPicker = true }
            }
            .sheet(
                isPresented: $showWebsiteGuide,
                onDismiss: {
                    guard guideWantsPicker else { return }
                    guideWantsPicker = false
                    openPicker(for: .website)
                }
            ) {
                AddWebsiteGuideView { guideWantsPicker = true }
            }
            .onChange(of: request) { _, asked in
                guard let asked else { return }
                request = nil
                if asked.destination == .anchor {
                    chooseForAnchor()
                    return
                }
                if let companion = asked.companion {
                    openPicker(for: asked.choice, companion: companion)
                    return
                }
                switch asked.choice {
                case .application: openPicker(for: .application)
                case .website: afterDismissal { showSiteSheet = true }
                }
            }
    }

    // Under everything-except scope the list is what stays open, so the picker is choosing
    // exceptions rather than what gets held.
    private var pickerHeader: String {
        if pickerDestination == .anchor {
            return model.state.config.anchor.anchorsEverything
                ? "Choose what stays open while anchored"
                : "Choose what the anchor holds"
        }
        return pickerCompanion.map { PickerCopy.companionHeader($0.title) } ?? PickerCopy.header(for: pickerFor)
    }

    private var pickerFooter: String {
        if pickerDestination == .anchor {
            return model.state.config.anchor.anchorsEverything
                ? "Picking a category keeps every app in it open."
                : "Picking a category locks every app in it."
        }
        return pickerCompanion == nil ? PickerCopy.footer(for: pickerFor) : PickerCopy.companionFooter
    }

    // An empty chosen-scope list offers what Furlough already blocks first, with Apple's picker
    // one tap further on; a non-empty list, or everything-except scope, goes straight to the picker.
    private func chooseForAnchor() {
        let anchor = model.state.config.anchor
        if anchor.scope == .chosen, anchor.kinds.isEmpty, !model.state.config.anchorCandidates.isEmpty {
            afterDismissal { showFromRules = true }
        } else {
            openAnchorPicker()
        }
    }

    private func openAnchorPicker() {
        pickerFor = .application
        pickerCompanion = nil
        pickerDestination = .anchor
        selection = model.anchorSelection
        afterDismissal { showPicker = true }
    }

    // Seeded with everything Furlough manages for the + button (unpicking there removes a
    // target), but empty for the companion nudge, which must only be able to answer its own question.
    private func openPicker(for choice: AddChoice, companion: AddRequest.Companion? = nil) {
        pickerFor = choice
        pickerCompanion = companion
        pickerDestination = .rules
        selection = companion == nil ? model.pickerSelection : FamilyActivitySelection()
        afterDismissal { showPicker = true }
    }

    private func afterDismissal(_ present: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            present()
        }
    }
}

extension View {
    func addTargetsFlow(_ request: Binding<AddRequest?>) -> some View {
        modifier(AddTargetsFlow(request: request))
    }
}

extension Companions.Half {
    var addChoice: AddChoice {
        switch self {
        case .sites: .website
        case .app: .application
        }
    }
}
