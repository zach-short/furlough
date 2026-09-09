import SwiftUI

/// The eight pages behind the question mark. Each one answers a single question and stops.
///
/// All of them are in the binary rather than on the site, because help is wanted at the moment
/// the app is in the way: on a train with no signal, on a phone whose browser may itself be
/// shielded, and with the numbers this phone would actually serve. Anything with a number in
/// it reads the number out of the config rather than repeating a default, so a phone with a
/// week-long delay is not told about 24 hours, and a phone that allows three tags does not
/// say two. furloughapp.com carries the same topics for anyone deciding whether to install
/// Furlough; these are the copies the app answers from.

// MARK: - Windows and budgets

struct WindowsHelp: View {
    /// The two limits iOS imposes, read from the constants the editor enforces rather than
    /// written into the sentence, so the page cannot drift from what a save will accept.
    private var shortestWindow: Int { Furlough.minimumWindowMinutes }
    private var windowBudget: Int { Furlough.maxActivities - 1 }

    var body: some View {
        HelpPage(
            title: "Windows and budgets",
            heading: "Hours and minutes",
            lead: "Every app you add gets a daily budget and, if you want, the hours it is allowed. Whichever runs out first closes it until the next opening."
        ) {
            SectionLabel(text: "The two limits")
            HelpPoints([
                .init("A window", "The hours an app is allowed, on the days you pick. With no windows at all it is open all day, up to its budget."),
                .init("A budget", "Minutes a day, counted across every window, spent whenever the app is in front. It resets at midnight."),
                .init("Together", "An and, not an or. A 30-minute budget inside an 8:00–10:00 PM window is 30 minutes, in that window. The rest of the evening is closed either way."),
            ])
            HelpProse("A rule with neither is not a block. Adding an app enforces nothing on its own — saving its first rule is what starts it.")
                .padding(.top, 10)

            SectionLabel(text: "Writing them")
            HelpPoints([
                .init("Same every day", "On to begin with. Turn it off and each window gets its own strip of weekdays: midnight on school nights, 2:00 AM on weekends."),
                .init("Past midnight", "Set 5:00 PM → 4:00 AM and the row is marked +1. Furlough keeps it as the evening and the early hours of the next day, and reads it back as the one night you wrote."),
                .init("Visualize windows", "The week as a grid. Tap a day to see and change just its hours, then apply those hours to any other days. Applying adds to what a day already has rather than replacing it, joining spans that overlap or touch."),
                .init("Copying a rule", "Use windows from another app pulls one in. Apply these windows to other apps pushes this one out to as many as you like, each judged on its own — so the tightenings land now and the loosenings queue."),
            ])
            HelpProse("Rows on the same days that overlap or touch are joined into one window when a time picker closes, so connected hours are always a single span rather than a pile of adjacent ones.")
                .padding(.top, 10)

            SectionLabel(text: "What Screen Time allows")
            HelpPoints([
                .init("\(shortestWindow) minutes", "The shortest window iOS accepts. A night counts as two — one either side of midnight — so each half needs its own \(shortestWindow)."),
                .init("\(windowBudget) windows", "Across every app together. iOS watches \(Furlough.maxActivities) things at once and Furlough spends one of them counting budgets."),
            ])
            Footnote(text: "Both numbers come from iOS rather than from Furlough, and neither can be worked around. A shorter window, or one that overlaps another on the same day, is refused in the editor before it can be saved. You will not find out at midnight.")
                .padding(.top, 10)

            SectionLabel(text: "Changing one later")
            HelpProse("Tightening a rule applies the moment you save it. Loosening one waits out a delay. How long yours is, and what shortens it, is Why changes wait — the first row on the help screen.")
                .padding(.top, 2)
        }
    }
}

// MARK: - Why changes wait

struct DelayHelp: View {
    @Environment(AppModel.self) private var model

    private var config: Config { model.state.config }
    private var base: String { TimeFormat.delay(hours: config.loosenDelayHours) }

