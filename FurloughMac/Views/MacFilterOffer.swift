import SwiftUI

/// The web filter, offered at the moment it first means something: the first website.
///
/// It used to be the last pane of the first run. That asked for a trip to System Settings before
/// there was a single rule to enforce — the one step almost everybody met, paid up front for a
/// benefit that did not exist yet — and someone who only ever blocks applications was made to
/// answer for a feature that could never do anything for them. The filter does nothing at all
/// until some host is blocked, which is the same condition `Enforcer` already checks before it
/// reads a browser. So the offer waits for that, and arrives with the site that caused it named
/// at the top, where the reason for saying yes is on screen rather than hypothetical.
///
/// Asked once. `MacModel.hasOfferedWebFilter` closes the question either way, because Settings >
/// Web has the same buttons for anyone who changes their mind, and a sheet that came back on
/// every website added is one people learn to click past.
struct WebFilterOfferSheet: View {
    /// The site just added, named at the top so the offer is about something.
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
                        // The paragraph this whole sheet exists for. The old wording named
                        // Firefox and a Dock web app as if they were the whole of the gap, which
                        // reads as a short list of things nobody uses; the gap is everything off
                        // a list of fifteen bundle identifiers, and adding to it is a download.
                        Text("It cannot see anything off that list: Firefox, a browser Furlough has not met, a site saved to the Dock, or an app that loads a page on its own. The web filter closes all of them at once — a system extension that refuses the connection itself, whatever opened it. It is the difference between a site that is awkward to reach and one that is not there.")
                            .emberBody(14)
                            .foregroundStyle(Ember.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    } else {
                        // Once Install has been pressed, what the filter is matters less than
                        // what is being waited on, and the steps need the room.
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
        // Either answer closes the question, including closing the sheet by hand: the offer has
        // been made, and it is the making of it that is not worth repeating.
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
                    .buttonStyle(.glassProminent)
                    .tint(Ember.ember)
                    .keyboardShortcut(.defaultAction)
                Button("Not now") { dismiss() }
                    .buttonStyle(.glass)
            // Nothing but a way out for the states in the middle of the walk: their buttons
            // belong to the step that calls for them, in the directions above.
            case .awaitingApproval, .disabledInSettings, .filterOff, .filterDenied, .installing:
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.defaultAction)
            case .on, .notInApplications:
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(Ember.ember)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }
}
