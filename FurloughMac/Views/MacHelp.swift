import SwiftUI

// Some pieces below are duplicated from the phone's HelpView.swift on purpose — the two sides
// move at different times. Unify into Shared/UI once both are quiet.

enum HelpTopic: String, Identifiable, CaseIterable {
    case windows, delay, targets, blocking, devices, elsewhere, stuck, about, whatsNew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: "Windows and budgets"
        case .delay: "Why changes wait"
        case .targets: "Apps and websites"
        case .blocking: "How blocking works here"
        case .devices: "The Anchor"
        case .elsewhere: "Outside the window"
        case .stuck: "If something gets stuck"
        case .about: "About"
        case .whatsNew: "What's new"
        }
    }

    var detail: String {
        switch self {
        case .windows: "Hours you allow, minutes a day"
        case .delay: "The delay, and what shortens it"
        case .targets: "What Furlough can hold, and how to add it"
        case .blocking: "No Screen Time on the Mac, so Furlough does it"
        case .devices: "One tap here. Your phone's tag lifts it."
        case .elsewhere: "The menu bar, the widget, notifications"
        case .stuck: "What to try, and the one way out"
        case .about: "What it keeps, and what leaves this Mac"
        case .whatsNew: ReleaseNotes.current().map { "\($0.version) · \($0.headline)" } ?? "What changed, version by version"
        }
    }

    var symbol: String {
        switch self {
        case .windows: "clock"
        case .delay: "hourglass"
        case .targets: "square.grid.2x2"
        case .blocking: "bolt.shield"
        case .devices: "laptopcomputer.and.iphone"
        case .elsewhere: "menubar.arrow.up.rectangle"
        case .stuck: "wrench.and.screwdriver"
        case .about: "info.circle"
        case .whatsNew: "sparkles"
        }
    }
}

// Window (not sheet), so the page can't be passed as an argument — callers must set topic
// before opening it.
@MainActor
@Observable
final class HelpRoute {
    static let windowID = "help"
    var topic: HelpTopic?
}

// A View, not a plain closure: openWindow is only readable via @Environment in a View, and
// menu commands don't inherit a window's environment.
struct HelpMenuItem: View {
    let route: HelpRoute
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Furlough Help") {
            route.topic = nil
            openWindow(id: HelpRoute.windowID)
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

// A window, not a sheet: sheets can't stack, and this needs to open from within one (the
// Anchor's phone link).
struct HelpWindow: View {
    @Environment(HelpRoute.self) private var route

    var body: some View {
        ZStack {
            EmberWall()
            VStack(spacing: 0) {
                // No title bar — this strip sits under the traffic lights and drags the window.
                Color.clear.frame(height: 32)
                if let topic = route.topic {
                    HelpPage(topic: topic) { route.topic = nil }
                } else {
                    hub
                }
            }
        }
        .frame(minWidth: 460, minHeight: 380)
        .preferredColorScheme(.dark)
        .tint(Ember.ember)
    }

    private var hub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                SectionLabel(text: "The rules")
                card([.windows, .delay, .targets])
                SectionLabel(text: "The Anchor")
                card([.devices])
                SectionLabel(text: "On this Mac")
                card([.blocking, .elsewhere])
                SectionLabel(text: "If you need it")
                card([.stuck, .about, .whatsNew])
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        // AppKit scroll views measure from the bottom; long wrapped text opens partway down
        // without this.
        .defaultScrollAnchor(.top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Furlough", color: Ember.amber)
                .padding(.top, 6)
            Text("No unblock button.")
                .emberDisplay(26)
                .foregroundStyle(Ember.cream)
                .padding(.top, 6)
            Text("Two ways to put an app out of reach. A rule gives it a daily budget, and the hours it is allowed if you want them; outside those, or once the budget is spent, Furlough closes it. Making a rule tighter applies at once. Making it looser waits.")
                .emberBody(13.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text("The Anchor is the other. One tap locks a list, or this whole Mac, and the only thing that lifts it is an NFC tag scanned on your iPhone.")
                .emberBody(13.5)
                .foregroundStyle(Ember.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 8)
    }

    private func card(_ topics: [HelpTopic]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(topics.enumerated()), id: \.element.id) { index, item in
                if index > 0 { CardDivider() }
                Button { route.topic = item } label: {
                    HelpRow(topic: item)
                }
                .buttonStyle(.plain)
            }
        }
        .emberCard()
    }
}

