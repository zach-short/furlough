import Foundation
import Testing

/// A setup file coming back in. The whole of what is being held to here is one sentence: an
/// import is a proposal, so a file can never be a shorter road to a loosening than the rule
/// editor is — and nothing outside targets and the base delay travels at all.
@Suite("Importing a setup")
struct ConfigImportTests {
    let now = at(8, 12, 0)

    // MARK: Building files

    func exported(
        _ kind: ExportedTarget.Kind = .app,
        _ identifier: String?,
        name: String? = nil,
        nickname: String? = nil,
        utility: ExportedTarget.Tier? = nil,
        rule: Rule? = nil
    ) -> ExportedTarget {
        ExportedTarget(
            kind: kind,
            identifier: identifier,
            name: name,
            nickname: nickname,
            utility: utility,
            rule: rule
        )
    }

    func file(
        _ targets: [ExportedTarget],
        delayHours: Int = 24,
        version: Int = ConfigExport.currentVersion,
        platform: ConfigExport.Platform = .mac
    ) -> ConfigExport {
        ConfigExport(
            version: version,
            platform: platform,
            exportedAt: at(8),
            appVersion: "1.0",
            loosenDelayHours: delayHours,
            targets: targets
        )
    }

    /// Chrome as this Mac has it today: open 5–7 PM, half an hour a day, and a hazard.
    func chrome(id: UUID = UUID()) -> Target {
        Target(
            id: id,
            kind: .macApp(bundleID: "com.google.Chrome"),
            nickname: "The bad one",
            rule: Rule(windows: [window(1020, 1140)], dailyBudgetMinutes: 30),
            addedAt: at(1),
            systemName: "Google Chrome",
            utilityLevel: .hazard
        )
    }

    /// The plan a Mac would make of `export` against `state`, matched the way the Mac matches.
    func plan(_ export: ConfigExport, _ state: SharedState) -> ImportPlan {
        ConfigImport.plan(
            export,
            matches: ConfigImport.matches(for: export, config: state.config),
            state: state,
            now: now
        )
    }

    func state(_ targets: [Target], delayHours: Int = 24, pending: [PendingChange] = []) -> SharedState {
        var state = SharedState()
        state.config.targets = targets
        state.config.loosenDelayHours = delayHours
        state.pending = pending
        return state
    }

    // MARK: What the file is allowed to be

    @Test("a phone file on a Mac is refused for the reason it cannot work")
    func refusesAPhoneFile() throws {
        let data = try file([exported(.app, nil)], platform: .iOS).json()
        #expect(throws: ConfigImport.Refusal.wrongPlatform(.iOS)) { try ConfigImport.read(data) }
        #expect(ConfigImport.Refusal.wrongPlatform(.iOS).message.contains("iPhone"))
    }

    @Test("a file from a newer Furlough is refused whole, with its number")
    func refusesAFileFromTheFuture() throws {
        let data = try file([], version: ConfigExport.currentVersion + 1).json()
        #expect(throws: ConfigImport.Refusal.fromTheFuture(version: 2)) { try ConfigImport.read(data) }
    }

    /// A file too new to decode still has to say so as a version, not as a missing key.
    @Test("a file too new to even decode is still read as a version")
    func refusesUndecodableFuture() {
        let data = Data(#"{"version": 9, "shape": "nothing this build knows"}"#.utf8)
        #expect(throws: ConfigImport.Refusal.fromTheFuture(version: 9)) { try ConfigImport.read(data) }
    }

    @Test("anything else is not a setup file")
    func refusesRubbish() {
        #expect(throws: ConfigImport.Refusal.unreadable) { try ConfigImport.read(Data("hello".utf8)) }
        #expect(throws: ConfigImport.Refusal.unreadable) { try ConfigImport.read(Data()) }
    }

    @Test("a file bigger than any setup is refused before it is parsed")
    func refusesSomethingHuge() {
        let data = Data(repeating: UInt8(ascii: "{"), count: ConfigImport.maxFileBytes + 1)
        #expect(throws: ConfigImport.Refusal.tooBig(bytes: ConfigImport.maxFileBytes + 1)) {
            try ConfigImport.read(data)
        }
    }

