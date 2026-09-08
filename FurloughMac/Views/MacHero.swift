import SwiftUI

/// The phone's hero page for one app, at the top of its rule: the living hourglass, an
/// eyebrow, the name, the big countdown and a sub line. `now` ticks once a second in the
/// editor, so the sand and the countdown share a clock. The Mac counts usage itself, so the
/// sub line can say how much of the budget is gone, which the phone cannot.
struct TargetHero: View {
    let target: Target
    let status: TargetStatus
    let runtime: RuntimeState
    /// Seconds counted against the budget today.
    let usedSeconds: Int
    let now: Date

    private struct Line {
        enum Big {
            case countdown(to: Date)
            case quiet(String)
        }

        var eyebrow: String
        var color: Color
        var big: Big
        var sub: String
    }

    var body: some View {
        let glass = HourglassState.of(target, status: status, runtime: runtime, now: now)
        let line = line()
        HStack(alignment: .center, spacing: 18) {
            LivingHourglass(state: glass)
                .frame(width: 74, height: 98)
                .compositingGroup()
                .shadow(color: (glass.glow ?? .clear).opacity(0.4), radius: 20)
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: line.eyebrow, color: line.color)
                HStack(spacing: 10) {
                    KindTile(kind: target.kind, size: 28)
                    Text(target.displayName)
                        .emberDisplay(26)
                        .foregroundStyle(Ember.cream)
                        .lineLimit(1)
                }
                .padding(.top, 4)
                big(line.big)
                Text(line.sub)
                    .emberBody(11.5)
                    .foregroundStyle(Ember.muted)
                    .lineLimit(2)
                    .padding(.top, 6)
                Text(identity)
                    .emberBody(10.5)
                    .foregroundStyle(Ember.faint)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func big(_ big: Line.Big) -> some View {
        switch big {
        case .countdown(let end):
            Text(TimeFormat.countdown(from: now, to: end))
                .emberNumerals(42)
                .padding(.top, 6)
        case .quiet(let text):
            Text(text)
                .font(EmberFont.numerals(30))
                .tracking(-0.6)
                .foregroundStyle(Ember.muted)
                .padding(.top, 10)
        }
    }

    /// What the target is underneath its name: the bundle identifier or the host.
    private var identity: String {
        switch target.kind {
        case .macApp(let bundleID): bundleID
        case .host(let host): "\(host) and its subdomains"
        }
    }

    private func line() -> Line {
        let budget = target.rule.map { TimeFormat.budget($0.dailyBudgetMinutes) } ?? ""
        let used = "\(usedSeconds / 60) of \(target.rule?.dailyBudgetMinutes ?? 0) min used today"
        switch status {
        case .open(let until):
            let end = Policy.date(atMinute: until, of: now)
            if runtime.wasWarned(target.id, dayKey: Policy.dayKey(now)) {
                return Line(
                    eyebrow: "Open now · \(Furlough.warningMinutes) min left", color: Ember.amber,
                    big: .countdown(to: end), sub: "\(used) · under \(Furlough.warningMinutes) min left"
                )
            }
            if target.rule?.isAllDay ?? false {
                return Line(
                    eyebrow: "Open all day", color: Ember.moss,
                    big: .countdown(to: end), sub: "\(used) · resets at midnight"
                )
            }
            return Line(
                eyebrow: "Open now · until \(TimeFormat.minute(until))", color: Ember.moss,
                big: .countdown(to: end), sub: used
            )
        case .closed(let next):
            return Line(
                eyebrow: "Next window", color: Ember.amber,
                big: .countdown(to: Policy.date(at: next, from: now)), sub: "opens \(TimeFormat.nextOpen(next)) · \(budget) a day"
            )
        case .exhausted(let next):
            if let next {
                return Line(
                    eyebrow: "Used up today", color: Ember.ember,
                    big: .countdown(to: Policy.date(at: next, from: now)), sub: "opens \(TimeFormat.nextOpen(next)) · \(budget) a day"
                )
            }
            return Line(eyebrow: "Used up today", color: Ember.ember, big: .quiet("spent"), sub: "\(budget) a day")
        case .anchored:
            // Only the phone can anchor, and rules are per device, so this never shows on a Mac.
            return Line(eyebrow: "Anchored", color: Ember.ember, big: .quiet("locked"), sub: RowCopy.detail(target: target, status: status, now: now))
        case .blockedAllDay:
            return Line(eyebrow: "Always blocked", color: Ember.muted, big: .quiet("all day"), sub: "No budget · set one below")
        case .unconfigured:
            return Line(
                eyebrow: "Needs a schedule", color: Ember.pending, big: .quiet("not enforced"),
                sub: "Set windows and a budget below"
            )
        }
    }
}

/// The list order from the phone: Open now · Later today · Tomorrow · Later this week ·
/// Always blocked · Needs a schedule. There is no Anchored section: a Mac has no NFC reader,
/// so nothing is ever anchored here.
struct HomeGroups {
    struct Section: Identifiable {
        let title: String
        let targets: [Target]
        var id: String { title }
    }

    var open: [(target: Target, until: Date)] = []
    var laterToday: [(target: Target, at: Date)] = []
    var tomorrow: [(target: Target, at: Date?)] = []
    /// Two or more days out: targets whose windows skip tomorrow.
    var laterThisWeek: [(target: Target, at: Date)] = []
    var alwaysBlocked: [Target] = []
    var unconfigured: [Target] = []

    init(targets: [Target], statuses: [UUID: TargetStatus], now: Date) {
        for target in targets {
            switch statuses[target.id] ?? .unconfigured {
            case .open(let until):
                open.append((target, Policy.date(atMinute: until, of: now)))
            case .closed(let next):
                let at = Policy.date(at: next, from: now)
                switch next.daysAhead {
                case 0: laterToday.append((target, at))
                case 1: tomorrow.append((target, at))
                default: laterThisWeek.append((target, at))
                }
            case .exhausted(let next):
                if let next, next.daysAhead >= 2 {
                    laterThisWeek.append((target, Policy.date(at: next, from: now)))
                } else {
                    tomorrow.append((target, next.map { Policy.date(at: $0, from: now) }))
                }
            case .blockedAllDay, .anchored:
                alwaysBlocked.append(target)
            case .unconfigured:
                unconfigured.append(target)
            }
        }
        open.sort { $0.until < $1.until }
        laterToday.sort { $0.at < $1.at }
        tomorrow.sort { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
        laterThisWeek.sort { $0.at < $1.at }
    }

    var sections: [Section] {
        [
            Section(title: "Open now", targets: open.map(\.target)),
            Section(title: "Later today", targets: laterToday.map(\.target)),
            Section(title: "Tomorrow", targets: tomorrow.map(\.target)),
            Section(title: "Later this week", targets: laterThisWeek.map(\.target)),
            Section(title: "Always blocked", targets: alwaysBlocked),
            Section(title: "Needs a schedule", targets: unconfigured),
        ].filter { !$0.targets.isEmpty }
    }
}
