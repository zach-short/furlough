import SwiftUI

/// The two help pages that stay in the binary. Every other topic behind the question mark is
/// on furloughapp.com/help, where the wording can be corrected without an App Store review.
///
/// These two cannot go. `DelayHelp` reads the delay out of the live config rather than
/// repeating a default, so a phone with a week-long delay is not told about 24 hours, and a
/// static page could only ever quote the default. `StuckHelp` is what you need at the moment a
/// shield will not lift — the worst possible moment to be sent to a browser, which may itself
/// be the thing that is blocked.

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
