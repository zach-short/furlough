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
            .familyActivityPicker(
                headerText: pickerHeader,
                footerText: pickerFooter,
                isPresented: $showPicker,
                selection: $selection
            )
            .onChange(of: showPicker) { _, presented in
                guard !presented else { return }
                if pickerDestination == .anchor {
                    model.setAnchorSelection(selection)
                    return
                }
                if let companion = pickerCompanion {
                    pickerCompanion = nil
                    companionOutcome = model.addCompanionApps(selection, for: companion).message
                    return
                }
                let result = model.applyPicker(selection)
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
