import Foundation
import Testing

@Suite("What a tier suggests on its own")
struct RuleSuggestionTierTests {
    @Test("The two tiers worth keeping say nothing")
    func quietTiers() {
        // Blocking an essential is the risk Furlough interrupts a person about, so suggesting a
        // budget for one would be the app arguing with its own caution banner. A work tool has no
        // healthy amount, and the only figure generous enough to stand for `.useful` is looser
        // than the 30 minutes the editor's slider already sits at.
        #expect(RuleSuggestion.draft(for: .essential) == nil)
        #expect(RuleSuggestion.draft(for: .useful) == nil)
    }

    @Test("Idle is a budget and no claim about when")
    func idleIsBudgetOnly() {
        let draft = RuleSuggestion.draft(for: .idle)
        #expect(draft?.budgetMinutes == 60)
        #expect(draft?.window == nil)
    }

    @Test("Hazard is a budget and the hours either end of the day")
    func hazardCarriesTheWindow() {
        let draft = RuleSuggestion.draft(for: .hazard)
        #expect(draft?.budgetMinutes == 30)
        #expect(draft?.window == RuleSuggestion.hazardWindow)
        #expect(draft?.window?.startMinute == 9 * 60)
        #expect(draft?.window?.endMinute == 22 * 60)
    }

    @Test("Every suggestion is a rule Furlough would accept from a person")
    func draftsAreValidRules() {
        for tier in Utility.allCases {
            guard let draft = RuleSuggestion.draft(for: tier) else { continue }
            #expect(draft.rule.validationError == nil, "\(tier.label) suggests a rule that would not save")
            if let window = draft.window {
                // 15 minutes is the floor and a stored window never crosses midnight, so a
                // suggestion costs exactly one activity span and no night's worth of arithmetic.
                #expect(window.isValidDraft)
                #expect(!window.isNight)
                #expect(draft.rule.windows.count == 1)
            }
        }
    }

    @Test("The suggested budget lands on a figure the slider actually stops at")
    func budgetsSitOnTicks() {
        let ticks = [5, 30, 60, 120, 240]
        #expect(ticks.contains(RuleSuggestion.idleBudgetMinutes))
        #expect(ticks.contains(RuleSuggestion.hazardBudgetMinutes))
        #expect(ticks.contains(RuleSuggestion.longFormBudgetMinutes))
    }
}

@Suite("Which tier a suggestion answers to")
struct RuleSuggestionTierChoiceTests {
    @Test("With no answer from anyone, the table's own guess stands in")
    func fallsBackToTheTable() {
        let tiktok = Target(kind: .macApp(bundleID: "com.zhiliaoapp.musically"))
        #expect(RuleSuggestion.tier(for: tiktok, chosen: nil) == .hazard)
        #expect(RuleSuggestion.suggestion(for: tiktok)?.budgetMinutes == 30)
    }

    @Test("An answer beats the guess, in both directions")
    func theChosenTierWins() {
        let tiktok = Target(kind: .macApp(bundleID: "com.zhiliaoapp.musically"))
        // Called useful by the person holding the phone: Furlough stops suggesting hours for it.
        #expect(RuleSuggestion.suggestion(for: tiktok, chosen: .useful) == nil)
        // And the other way: a tier chosen for something the table has never heard of still gets
        // the tier's own starting rule.
        let unknown = Target(kind: .macApp(bundleID: "com.nobody.at.all"))
        #expect(RuleSuggestion.suggestion(for: unknown) == nil)
        #expect(RuleSuggestion.suggestion(for: unknown, chosen: .hazard)?.window == RuleSuggestion.hazardWindow)
    }
}

@Suite("A suggestion never lands on a rule that exists")
struct RuleSuggestionGuardTests {
    @Test("Anything already configured is left alone")
    func existingRulesAreNeverOverwritten() {
        var netflix = Target(kind: .macApp(bundleID: "com.netflix.netflix"))
        #expect(RuleSuggestion.suggestion(for: netflix) != nil)
        // The same target, once it has a rule of its own: nothing more is offered, whatever that
        // rule says. A suggestion is for the cold start; one that could land on top of a rule
        // someone is living under would be a second way to edit it.
        netflix.rule = Rule(windows: [window(8 * 60, 9 * 60)], dailyBudgetMinutes: 15)
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
        netflix.rule = .unrestricted
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
        netflix.rule = .alwaysBlocked
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
    }

