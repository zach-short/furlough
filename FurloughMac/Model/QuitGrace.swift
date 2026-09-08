import Foundation

/// The pause between asking a blocked app to quit and forcing it.
///
/// Two seconds was enough for an app that goes quietly and far too little for one that stops
/// to ask "Save changes?": the sheet appeared and the app was killed underneath it, taking the
/// work with it. So Furlough asks, shows the countdown on the shield, and only forces the issue
/// when the grace runs out. The rule does not move — the app still goes — the user just gets
/// long enough to answer the dialog.
///
/// The grace is measured per process, and a process that started moments ago does not get it:
/// it cannot have unsaved work, and without that rule quitting and relaunching a blocked app
/// would hand out a fresh three-quarters of a minute every time. In practice a long-lived
/// blocked process only exists when the block just arrived — a window closed or a budget ran
/// out while the app was open — which is exactly the case worth protecting.
struct QuitGrace {
    /// Long enough to read a save dialog and click through it.
    static let full: TimeInterval = 45
    /// What a process that has only just launched gets: the old behaviour.
    static let brief: TimeInterval = 2
    /// How long a process must have been running to count as a session with work in it.
    static let settled: TimeInterval = 60

    static func duration(age: TimeInterval) -> TimeInterval {
        age >= settled ? full : brief
    }

    /// What to do with a blocked app on this tick.
    enum Step: Equatable {
        /// Not asked yet: ask it to quit, and start the grace.
        case ask(deadline: Date)
        /// Asked, still running, still inside the grace.
        case wait(deadline: Date)
        /// The grace is up. `first` is true only on the tick that runs out, so the log gets
        /// one line rather than one a second while a stubborn app is on its way out.
        case force(first: Bool)
    }

    /// When each asked-to-quit process runs out of grace.
    private var deadlines: [pid_t: Date] = [:]
    /// Processes already past their deadline, so forcing is logged once.
    private var forced: Set<pid_t> = []

    /// The moment `pid` will be forced, if it has been asked.
    func deadline(for pid: pid_t) -> Date? { deadlines[pid] }

    /// `age` is how long the process has been running. `now` is Furlough's own time.
    mutating func step(pid: pid_t, age: TimeInterval, now: Date) -> Step {
        guard let deadline = deadlines[pid] else {
            let deadline = now.addingTimeInterval(Self.duration(age: age))
            deadlines[pid] = deadline
            return .ask(deadline: deadline)
        }
        guard now >= deadline else { return .wait(deadline: deadline) }
        return .force(first: forced.insert(pid).inserted)
    }

    /// Forgets every process that is no longer running, so a pid the system hands out again
    /// starts its own grace rather than inheriting a dead one's.
    mutating func forget(except alive: Set<pid_t>) {
        deadlines = deadlines.filter { alive.contains($0.key) }
        forced = forced.intersection(alive)
    }

    #if DEBUG
    mutating func forgetAll() {
        deadlines = [:]
        forced = []
    }
    #endif
}
