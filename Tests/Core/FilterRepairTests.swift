import Foundation
import Testing

/// When a launch asks macOS for the web filter again.
///
/// The case this exists for is the one HANDOFF 35 wrote down and nothing caught: replacing
/// `/Applications/Furlough.app` leaves macOS holding the extension the old bundle staged, and
/// the app used to read that as "nobody ever installed one". Every test here is a state a Mac
/// can actually be left in by an install.
struct FilterRepairTests {
    private let thisBuild = "1+9f2c1a7b"
    private let lastBuild = "1+04d5e6f7"

    private func decide(
        wanted: Bool = true,
        _ presence: FilterRepair.Presence,
        bundled: String? = "1+9f2c1a7b",
        activated: String? = "1+9f2c1a7b",
        attempted: String? = nil
    ) -> FilterRepair.Action {
        FilterRepair.decide(
            wanted: wanted,
            presence: presence,
            bundled: bundled,
            activated: activated,
            attempted: attempted
        )
    }

    // MARK: Nothing was asked for

    /// Nothing installs a system extension somebody did not ask for, whatever state macOS is in.
    @Test func aFilterNobodyAskedForIsNeverInstalled() {
        for presence in [FilterRepair.Presence.notInstalled, .unanswered, .refused, .declined, .running, .notFiltering] {
            #expect(decide(wanted: false, presence, activated: nil) == .leaveAlone)
        }
    }

    // MARK: The reinstall

    /// The whole point. macOS says it has nothing, the app knows it accepted a different build's
    /// copy, so this is a replacement rather than a first install — and it says so in the log,
    /// where the difference is the only clue anyone gets.
    @Test func aReplacedBundleIsInstalledAgainAndNamedAsAReplacement() {
        #expect(decide(.notInstalled, activated: lastBuild) == .activate(.replacedByThisBuild))
    }

    /// A filter that is running is not necessarily *this* build's filter. An update that lands
    /// while the old extension keeps running is a Mac enforcing with the previous version's code.
    @Test func anOldExtensionStillRunningIsReplaced() {
        #expect(decide(.running, activated: lastBuild) == .activate(.replacedByThisBuild))
        #expect(decide(.notFiltering, activated: lastBuild) == .activate(.replacedByThisBuild))
    }

    /// The first launch of a build that has never recorded an identity — every Mac already
    /// running Furlough, the moment this lands — is a replacement too, because the app it is
    /// running in was itself just replaced.
    @Test func aBuildThatHasNeverRecordedAnIdentityAsksOnce() {
        #expect(decide(.running, activated: nil) == .activate(.replacedByThisBuild))
        #expect(decide(.running, activated: nil, attempted: thisBuild) == .leaveAlone)
    }

    /// And it asks once. A request that macOS completes without actually replacing anything must
    /// not turn every launch into another one.
    @Test func aReplacementIsAskedForOncePerBuild() {
        #expect(decide(.running, activated: lastBuild, attempted: thisBuild) == .leaveAlone)
    }

    @Test func aFilterThatIsThisBuildsIsLeftAlone() {
        #expect(decide(.running) == .leaveAlone)
        #expect(decide(.notFiltering) == .leaveAlone)
    }

    /// Nothing is guessed at from an extension whose identity cannot be read: a filter that is
    /// running stays running rather than being reinstalled on a hunch.
    @Test func anUnreadableBundleLeavesARunningFilterAlone() {
        #expect(decide(.running, bundled: nil, activated: lastBuild) == .leaveAlone)
        #expect(decide(.notFiltering, bundled: nil, activated: nil) == .leaveAlone)
    }

    // MARK: The plain case

    /// Asked for, and macOS has none: re-asked on every launch rather than once per build. This
    /// is what somebody asked for, and the request is what puts it back.
    @Test func aMissingFilterIsAskedForOnEveryLaunch() {
        #expect(decide(.notInstalled, activated: nil) == .activate(.neverInstalled))
        #expect(decide(.notInstalled, activated: nil, attempted: thisBuild) == .activate(.neverInstalled))
    }

    // MARK: The stuck service

    /// No answer is not a refusal. A fresh activation request is what clears the record a bundle
    /// replacement leaves stuck, so the app now does by itself what its own directions told the
    /// person to do.
    @Test func aStuckServiceIsAskedAgainOnce() {
        #expect(decide(.unanswered, activated: lastBuild) == .activate(.serviceStuck))
        #expect(decide(.unanswered, activated: lastBuild, attempted: thisBuild) == .leaveAlone)
    }

    /// A refusal macOS made on its own gets the same one attempt per build and no more: if a
    /// leftover configuration or the entitlement is the problem, asking again on every launch
    /// only buys another failure.
    @Test func aRefusalIsRetriedOncePerBuild() {
        #expect(decide(.refused) == .activate(.attemptRefused))
        #expect(decide(.refused, attempted: thisBuild) == .leaveAlone)
    }

    /// The one thing a repair must never do. `refused` and `declined` are the same failure to
    /// macOS and opposite failures to a person, and the app already knows which it got.
    @Test func somebodyWhoSaidNoIsNotAskedAgain() {
        #expect(decide(.declined) == .leaveAlone)
        #expect(decide(.declined, activated: lastBuild) == .leaveAlone)
    }

    // MARK: What is left alone

    /// Switched off by hand is the one state where going without is deliberate.
    @Test func aFilterSwitchedOffInSystemSettingsIsNotReinstated() {
        #expect(decide(.disabledInSettings, activated: lastBuild) == .leaveAlone)
    }

    /// Somebody is already being asked something, or the app is somewhere macOS will not load an
    /// extension from at all.
    @Test func nothingIsAskedWhileAQuestionIsOutstanding() {
        #expect(decide(.awaitingApproval, activated: lastBuild) == .leaveAlone)
        #expect(decide(.installing, activated: lastBuild) == .leaveAlone)
        #expect(decide(.elsewhere, activated: lastBuild) == .leaveAlone)
    }
}