    @Test("A typed site is offered hours and never minutes")
    func uncountedTargetsGetTheWindowOrNothing() {
        // Nothing counts a typed site's minutes, so a budget on one would be a figure that is
        // never enforced. Its hours are enforced, so a hazard site keeps its window…
        let tiktok = makeTarget("TikTok", rule: nil)
        #expect(tiktok.isCounted == false)
        #expect(RuleSuggestion.suggestion(for: tiktok)?.window == RuleSuggestion.hazardWindow)
        // …and an idle one, whose whole suggestion is a budget, is offered nothing at all.
        let netflix = makeTarget("Netflix", rule: nil)
        #expect(AppUtility.suggestion(for: netflix)?.utility == .idle)
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
    }
}

@Suite("RuleSuggestion's table of exceptions")
struct RuleSuggestionTableTests {
    @Test("Long-form video is watched in sittings, so an hour is not the figure")
    func longFormBeatsTheIdleDefault() {
        // By bundle identifier, by host, and by the name a Mac target was called: the three ways
        // `AppUtility` is keyed, answered here the same way.
        #expect(RuleSuggestion.suggestion(for: Target(kind: .macApp(bundleID: "com.netflix.netflix")))?.budgetMinutes == 120)
        #expect(RuleSuggestion.suggestion(for: Target(kind: .macApp(bundleID: "com.hulu.plus")))?.budgetMinutes == 120)
        #expect(RuleSuggestion.suggestion(for: Target(kind: .macApp(bundleID: "com.apple.TV")))?.budgetMinutes == 120)
        var named = Target(kind: .macApp(bundleID: "com.unknown.vendor.app"))
        named.nickname = "Paramount+"
        #expect(RuleSuggestion.suggestion(for: named)?.budgetMinutes == 120)
        // And none of them gains a window: the exception refines the figure, not the tier.
        #expect(RuleSuggestion.suggestion(for: Target(kind: .macApp(bundleID: "com.netflix.netflix")))?.window == nil)
        // Streaming that is not long-form stays on the idle default.
        #expect(RuleSuggestion.suggestion(for: Target(kind: .macApp(bundleID: "com.google.ios.youtube")))?.budgetMinutes == 60)
    }

    @Test("A hazard that is also how people reach you keeps its budget and loses its hours")
    func snapchatKeepsItsHours() {
        let snapchat = Target(kind: .macApp(bundleID: "com.toyopagroup.picaboo"))
        let draft = RuleSuggestion.suggestion(for: snapchat)
        #expect(draft?.budgetMinutes == 30)
        // Closing it from 10 PM to 9 AM would shut the door somebody is knocked on, which is the
        // harm `.essential` exists to warn about arriving through the back of a suggestion.
        #expect(draft?.window == nil)
        // The rest of the hazard tier is unaffected.
        #expect(RuleSuggestion.suggestion(for: Target(kind: .macApp(bundleID: "com.burbn.instagram")))?.window == RuleSuggestion.hazardWindow)
    }

    @Test("An exception written for one tier does not follow its app to another")
    func exceptionsAreTiedToTheirTier() {
        let netflix = Target(kind: .macApp(bundleID: "com.netflix.netflix"))
        // Called a hazard by the person holding the phone: the "two hours for a film" argument
        // was about Netflix while Netflix was idle, so it has nothing to say here.
        #expect(RuleSuggestion.suggestion(for: netflix, chosen: .hazard)?.budgetMinutes == 30)
        #expect(RuleSuggestion.suggestion(for: netflix, chosen: .hazard)?.window == RuleSuggestion.hazardWindow)
        #expect(RuleSuggestion.suggestion(for: netflix, chosen: .useful) == nil)
    }

