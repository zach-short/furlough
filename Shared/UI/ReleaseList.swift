import SwiftUI

/// Every version and what it changed, as both apps draw it.
///
/// The text is not here: `release-notes.json` at the root of the repo is the one copy, bundled
/// into both apps and imported by the site, so a release cannot be described one way in the app
/// and another way on furloughapp.com. This is the shape it takes on screen, and it is one
/// shape rather than two because there is nothing about a list of changes that should read
/// differently on a Mac.
///
/// Self-contained the way `LinkCards` is — Ember and the theme helpers only, no `SectionLabel`,
/// `Footnote` or `CardDivider` — because Shared/UI is compiled into extensions that carry none
/// of each app's own components. The version heading repeats `SectionLabel`'s own padding so it
/// still sits where every other section heading in the app sits.
struct ReleaseList: View {
    /// Only what applies to this device, which `ReleaseNotes.all(on:)` has already filtered.
    var releases: [ReleaseNotes.Release] = ReleaseNotes.all()
    /// Which one is the build in hand, so it can say so. Nil on a build the file does not cover.
    var current: Version? = ReleaseNotes.bundleVersion
    /// The device the list was filtered for, which decides which changes wear a badge. Passed
    /// rather than read from the platform this binary is, so that the two cannot disagree — a
    /// list filtered for the phone must not badge its own rows "iPhone".
    var platform: ReleaseNotes.Platform = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(releases) { release in
                Eyebrow(text: "\(release.version) · \(release.dayLabel)", color: Ember.faint, size: 10.5)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                ReleaseCard(release: release, isCurrent: release.number == current, platform: platform)
            }
        }
    }
}

/// One version: what it was for, then every change in it.
private struct ReleaseCard: View {
    let release: ReleaseNotes.Release
    let isCurrent: Bool
    let platform: ReleaseNotes.Platform

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // Both labels on one line above the headline rather than around it: the
                // headline is the only thing on the card allowed to wrap, and a badge beside a
                // two-line headline squeezes it into three.
                HStack(spacing: 8) {
                    Eyebrow(text: release.channel.label, color: Ember.faint, size: 9)
                    Spacer(minLength: 4)
                    // Worth carrying on the card rather than only in the list: someone reading a
                    // version number back off a bug report wants to know which of these they
                    // are actually running.
                    if isCurrent {
                        Eyebrow(text: "This build", color: Ember.amber, size: 9)
                    }
                }
                Text(release.headline)
                    .emberDisplaySmall(14.5)
                    .foregroundStyle(Ember.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Text(release.lead)
                    .emberBody(12)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            ForEach(release.changes) { change in
                Rectangle().fill(Ember.cardBorder).frame(height: 1)
                ChangeRow(change: change, platform: platform)
            }
        }
        .emberCard()
    }
}

/// One change: what kind it is, then the thing, then what it means. The kind is a word and not
/// a colour alone — the colour is the only thing separating New from Fixed, and the difference
/// between those two is worth reading without one.
private struct ChangeRow: View {
    let change: ReleaseNotes.Change
    let platform: ReleaseNotes.Platform

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Eyebrow(text: change.kind.label, color: colour, size: 9)
                // Nothing at all on a change that is for this device, which is nearly all of
                // them: a badge on every row is a badge that says nothing.
                if let badge = change.platform.badge(on: platform) {
                    Eyebrow(text: badge, color: Ember.faint, size: 9)
                }
            }
            Text(change.title)
                .emberDisplaySmall(13.5)
                .foregroundStyle(Ember.cream)
                .fixedSize(horizontal: false, vertical: true)
            Text(change.detail)
                .emberBody(12)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.kind.label). \(change.title). \(change.detail)")
    }

    private var colour: Color {
        switch change.kind {
        case .new: Ember.amber
        case .better: Ember.moss
        case .fixed: Ember.ember
        }
    }
}
