import SwiftUI

/// What the app will not stop to explain while you are using it: what a rule means, why a
/// change waits, and the one way out. Reached from the question mark beside the gear on Home.
///
/// Eight topics, one idea each, in the app's own voice. Two are pages in the app and six open
/// furloughapp.com — the split is in `HelpTopics.swift`, and it is the difference between a
/// topic that has to read this phone's own settings and one that is the same on every phone.
/// Anything with a number in it reads the number out of the config rather than repeating the
/// default, so a phone with a week-long delay is not told about 24 hours.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    SectionLabel(text: "The rules")
                    rulesCard
                    SectionLabel(text: "Beyond the rules")
                    beyondCard
                    SectionLabel(text: "If you need it")
                    needCard
                    Footnote(text: "Rows with an arrow open furloughapp.com in Safari, where a page can be corrected without an app update. The two that stay here need no connection: one reads the delay off your own settings, and the other is what you want when a shield sticks, which is no time to go looking for a browser.")
                        .padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
            }
            .background(EmberWall())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Help")
                        .emberBody(15, .semibold)
                        .foregroundStyle(Ember.cream)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Ember.cream)
                }
            }
        }
        .presentationBackground(Ember.ground)
    }

    /// The whole app in three sentences, so someone who reads nothing else has the shape of it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Furlough", color: Ember.amber)
                .padding(.top, 8)
            Text("No unblock button.")
                .emberDisplay(28)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Pick what eats your time. Give each one a daily budget, and the hours it is allowed if you want them. Outside those hours, or once the budget is spent, iOS shields it.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("Making a rule tighter applies at once. Making it looser waits.")
                .emberBody(14.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.horizontal, 8)
    }

    private var rulesCard: some View {
        VStack(spacing: 0) {
            NavigationLink { DelayHelp() } label: {
                HelpRow(title: "Why changes wait", detail: "The delay, and what shortens it") {
                    HelpTile(symbol: "hourglass")
                }
            }
            .buttonStyle(.plain)
            CardDivider()
            linkRow("Windows and budgets", "Hours you allow, minutes a day", page: "windows-and-budgets") {
                HelpTile(symbol: "clock")
            }
            CardDivider()
            linkRow("Apps and websites", "What Furlough can hold, and how to add it", page: "apps-and-websites") {
                HelpTile(symbol: "square.grid.2x2")
            }
            CardDivider()
            linkRow("Apps the picker will not show", "Safari, Settings, the App Store, Phone", page: "beyond-the-picker") {
                HelpTile(symbol: "eye.slash")
            }
        }
        .emberCard()
    }

    private var beyondCard: some View {
        VStack(spacing: 0) {
            linkRow("The Anchor", "One tap to lock. The tag to unlock.", page: "the-anchor") {
                AnchorGlyph(isAnchored: false)
            }
            CardDivider()
            linkRow("Outside the app", "Notifications, the widget, the lock screen", page: "outside-the-app") {
                HelpTile(symbol: "bell")
            }
        }
        .emberCard()
    }

    private var needCard: some View {
        VStack(spacing: 0) {
            NavigationLink { StuckHelp() } label: {
                HelpRow(title: "If something gets stuck", detail: "What to try, and the one way out") {
                    HelpTile(symbol: "wrench.and.screwdriver")
                }
            }
            .buttonStyle(.plain)
            CardDivider()
            linkRow("About Furlough", "What it keeps, and what leaves the phone", page: "about") {
                HelpTile(symbol: "info.circle")
            }
        }
        .emberCard()
    }

    /// A row that leaves the app. The topics with no live data in them are written on the site
    /// rather than compiled in, so a sentence that turns out to be wrong can be fixed the same
    /// day instead of waiting on a review. Tapping one hands the address to Safari; Furlough
    /// makes no request itself, which is why the About page can still say it has no network
    /// code at all.
    private func linkRow<Icon: View>(
        _ title: String,
        _ detail: String,
        page: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            if let url = Furlough.helpURL(page) { openURL(url) }
        } label: {
            HelpRow(title: title, detail: detail, isExternal: true, icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens furloughapp.com in Safari")
    }
}

// MARK: - The pieces the pages are built from

/// A symbol in the tile every other icon in the app wears: the proportions are `TokenTile`'s,
/// so a help row and an app row read as the same list.
struct HelpTile: View {
    let symbol: String
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Ember.amber)
            .frame(width: size, height: size)
            .background(
                Color.white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Ember.cardBorder, lineWidth: 1)
            )
    }
}

/// One topic on the hub: its mark, what it covers, and where it goes.
struct HelpRow<Icon: View>: View {
    let title: String
    let detail: String
    /// Whether the row opens the site rather than pushing a page. Only the chevron changes:
    /// an arrow leaving the corner is the one bit of chrome that says a tap leaves the app.
    let isExternal: Bool
    let icon: Icon

    init(title: String, detail: String, isExternal: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.detail = detail
        self.isExternal = isExternal
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .emberDisplaySmall(13.5)
                    .foregroundStyle(Ember.cream)
                Text(detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: isExternal ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ember.faint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// The chrome every help page shares: the wall, the title in the bar, a display heading, the
/// one paragraph that answers the question, and then the detail.
struct HelpPage<Content: View>: View {
    let title: String
    let heading: String
    let lead: String
    let content: Content

    init(title: String, heading: String, lead: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.heading = heading
        self.lead = lead
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(heading)
                    .emberDisplay(26)
                    .foregroundStyle(Ember.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                Text(lead)
                    .emberBody(14.5)
                    .foregroundStyle(Ember.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 48)
        }
        .background(EmberWall())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .emberBody(15, .semibold)
                    .foregroundStyle(Ember.cream)
            }
        }
    }
}

/// A card of short points: the thing named, then what it does. The unit every help page is
/// written in, so no page turns into an essay.
struct HelpPoints: View {
    struct Point: Identifiable {
        let title: String
        let detail: String
        var id: String { title }

        init(_ title: String, _ detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    let points: [Point]

    init(_ points: [Point]) { self.points = points }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                if index > 0 { CardDivider() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.title)
                        .emberDisplaySmall(14)
                        .foregroundStyle(Ember.cream)
                    Text(point.detail)
                        .emberBody(12)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .emberCard()
    }
}

/// A paragraph with no card under it, for the one thing on a page that is not a list.
struct HelpProse: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .emberBody(12.5)
            .foregroundStyle(Ember.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}
