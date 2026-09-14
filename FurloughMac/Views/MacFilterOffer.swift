import SwiftUI

struct WebFilterOfferSheet: View {
    let host: String
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var filter: WebFilter { model.enforcer.webFilter }

    var body: some View {
        SheetFrame(title: "The web filter", width: 560, height: 620) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "One thing to allow", color: Ember.amber)
                    Text(headline)
                        .emberDisplay(30)
                        .foregroundStyle(Ember.cream)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    if filter.status == .notInstalled {
                        Text("\(host) is held in every browser Furlough knows — Safari, Chrome, Arc, Brave, Edge and the other Chromium ones. It reads the address bar and sends a blocked tab to the shield page, so macOS asks once per browser.")
                            .emberBody(14)
                            .foregroundStyle(Ember.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                        Text("It cannot see anything off that list: Firefox, a browser Furlough has not met, a site saved to the Dock, or an app that loads a page on its own. The web filter closes all of them at once — a system extension that refuses the connection itself, whatever opened it. It is the difference between a site that is awkward to reach and one that is not there.")
                            .emberBody(14)
                            .foregroundStyle(Ember.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    } else {
                        Text(filter.status.label)
                            .emberBody(13, .semibold)
                            .foregroundStyle(filter.status.isOn ? Ember.moss : Ember.pending)
                            .padding(.top, 14)
                    }
                    FilterDirections(guidance: filter.status.guidance, perform: filter.perform)
                        .padding(.top, 14)
                    buttons
                        .padding(.top, 24)
                    Footnote(text: "Settings > Web has these buttons whenever you want them. Furlough will not ask again.")
                        .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .task { await filter.refresh() }
        // onDisappear fires on any dismissal path, so this always counts as offered.
        .onDisappear { model.noteWebFilterOffered() }
    }

    private var headline: String {
        filter.status.isOn ? "The web filter is on." : "Held in Safari and Chrome."
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            switch filter.status {
            case .notInstalled, .failed:
                Button("Install the web filter") { filter.install() }
                    .emberGlassButton(prominent: true, tint: Ember.ember)
                    .keyboardShortcut(.defaultAction)
                // .glass alone inherits the window's ember tint; untinted explicitly so it
                // doesn't read as a second prominent button.
                Button("Not now") { dismiss() }
                    .emberGlassButton(tint: Ember.muted)
            case .awaitingApproval, .disabledInSettings, .filterOff, .filterDenied, .installing:
                Button("Done") { dismiss() }
                    .emberGlassButton()
                    .keyboardShortcut(.defaultAction)
            case .on, .notInApplications:
                Button("Done") { dismiss() }
                    .emberGlassButton(prominent: true, tint: Ember.ember)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }
}