// MARK: - The pieces the pages are built from

struct HelpTile: View {
    let symbol: String
    var size: CGFloat = 32

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

struct HelpRow: View {
    let topic: HelpTopic

    var body: some View {
        HStack(spacing: 10) {
            HelpTile(symbol: topic.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(topic.title)
                    .emberDisplaySmall(13.5)
                    .foregroundStyle(Ember.cream)
                Text(topic.detail)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
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
                        .emberDisplaySmall(13.5)
                        .foregroundStyle(Ember.cream)
                    Text(point.detail)
                        .emberBody(12)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
        }
        .emberCard()
    }
}

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

// MARK: - The pages

struct HelpPage: View {
    @Environment(MacModel.self) private var model
    let topic: HelpTopic
    let onBack: () -> Void
    #if DEBUG || TESTING_TOOLS
    @State private var askedForTesting = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { onBack() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text("Help").emberBody(12.5, .semibold)
                    }
                    .foregroundStyle(Ember.ember)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(heading)
                        .emberDisplay(24)
                        .foregroundStyle(Ember.cream)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                    Text(lead)
                        .emberBody(13.5)
                        .foregroundStyle(Ember.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    body(for: topic)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            // Same bottom-anchored scroll issue as the hub.
            .defaultScrollAnchor(.top)
        }
    }

    private var heading: String {
        switch topic {
        case .windows: "Hours and minutes"
        case .delay: "Tighter now, looser later"
        case .targets: "What Furlough can hold"
        case .blocking: "No Screen Time on the Mac"
        case .devices: "One Anchor, both devices"
        case .elsewhere: "Where Furlough shows up"
        case .stuck: "When a block will not lift"
        case .about: "About Furlough"
        case .whatsNew: "What changed"
        }
    }

    private var lead: String {
        switch topic {
        case .windows:
            "Every app and site you add gets a daily budget and, if you want, the hours it is allowed. Whichever runs out first closes it until the next opening."
        case .delay:
            "Furlough has no unblock button. What it has instead is a delay. Anything that gives you back time waits it out, and you can cancel it while it does."
        case .targets:
            "The + button asks Application or Website. An app is any app on this Mac; a website is an address you type."
        case .blocking:
            "Apple's Screen Time API does not exist on macOS — FamilyControls, ManagedSettings and DeviceActivity are all unavailable — so nothing here can ask the system to shield an app. Furlough shares the phone's rules engine and does the blocking itself."
        case .devices:
            "Furlough on this Mac and Furlough on your iPhone share one Anchor. There is nothing to pair and nothing to switch on: both are signed into your Apple Account, and that is the whole of the link."
        case .elsewhere:
            "The window is where rules are written. Almost everything else happens while it is closed."
        case .stuck:
            "Furlough re-derives every block from saved state once a second, so drift is rare and short. If something still looks wrong:"
        case .about:
            "A personal app blocker with no unblock button. It has no account, no server and no analytics. The one thing it writes off this Mac is the Anchor's state, to your own iCloud, so the iPhone and the Mac lock together."
        case .whatsNew:
            whatsNewLead
        }
    }

    private var whatsNewLead: String {
        if let current = ReleaseNotes.current() {
            return "You are on \(current.version). \(current.headline) Every version is below, newest first."
        }
        if let build = ReleaseNotes.bundleRelease() {
            return "You are on \(build.version), which changed nothing on the Mac. Every version is below, newest first."
        }
        return "Each version of Furlough, newest first, and what it changed on this Mac."
    }

    @ViewBuilder
    private func body(for topic: HelpTopic) -> some View {
        switch topic {
        case .windows: windows
        case .delay: delay
        case .targets: targets
        case .blocking: blocking
        case .devices: devices
        case .elsewhere: elsewhere
        case .stuck: stuck
        case .about: about
        case .whatsNew: whatsNew
        }
    }

    // MARK: Windows and budgets