    var body: some View {
        HelpPage(
            title: "Why changes wait",
            heading: "Tighter now, looser later",
            lead: "Furlough has no unblock button. What it has instead is a delay. Anything that gives you back time waits it out, and you can cancel it while it does."
        ) {
            SectionLabel(text: "The two directions")
            HelpPoints([
                .init("Applies the moment you save", "Shrinking a window, removing one, taking a day off it, lowering a budget, giving an app its first window, and raising the delay."),
                .init("Waits", "Extending or adding a window, adding a day to one, raising a budget, removing the last window, removing an app, and lowering the delay."),
                .init("The first rule is free", "Adding an app enforces nothing. Its first rule is always tighter than nothing, so it lands at once."),
            ])

            SectionLabel(text: "How much it is worth")
            HelpProse("Each app sits in one of four tiers, set at the bottom of its rule. The tier scales the delay, because needing Messages back is not the same as needing TikTok back. Your base delay is \(base).")
                .padding(.top, 2)
            HelpPoints(Utility.allCases.map { tier in
                HelpPoints.Point(tier.label, "\(tier.summary) Waits \(TimeFormat.delay(hours: config.delayHours(for: tier))).")
            })
            .padding(.top, 10)
            Footnote(text: "A new app is Useful until you say otherwise. Moving one toward Hazard lengthens its delay, so it applies now. Moving it toward Essential shortens it, which is itself a loosening, so it queues behind the delay that app has today.")
                .padding(.top, 8)

            SectionLabel(text: "While a change waits")
            HelpPoints([
                .init("The pending pill", "Home's top bar counts them. Each one shows the rule you have against the one waiting, so what the change costs stays readable."),
                .init("Cancelling", "Any pending change can be taken back until it lands. A notification an hour beforehand is the reminder that there is still time."),
                .init("Lowering the delay", "It loosens every app at once, so it waits out the longest delay in play — the slowest tier you have set, not the base."),
            ])

            SectionLabel(text: "The clock")
            HelpProse("Moving the phone's clock forward does not buy time. Every save records the wall clock beside the machine's own count of seconds since it booted, which nothing in Settings can change. When the two disagree by more than ten minutes, every queued loosening is held and the Pending screen says so. Tightening still applies. Setting the clock back releases them.")
                .padding(.top, 2)
        }
    }
}

// MARK: - Apps and websites

struct TargetsHelp: View {
    var body: some View {
        HelpPage(
            title: "Apps and websites",
            heading: "What Furlough can hold",
            lead: "The + button asks Application or Website. Apps and categories come from Apple's own picker; a website can come from there too, or be typed."
        ) {
            SectionLabel(text: "Three kinds")
            HelpPoints([
                .init("An app", "Picked from Apple's list. Furlough is never told which app it is — iOS hands over a token that means nothing off this phone — but iOS still draws the real icon and name beside it."),
                .init("A category", "Social, Entertainment, and the rest. Everything in a category is blocked all day. An app inside one that you give windows to is excepted from it."),
                .init("A website", "Blocked in every browser on the phone, subdomains included. There are two kinds, and they are not the same."),
            ])

            SectionLabel(text: "The two kinds of website")
            HelpProse("Worth reading twice, because the difference is invisible once a site is in the list.")
                .padding(.top, 2)
            HelpPoints([
                .init("Typed", "Website on the + button asks for an address. Its hours are enforced, but it gets no daily budget: iOS only counts a site it minted itself."),
                .init("From the picker", "Three levels in — open a category, scroll past its apps, tap Add Website. That one gets a budget and Furlough's own shield."),
            ])
            .padding(.top, 10)
            HelpProse("The guide sheet walks you into the picker, and the picker repeats the steps in its footer, because three levels down is easy to lose. If a site needs a budget rather than only hours, it has to come from there.")
                .padding(.top, 10)

            SectionLabel(text: "Once it is added")
            HelpPoints([
                .init("Nothing is enforced yet", "Adding is instant and changes nothing at all. Saving the first rule is what starts it — and a first rule is always tighter than nothing, so it lands at once rather than waiting."),
                .init("Nicknames", "A nickname takes the app's place on the shield, the widget and its notifications."),
                .init("The other half", "Blocking the YouTube app and leaving youtube.com open is the gap most people find a week later. Furlough offers the other side when it recognises one."),
            ])

            Footnote(text: "While anything is shielded, iOS is told to refuse app deletion, so Furlough cannot be deleted as a shortcut past it. Turning off Screen Time access still lifts everything — that is in If something gets stuck, and it is the one way out on purpose.")
                .padding(.top, 10)
        }
    }
}

// MARK: - Apps the picker will not show

