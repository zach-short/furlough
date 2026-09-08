import Foundation
import Testing

/// The Mac's grace between asking a blocked app to quit and forcing it. The two rules that
/// matter: a working session gets long enough to answer a save dialog, and relaunching a
/// blocked app does not buy another one.
struct QuitGraceTests {
    private let pid: pid_t = 501

    @Test func aSettledProcessGetsTheFullGrace() {
        var grace = QuitGrace()
        let now = at(8, 12, 0)
        let step = grace.step(pid: pid, age: 10 * 60, now: now)
        #expect(step == .ask(deadline: now.addingTimeInterval(QuitGrace.full)))
    }

    @Test func aFreshlyLaunchedProcessGetsOnlyTheBriefOne() {
        var grace = QuitGrace()
        let now = at(8, 12, 0)
        let step = grace.step(pid: pid, age: 3, now: now)
        #expect(step == .ask(deadline: now.addingTimeInterval(QuitGrace.brief)))
    }

    @Test func theGraceIsHeldUntilItRunsOut() {
        var grace = QuitGrace()
        let now = at(8, 12, 0)
        _ = grace.step(pid: pid, age: QuitGrace.settled, now: now)
        let deadline = now.addingTimeInterval(QuitGrace.full)
        #expect(grace.step(pid: pid, age: QuitGrace.settled, now: now.addingTimeInterval(1)) == .wait(deadline: deadline))
        #expect(grace.step(pid: pid, age: QuitGrace.settled, now: deadline.addingTimeInterval(-0.5)) == .wait(deadline: deadline))
        #expect(grace.step(pid: pid, age: QuitGrace.settled, now: deadline) == .force(first: true))
    }

    /// The app is force-quit on every tick until it is actually gone, but only the first says so
    /// in the log.
    @Test func forcingIsAnnouncedOnce() {
        var grace = QuitGrace()
        let now = at(8, 12, 0)
        _ = grace.step(pid: pid, age: QuitGrace.settled, now: now)
        let after = now.addingTimeInterval(QuitGrace.full + 5)
        #expect(grace.step(pid: pid, age: QuitGrace.settled, now: after) == .force(first: true))
        #expect(grace.step(pid: pid, age: QuitGrace.settled, now: after) == .force(first: false))
    }

    /// Quitting and relaunching would hand out a fresh 45 seconds every time if the grace went
    /// by app rather than by process age. The relaunched process is young, so it does not.
    @Test func relaunchingDoesNotBuyAnotherFullGrace() {
        var grace = QuitGrace()
        let now = at(8, 12, 0)
        _ = grace.step(pid: pid, age: 10 * 60, now: now)
        grace.forget(except: [])

        let relaunched: pid_t = 502
        let step = grace.step(pid: relaunched, age: 1, now: now.addingTimeInterval(60))
        #expect(step == .ask(deadline: now.addingTimeInterval(60 + QuitGrace.brief)))
    }

    /// A pid the system hands out again must not inherit a dead process's deadline.
    @Test func aDeadProcessIsForgotten() {
        var grace = QuitGrace()
        let now = at(8, 12, 0)
        _ = grace.step(pid: pid, age: QuitGrace.settled, now: now)
        #expect(grace.deadline(for: pid) != nil)

        grace.forget(except: [999])
        #expect(grace.deadline(for: pid) == nil)

        let later = now.addingTimeInterval(QuitGrace.full * 2)
        #expect(grace.step(pid: pid, age: QuitGrace.settled, now: later) == .ask(deadline: later.addingTimeInterval(QuitGrace.full)))
    }

    @Test func aLivingProcessKeepsItsDeadline() {
        var grace = QuitGrace()
        let now = at(8, 12, 0)
        _ = grace.step(pid: pid, age: QuitGrace.settled, now: now)
        grace.forget(except: [pid, 999])
        #expect(grace.deadline(for: pid) == now.addingTimeInterval(QuitGrace.full))
    }

    @Test(arguments: [0.0, 1.0, QuitGrace.settled - 1])
    func anythingYoungerThanSettledIsBrief(age: TimeInterval) {
        #expect(QuitGrace.duration(age: age) == QuitGrace.brief)
    }

    @Test(arguments: [QuitGrace.settled, QuitGrace.settled + 1, 3600.0])
    func anythingSettledIsFull(age: TimeInterval) {
        #expect(QuitGrace.duration(age: age) == QuitGrace.full)
    }
}
