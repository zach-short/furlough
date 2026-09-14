import SwiftUI

/// Text lives in `release-notes.json` (bundled into both apps and the site) — one shape, not
/// two, since a list of changes shouldn't read differently on a Mac. Self-contained like
/// `LinkCards` for the same widget-extension reason; the version heading repeats
/// `SectionLabel`'s padding so it still lines up with other section headings.
struct ReleaseList: View {
    /// Only what applies to this device, which `ReleaseNotes.all(on:)` has already filtered.
    var releases: [ReleaseNotes.Release] = ReleaseNotes.all()
    /// Which one is the build in hand, so it can say so. Nil on a build the file does not cover.
    var current: Version? = ReleaseNotes.bundleVersion
    /// Passed rather than read from the running platform, so the filter and the badges can't
    /// disagree.
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

private struct ReleaseCard: View {
    let release: ReleaseNotes.Release
    let isCurrent: Bool
    let platform: ReleaseNotes.Platform

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // Labels above the headline, not beside it — a badge next to a two-line
                // headline would squeeze it to three.
                HStack(spacing: 8) {
                    Eyebrow(text: release.channel.label, color: Ember.faint, size: 9)
                    Spacer(minLength: 4)
                    // Repeated here (not just the list) so a bug report's version number is
                    // easy to confirm.
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

/// Kind is a word, not colour alone — colour is the only difference between New/Fixed
/// otherwise.
private struct ChangeRow: View {
    let change: ReleaseNotes.Change
    let platform: ReleaseNotes.Platform

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Eyebrow(text: change.kind.label, color: colour, size: 9)
                // Omitted for changes on this device (nearly all) — a badge on every row says
                // nothing.
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