    @ViewBuilder
    private var windows: some View {
        SectionLabel(text: "The two limits")
        HelpPoints([
            .init("A window", "The hours an app is allowed, on the days you pick. With no windows at all it is open all day, up to its budget."),
            .init("A budget", "Minutes a day. Furlough counts them itself: a minute is spent while the app or site is in front of you and you have touched the Mac in the last two minutes. It resets at midnight."),
            .init("Together", "A 30-minute budget inside an 8:00–10:00 PM window is 30 minutes, in that window. The rest of the evening is closed either way."),
        ])

        SectionLabel(text: "Writing them")
        HelpPoints([
            .init("Same every day", "On to begin with. Turn it off and each window gets its own strip of weekdays: midnight on school nights, 2:00 AM on weekends."),
            .init("Past midnight", "Set 5:00 PM → 4:00 AM and the row is marked +1. Furlough keeps it as the evening and the early hours of the next day, and reads it back as the one night you wrote."),
            .init("Visualize windows", "The week as a grid. Click a day to see and change just its hours, then apply those hours to any other days."),
            .init("Copying a rule", "Use windows from another app pulls one in. Apply these windows to other apps pushes this one out to as many as you like, each judged on its own."),
        ])

        Footnote(text: "A window must be at least 15 minutes long, and a night that runs past midnight needs that much on each side of it. A window that overlaps another on the same day is refused before it can be saved.")
            .padding(.top, 10)
    }

    // MARK: Why changes wait

    @ViewBuilder
    private var delay: some View {
        SectionLabel(text: "The two directions")
        HelpPoints([
            .init("Applies the moment you save", "Shrinking a window, removing one, taking a day off it, lowering a budget, giving an app its first window, and raising the delay."),
            .init("Waits", "Extending or adding a window, adding a day to one, raising a budget, removing the last window, removing an app, and lowering the delay."),
            .init("The first rule is free", "Adding an app enforces nothing. Its first rule is always tighter than nothing, so it lands at once."),
        ])

        SectionLabel(text: "How much it is worth")
        HelpProse("Each app sits in one of four tiers, set at the bottom of its rule. The tier scales the delay, because needing your mail back is not the same as needing Twitter back. Your base delay is \(TimeFormat.delay(hours: model.state.config.loosenDelayHours)).")
            .padding(.top, 2)
        HelpPoints(Utility.allCases.map { tier in
            HelpPoints.Point(tier.label, "\(tier.summary) Waits \(TimeFormat.delay(hours: model.state.config.delayHours(for: tier))).")
        })
        .padding(.top, 10)
        Footnote(text: "A new app is Useful until you say otherwise. Moving one toward Hazard lengthens its delay, so it applies now. Moving it toward Essential shortens it, which is itself a loosening, so it queues behind the delay that app has today.")
            .padding(.top, 8)

        SectionLabel(text: "While a change waits")
        HelpPoints([
            .init("The pending button", "The clock in the header carries the count. Each change shows the rule you have against the one waiting, so what it costs stays readable."),
            .init("Cancelling", "Any pending change can be taken back until it lands. A notification an hour beforehand is the reminder that there is still time."),
            .init("Lowering the delay", "It loosens every app at once, so it waits out the longest delay in play — the slowest tier you have set, not the base."),
        ])

        SectionLabel(text: "The clock")
        HelpProse("Moving the Mac's clock forward does not buy time. Every save records the wall clock beside the machine's own count of seconds since it booted, which nothing in System Settings can change. When the two disagree by more than ten minutes, every queued loosening is held. Tightening still applies. Setting the clock back releases them.")
            .padding(.top, 2)
    }

    // MARK: Apps and websites

    @ViewBuilder
    private var targets: some View {
        SectionLabel(text: "The two kinds")
        HelpPoints([
            .init("An app", "Any app on this Mac, picked by name. Furlough holds on to its bundle identifier, so the rule follows the app rather than where it happens to sit on disk."),
            .init("A website", "Type youtube.com and it covers m.youtube.com too: the host and every subdomain, in every browser Furlough can read. Sites get budgets here, because Furlough counts the time itself."),
        ])

        SectionLabel(text: "Once it is added")
        HelpPoints([
            .init("Nothing is enforced yet", "Adding is instant and changes nothing at all. Saving the first rule is what starts it."),
            .init("Nicknames", "A nickname takes the app's place on the shield card, in the menu bar's menu and on the widget."),
            .init("The other half", "Blocking the YouTube app and leaving youtube.com open is the gap most people find a week later. Furlough offers the other side when it recognises one, in both directions — including a site whose browser wrapper is installed here as an app."),
        ])

        Footnote(text: "Rules are per device. A Mac target is a bundle identifier or a host, and the phone's is an opaque Screen Time token, so nothing syncs between them. Settings > Download my setup moves a Mac setup to another Mac whole.")
            .padding(.top, 10)
    }

