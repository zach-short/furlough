import Foundation
import Testing

/// Which notifications carry the Drop anchor button. `Tests/Core` cannot post one, so this pins
/// the pure half: the choice, and that nothing `plan` schedules gets it.
@Suite("The Drop anchor button on a notification")
struct AnchorOfferTests {
    @Test("the four notifications about a moment carry it, and no other")
    func moments() {
        let carrying = NotificationKind.allCases.filter(AnchorOffer.carries)
        #expect(Set(carrying) == [.windowOpened, .windowClosing, .budgetWarning, .budgetSpent])
        for kind in carrying {
            #expect(AnchorOffer.category(for: kind) == Furlough.anchorNotificationCategory)
        }
        for kind in NotificationKind.allCases where !carrying.contains(kind) {
            #expect(AnchorOffer.category(for: kind) == nil)
        }
    }

    // A queued change and the digest are about a rule, not a temptation; the anchor's own two
    // announce a drop that already happened or a lift the person chose.
    @Test("nothing the plan schedules carries it")
    func plannedNotificationsDoNot() {
        let youTube = makeTarget("YouTube", rule: .alwaysBlocked)
        let queued = PendingChange(
            kind: .setRule(targetID: youTube.id, rule: Rule(windows: [], dailyBudgetMinutes: 30)),
            createdAt: at(7), effectiveAt: at(8, 20, 0)
        )
        var state = makeState([youTube], pending: [queued])
        var day = DayRecord()
        var held = TargetDay()
        held.shieldedMinutes = 600
        day.targets[youTube.id.uuidString] = held
        state.runtime.days["2026-09-07"] = day
        let planned = PendingNotifications.plan(state: state, now: at(8, 12, 0), calendar: cal)
        #expect(planned.count == 3)
        for note in planned {
            #expect(AnchorOffer.category(for: note.kind) == nil, "\(note.id)")
        }
    }

    @Test("the category and the action are two different identifiers, and neither is the control's")
    func identifiers() {
        #expect(Furlough.anchorNotificationCategory != Furlough.anchorNotificationAction)
        #expect(Furlough.anchorNotificationAction != Furlough.anchorControlKind)
        #expect(Furlough.anchorNotificationCategory.hasPrefix(Furlough.bundleID))
    }
}
