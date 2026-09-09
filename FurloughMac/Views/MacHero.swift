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
        let today = Policy.weekday(now)
        let budget = target.rule.map { TimeFormat.budget($0.budget(on: today)) } ?? ""
        let used = "\(usedSeconds / 60) of \(target.rule?.budget(on: today) ?? 0) min used today"
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
                eyebrow: "Open now · until \(TimeFormat.until(until))", color: Ember.moss,
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
            // Since 2026-09-09 the Mac anchors too: dropped here, or on the phone and arrived
            // through iCloud. Only the phone's tag releases it.
            return Line(eyebrow: "Anchored", color: Ember.ember, big: .quiet("locked"), sub: "Your iPhone's tag releases it · \(RowCopy.detail(target: target, status: status, now: now))")
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

    /// Every target in the list's order: one hero page each, as on the phone.
    var ordered: [Target] { sections.flatMap(\.targets) }

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


/// The phone's hero header (H1 in design/HOURGLASS.md) as the Mac's front page: one page per
/// managed app in the list's order, with a strip of tiny status hourglasses under it that is a
/// status summary in itself. The Mac has no swipe, so the strip and a pair of chevrons turn the
/// pages; clicking the page opens that app's rule, which is what tapping it does on the phone.
/// It fills the detail pane while nothing is selected, so the living hourglass is the first
/// thing the window shows rather than something you have to click to find.
struct MacHeroPager: View {
    let targets: [Target]
    let statuses: [UUID: TargetStatus]
    let runtime: RuntimeState
    let now: Date
    /// Seconds counted against the budget today, per target.
    let usedSeconds: (UUID) -> Int
    let onOpen: (UUID) -> Void
    /// The page being shown; the second ticks rebuild this view, so it is state.
    @State private var featured: UUID?

    private var landing: UUID? {
        targets.first { if case .open = statuses[$0.id] { return true }; return false }?.id ?? targets.first?.id
    }

    private var current: Target? {
        targets.first { $0.id == featured } ?? targets.first
    }

    private var glasses: [UUID: HourglassState] {
        Dictionary(uniqueKeysWithValues: targets.map { target in
            (target.id, HourglassState.of(target, status: statuses[target.id] ?? .unconfigured, runtime: runtime, now: now))
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let target = current {
                HStack(spacing: 10) {
                    turner(symbol: "chevron.left", by: -1)
                    Button { onOpen(target.id) } label: {
                        TargetHero(
                            target: target,
                            status: statuses[target.id] ?? .unconfigured,
                            runtime: runtime,
                            usedSeconds: usedSeconds(target.id),
                            now: now
                        )
                        .frame(width: 420, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(target.displayName)'s rule")
                    turner(symbol: "chevron.right", by: 1)
                }
                if targets.count > 1 {
                    HeroIndicator(pages: targets, glasses: glasses, featured: $featured)
                        .frame(maxWidth: 420)
                }
                Text(targets.count > 1 ? "Click a glass to page through, or the page to set its windows." : "Click it to set its windows and budget.")
                    .emberBody(11.5)
                    .foregroundStyle(Ember.faint)
                    .padding(.top, 6)
            }
        }
        .animation(.snappy, value: featured)
        .onAppear { if !targets.contains(where: { $0.id == featured }) { featured = landing } }
        .onChange(of: targets.map(\.id)) { _, ids in
            if let featured, !ids.contains(featured) { self.featured = landing }
        }
    }

    /// One page forward or back, wrapping, for the mouse and for ⌘← / ⌘→.
    @ViewBuilder
    private func turner(symbol: String, by step: Int) -> some View {
        Button {
            guard let featured, let index = targets.firstIndex(where: { $0.id == featured }), targets.count > 1 else { return }
            let next = (index + step + targets.count) % targets.count
            self.featured = targets[next].id
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Ember.faint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(targets.count > 1 ? 1 : 0)
        .disabled(targets.count < 2)
        .keyboardShortcut(step < 0 ? .leftArrow : .rightArrow, modifiers: .command)
    }
}