    // MARK: How blocking works here

    @ViewBuilder
    private var blocking: some View {
        SectionLabel(text: "A blocked app")
        HelpPoints([
            .init("Asked to quit", "The moment it launches, or the moment its window closes under it. A floating card says what was blocked and when it opens next."),
            .init("Time to save", "An app that has been open a while gets 45 seconds to answer a Save changes? dialog, counted down on the card, before it is force-quit. One that has only just launched has nothing to save and goes at once, so relaunching buys nothing."),
        ])

        SectionLabel(text: "A blocked site")
        HelpPoints([
            .init("Every browser, not just the front one", "Furlough reads the address of each window's front tab in Safari and the Chromium browsers — Chrome, Arc, Brave, Edge, Vivaldi, Opera, Dia — and sends the ones showing a blocked site to its shield page."),
            .init("macOS asks once per browser", "The first time Furlough reads that browser while a site has a rule. Refusing means that browser is not enforced; Settings > Web shows which are allowed, and System Settings > Privacy & Security > Automation is where to change it."),
            .init("Everywhere else: the web filter", "A system extension that sees every connection this Mac opens and refuses the ones to a blocked site, from any app — Firefox, a site saved to the Dock, anything that loads a site outside a browser. Those get the floating card rather than the shield page. macOS asks twice before it runs, and Settings > Web says whether it is on."),
            .init("What the filter cannot see", "A connection with no name on it. An app that hides the name with Encrypted Client Hello, or connects to a bare address, gets through the filter; the tab reader still catches it in the browsers it can read."),
        ])

        SectionLabel(text: "Underneath")
        HelpProse("Once a second Furlough re-derives the whole picture from saved state: which apps are blocked, which tabs are on a blocked site, and how much of today's budget each thing has spent. Nothing is remembered between ticks that could drift out of step with the rules, which is why closing the window or restarting the Mac changes nothing about what is enforced.")
            .padding(.top, 2)
    }

    // MARK: Across your devices