    @Test("Every exception still agrees with the tier it was written against")
    func exceptionsHaveNotDrifted() {
        // The one place the two tables touch. Retiering an app in `AppUtility` — a table of
        // facts, edited whenever a fact changes — would otherwise switch its exception off in
        // silence. Here it fails instead.
        for (key, exception) in RuleSuggestion.names {
            #expect(AppUtility.names[key]?.utility == exception.utility, "\(key) is tiered elsewhere in AppUtility")
        }
        for (key, exception) in RuleSuggestion.bundleIDs {
            #expect(AppUtility.bundleIDs[key]?.utility == exception.utility, "\(key) is tiered elsewhere in AppUtility")
        }
        for entry in RuleSuggestion.hosts {
            #expect(AppUtility.byHost(entry.host)?.utility == entry.value.utility, "\(entry.host) is tiered elsewhere in AppUtility")
        }
    }

    @Test("Every key is lowercase, known to AppUtility, and claimed once")
    func tableIsWellFormed() {
        for key in RuleSuggestion.names.keys {
            #expect(key == key.lowercased(), "\(key) is not lowercase")
            #expect(AppUtility.names[key] != nil, "\(key) has a suggested rule but no tier")
        }
        for key in RuleSuggestion.bundleIDs.keys {
            #expect(key == key.lowercased(), "\(key) is not lowercase")
            #expect(AppUtility.bundleIDs[key] != nil, "\(key) has a suggested rule but no tier")
        }
        let hosts = RuleSuggestion.hosts.map(\.host)
        #expect(hosts.count == Set(hosts).count, "a host appears more than once in RuleSuggestion.hosts")
        for host in hosts {
            #expect(host == host.lowercased(), "\(host) is not lowercase")
        }
    }
}

@Suite("What the offer says")
struct RuleSuggestionOfferTests {
    @Test("A counted target hears the budget and the hours; a typed site hears only the hours")
    func offerReadsAsASentence() {
        let hazard = RuleSuggestion.draft(for: .hazard) ?? .init(budgetMinutes: 0)
        #expect(plainSpaces(RuleSuggestion.offer(hazard, calendar: cal))
            == "Furlough would start it at 30 min a day, 9 AM to 10 PM")
        #expect(plainSpaces(RuleSuggestion.offer(hazard, counted: false, calendar: cal))
            == "Furlough would start it at 9 AM to 10 PM")
        let idle = RuleSuggestion.draft(for: .idle) ?? .init(budgetMinutes: 0)
        #expect(RuleSuggestion.offer(idle, calendar: cal) == "Furlough would start it at 1 hour a day")
    }
}

@Suite("The name Furlough already knows")
struct OfferedNicknameTests {
    @Test("A site going by its address is offered the name the tables call it")
    func typedSitesAreOfferedAProperName() {
        #expect(AppUtility.offeredNickname(for: Target(kind: .host("m.youtube.com"))) == "YouTube")
        #expect(AppUtility.offeredNickname(for: Target(kind: .host("netflix.com"))) == "Netflix")
        // Nothing is invented for a site no table has heard of.
        #expect(AppUtility.offeredNickname(for: Target(kind: .host("some-site-nobody-listed.example"))) == nil)
    }

    @Test("A Mac app with no name of its own is offered one")
    func macAppsAreOfferedAProperName() {
        // Without this the row, the shield card and the widget all read "com.bereal.bereal".
        #expect(AppUtility.offeredNickname(for: Target(kind: .macApp(bundleID: "com.bereal.bereal"))) == "BeReal")
        #expect(AppUtility.offeredNickname(for: Target(kind: .macApp(bundleID: "com.netflix.netflix"))) == "Netflix")
        #expect(AppUtility.offeredNickname(for: Target(kind: .macApp(bundleID: "com.nobody.at.all"))) == nil)
    }

    @Test("Nothing is offered over a name that is already there")
    func neverTalksOverAName() {
        // A nickname is an answer, and this may never argue with one.
        var named = Target(kind: .host("youtube.com"))
        named.nickname = "The time sink"
        #expect(AppUtility.offeredNickname(for: named) == nil)
        // Nor when the app already shows exactly the name the table would offer.
        var known = Target(kind: .macApp(bundleID: "com.netflix.netflix"))
        known.systemName = "Netflix"
        #expect(known.defaultName == "Netflix")
        #expect(AppUtility.offeredNickname(for: known) == nil)
    }
}
