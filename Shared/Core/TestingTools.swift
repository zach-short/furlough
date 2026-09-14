import Foundation

#if DEBUG || TESTING_TOOLS
/// The switch behind Settings > Testing — the buttons that forget the whole setup.
///
/// Two gates: the compiler excludes this whole file (and `resetEverything`) from a plain Release
/// build via `#if DEBUG || TESTING_TOOLS` — `scripts/archive.sh` verifies that against the
/// archived binary, and an opt-in Release build needs `TESTING_TOOLS=1`/the matching Xcode flag.
/// Even a build that carries the code keeps it hidden until five clicks on the Version row unlock
/// it, because TestFlight and the App Store ship the same binary, so nothing at compile time can
/// tell a tester's copy from a customer's. Debug builds start shown.
enum TestingTools {
    /// Outside the App Group state so `resetEverything` can't hide the button that triggered it.
    private static let key = "furlough.testing.shown"

    private static let clicksToShow = 5

    #if DEBUG
    private static let startsShown = true
    #else
    private static let startsShown = false
    #endif

    static var isShown: Bool {
        get { SharedStore.defaults.object(forKey: key) as? Bool ?? startsShown }
        set {
            SharedStore.defaults.set(newValue, forKey: key)
            SharedStore.log("testing buttons \(newValue ? "shown" : "hidden")")
        }
    }

    /// True only on the click that opens the section; the count does not persist across launches.
    @MainActor
    static func noteVersionClick() -> Bool {
        guard !isShown else { return false }
        clicks += 1
        guard clicks >= clicksToShow else { return false }
        clicks = 0
        isShown = true
        return true
    }

    @MainActor private static var clicks = 0
}
#endif
