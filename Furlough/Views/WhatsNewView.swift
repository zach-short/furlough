import SwiftUI

/// What changed, version by version. Reached from Help and from Settings > About.
///
/// The list itself is `ReleaseList` in `Shared/UI`, drawn the same way on the Mac; this is the
/// phone's chrome around it. The text behind both is `release-notes.json`, the one copy, which
/// the site imports too.
///
/// It wears `HelpPage`'s chrome rather than its own, because it is read the way a help page is
/// read — a heading, a paragraph, then cards of short points — and a second kind of page would
/// be a second thing to learn for no gain. What it does not do is interrupt: no sheet throws
/// itself at you after an update. An app whose whole argument is that it will not nag you into
/// opening something has no business nagging you into reading its own release notes.
struct WhatsNewView: View {
    private let releases = ReleaseNotes.all()

    var body: some View {
        HelpPage(title: "What's new", heading: "What changed", lead: lead) {
            if releases.isEmpty {
                // The resource is missing or would not decode. Say so plainly rather than
                // showing an empty screen that reads as nothing having ever changed.
                HelpProse("The notes for this build could not be read. furloughapp.com/releases has them.")
                    .padding(.top, 12)
            } else {
                ReleaseList(releases: releases)
                Footnote(text: "Every version so far has gone to TestFlight rather than the App Store. The same notes are at furloughapp.com/releases.")
                    .padding(.top, 14)
            }
        }
    }

    /// Names the version in hand, since that is what someone opening this came to check. The
    /// plain sentence on a build `release-notes.json` has no entry for — a Debug build off a
    /// branch mid-version is exactly that, and it should not claim to be a release.
    private var lead: String {
        guard let current = ReleaseNotes.current() else {
            return "Each version of Furlough, newest first, and what it changed on this phone."
        }
        return "You are on \(current.version). \(current.headline) Every version is below, newest first."
    }
}