struct PickerHelp: View {
    var body: some View {
        HelpPage(
            title: "Apps the picker will not show",
            heading: "Four apps you cannot pick",
            lead: "Apple's picker leaves four apps out, on every Screen Time app and not only Furlough: Safari, Settings, the App Store and Phone. Furlough cannot add what the picker will not offer. Here is what that means for each, and what actually helps."
        ) {
            SectionLabel(text: "Safari")
            HelpProse("Safari itself is not a target, but the sites you open in it are. Block a domain and it is closed in Safari, in Chrome and in every other browser on the phone, at the times and the budget you set. That is what to reach for — one site at a time, the same way as any other website in Furlough. There is no single switch that closes all of Safari's web at once.")
                .padding(.top, 2)

            SectionLabel(text: "Settings and the App Store")
            HelpProse("Neither can be shielded, by Furlough or by anything built on the same API — Apple keeps them out of the picker for every app that uses it. What helps is not a block but friction: a Shortcuts automation that sends you back to the Home Screen the moment either one opens.")
                .padding(.top, 2)
            HelpSteps([
                .init("Open Shortcuts", "Automation, then +, then Create Personal Automation."),
                .init("Choose the app", "App, then Is Opened, then Settings. Repeat for the App Store as a second automation."),
                .init("Add the action", "Go to Home Screen."),
                .init("Anchor too, if you like", "Furlough's own Drop Anchor action underneath it, so opening either app also locks whatever the Anchor holds."),
                .init("Turn off Ask Before Running", "So it fires without a prompt."),
            ])
            .padding(.top, 10)
            HelpProse("This is friction, not a lock. An automation lives in the Shortcuts app, and anything you can turn on you can turn off — including this one, in a few taps, any time you like. It buys the same thing a tag in another room buys the Anchor: a pause before you get what you were going to get anyway.")
                .padding(.top, 10)
            Footnote(text: "Written from how Shortcuts automations work rather than from a phone that has run this one. If a step reads differently on yours, that is the thing worth writing in about.")
                .padding(.top, 8)

            SectionLabel(text: "Phone")
            HelpProse("Phone is left out of the picker too, and Furlough leaves it alone on purpose rather than offering the same trick. A phone you cannot call out from is not a commitment device, it is a hazard — and an app that carries something you might need in an emergency is worth a warning, never a block. If Phone itself is the distraction, the honest answer is that Furlough is not the tool for that part.")
                .padding(.top, 2)

            SectionLabel(text: "On the Mac")
            HelpProse("The Mac has no picker at all — no Screen Time API to draw one from — so it reads instead: every window of Safari and the Chromium browsers, tab by tab, redirected to Furlough's shield the moment a blocked host shows up there. A tab is the whole of what that reader can see, and three things live outside it.")
                .padding(.top, 2)
            HelpPoints([
                .init("Firefox", "Not scriptable the way the others are, so none of its tabs can be read."),
                .init("Safari web apps in the Dock", "They run under their own identifier rather than Safari's, so the same host inside one is not caught."),
                .init("Anything without a tab", "An app with its own network code is invisible to a reader built on browser windows."),
            ])
            .padding(.top, 10)
            HelpProse("The Mac's web filter covers all three. It is a system extension that sees every connection the Mac opens and refuses the ones going to a blocked site, whichever app opened it; those get Furlough's floating card rather than the shield page. It is switched on in Settings > Web on the Mac, needs Furlough in the Applications folder, and macOS asks twice before it runs.")
                .padding(.top, 10)
            Footnote(text: "The filter is built and tested but has not been run on a Mac yet, since installing a system extension takes two approvals in front of the screen. If what you see differs from this, that is the thing worth writing in about.")
                .padding(.top, 8)
        }
    }
}

// MARK: - The Anchor

struct AnchorHelp: View {
    private var maxTags: Int { Furlough.maxAnchorTags }

