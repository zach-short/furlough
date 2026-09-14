import Foundation

/// One-time migration: the Mac used to write its looked-up name into `nickname` (Zach's own
/// field), so clearing a nickname fell back to the bundle ID instead of the real name. Moves
/// that value into `systemName` instead.
@MainActor
enum MacNames {
    /// Only moves a nickname that still matches the looked-up name — anything else is Zach's.
    /// Uninstalled apps are left alone. Idempotent once `systemName` is set.
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
                // A host's nickname repeating its own name says nothing; no lookup to do here.
                guard target.nickname == host else { continue }
                config.targets[index].nickname = ""
                moved = true
            }
        }
        return moved
    }
}