    // Live lines read from the model rather than hardcoded — both can change while this page
    // is open.
    @ViewBuilder
    private var devices: some View {
        HelpProse("No account of Furlough's and no server of Furlough's: the link rides on your own iCloud, under your Apple Account. Each device joins from its own Devices screen — Settings > Devices here — and nothing crosses to or from one that has not. What there is to manage is the roster: every device that has joined, by the name you gave it, and any can be taken off from any other, except while the anchor is down.")
            .padding(.top, 12)

        SectionLabel(text: "What crosses")
        HelpPoints([
            .init("The Anchor's state", "Whether it is down, since when, and until when. Furlough writes it to your own iCloud, where only your devices can read it."),
            .init("The names of what you add", "If you let it — Settings > Devices, Always, Ask or Never — adding something here tells the other devices its name, and each blocks what it can find: an iPhone blocks the site at once and is offered the app in Apple's picker. What comes the other way lands here as the app if this Mac has it, and the site either way. A first rule follows the name."),
            .init("Not your rules or your list", "This Mac names an app with a bundle identifier, which means nothing on a phone, and Screen Time names one with a token, which means nothing off the phone that minted it. So each device keeps its own list — see Moving a setup across below."),
            .init("Not your tags", "A tag is a physical key, read over NFC. This Mac has no reader, so every tag is paired on an iPhone, and an iPhone is the only place one can be read."),
        ])

        SectionLabel(text: "Which way it goes")
        HelpPoints([
            .init("Drop here, and your iPhone locks", "Whatever the phone's own Anchor list holds is shielded there too — its list, not this one, because the lists cannot travel."),
            .init("Drop on the iPhone, and this Mac locks", "The same, the other way round. Either device can start it."),
            .init("Only the phone's tag releases either", "With no reader this Mac has no key of its own. An anchor dropped here waits for a scan on your iPhone, and there is no way round that from this side — which is the point of it."),
            .init("Where this Mac stands", cloudAndPhoneLine),
        ])

        SectionLabel(text: "When it does not cross")
        HelpPoints([
            .init("Out of signal", "Nothing unlocks by going offline. Each device keeps the state it has and sends what it wrote when it can reach iCloud again."),
            .init("About half a minute", "How long a drop on the phone takes to reach this Mac. Furlough asks iCloud again on that beat whether or not it has been told anything changed."),
            .init("Signed out of iCloud", "The Anchor stops at the device it was dropped on, and this Mac then refuses to drop one at all: your tag could not reach it, so the lock would have no key. The Anchor screen says so rather than letting you find out at the tag."),
        ])

        SectionLabel(text: "Moving a setup across")
        HelpProse("Since rules cannot sync, they travel as a file instead. Settings > Your setup writes your rules, budgets, tiers and delay as JSON; the other device opens it and shows you every line before anything happens.")
            .padding(.top, 2)
        HelpPoints([
            .init("A proposal, never a restore", "Every rule in a file goes through the same gate the editor does, so the tightenings land and the loosenings wait out your delay. A file cannot hand you back time by going round it."),
            .init("A Mac file travels whole", "An app here is a bundle identifier and a site is an address, and another Mac can look either one up. A file from a phone carries every rule but can only say what each app was called, because a token cannot travel."),
            .init("The Anchor is not in it", "Its list is this Mac's own and its key is a physical tag, so none of it would survive the trip. A file that looked like it carried the Anchor would be worse than one that plainly does not."),
        ])

        SectionLabel(text: "Turning it off")
        HelpProse("Settings > Devices takes this Mac off the link, or any other device off it from here. Refused while the anchor is down, on any device: taking one off then would either leave it locked with no key or let it go, and both are the thing the Anchor exists to make impossible. Signing out of iCloud, or turning off iCloud Drive in System Settings, stops everything crossing too — and stops this Mac dropping one. Nothing already anchored is released by any of that.")
            .padding(.top, 2)
    }

    // Order must match AnchorSync.macDrop's decision order, or the text and button could
    // disagree.
    private var cloudAndPhoneLine: String {
        if !model.cloudAvailable {
            return "Right now Furlough cannot reach iCloud, so this Mac will not drop the anchor at all. Turn on iCloud Drive in System Settings > your name > iCloud."
        }
        if !model.isEnrolled {
            return "This Mac is not on the link, so Drop anchor is refused here and nothing crosses either way. Settings > Devices puts it on."
        }
        if !model.hasKey {
            return "This Mac is on the link, but no iPhone is, so Drop anchor is refused here: only an iPhone's tag could release it. Link your iPhone from its own Devices screen and this Mac can drop whenever you like."
        }
        return "This Mac and an iPhone are both on the link, so Drop anchor works here. Without the iPhone it is refused, because a Mac that locked itself with no phone to unlock it would be a lock with nothing to open it."
    }

    // MARK: Outside the window

    @ViewBuilder
    private var elsewhere: some View {
        SectionLabel(text: "On the screen")
        HelpPoints([
            .init("The menu bar", "Furlough's hourglass, drawn at the level this moment has reached and redrawn as the sand moves. Its menu carries the countdown and every app's status."),
            .init("The desktop widget", "Edit Widgets on the desktop or in Notification Center, then add Furlough. It reads the same rules the app does."),
            .init("The shield card", "The floating card shown when a blocked app is closed: what it was, and when it opens next."),
        ])

        SectionLabel(text: "Notifications")
        HelpPoints([
            .init("Five minutes left", "Once when a window is five minutes from closing, and once when a budget is five minutes from running out."),
            .init("Time's up", "When a budget is spent, with the next opening if there is one."),
            .init("Around a pending change", "One an hour before a queued loosening lands, while you can still cancel it, and one when it lands."),
        ])

        SectionLabel(text: "Asking")
        HelpPoints([
            .init("What's Open", "Furlough's one Shortcut. It says what is open now and when the next thing opens, without bringing the window forward. It changes nothing, so it is always allowed."),
            .init("Open at login", "On by default, under Settings > Enforcement. Furlough enforces nothing while it is not running, so it is meant to be running."),
        ])
    }

