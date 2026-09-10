import SwiftUI

/// What the app will not stop to explain while you are using it: what a rule means, why a
/// change waits, and the one way out. Reached from the question mark beside the gear on Home.
///
/// Nine pages, one idea each, in the app's own voice, and all nine of them here rather than
/// on the site — the pages are in `HelpTopics.swift`. Help is wanted at the moment the app is
/// in the way, which is no time to be handed to a browser that may itself be shielded, and
/// anything with a number in it reads the number out of the config rather than repeating the
/// default, so a phone with a week-long delay is not told about 24 hours.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

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
                    Footnote(text: "Every page here is in the app and needs no connection. The same topics are on furloughapp.com for anyone deciding whether to install Furlough; these are the copies that quote your own settings, and the ones still there when a shield sticks.")
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
            NavigationLink { WindowsHelp() } label: {
                HelpRow(title: "Windows and budgets", detail: "Hours you allow, minutes a day") {
                    HelpTile(symbol: "clock")
                }
            }
            .buttonStyle(.plain)
            CardDivider()
            NavigationLink { TargetsHelp() } label: {
                HelpRow(title: "Apps and websites", detail: "What Furlough can hold, and how to add it") {
                    HelpTile(symbol: "square.grid.2x2")
                }
            }
            .buttonStyle(.plain)
            CardDivider()
            NavigationLink { PickerHelp() } label: {
                HelpRow(title: "Apps the picker will not show", detail: "Safari, Settings, the App Store, Phone") {
                    HelpTile(symbol: "eye.slash")
                }
            }
            .buttonStyle(.plain)
        }
        .emberCard()
    }

    private var beyondCard: some View {
        VStack(spacing: 0) {
            NavigationLink { AnchorHelp() } label: {
                HelpRow(title: "The Anchor", detail: "One tap to lock. The tag to unlock.") {
                    AnchorGlyph(isAnchored: false)
                }
            }
            .buttonStyle(.plain)
            CardDivider()
            NavigationLink { DevicesHelp() } label: {
                HelpRow(title: "Across your devices", detail: "What the Anchor carries to your Mac") {
                    HelpTile(symbol: "laptopcomputer.and.iphone")
                }
            }
            .buttonStyle(.plain)
            CardDivider()
            NavigationLink { ElsewhereHelp() } label: {
                HelpRow(title: "Outside the app", detail: "Notifications, the widget, the lock screen") {
                    HelpTile(symbol: "bell")
                }
            }
            .buttonStyle(.plain)
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
            NavigationLink { AboutHelp() } label: {
                HelpRow(title: "About Furlough", detail: "What it keeps, and what leaves the phone") {
                    HelpTile(symbol: "info.circle")
                }
            }
            .buttonStyle(.plain)
        }
        .emberCard()
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
    let icon: Icon

    init(title: String, detail: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.detail = detail
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
            Image(systemName: "chevron.right")
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

/// A card of numbered steps, for the few places help has to be followed in order rather than
/// read. The numeral is the one `AddWebsiteGuideView` draws, so a set of steps looks the same
/// wherever the app gives them.
struct HelpSteps: View {
    struct Step: Identifiable {
        let title: String
        let detail: String
        var id: String { title }

        init(_ title: String, _ detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    let steps: [Step]

    init(_ steps: [Step]) { self.steps = steps }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 { CardDivider() }
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(EmberFont.numerals(13))
                        .monospacedDigit()
                        .foregroundStyle(Ember.amber)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.07), in: Circle())
                        .overlay(Circle().strokeBorder(Ember.cardBorder, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .emberDisplaySmall(14)
                            .foregroundStyle(Ember.cream)
                        Text(step.detail)
                            .emberBody(12)
                            .foregroundStyle(Ember.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step.title). \(step.detail)")
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
