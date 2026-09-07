import Foundation
import ManagedSettings

/// A span of minutes inside one calendar day. `endMinute` is exclusive and may be 1440 (midnight).
struct TimeWindow: Codable, Hashable, Identifiable, Comparable {
    var startMinute: Int
    var endMinute: Int

    var id: String { "\(startMinute)-\(endMinute)" }
    var durationMinutes: Int { endMinute - startMinute }

    var isValid: Bool {
        startMinute >= 0
            && endMinute <= Furlough.minutesPerDay
            && durationMinutes >= Furlough.minimumWindowMinutes
    }

    func contains(minuteOfDay minute: Int) -> Bool {
        minute >= startMinute && minute < endMinute
    }

    func overlaps(_ other: TimeWindow) -> Bool {
        startMinute < other.endMinute && other.startMinute < endMinute
    }

    static func < (lhs: TimeWindow, rhs: TimeWindow) -> Bool {
        (lhs.startMinute, lhs.endMinute) < (rhs.startMinute, rhs.endMinute)
    }
}

/// When a target may be used, and for how many minutes per day in total.
struct Rule: Codable, Hashable {
    var windows: [TimeWindow] = []
    var dailyBudgetMinutes: Int = Furlough.defaultBudgetMinutes

    /// Permits everything. The baseline for a target that has no rule yet, and what "remove" means.
    static let unrestricted = Rule(
        windows: [TimeWindow(startMinute: 0, endMinute: Furlough.minutesPerDay)],
        dailyBudgetMinutes: Furlough.minutesPerDay
    )
    static let alwaysBlocked = Rule(windows: [], dailyBudgetMinutes: 0)

    var isEverAllowed: Bool { !windows.isEmpty && dailyBudgetMinutes > 0 }
    var effectiveBudgetMinutes: Int { isEverAllowed ? dailyBudgetMinutes : 0 }
    var sortedWindows: [TimeWindow] { windows.sorted() }

    /// One flag per minute of the day; true where use is permitted.
    var allowedMask: [Bool] {
        var mask = [Bool](repeating: false, count: Furlough.minutesPerDay)
        guard isEverAllowed else { return mask }
        for window in windows {
            let lower = max(0, window.startMinute)
            let upper = min(Furlough.minutesPerDay, window.endMinute)
            guard lower < upper else { continue }
            for minute in lower..<upper { mask[minute] = true }
        }
        return mask
    }

    func window(containing minute: Int) -> TimeWindow? {
        guard isEverAllowed else { return nil }
        return windows.first { $0.contains(minuteOfDay: minute) }
    }

    /// True when this rule allows no minute that `other` forbids and has no larger budget.
    func isTighterOrEqual(to other: Rule) -> Bool {
        let mine = allowedMask
        let theirs = other.allowedMask
        for minute in 0..<Furlough.minutesPerDay where mine[minute] && !theirs[minute] {
            return false
        }
        return effectiveBudgetMinutes <= other.effectiveBudgetMinutes
    }

    /// Problems that make the rule unusable, or nil.
    var validationError: String? {
        for window in windows where !window.isValid {
            return "Each window must be at least \(Furlough.minimumWindowMinutes) minutes and end after it starts."
        }
        let sorted = sortedWindows
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.overlaps(b) {
            return "Windows must not overlap."
        }
        return nil
    }
}

enum TargetKind: Codable, Hashable {
    case application(ApplicationToken)
    case webDomain(WebDomainToken)
    case category(ActivityCategoryToken)

    var isCategory: Bool {
        if case .category = self { return true }
        return false
    }
}

/// One app, website, or category that Furlough manages.
struct Target: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: TargetKind
    var nickname = ""
    /// nil means "not configured yet": nothing is enforced until the first rule is saved.
    var rule: Rule?
    var addedAt = Date.now

    var defaultName: String {
        switch kind {
        case .application: "This app"
        case .webDomain: "This website"
        case .category: "This category"
        }
    }

    var displayName: String { nickname.isEmpty ? defaultName : nickname }
}

/// A set of apps, sites, or categories locked behind a physical NFC tag. Bricking is instant
/// from the app; unbricking needs the paired tag. This is the only unblock path in Furlough,
/// and it exists only here: rule-based targets never get one. While bricked, the list and the
/// tag cannot be changed.
struct BrickProfile: Codable, Equatable {
    var kinds: [TargetKind] = []
    var isBricked = false
    var brickedAt: Date?
    /// Hardware identifier of the paired tag, read over NFC.
    var tagID: Data?

    var isPaired: Bool { tagID != nil }
    var count: Int { kinds.count }
    /// Ready to brick: something to lock and a tag to unlock it with.
    var canBrick: Bool { !kinds.isEmpty && isPaired && !isBricked }
    func contains(_ kind: TargetKind) -> Bool { kinds.contains(kind) }
    /// True when `kind` is blocked by the brick right now.
    func blocks(_ kind: TargetKind) -> Bool { isBricked && contains(kind) }
}

struct Config: Codable, Equatable {
    var targets: [Target] = []
    var loosenDelayHours: Int = Furlough.defaultLoosenDelayHours
    var brick = BrickProfile()
    var schemaVersion = 1

    init() {}

    /// `brick` arrived after the first stored states, so its absence must decode cleanly.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decode([Target].self, forKey: .targets)
        loosenDelayHours = try container.decode(Int.self, forKey: .loosenDelayHours)
        brick = try container.decodeIfPresent(BrickProfile.self, forKey: .brick) ?? BrickProfile()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

    var loosenDelay: TimeInterval { TimeInterval(loosenDelayHours) * 3600 }

    /// Whether `target` is locked by the brick right now.
    func isBricked(_ target: Target) -> Bool { brick.blocks(target.kind) }

    func target(id: UUID) -> Target? { targets.first { $0.id == id } }
    func target(kind: TargetKind) -> Target? { targets.first { $0.kind == kind } }
}

enum PendingKind: Codable, Hashable {
    case setRule(targetID: UUID, rule: Rule)
    case removeTarget(targetID: UUID)
    case setDelay(hours: Int)
}

/// A loosening edit waiting out the delay.
struct PendingChange: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: PendingKind
    var createdAt = Date.now
    var effectiveAt: Date

    var targetID: UUID? {
        switch kind {
        case .setRule(let id, _), .removeTarget(let id): id
        case .setDelay: nil
        }
    }
}

/// Facts the monitor extension learns at runtime, keyed by target id and day.
struct RuntimeState: Codable, Equatable {
    var exhausted: [String: String] = [:]
    var warned: [String: String] = [:]
    var lastReconcile: Date?
    var lastRegistration: Date?
    var registrationError: String?

    func isExhausted(_ id: UUID, dayKey: String) -> Bool { exhausted[id.uuidString] == dayKey }
    func wasWarned(_ id: UUID, dayKey: String) -> Bool { warned[id.uuidString] == dayKey }
}

struct SharedState: Codable, Equatable {
    var config = Config()
    var pending: [PendingChange] = []
    var runtime = RuntimeState()
}