    // MARK: The one rule that matters

    /// The attack the whole design exists to stop: export, open the JSON, raise the budget,
    /// import. It has to come out the far side as a change that waits, exactly as typing the
    /// same budget into the rule editor would.
    @Test("loosening a budget in a text editor still waits out the delay")
    func theBudgetAttack() {
        let target = chrome()
        var before = state([target])
        let edited = file([exported(.app, "com.google.Chrome",
                                    utility: .hazard,
                                    rule: Rule(windows: [window(1020, 1140)], dailyBudgetMinutes: 1440))])
        let plan = plan(edited, before)

        // Hazard on a 24-hour base waits four days, and the file cannot shorten that.
        let due = now.addingTimeInterval(96 * 3600)
        #expect(plan.queued.count == 1)
        #expect(plan.queued.first?.outcome == .queued(due))
        #expect(plan.immediate.isEmpty)

        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.targets[0].rule?.dailyBudgetMinutes == 30)
        #expect(before.pending.count == 1)
        #expect(before.pending[0].effectiveAt == due)
    }

    @Test("a tightening in the same file lands at once")
    func tighteningLandsNow() {
        let target = chrome()
        var before = state([target])
        let tighter = Rule(windows: [window(1020, 1080)], dailyBudgetMinutes: 15)
        let plan = plan(file([exported(.app, "com.google.Chrome", rule: tighter)]), before)

        #expect(plan.immediate.count == 1)
        #expect(plan.queued.isEmpty)
        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.targets[0].rule == tighter)
        #expect(before.pending.isEmpty)
    }

    /// One file, two targets, each judged on its own — Messages gets its rule now and YouTube
    /// waits, rather than both waiting for the slower of them.
    @Test("each target in a file is judged on its own")
    func eachTargetOnItsOwn() {
        let youTube = Target(
            kind: .host("youtube.com"),
            rule: Rule(windows: [window(1020, 1140)], dailyBudgetMinutes: 30),
            addedAt: at(1)
        )
        let news = Target(kind: .host("news.com"), rule: .unrestricted, addedAt: at(1))
        var before = state([youTube, news])
        let plan = plan(file([
            exported(.website, "youtube.com", rule: Rule(windows: [window(600, 1140)], dailyBudgetMinutes: 120)),
            exported(.website, "news.com", rule: Rule(windows: [window(1020, 1140)], dailyBudgetMinutes: 30)),
        ]), before)

        #expect(plan.queued.count == 1)
        #expect(plan.queued.first?.name == "youtube.com")
        #expect(plan.immediate.count == 1)
        #expect(plan.immediate.first?.name == "news.com")

        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.target(host: "youtube.com")?.rule?.dailyBudgetMinutes == 30)
        #expect(before.config.target(host: "news.com")?.rule?.dailyBudgetMinutes == 30)
    }

    // MARK: Tiers

    @Test("a file cannot call everything essential to shorten the wait")
    func essentialQueues() {
        let target = chrome()
        var before = state([target])
        let plan = plan(file([exported(.app, "com.google.Chrome", utility: .essential)]), before)

        #expect(plan.queued.count == 1)
        #expect(plan.queued.first?.subject == .tier)
        // Waits out the tier it has today — hazard, four days — not the one it is moving to.
        #expect(plan.queued.first?.outcome == .queued(now.addingTimeInterval(96 * 3600)))

        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.targets[0].utilityLevel == .hazard)
    }

    /// The tier is read before the rule under it, so a file that raises a tier and loosens a
    /// rule in one breath pays the longer wait — which is what saving the two by hand does.
    @Test("a tier that lands now lengthens the wait on the rule beneath it")
    func tierLandsBeforeTheRuleItLengthens() {
        let target = Target(
            kind: .macApp(bundleID: "com.google.Chrome"),
            rule: Rule(windows: [window(1020, 1140)], dailyBudgetMinutes: 30),
            addedAt: at(1),
            utilityLevel: .useful
        )
        var before = state([target])
        let plan = plan(file([exported(.app, "com.google.Chrome",
                                       utility: .hazard,
                                       rule: Rule(windows: [window(600, 1140)], dailyBudgetMinutes: 120))]), before)

        #expect(plan.immediate.map(\.subject) == [.tier])
        #expect(plan.queued.map(\.subject) == [.rule])
        // Hazard's four days, not the one day the target had when the file was opened.
        #expect(plan.queued.first?.outcome == .queued(now.addingTimeInterval(96 * 3600)))

        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.targets[0].utilityLevel == .hazard)
        #expect(before.config.targets[0].rule?.dailyBudgetMinutes == 30)
    }

    // MARK: The base delay

    @Test("raising the delay applies now and lowering it waits out the slowest target")
    func theBaseDelay() {
        var raised = state([chrome()])
        let up = plan(file([], delayHours: 48), raised)
        #expect(up.immediate.map(\.subject) == [.delay])
        ConfigImport.apply(up, to: &raised, now: now)
        #expect(raised.config.loosenDelayHours == 48)

        var lowered = state([chrome()])
        let down = plan(file([], delayHours: 6), lowered)
        // Chrome is a hazard, so the slowest wait on a 24-hour base is four days.
        #expect(down.queued.first?.outcome == .queued(now.addingTimeInterval(96 * 3600)))
        ConfigImport.apply(down, to: &lowered, now: now)
        #expect(lowered.config.loosenDelayHours == 24)
        #expect(lowered.pending.count == 1)
    }

    @Test("a delay the stepper could not have written is named, not rounded")
    func anImpossibleDelay() {
        var before = state([chrome()])
        let plan = plan(file([], delayHours: 100_000), before)
        #expect(plan.skipped.map(\.subject) == [.delay])
        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.loosenDelayHours == 24)
    }

    // MARK: A fresh install

    /// The case that actually matters, and it needs no path of its own: nothing here to
    /// compare against, so everything is a tightening and lands at once.
    @Test("a first import on a fresh install lands whole")
    func aFreshInstall() {
        var before = state([])
        let rule = Rule(windows: [window(1020, 1140)], dailyBudgetMinutes: 30)
        let plan = plan(file([
            exported(.app, "com.google.Chrome", name: "Google Chrome", nickname: "The bad one", utility: .hazard, rule: rule),
            exported(.website, "youtube.com", rule: .alwaysBlocked),
        ]), before)

        #expect(plan.added.count == 2)
        #expect(plan.queued.isEmpty)

        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.pending.isEmpty)
        let chrome = before.config.target(bundleID: "com.google.Chrome")
        #expect(chrome?.rule == rule)
        #expect(chrome?.utilityLevel == .hazard)
        #expect(chrome?.nickname == "The bad one")
        #expect(chrome?.systemName == "Google Chrome")
        #expect(before.config.target(host: "youtube.com")?.rule == .alwaysBlocked)
    }

    @Test("a target added by a file is one line, not three")
    func aNewTargetReadsAsOneLine() {
        let plan = plan(file([
            exported(.app, "com.google.Chrome", nickname: "The bad one", utility: .hazard,
                     rule: Rule(windows: [window(1020, 1140)], dailyBudgetMinutes: 30)),
        ]), state([]))
        #expect(plan.items.count == 1)
        #expect(plan.items[0].delta?.now == "Not managed by Furlough")
        #expect(plan.items[0].delta?.becomes.contains("30 min/day") == true)
    }

    // MARK: What may not travel

    /// The mirror of the export's leak test. A hand-written file carrying the keys the export
    /// leaves out must be read for its targets and ignored for the rest — quietly, not fatally.
    @Test("the anchor, the queue and today's usage are not read from a file")
    func nothingElseTravels() throws {
        let json = """
        {
          "version": 1,
          "platform": "mac",
          "exportedAt": "2026-09-08T00:00:00Z",
          "loosenDelayHours": 24,
          "anchor": { "kinds": [], "isAnchored": false, "tagID": "AQID" },
          "pending": [
            { "id": "9E3C1E9E-0000-0000-0000-000000000001",
              "kind": { "setDelay": { "hours": 1 } },
              "createdAt": "2026-09-01T00:00:00Z",
              "effectiveAt": "2026-09-02T00:00:00Z" }
          ],
          "runtime": { "exhausted": {}, "warned": {} },
          "somethingNobodyHasWrittenYet": true,
          "targets": [
            { "kind": "app", "identifier": "com.google.Chrome",
              "rule": { "windows": [], "dailyBudgetMinutes": 15 } }
          ]
        }
        """
        let export = try ConfigImport.read(Data(json.utf8))
        #expect(export.targets.count == 1)

        let target = chrome()
        var before = state([target])
        before.config.anchor = AnchorProfile(
            kinds: [.host("youtube.com")],
            isAnchored: true,
            anchoredAt: at(7),
            tagID: Data([9, 9, 9])
        )
        before.runtime.exhausted = [target.id.uuidString: Policy.dayKey(now, calendar: cal)]
        before.runtime.warned = [target.id.uuidString: Policy.dayKey(now, calendar: cal)]
        let anchorBefore = before.config.anchor
        let runtimeBefore = before.runtime

        ConfigImport.apply(plan(export, before), to: &before, now: now)

        #expect(before.config.anchor == anchorBefore)
        #expect(before.runtime == runtimeBefore)
        // The file's own queue is not the device's: nothing it listed is waiting here.
        #expect(before.pending.allSatisfy { $0.effectiveAt > now })
        #expect(before.config.loosenDelayHours == 24)
    }

    @Test("targets this device has and the file does not are left alone and said so")
    func untouchedTargets() {
        let target = chrome()
        let slack = Target(kind: .macApp(bundleID: "com.tinyspeck.slackmacgap"),
                           rule: .alwaysBlocked, addedAt: at(1), systemName: "Slack")
        var before = state([target, slack])
        let plan = plan(file([exported(.app, "com.google.Chrome", rule: .alwaysBlocked)]), before)

        #expect(plan.untouched == ["Slack"])
        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.targets.count == 2)
        #expect(before.config.target(bundleID: "com.tinyspeck.slackmacgap")?.rule == .alwaysBlocked)
    }

    // MARK: Rules a file got wrong

    @Test("a rule Furlough could not have written is dropped and named, not repaired")
    func malformedRulesAreDropped() {
        var before = state([chrome()])
        let overlapping = Rule(windows: [window(600, 800), window(700, 900)], dailyBudgetMinutes: 30)
        let plan = plan(file([exported(.app, "com.google.Chrome", rule: overlapping)]), before)

        #expect(plan.skipped.count == 1)
        #expect(plan.skipped.first?.subject == .rule)
        #expect(plan.isEmpty)
        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.targets[0].rule?.dailyBudgetMinutes == 30)
    }

    @Test("a budget no day could hold is a rule that is not understood")
    func impossibleBudgets() {
        #expect(ConfigImport.problem(with: Rule(windows: [], dailyBudgetMinutes: 5000)) != nil)
        #expect(ConfigImport.problem(with: Rule(windows: [], dailyBudgetMinutes: -1)) != nil)
        #expect(ConfigImport.problem(with: Rule(windows: [], dailyBudgetMinutes: 30)) == nil)
        let many = Rule(windows: (0..<200).map { window($0 * 2, $0 * 2 + 1) }, dailyBudgetMinutes: 30)
        #expect(ConfigImport.problem(with: many)?.contains("200 windows") == true)
    }

    // MARK: What the Mac makes of a file

    @Test("a website matches the parent domain already here")
    func parentDomains() {
        let youTube = Target(kind: .host("youtube.com"), rule: .alwaysBlocked, addedAt: at(1))
        let export = file([exported(.website, "m.youtube.com", rule: .alwaysBlocked)])
        let matches = ConfigImport.matches(for: export, config: state([youTube]).config)
        #expect(matches.map(\.resolution) == [.existing(youTube.id)])
    }

    @Test("a category in a file means nothing on a Mac")
    func categoriesAreSkipped() {
        let export = file([exported(.category, nil, name: "Social")])
        let matches = ConfigImport.matches(for: export, config: Config())
        guard case .skipped(let why) = matches[0].resolution else {
            Issue.record("a category should be skipped")
            return
        }
        #expect(why.contains("Screen Time"))
        #expect(plan(export, state([])).skipped.count == 1)
    }

    @Test("a file that lists the same thing twice only does it once")
    func listedTwice() {
        let export = file([
            exported(.website, "youtube.com", rule: .alwaysBlocked),
            exported(.website, "m.youtube.com", rule: .alwaysBlocked),
        ])
        var before = state([])
        let plan = plan(export, before)
        #expect(plan.added.count == 1)
        #expect(plan.skipped.count == 1)
        ConfigImport.apply(plan, to: &before, now: now)
        #expect(before.config.targets.count == 1)
    }

    @Test("a website the file writes in a way Furlough cannot read is named")
    func unreadableHosts() {
        let export = file([exported(.website, "not a host at all", rule: .alwaysBlocked)])
        let matches = ConfigImport.matches(for: export, config: Config())
        guard case .skipped(let why) = matches[0].resolution else {
            Issue.record("an unreadable host should be skipped")
            return
        }
        #expect(why.contains("not a host at all"))
    }

    // MARK: Applying

    /// The review can be left open. Reading it is not serving the delay.
    @Test("a queued change counts its wait from when the plan was made")
    func readingTheReviewServesNothing() {
        var before = state([chrome()])
        let plan = plan(file([exported(.app, "com.google.Chrome", rule: .unrestricted)]), before)
        let anHourLater = now.addingTimeInterval(3600)
        ConfigImport.apply(plan, to: &before, now: anHourLater)
        // Four days from the moment the button was pressed, not from when the file was opened.
        #expect(before.pending[0].effectiveAt == anHourLater.addingTimeInterval(96 * 3600))
    }

    /// At most one change per target is ever in flight — the rule editor drops what was queued
    /// rather than stacking on it, and an import is not allowed to be the one edit that does.
    @Test("an import replaces what was already queued for a target")
    func replacesRatherThanStacks() {
        let target = chrome()
        let queued = PendingChange(
            kind: .setRule(targetID: target.id, rule: .unrestricted),
            createdAt: at(7),
            effectiveAt: at(20)
        )
        var before = state([target], pending: [queued])
        let looser = Rule(windows: [window(600, 1140)], dailyBudgetMinutes: 120)
        ConfigImport.apply(plan(file([exported(.app, "com.google.Chrome", rule: looser)]), before), to: &before, now: now)

        #expect(before.pending.count == 1)
        #expect(before.pending[0].id != queued.id)
        if case .setRule(_, let rule) = before.pending[0].kind {
            #expect(rule == looser)
        } else {
            Issue.record("the queued change should still be a rule")
        }
    }

    @Test("a file that says what is already here does nothing")
    func nothingToDo() {
        let target = chrome()
        let plan = plan(file([exported(.app, "com.google.Chrome", nickname: "The bad one", utility: .hazard, rule: target.rule)]), state([target]))
        #expect(plan.isEmpty)
        #expect(plan.headline.contains("nothing in this file"))
        #expect(plan.confirmation.contains("nothing changed"))
    }

    // MARK: Pressing the button twice

    /// The one place import diverges from `assign`, and the reason the divergence is worth it:
    /// a file is applied whole and is easy to press twice, and every press used to restart the
    /// clock on every loosening in it. The activity log for 8 Sep 2026 has three of these
    /// inside two minutes.
    @Test("applying the same file twice does not push its loosenings further out")
    func pressingApplyTwiceCostsNothing() {
        var before = state([chrome()])
        let setup = file([exported(.app, "com.google.Chrome", rule: .unrestricted)])
        ConfigImport.apply(plan(setup, before), to: &before, now: now)
        #expect(before.pending.count == 1)
        let landed = before.pending[0].effectiveAt

        let twoMinutesLater = now.addingTimeInterval(120)
        let again = ConfigImport.plan(
            setup,
            matches: ConfigImport.matches(for: setup, config: before.config),
            state: before,
            now: twoMinutesLater
        )
        ConfigImport.apply(again, to: &before, now: twoMinutesLater)

        #expect(before.pending.count == 1)
        #expect(before.pending[0].effectiveAt == landed)
    }

    /// And the divergence stops there. Anything that differs in the least is a decision, and a
    /// decision supersedes what was queued on the new clock, exactly as the rule editor does.
    @Test("a file that differs from what is queued still supersedes it on the new clock")
    func adifferentFileStillRestartsTheClock() {
        var before = state([chrome()])
        ConfigImport.apply(plan(file([exported(.app, "com.google.Chrome", rule: .unrestricted)]), before), to: &before, now: now)
        let first = before.pending[0].effectiveAt

        let later = now.addingTimeInterval(120)
        let other = file([exported(.app, "com.google.Chrome", rule: Rule(windows: [window(600, 1140)], dailyBudgetMinutes: 120))])
        ConfigImport.apply(
            ConfigImport.plan(other, matches: ConfigImport.matches(for: other, config: before.config), state: before, now: later),
            to: &before,
            now: later
        )

        #expect(before.pending.count == 1)
        #expect(before.pending[0].effectiveAt == first.addingTimeInterval(120))
    }

    // MARK: What it says afterwards

    /// Every other mutation ends in a sentence. An import that closed in silence was the one
    /// change in the app that said nothing, and it is the largest one.
    @Test("the confirmation says what is in force now and when the rest lands")
    func whatItSaysAfterwards() {
        let plan = plan(
            file([
                exported(.app, "com.apple.Safari", name: "Safari", rule: Rule(windows: [window(540, 600)], dailyBudgetMinutes: 20)),
                exported(.app, "com.google.Chrome", rule: .unrestricted),
            ]),
            state([chrome()])
        )
        let said = plan.confirmation
        #expect(said.hasPrefix("1 app or website is now managed and 1 loosening is waiting out the delay."))
        let when = try! #require(plan.lastEffectiveAt).formatted(date: .abbreviated, time: .shortened)
        #expect(said.hasSuffix("It takes effect \(when)."))
        // The review's own sentence is the same shape in the future tense, and the two must not
        // drift into two vocabularies for one import.
        #expect(plan.headline.hasPrefix("1 app or website is new and 1 loosens your rules"))
    }

    @Test("several queued changes are counted together and the last one is dated")
    func theLastOneLands() {
        let a = makeTarget("A", rule: Rule(windows: [window(600, 660)], dailyBudgetMinutes: 30))
        let b = makeTarget("B", rule: Rule(windows: [window(600, 660)], dailyBudgetMinutes: 30))
        let plan = plan(
            file([
                exported(.website, "a.com", rule: .unrestricted),
                exported(.website, "b.com", rule: .unrestricted),
            ]),
            state([a, b])
        )
        #expect(plan.confirmation.contains("2 loosenings are waiting out the delay"))
        #expect(plan.confirmation.contains("The last of them takes effect"))
    }

    // MARK: Where the file came from

    /// Decoded since the first version and ignored by the UI until now. A setup file is worth
    /// keeping and worth sending, so the one from March and the one from last night are the
    /// same two lines in a Downloads folder.
    @Test("the plan carries when the file was written and by which build")
    func provenanceTravels() {
        let plan = plan(file([exported(.app, "com.google.Chrome")]), state([chrome()]))
        #expect(plan.exportedAt == at(8))
        #expect(plan.appVersion == "1.0")
    }

    // MARK: What the button is allowed to do

    @Test("a plan with changes can be applied, and an empty one cannot")
    func emptyCannotBeApplied() {
        let target = chrome()
        let looser = plan(file([exported(.app, "com.google.Chrome", rule: .unrestricted)]), state([target]))
        #expect(looser.canApply)
        let same = plan(file([exported(.app, "com.google.Chrome", nickname: "The bad one", utility: .hazard, rule: target.rule)]), state([target]))
        #expect(!same.canApply)
    }

    /// An import iOS will not register is worse than one that does not happen: the rules land,
    /// registration throws, `enforce` saves anyway, and nothing at all is monitored.
    @Test("a plan over the ceiling cannot be applied even though it has changes")
    func overTheCeilingCannotBeApplied() {
        var plan = plan(file([exported(.app, "com.google.Chrome", rule: .unrestricted)]), state([chrome()]))
        #expect(plan.canApply)
        plan.limitReason = "That would need too many windows."
        #expect(!plan.canApply)
        #expect(!plan.isEmpty)
    }
}
