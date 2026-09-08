import FamilyControls
import SwiftUI

/// What Apple's picker says on the way in. One place, because the phone opens the same picker
/// from more than one screen: the + button on Home, and the companion nudge in a rule editor.
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

    /// What the companion nudge's trip says instead. It is asking one question, so it says so:
    /// nothing here is removed by leaving it unpicked, and what is picked arrives already
    /// carrying the hours of the thing that offered it.
    static func companionHeader(_ title: String) -> String {
        title.isEmpty ? "Choose the app" : "Choose \(title)"
    }

    static let companionFooter = "It gets the same hours as the site it belongs with. Nothing else here changes."
}

/// The way to a new target, from wherever the asking happened.
///
/// Application goes straight to Apple's picker. Website lands on `AddSiteSheet` instead, where
/// the address is typed — the fast path, and Zach's call on 2026-09-08 — and only the person
/// who wants a daily limit on a site goes on from there to `AddWebsiteGuideView` and the
/// picker, which keeps sites three steps in where the footer alone read as a broken button.
///
/// Everything is presented after a short wait: a sheet raised while a popover or the previous
/// sheet is still leaving is dropped. Set `request` to start it; it is put back to nil as soon
/// as it is read, so the same screen can ask again.
struct AddTargetsFlow: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var request: AddRequest?
    /// Which of the two the picker was opened for; it wears a matching header and footer.
    @State private var pickerFor: AddChoice = .application
    /// Set when the trip was the companion nudge's, so the answer is added beside that target
    /// rather than read as the whole selection.
    @State private var pickerCompanion: AddRequest.Companion?
    @State private var companionOutcome: String?
    /// Typing a host: what Website opens now.
    @State private var showSiteSheet = false
    /// Set by the site sheet's second option, read once that sheet has finished dismissing.
    @State private var siteWantsPicker = false
    /// The three steps to a website, shown before the picker.
    @State private var showWebsiteGuide = false
    /// Set by the guide's button, read once the guide has finished dismissing.
    @State private var guideWantsPicker = false
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var outcome: AppModel.PickerOutcome?

    func body(content: Content) -> some View {
        content
            .familyActivityPicker(
                headerText: pickerCompanion.map { PickerCopy.companionHeader($0.title) }
                    ?? PickerCopy.header(for: pickerFor),
                footerText: pickerCompanion == nil ? PickerCopy.footer(for: pickerFor) : PickerCopy.companionFooter,
                isPresented: $showPicker,
                selection: $selection
            )
            .onChange(of: showPicker) { _, presented in
                guard !presented else { return }
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

    /// Opens the picker once whatever came before it has gone.
    ///
    /// Seeded with everything Furlough manages for the + button, because there the selection is
    /// the whole truth and unpicking is how a target is removed — and **empty** for the
    /// companion nudge, which is asking one question and must not be able to answer any other.
    private func openPicker(for choice: AddChoice, companion: AddRequest.Companion? = nil) {
        pickerFor = choice
        pickerCompanion = companion
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
    /// Adds the guide-and-picker path to a screen. Set the binding to ask for it.
    func addTargetsFlow(_ request: Binding<AddRequest?>) -> some View {
        modifier(AddTargetsFlow(request: request))
    }
}

extension Companions.Half {
    /// Which side of the picker takes this one: an app straight there, a website through the
    /// typing sheet, which no longer needs the picker at all.
    var addChoice: AddChoice {
        switch self {
        case .sites: .website
        case .app: .application
        }
    }
}
