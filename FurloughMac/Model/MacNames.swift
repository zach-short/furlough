import Foundation

/// What a Mac target is called, and the one-time move that separated the two answers.
///
/// The phone has Screen Time to ask what an app is called, so `nickname` there has only ever
/// been Zach's own word for it. The Mac has to look the name up itself, and for a while it
/// wrote the answer into `nickname` — the same field he types into. That made a nickname
/// impossible to take off again: clearing it fell back to `defaultName`, which for a Mac app
/// is its bundle identifier, so removing "Safari" left "com.apple.Safari". `systemName` is the
/// field that means "the name it came with", and that is where the lookup belongs.
///
/// Pure, with the lookup passed in, so the migration is tested rather than trusted: it edits
/// state Zach already has.
@MainActor
enum MacNames {
    /// Moves each target's own name out of `nickname` and into `systemName`, and returns
    /// whether anything changed.
    ///
    /// Only a nickname that is still the name the target was added under is moved: anything
    /// else is Zach's and stays where it is. An app that is no longer installed cannot be
    /// checked, so it is left exactly as it is rather than guessed at — its nickname goes on
    /// showing, which is what it did before. Idempotent: a target that has been through this
    /// has a `systemName` and is skipped.
    @discardableResult
    static func adopt(_ config: inout Config, name: (String) -> String?) -> Bool {
        var moved = false
        for index in config.targets.indices {
            let target = config.targets[index]
            guard target.systemName?.isEmpty ?? true else { continue }
            switch target.kind {
            case .macApp(let bundleID):
                guard let real = name(bundleID) else { continue }
                config.targets[index].systemName = real
                if target.nickname == real { config.targets[index].nickname = "" }
                moved = true
            case .host(let host):
                // A host is already its own default name, so a nickname that repeats it says
                // nothing; there is no lookup to do and nothing to put in `systemName`.
                guard target.nickname == host else { continue }
                config.targets[index].nickname = ""
                moved = true
            }
        }
        return moved
    }
}
