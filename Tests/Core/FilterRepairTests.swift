import Foundation
import Testing

/// When a launch asks macOS for the web filter again. Written for HANDOFF 35: replacing
/// `/Applications/Furlough.app` leaves macOS holding the old bundle's extension, which used to
/// read as "nobody ever installed one". Every test is a state an install can actually leave a Mac in.
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

    @Test func aFilterNobodyAskedForIsNeverInstalled() {
        for presence in [FilterRepair.Presence.notInstalled, .unanswered, .refused, .declined, .running, .notFiltering] {
            #expect(decide(wanted: false, presence, activated: nil) == .leaveAlone)
        }
    }

    // MARK: The reinstall

    // macOS says it has nothing, but the app knows it accepted a different build's copy: a
    // replacement, not a first install — named as such in the log.
    @Test func aReplacedBundleIsInstalledAgainAndNamedAsAReplacement() {
        #expect(decide(.notInstalled, activated: lastBuild) == .activate(.replacedByThisBuild))
    }

    // Running is not necessarily *this* build's filter — an update can land while the old
    // extension keeps enforcing.
    @Test func anOldExtensionStillRunningIsReplaced() {
        #expect(decide(.running, activated: lastBuild) == .activate(.replacedByThisBuild))
        #expect(decide(.notFiltering, activated: lastBuild) == .activate(.replacedByThisBuild))
    }

    // A build with no recorded identity yet is itself a replacement — the app it runs in just changed.
    @Test func aBuildThatHasNeverRecordedAnIdentityAsksOnce() {
        #expect(decide(.running, activated: nil) == .activate(.replacedByThisBuild))
        #expect(decide(.running, activated: nil, attempted: thisBuild) == .leaveAlone)
    }

    // A request macOS completes without actually replacing anything must not repeat every launch.
    @Test func aReplacementIsAskedForOncePerBuild() {
        #expect(decide(.running, activated: lastBuild, attempted: thisBuild) == .leaveAlone)
    }

    @Test func aFilterThatIsThisBuildsIsLeftAlone() {
        #expect(decide(.running) == .leaveAlone)
        #expect(decide(.notFiltering) == .leaveAlone)
    }

    // An unreadable identity is never guessed at: running stays running rather than reinstalled on a hunch.
    @Test func anUnreadableBundleLeavesARunningFilterAlone() {
        #expect(decide(.running, bundled: nil, activated: lastBuild) == .leaveAlone)
        #expect(decide(.notFiltering, bundled: nil, activated: nil) == .leaveAlone)
    }

    // MARK: The plain case

    // Re-asked every launch, not once per build: this was actually requested, not inferred.
    @Test func aMissingFilterIsAskedForOnEveryLaunch() {
        #expect(decide(.notInstalled, activated: nil) == .activate(.neverInstalled))
        #expect(decide(.notInstalled, activated: nil, attempted: thisBuild) == .activate(.neverInstalled))
    }

    // MARK: The stuck service

    // No answer is not a refusal; a fresh request clears the stuck record itself, rather than
    // making the person do it.
    @Test func aStuckServiceIsAskedAgainOnce() {
        #expect(decide(.unanswered, activated: lastBuild) == .activate(.serviceStuck))
        #expect(decide(.unanswered, activated: lastBuild, attempted: thisBuild) == .leaveAlone)
    }

    // One retry per build, no more: if config or entitlement is the real problem, asking again
    // every launch just fails again.
    @Test func aRefusalIsRetriedOncePerBuild() {
        #expect(decide(.refused) == .activate(.attemptRefused))
        #expect(decide(.refused, attempted: thisBuild) == .leaveAlone)
    }

    // `refused` and `declined` look the same to macOS but are opposites to a person; the app knows which it got.
    @Test func somebodyWhoSaidNoIsNotAskedAgain() {
        #expect(decide(.declined) == .leaveAlone)
        #expect(decide(.declined, activated: lastBuild) == .leaveAlone)
    }

    // MARK: What is left alone

    // The one state where going without is deliberate.
    @Test func aFilterSwitchedOffInSystemSettingsIsNotReinstated() {
        #expect(decide(.disabledInSettings, activated: lastBuild) == .leaveAlone)
    }

    @Test func nothingIsAskedWhileAQuestionIsOutstanding() {
        #expect(decide(.awaitingApproval, activated: lastBuild) == .leaveAlone)
        #expect(decide(.installing, activated: lastBuild) == .leaveAlone)
        #expect(decide(.elsewhere, activated: lastBuild) == .leaveAlone)
    }
}
