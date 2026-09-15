import Foundation
import Testing

/// A switch per notification: what `plan` leaves out, and how an older build's one preference
/// reads after being folded into the set.
@Suite("Notification kinds: the switch each one has")
struct NotificationKindTests {
    let youTube = makeTarget("YouTube", rule: Rule(windows: [window(1080, 1200)], dailyBudgetMinutes: 30))
    let now = at(8, 12, 0)

    /// A loosening queued for tomorrow: a warning an hour ahead and the landing itself.
    private func queued() -> SharedState {
        let change = PendingChange(kind: .setDelay(hours: 2), createdAt: now, effectiveAt: at(9, 12, 0))
        return makeState([youTube], pending: [change])
    }

    private func plan(_ muted: Set<NotificationKind>) -> [PlannedNotification] {
        PendingNotifications.plan(state: queued(), now: now, muted: muted, calendar: cal)
    }

    @Test("with nothing muted, every planned notification is planned")
    func nothingMuted() {
        let kinds = plan([]).map(\.kind)
        #expect(kinds == [.looseningWarning, .looseningLanded])
    }

    @Test("plan omits exactly the kinds that are off, and keeps the rest")
    func omitsTheMuted() {
        #expect(plan([.looseningWarning]).map(\.kind) == [.looseningLanded])
        #expect(plan([.looseningLanded]).map(\.kind) == [.looseningWarning])
        #expect(plan([.looseningWarning, .looseningLanded]).isEmpty)
        // Muting something that isn't planned here changes nothing.
        #expect(plan([.windowOpened, .budgetSpent, .anchorDropped]).count == 2)
    }

    @Test("the digest is planned or not by its own switch, beside the others")
    func digestFollowsItsSwitch() {
        var state = makeState([])
        // A week that actually held something, or there is no digest to plan.
        var day = DayRecord()
        var entry = TargetDay()
        entry.shieldedMinutes = 120
        day.targets[UUID().uuidString] = entry
        for offset in 1...7 {
            state.runtime.days[Policy.dayKey(at(14 - offset), calendar: cal)] = day
        }
        let on = PendingNotifications.plan(state: state, now: now, muted: [], calendar: cal)
        #expect(on.map(\.kind) == [.weeklyDigest])
        #expect(PendingNotifications.plan(state: state, now: now, muted: [.weeklyDigest], calendar: cal).isEmpty)
    }

    // MARK: What a store with no answers reads as

    @Test("a store with no preferences reads as all on")
    func freshInstallIsAllOn() {
        #expect(NotificationPreferences.muted(stored: nil, legacyDigest: nil).isEmpty)
        #expect(NotificationPreferences.muted(stored: [], legacyDigest: nil).isEmpty)
    }

    @Test("the digest preference written by an older build still reads correctly after the fold")
    func legacyDigestSurvives() {
        // The one preference that existed before this screen: a Bool of its own.
        #expect(NotificationPreferences.muted(stored: nil, legacyDigest: false) == [.weeklyDigest])
        #expect(NotificationPreferences.muted(stored: nil, legacyDigest: true).isEmpty)
        // Once this build has written its own answer, the old key stops being consulted.
        #expect(NotificationPreferences.muted(stored: [], legacyDigest: false).isEmpty)
        #expect(
            NotificationPreferences.muted(stored: ["windowOpened"], legacyDigest: false) == [.windowOpened]
        )
    }

    @Test("a stored name this build does not know mutes nothing")
    func unknownKindIsIgnored() {
        #expect(
            NotificationPreferences.muted(stored: ["windowOpened", "somethingElse"], legacyDigest: nil)
                == [.windowOpened]
        )
    }

    @Test("every kind has its own words, and no two rows read the same")
    func everyKindIsNamed() {
        let titles = NotificationKind.allCases.map(\.title)
        #expect(titles.count == 9)
        #expect(Set(titles).count == titles.count)
        #expect(Set(NotificationKind.allCases.map(\.detail)).count == titles.count)
        #expect(!titles.contains { $0.isEmpty })
    }
}
