import Foundation

#if DEBUG || TESTING_TOOLS
/// The switch behind Settings > Testing — the buttons that forget the whole setup.
///
/// There are two locks on those buttons and both have to be open.
///
/// The compiler is the first. This file, `resetEverything` on both models, and the sections that
/// call it are all inside `#if DEBUG || TESTING_TOOLS`, so a plain Release build does not carry
/// any of it: that is what `scripts/archive.sh` proves against the archived binary before it will
/// ship, and it is the promise the app makes in onboarding and in Settings. A Release build that
/// does carry them has to be asked for, by name:
///
///     TESTING_TOOLS=1 scripts/archive.sh                                    the phone
///     xcodebuild -project Furlough.xcodeproj -scheme FurloughMac \
///       -configuration Release -derivedDataPath build/mac \
///       SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TESTING_TOOLS'    the Mac
///
/// This switch is the second, and it is the one that matters once a build is out. TestFlight and
/// the App Store are the same binary — a build is promoted, not rebuilt — so nothing decided at
/// compile time can tell a tester's copy from a customer's. So a build that carries the buttons
/// still keeps them put away: the Testing section shows only once it has been asked for, by
/// clicking the Version row in About five times, and "Hide these buttons" puts it back. A Debug
/// build starts shown, because that is where the reset button is used every day.
enum TestingTools {
    /// Beside the state in the App Group rather than in it, so `resetEverything` cannot switch
    /// off the section the button that was just pressed lives in.
    private static let key = "furlough.testing.shown"

    /// Clicks on the Version row that ask for the section. Enough that nobody arrives by accident.
    private static let clicksToShow = 5

    #if DEBUG
    private static let startsShown = true
    #else
    private static let startsShown = false
    #endif

    /// Whether the Testing section is showing.
    static var isShown: Bool {
        get { SharedStore.defaults.object(forKey: key) as? Bool ?? startsShown }
        set {
            SharedStore.defaults.set(newValue, forKey: key)
            SharedStore.log("testing buttons \(newValue ? "shown" : "hidden")")
        }
    }

    /// Counts a click on the Version row. Returns true on the click that opens the section, so
    /// the screen that took the click can say something; the count is not kept across launches.
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