    var body: some View {
        HelpPage(
            title: "The Anchor",
            heading: "One tap to lock. The tag to unlock.",
            lead: "The Anchor is a second list, locked in one tap from anywhere and released only by a physical NFC tag you paired. Leave the tag at home and the phone stays anchored until you are back."
        ) {
            HelpProse("It is separate from your rules and it does not use the delay. Anchoring only ever takes things away, so it needs no waiting; the walk back to the tag is the whole of the friction.")
                .padding(.top, 12)

            SectionLabel(text: "Using it")
            HelpSteps([
                .init("Choose apps", "The first time, the anchor offers what you already block, every one checked. Keep what it should hold, or go on to the picker for anything else. After that, Change apps opens the picker with the list filled in."),
                .init("Pair a tag", "Hold the phone to any NTAG sticker, or the tag that came with another blocking product if you already own one. Furlough reads its hardware identifier and writes nothing to it. Up to \(maxTags) can be paired, so a key can live at each place you do — name each one for its place."),
                .init("Anchor", "Everything on the list is shielded immediately. No tag is needed to lock and no delay applies."),
                .init("Unanchor", "Opens the reader. Only a tag you paired lifts the anchor, and any of them does, at once. This is the one unblock in Furlough, and it exists only here."),
            ])

            SectionLabel(text: "The tag")
            HelpPoints([
                .init("What to buy", "Search for NTAG213 stickers and buy the cheapest pack with decent reviews. Memory does not matter, because Furlough writes nothing; the shape does — a sticker for a cupboard door, a fob for a jar, a card for a wallet you leave behind."),
                .init("What you may already own", "The tag from another blocking product, an NFC business card, a gym or hotel fob, an amiibo. If it reads once while pairing, it will read every time."),
                .init("What will not work", "Contactless bank cards and phone wallets, which hand out a fresh identifier each tap on purpose; passports and ID cards, which are locked to their own readers; a second phone; a QR code, which is not NFC at all."),
                .init("Metal detunes a tag", "A plain sticker on a fridge, a laptop lid or a tin will not read. Stick it to wood, card, glass or plastic, or buy the ones sold as on-metal."),
            ])

            SectionLabel(text: "The whole phone")
            HelpProse("The Anchor screen has a scope. Chosen apps is the list above. Everything except turns the list inside out: while anchored, every app and every website on the phone is shielded, and the list is what stays open.")
                .padding(.top, 2)
            HelpPoints([
                .init("The list starts with your essentials", "Switching to Everything except puts every app you tiered Essential on the list — Messages, the authenticator, the way home — so they stay reachable unless you take them off."),
                .init("Rules still apply to the list", "An app that stays open keeps its own windows and budget, so YouTube on the list is still shut outside its window."),
                .init("Switching starts the list again", "A list that means held under one scope would mean let through under the other, so it is not carried across. The screen says so before it switches."),
                .init("Websites", "A site off the list is blocked in every browser. Where Furlough's own shield does not reach, iOS shows its Website Not Allowed page instead."),
            ])

            SectionLabel(text: "On a schedule")
            HelpProse("Schedule adds drop times: an hour, on the days you pick, at which the anchor drops by itself. Each one either lifts at an hour you give it or holds until the tag — 10 PM on school nights, lifted by the tag in the morning, is what it was built for.")
                .padding(.top, 2)

            SectionLabel(text: "While anchored")
            HelpPoints([
                .init("Nothing can loosen", "The list and the tags cannot be changed until the anchor is off, so no key can be cut from under the lock. Pair every tag you want before you anchor."),
                .init("Rules still stand", "An app can be anchored and have windows too. With the anchor off it falls back to its rule, or to nothing if it has none."),
                .init("Forget tag", "Unpairs one after a confirmation, and only while the anchor is off. Anchoring is refused once the last one is gone, so there is always a way back."),
                .init("There is no pause", "No break, no temporary access, no emergency unblock — each of those is an early release with a nicer name. The tag lifts the anchor, and beyond that only Apple's own way out, which lifts everything Furlough does rather than the Anchor alone."),
            ])

            SectionLabel(text: "Before you tap it")
            HelpProse("Anchoring something Essential warns first and asks again before it drops. The anchor is instant and only a tag lifts it, so a tag in another room means Messages stays gone until you find it. Keep every tag somewhere that makes you think — a key in your bag is no lock at all.")
                .padding(.top, 2)
        }
    }
}

// MARK: - Outside the app

struct ElsewhereHelp: View {
    var body: some View {
        HelpPage(
            title: "Outside the app",
            heading: "Where Furlough shows up",
            lead: "Almost everything Furlough does happens while you are looking at something else. Opening the app is for writing rules; the rest of the time it is the shield, a notification and a countdown on the lock screen."
        ) {
            SectionLabel(text: "Notifications")
            HelpPoints([
                .init("Around a window", "One when it opens, one five minutes before it closes, one five minutes before the budget runs out, and one when it is spent."),
                .init("Around a pending change", "One an hour before a queued loosening lands, while you can still cancel it, and one when it lands."),
            ])

            SectionLabel(text: "On the screen")
            HelpPoints([
                .init("The shield", "iOS draws it over a blocked app: why it is blocked and when it opens next."),
                .init("The lock screen", "A Live Activity while a window is open, counting down, with the same hourglass in the Dynamic Island."),
                .init("The home screen", "A widget with the next opening, or the time left in the one running, and a button that drops the anchor without opening the app."),
                .init("Control Center", "A Drop Anchor button, reachable from the lock screen. There is deliberately no release beside it — that stays in the app, behind the tag."),
            ])

            SectionLabel(text: "Asking")
            HelpPoints([
                .init("Three Shortcuts", "Drop Anchor locks what the Anchor holds. Weigh Anchor opens the app and asks for the tag, because a tag can only be read with the app in front. What's Open says what is open now and when the next thing opens, without opening the app at all."),
                .init("Where the time goes", "Settings ranks the apps that took your last two weeks and suggests a rule for each. Screen Time draws those cards in a sandbox of its own; the numbers never reach the app."),
            ])

            Footnote(text: "The hourglass is the same drawing everywhere it appears — shield, widget, Dynamic Island. The top bulb is the window draining with the countdown; the mound turns amber five minutes out and ember once the budget is spent.")
                .padding(.top, 10)
        }
    }
}

