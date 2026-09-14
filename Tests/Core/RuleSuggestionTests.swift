import Foundation
import Testing

@Suite("What a tier suggests on its own")
struct RuleSuggestionTierTests {
    @Test("The two tiers worth keeping say nothing")
    func quietTiers() {
        // A budget on essential would contradict Furlough's own caution banner; useful has no
        // figure generous enough to be worth suggesting.
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
                // Never crosses midnight, so a suggestion costs exactly one activity span.
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
        // A chosen tier still gets its starting rule even for an app the table has never heard of.
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
        // A suggestion is only for the cold start; once a rule exists, offering another would be
        // a second way to edit it.
        netflix.rule = Rule(windows: [window(8 * 60, 9 * 60)], dailyBudgetMinutes: 15)
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
        netflix.rule = .unrestricted
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
        netflix.rule = .alwaysBlocked
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
    }

    @Test("A typed site is offered hours and never minutes")
    func uncountedTargetsGetTheWindowOrNothing() {
        // A typed site's minutes are never counted, so only its (enforced) hours are suggested.
        let tiktok = makeTarget("TikTok", rule: nil)
        #expect(tiktok.isCounted == false)
        #expect(RuleSuggestion.suggestion(for: tiktok)?.window == RuleSuggestion.hazardWindow)
        // An idle site's whole suggestion is a budget, so it gets nothing at all.
        let netflix = makeTarget("Netflix", rule: nil)
        #expect(AppUtility.suggestion(for: netflix)?.utility == .idle)
        #expect(RuleSuggestion.suggestion(for: netflix) == nil)
    }
}

@Suite("RuleSuggestion's table of exceptions")
struct RuleSuggestionTableTests {
    @Test("Long-form video is watched in sittings, so an hour is not the figure")
    func longFormBeatsTheIdleDefault() {
        // The three ways `AppUtility` is keyed — bundle ID, host, nickname — all answered the same.
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
        // A 10 PM–9 AM window would shut the door somebody is knocking on — the harm `.essential` warns about.
        #expect(draft?.window == nil)
        // The rest of the hazard tier is unaffected.
        #expect(RuleSuggestion.suggestion(for: Target(kind: .macApp(bundleID: "com.burbn.instagram")))?.window == RuleSuggestion.hazardWindow)
    }

    @Test("An exception written for one tier does not follow its app to another")
    func exceptionsAreTiedToTheirTier() {
        let netflix = Target(kind: .macApp(bundleID: "com.netflix.netflix"))
        // The "two hours for a film" exception was written for idle Netflix, not hazard Netflix.
        #expect(RuleSuggestion.suggestion(for: netflix, chosen: .hazard)?.budgetMinutes == 30)
        #expect(RuleSuggestion.suggestion(for: netflix, chosen: .hazard)?.window == RuleSuggestion.hazardWindow)
        #expect(RuleSuggestion.suggestion(for: netflix, chosen: .useful) == nil)
    }

    @Test("Every exception still agrees with the tier it was written against")
    func exceptionsHaveNotDrifted() {
        // The one place the two tables touch: retiering an app in AppUtility would otherwise
        // silently disable its exception here.
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

    @Test("The card states the rule rather than the act of taking it")
    func statementReadsAsARule() {
        let hazard = RuleSuggestion.draft(for: .hazard) ?? .init(budgetMinutes: 0)
        #expect(plainSpaces(RuleSuggestion.statement(hazard, calendar: cal))
            == "Open 9 AM to 10 PM, 30 min a day.")
        // Nothing counts a typed site's minutes, so the hours are the whole rule and no figure
        // is promised that nothing would enforce.
        #expect(plainSpaces(RuleSuggestion.statement(hazard, counted: false, calendar: cal))
            == "Open 9 AM to 10 PM.")
        let idle = RuleSuggestion.draft(for: .idle) ?? .init(budgetMinutes: 0)
        #expect(RuleSuggestion.statement(idle, calendar: cal) == "Open at any hour, 1 hour a day.")
    }

    @Test("A 24-hour clock still reads as a time")
    func statementOnATwentyFourHourClock() {
        var british = fixedCalendar()
        british.locale = Locale(identifier: "en_GB")
        let hazard = RuleSuggestion.draft(for: .hazard) ?? .init(budgetMinutes: 0)
        // "Open 09 to 22." is a pair of numbers, not a sentence. A clock that counts to 23 keeps
        // its minutes on a whole hour, so the card reads as hours either way.
        #expect(plainSpaces(RuleSuggestion.statement(hazard, calendar: british))
            == "Open 09:00 to 22:00, 30 min a day.")
    }

    @Test("The reason names the tier in the word the chips use")
    func becauseNamesTheTier() {
        #expect(RuleSuggestion.because(.hazard) == "Furlough would call this Hazard.")
        #expect(RuleSuggestion.because(.idle) == "Furlough would call this Idle.")
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
