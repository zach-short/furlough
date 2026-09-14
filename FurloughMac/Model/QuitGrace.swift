import Foundation

/// Delay before force-quitting a blocked app, long enough to answer a "Save changes?" dialog.
/// Only applies to processes older than `settled`, so quitting and relaunching a blocked app
/// can't repeatedly earn a fresh grace period.
struct QuitGrace {
    static let full: TimeInterval = 45
    /// Grace for a freshly launched process, too new to have unsaved work.
    static let brief: TimeInterval = 2
    static let settled: TimeInterval = 60

    static func duration(age: TimeInterval) -> TimeInterval {
        age >= settled ? full : brief
    }

    enum Step: Equatable {
        case ask(deadline: Date)
        case wait(deadline: Date)
        /// `first` is true only on the tick the grace runs out, so logging doesn't repeat every tick.
        case force(first: Bool)
    }

    private var deadlines: [pid_t: Date] = [:]
    private var forced: Set<pid_t> = []

    func deadline(for pid: pid_t) -> Date? { deadlines[pid] }

    mutating func step(pid: pid_t, age: TimeInterval, now: Date) -> Step {
        guard let deadline = deadlines[pid] else {
            let deadline = now.addingTimeInterval(Self.duration(age: age))
            deadlines[pid] = deadline
            return .ask(deadline: deadline)
        }
        guard now >= deadline else { return .wait(deadline: deadline) }
        return .force(first: forced.insert(pid).inserted)
    }

    /// Clears dead pids so a reused pid starts its own grace, not a dead process's.
    mutating func forget(except alive: Set<pid_t>) {
        deadlines = deadlines.filter { alive.contains($0.key) }
        forced = forced.intersection(alive)
    }

    #if DEBUG || TESTING_TOOLS
    mutating func forgetAll() {
        deadlines = [:]
        forced = []
    }
    #endif
}
