import SwiftUI

/// `ReleaseList` (`Shared/UI`) is the same view used on the Mac, backed by the single
/// `release-notes.json` that the site also imports.
struct WhatsNewView: View {
    private let releases = ReleaseNotes.all()

    var body: some View {
        HelpPage(title: "What's new", heading: "What changed", lead: lead) {
            if releases.isEmpty {
                // Missing/undecodable resource: say so rather than showing a blank "nothing changed" screen.
                HelpProse("The notes for this build could not be read. furloughapp.com/releases has them.")
                    .padding(.top, 12)
            } else {
                ReleaseList(releases: releases)
                Footnote(text: "The same notes are at furloughapp.com/releases.")
                    .padding(.top, 14)
            }
        }
    }

    /// Three cases: this build changed something; it shipped but changed nothing on this
    /// device (so the list below starts at an older version); or it has no entry at all
    /// (a Debug build off a branch mid-version).
    private var lead: String {
        if let current = ReleaseNotes.current() {
            return "You are on \(current.version). \(current.headline) Every version is below, newest first."
        }
        if let build = ReleaseNotes.bundleRelease() {
            return "You are on \(build.version), which changed nothing on the iPhone. Every version is below, newest first."
        }
        return "Each version of Furlough, newest first, and what it changed on this phone."
    }
}
