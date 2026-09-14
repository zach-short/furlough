import Foundation
import Testing

/// Websites by name (the phone gained this 2026-09-08; the Mac always had it). The phone blocks
/// one via `WebContentSettings.blockedByFilter`'s `.specific` case, which takes a plain host and
/// needs no token — so what it costs is a daily budget rather than a DeviceActivity count.
///
/// Builds for macOS, reading the Mac's `TargetKind`/`Decision`; the shared rule engine makes
/// this hold for the phone too. Unreachable from here: iOS's `Decision.filteredHosts` and
/// `ShieldReconciler.apply` — why `webFilterHosts` lives on `Decision` rather than the reconciler.
@Suite("Websites by name")
struct HostTargetTests {

    // MARK: A rule with hours and no budget

    // A whole day of budget, since 0 would mean blocked all day and anything else an
    // unenforceable limit.
    let noLimit = Furlough.minutesPerDay

    @Test("a whole day of budget is not a limit")
    func fullDayIsNoLimit() {
        #expect(Rule(windows: [], dailyBudgetMinutes: noLimit).limit(on: 1) == nil)
        #expect(Rule.unrestricted.limit(on: 1) == nil)
        #expect(Rule(windows: [], dailyBudgetMinutes: 30).limit(on: 1) == 30)
        #expect(Rule.alwaysBlocked.limit(on: 1) == 0)
    }

    @Test("a rule with hours and no limit still opens and closes on its windows")
    func windowsWithoutABudget() {
        let rule = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: noLimit)
        let target = makeTarget("Youtube", rule: rule)
        let config = makeConfig([target])
        // 8:30 PM, inside the window.
        let open = Policy.status(of: target, config: config, runtime: RuntimeState(), now: at(8, 20, 30), calendar: cal)
        #expect(open == .open(until: 1320))
        // 10:30 PM, after it.
        let shut = Policy.status(of: target, config: config, runtime: RuntimeState(), now: at(8, 22, 30), calendar: cal)
        #expect(shut == .closed(nextOpen: NextOpen(minuteOfDay: 1200, daysAhead: 1)))
    }

    @Test("a rule with hours and no limit is never exhausted by its budget")
    func neverExhausted() {
        let rule = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: noLimit)
        #expect(rule.isEverAllowed)
        #expect(rule.effectiveBudget(on: 1) == noLimit)
    }

    @Test("a rule saying nothing but hours reads back without a budget clause")
    func ruleReadsWithoutABudget() {
        let rule = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: noLimit)
        let text = plainSpaces(TimeFormat.rule(rule, calendar: cal))
        #expect(!text.contains("/day"))
        #expect(text.contains("8:00 PM"))
        let limited = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: 30)
        #expect(plainSpaces(TimeFormat.rule(limited, calendar: cal)).contains("30 min/day"))
    }

    @Test("a target opening next with no limit offers the widget no budget line")
    func summaryOffersNoBudget() {
        let rule = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: noLimit)
        let state = makeState([makeTarget("Youtube", rule: rule)])
        let summary = Policy.summary(state: state, now: at(8, 10), calendar: cal)
        #expect(summary.nextOpenNames == ["Youtube"])
        #expect(summary.nextOpenBudgetMinutes == nil)
    }

    // MARK: Classifying, queueing and applying

    @Test("adding hours to a rule with no limit still queues as a loosening")
    func loosensTheSameWay() {
        let tight = Rule(windows: [window(1200, 1260)], dailyBudgetMinutes: noLimit)
        let loose = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: noLimit)
        let target = makeTarget("Youtube", rule: tight)
        #expect(Policy.classify(newRule: loose, against: target) == .loosening)
        #expect(Policy.classify(newRule: tight, against: makeTarget("Youtube", rule: loose)) == .tightening)
    }

    @Test("a queued rule with no limit lands when its time comes")
    func queuedRuleApplies() {
        let target = makeTarget("Youtube", rule: Rule(windows: [window(1200, 1260)], dailyBudgetMinutes: noLimit))
        let loose = Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: noLimit)
        var state = makeState(
            [target],
            pending: [PendingChange(kind: .setRule(targetID: target.id, rule: loose), effectiveAt: at(9))]
        )
        #expect(Policy.applyDuePending(&state, now: at(9, 1)))
        #expect(state.config.targets[0].rule?.isEquivalent(to: loose) == true)
        #expect(state.pending.isEmpty)
    }

    // MARK: The 19-span ceiling

    @Test("a typed host's windows count against the span limit like anything else")
    func hostSpansCount() {
        let hours = (0..<3).map { window($0 * 60, $0 * 60 + 30) }
        let host = Target(kind: .host("youtube.com"), rule: Rule(windows: hours, dailyBudgetMinutes: noLimit))
        #expect(ActivityLimit.spans(in: makeState([host])).count == 3)
    }

    @Test("a host sharing hours with an app costs nothing extra")
    func hostSharesSpans() {
        let hours = [window(1200, 1320)]
        let host = Target(kind: .host("youtube.com"), rule: Rule(windows: hours, dailyBudgetMinutes: noLimit))
        let other = makeTarget("Other", rule: Rule(windows: hours, dailyBudgetMinutes: 30))
        #expect(ActivityLimit.spans(in: makeState([host, other])).count == 1)
    }

    @Test("hosts can overflow the ceiling on their own")
    func hostsCanOverflow() {
        let many = (0...ActivityLimit.maxSpans).map { window($0 * 60 % 1380, $0 * 60 % 1380 + 30) }
        let host = Target(kind: .host("youtube.com"), rule: Rule(windows: [window(0, 30)], dailyBudgetMinutes: noLimit))
        let reason = ActivityLimit.reason(
            applying: Rule(windows: many, dailyBudgetMinutes: noLimit),
            to: [host.id],
            in: makeState([host])
        )
        #expect(reason != nil)
    }

    // MARK: A host is its own name

    @Test("a typed host needs no learned name")
    func hostNamesItself() {
        let target = Target(kind: .host("youtube.com"))
        #expect(target.defaultName == "youtube.com")
        #expect(target.displayName == "youtube.com")
        var nicknamed = target
        nicknamed.nickname = "The time sink"
        #expect(nicknamed.displayName == "The time sink")
    }

    @Test("a host is found by any subdomain of it, longest match first")
    func lookupMatchesSubdomains() {
        let config = makeConfig([Target(kind: .host("youtube.com")), Target(kind: .host("music.youtube.com"))])
        #expect(config.target(host: "m.youtube.com")?.host == "youtube.com")
        #expect(config.target(host: "music.youtube.com")?.host == "music.youtube.com")
        #expect(config.target(host: "example.com") == nil)
    }

    // MARK: Carrying a setup between devices

    @Test("a typed host exports with its name, so another device can look it up")
    func exportsWithAnIdentifier() {
        let target = Target(kind: .host("youtube.com"), rule: Rule(windows: [window(1200, 1320)], dailyBudgetMinutes: noLimit))
        let exported = ExportedTarget(target)
        #expect(exported.kind == .website)
        #expect(exported.identifier == "youtube.com")
    }
}
