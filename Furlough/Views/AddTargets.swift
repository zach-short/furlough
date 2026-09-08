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
}

/// The way to Apple's picker, from wherever the asking happened.
///
/// Website goes through `AddWebsiteGuideView` first, because the picker keeps sites three
/// steps in and the footer alone read as a broken button. Everything is presented after a
/// short wait: a sheet raised while a popover or the previous sheet is still leaving is
/// dropped. Set `request` to start it; it is put back to nil as soon as it is read, so the
/// same screen can ask again.
struct AddTargetsFlow: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var request: AddChoice?
    /// Which of the two the picker was opened for; it wears a matching header and footer.
    @State private var pickerFor: AddChoice = .application
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
                headerText: PickerCopy.header(for: pickerFor),
                footerText: PickerCopy.footer(for: pickerFor),
                isPresented: $showPicker,
                selection: $selection
            )
            .onChange(of: showPicker) { _, presented in
                guard !presented else { return }
                let result = model.applyPicker(selection)
                if result.added > 0 || result.removalsScheduled > 0 {
                    outcome = result
                }
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
                switch asked {
                case .application: openPicker(for: .application)
                case .website: afterDismissal { showWebsiteGuide = true }
                }
            }
    }

    /// Opens the picker once whatever came before it has gone.
    private func openPicker(for choice: AddChoice) {
        pickerFor = choice
        selection = model.pickerSelection
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
    func addTargetsFlow(_ request: Binding<AddChoice?>) -> some View {
        modifier(AddTargetsFlow(request: request))
    }
}

extension Companions.Half {
    /// Which side of the picker takes this one: an app straight there, a website through the
    /// guide, since Apple keeps sites three steps in.
    var addChoice: AddChoice {
        switch self {
        case .sites: .website
        case .app: .application
        }
    }
}