// MARK: - If something gets stuck

struct StuckHelp: View {
    var body: some View {
        HelpPage(
            title: "If something gets stuck",
            heading: "When a shield will not lift",
            lead: "Furlough re-registers every schedule and re-applies every shield from saved state each time it launches, so drift is usually fixed by opening it. If a shield still refuses to lift when it should, in this order:"
        ) {
            SectionLabel(text: "What to try")
            HelpPoints([
                .init("Re-apply enforcement now", "Settings > Enforcement. Does that whole pass again on demand, without waiting for a launch."),
                .init("Activity log", "Settings > Activity log. Says what the monitor extension has been doing and when it last ran."),
                .init("Turn Screen Time access off, then on", "The Settings app > Screen Time > Apps with Screen Time Access > Furlough. iOS clears every shield. Your rules are kept; reopen Furlough to enforce them again."),
            ])

            SectionLabel(text: "The way out")
            HelpProse("That last step is also the escape hatch. Turning Furlough off in Screen Time lifts every shield and the delete-protection flag with it, and Furlough cannot prevent it. That is written here on purpose: the delay is a wall worth climbing, not a door that locks from the outside.")
                .padding(.top, 2)

            SectionLabel(text: "Worth knowing")
            HelpPoints([
                .init("The monitor runs late sometimes", "iOS wakes it at window edges, at midnight and when a budget is reached. A few minutes of drift is normal, and every wake-up re-derives the shields, so nothing compounds."),
                .init("Enforcement is listed", "Settings > Enforcement shows Screen Time access, notifications, the App Group, and when the shields and schedules were last written."),
            ])
        }
    }
}

// MARK: - About

struct AboutHelp: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        HelpPage(
            title: "About",
            heading: "About Furlough",
            lead: "A personal app blocker with no unblock button, built on Apple's Screen Time API. It has no account, no server and no analytics. The one thing it writes off the device is the Anchor's state, to your own iCloud, so the Mac and the iPhone lock together."
        ) {
            SectionLabel(text: "What stays on the phone")
            HelpPoints([
                .init("Which apps you picked", "iOS never tells Furlough. An app is an opaque token that means nothing off this phone; the icon and the name beside it are drawn by iOS itself."),
                .init("Your rules", "In a container shared by the app and its extensions, so all of them read the same state. Rules never sync and are never uploaded; only the Anchor's state — down or not, since when, until when — goes to your own iCloud, and only so your other device can follow it."),
                .init("Your usage", "Screen Time hands the hours to a report extension with no network of its own and nowhere to write. Only the picture reaches the app."),
            ])

            SectionLabel(text: "Your setup")
            HelpPoints([
                .init("Download my setup", "Writes your rules, budgets, tiers and delay to a JSON file you keep. Because a token means nothing elsewhere, the file records what each app is called rather than the app itself. The Anchor is not included."),
                .init("Restore from a file", "Asks which app each rule was, since the file cannot say. It is a proposal, not a rewind: every rule goes through the same delay the editor does, so anything that loosens waits."),
            ])

            SectionLabel(text: "This build")
            VStack(spacing: 0) {
                row("Version", version)
                CardDivider()
                row("Built on", "FamilyControls, ManagedSettings, DeviceActivity, Core NFC")
                CardDivider()
                row("Type", "Bricolage Grotesque, Onest, Geist Mono")
            }
            .emberCard()
            Footnote(text: "Swift and SwiftUI, no third-party code. The three faces are used under the SIL Open Font License. The formal version of what stays on this phone is the privacy policy at furloughapp.com/privacy, which is also linked from the App Store listing.")
                .padding(.top, 8)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .emberBody(13)
                .foregroundStyle(Ember.cream)
            Spacer(minLength: 8)
            Text(value)
                .emberBody(13)
                .foregroundStyle(Ember.muted)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}