    // MARK: If something gets stuck

    @ViewBuilder
    private var stuck: some View {
        SectionLabel(text: "What to try")
        HelpPoints([
            .init("Re-apply enforcement now", "Settings > Diagnostics. Does the whole pass again on demand rather than waiting for the next tick."),
            .init("A site is not blocked", "Settings > Web. A browser marked Refused is not enforced; Ask for browser access now puts the question again, and System Settings > Privacy & Security > Automation is where a past refusal is undone. If the web filter says Off in System Settings, General > Login Items & Extensions > Network Extensions is where it went."),
            .init("Activity log", "Settings > Diagnostics > Activity log. Says what Furlough has been doing and when, including every block it applied and every browser it could not read."),
        ])

        SectionLabel(text: "The one escape")
        HelpProse("Furlough blocks by quitting apps and redirecting tabs, so it has to keep running: Quit is refused while anything is blocked. Force Quit (Option-Command-Escape) ends enforcement, the way turning off Screen Time access does on the phone, and it is documented on purpose. Logging out and shutting down are always allowed.")
            .padding(.top, 2)
        Footnote(text: "With Reopen after a Force Quit on, a launchd agent opens Furlough again within about ten seconds. Force Quit still lifts every block; it just buys seconds rather than an evening.")
            .padding(.top, 8)
    }

    // MARK: What's new

    // Backed by release-notes.json, shared with the phone and the site.
    @ViewBuilder
    private var whatsNew: some View {
        let releases = ReleaseNotes.all()
        if releases.isEmpty {
            HelpProse("The notes for this build could not be read. furloughapp.com/releases has them.")
                .padding(.top, 12)
        } else {
            ReleaseList(releases: releases)
            Footnote(text: "Every version so far has gone to TestFlight rather than the App Store, and the Mac app is built from source. The same notes are at furloughapp.com/releases.")
                .padding(.top, 14)
        }
    }

    // MARK: About

    @ViewBuilder
    private var about: some View {
        SectionLabel(text: "What stays on this Mac")
        HelpPoints([
            .init("Everything", "Your apps, sites, rules and today's minutes live in a container this app and its widget share, under ~/Library/Group Containers. Nothing is uploaded and nothing syncs."),
            .init("What Furlough reads", "The name of the app in front, the address of each browser window's front tab, and, with the web filter on, the name of the site each connection is opened to. All of it is read to decide one thing — whether to block — and none of it is stored or sent."),
            .init("Rules are per device", "The phone knows an app as an opaque Screen Time token; this Mac knows it as a bundle identifier. Neither means anything to the other, so the two are set up separately."),
        ])

        SectionLabel(text: "Your setup")
        HelpPoints([
            .init("Download my setup", "Writes your apps, sites, rules, budgets, tiers and delay to a JSON file. A Mac target is a bundle identifier or a host, so the file is the whole setup and another Mac can take it as it stands."),
            .init("Restore from a file", "A proposal, not a rewind: you see the whole of it first, and every rule goes through the same delay the editor does, so anything that loosens waits."),
        ])

        SectionLabel(text: "This build")
        VStack(spacing: 0) {
            row("Version", version)
                .contentShape(Rectangle())
                .onTapGesture { noteVersionClick() }
            CardDivider()
            row("Enforced by", "AppKit, Apple Events, launchd, a network filter")
            CardDivider()
            row("Type", "Bricolage Grotesque, Onest, Geist Mono")
        }
        .emberCard()
        Footnote(text: "Swift and SwiftUI, no third-party code. The three faces are used under the SIL Open Font License.")
            .padding(.top, 8)
        #if DEBUG || TESTING_TOOLS
        if askedForTesting {
            Footnote(text: "Testing buttons are showing in Settings.")
                .padding(.top, 8)
        }
        #endif
    }

    // Five clicks on Version reveals Settings > Testing; see TestingTools for why it can still
    // stay hidden.
    private func noteVersionClick() {
        #if DEBUG || TESTING_TOOLS
        if TestingTools.noteVersionClick() { askedForTesting = true }
        #endif
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).emberBody(13).foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            Text(value)
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
