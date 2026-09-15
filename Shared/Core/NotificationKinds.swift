import Foundation

/// Every notification Furlough posts, and the one switch each of them has.
///
/// Muting one changes nothing about what is shielded, so — unlike almost everything else in this
/// app — it applies instantly and waits out no delay. That is worth saying on the screen: it is
/// the rare setting here that is free.
///
/// Before this there was one preference, for the weekly digest, and the other eight fired
/// unconditionally: a person who found "Window opened" noisy had one lever, iOS's own switch,
/// and it took "Time's up" and the loosening warnings with it.
enum NotificationKind: String, CaseIterable, Codable, Sendable {
    /// A window opened and something is usable now.
    case windowOpened
    /// A window closes in five minutes.
    case windowClosing
    /// Five minutes of today's budget left.
    case budgetWarning
    /// The budget is spent and the shield is back.
    case budgetSpent
    /// The anchor dropped — on a schedule, or from another device.
    case anchorDropped
    /// A timed anchor's time came and it lifted by itself.
    case anchorLifted
    /// A queued loosening lands in an hour; there is still time to cancel it.
    case looseningWarning
    /// A queued loosening waited out the delay and landed.
    case looseningLanded
    /// Monday morning's summary of the week's record.
    case weeklyDigest

    /// The row's label on the settings screen.
    var title: String {
        switch self {
        case .windowOpened: "Window opened"
        case .windowClosing: "Window closing"
        case .budgetWarning: "\(Furlough.warningMinutes) minutes left"
        case .budgetSpent: "Time's up"
        case .anchorDropped: "Anchor dropped"
        case .anchorLifted: "Anchor lifted"
        case .looseningWarning: "Loosening lands in an hour"
        case .looseningLanded: "Change landed"
        case .weeklyDigest: "Weekly digest"
        }
    }

    /// One line under it, saying when it arrives rather than what it is called.
    var detail: String {
        switch self {
        case .windowOpened: "When an app or site becomes usable."
        case .windowClosing: "Five minutes before a window shuts."
        case .budgetWarning: "Five minutes of a daily budget left."
        case .budgetSpent: "A budget is spent and the shield is back."
        case .anchorDropped: "The anchor dropped on a schedule, or on another device."
        case .anchorLifted: "A timed anchor's time came and it lifted."
        case .looseningWarning: "An hour before a queued loosening lands — time to cancel it."
        case .looseningLanded: "A queued change has landed."
        case .weeklyDigest: "Monday morning, the week just gone."
        }
    }
}

/// Which notifications this device wants. Kept in the **App Group**, not `Config`: it is this
/// device's own, it must not travel in an exported setup or wait out a loosening delay, and an
/// app extension does not share the app's `UserDefaults.standard` — the monitor reads it to
/// decide whether to post at all.
///
/// Stored as the set that is *off*, so a kind added later is on by default without a migration.
enum NotificationPreferences {
    #if os(iOS)
    static let key = "furlough.notifications.muted"
    /// The one preference that existed before this: the weekly digest's own Bool, read once here
    /// so an older build's answer survives the fold. See `DecodingTests` for the same idea.
    static let legacyDigestKey = "furlough.weeklyDigest"
    #else
    static let key = "furlough.mac.notifications.muted"
    static let legacyDigestKey = "furlough.mac.weeklyDigest"
    #endif

    /// The kinds this device has switched off. Everything absent is on, which is what a fresh
    /// install has and what every build before this one did.
    static var muted: Set<NotificationKind> {
        muted(
            stored: SharedStore.defaults.array(forKey: key) as? [String],
            legacyDigest: SharedStore.defaults.object(forKey: legacyDigestKey) as? Bool
        )
    }

    /// The same, from the two raw values rather than the store — pure, so the fold of an older
    /// build's digest answer can be tested without writing anybody's preferences.
    static func muted(stored: [String]?, legacyDigest: Bool?) -> Set<NotificationKind> {
        guard let stored else {
            // Never answered here. An older build's digest switch is the one answer that can
            // exist, so it is honoured rather than left as a second mechanism.
            return legacyDigest == false ? [.weeklyDigest] : []
        }
        // A raw value this build doesn't know (a kind removed later) reads as nothing rather
        // than muting something it isn't.
        return Set(stored.compactMap(NotificationKind.init(rawValue:)))
    }

    static func isOn(_ kind: NotificationKind) -> Bool { !muted.contains(kind) }

    static func set(_ kind: NotificationKind, on: Bool) {
        var off = muted
        if on { off.remove(kind) } else { off.insert(kind) }
        // Written whole, so the legacy key stops being consulted from the first change onwards.
        SharedStore.defaults.set(off.map(\.rawValue).sorted(), forKey: key)
        // Kept in step while an older build could still be reading it — a downgrade that lost
        // a digest switch would be a notification arriving after it was told not to.
        if kind == .weeklyDigest { SharedStore.defaults.set(on, forKey: legacyDigestKey) }
    }

    /// Back to what a fresh install has, for `SharedStore.reset()` and the testing reset.
    static func forgetAll() {
        SharedStore.defaults.removeObject(forKey: key)
        SharedStore.defaults.removeObject(forKey: legacyDigestKey)
    }
}
