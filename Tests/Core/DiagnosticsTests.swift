import Foundation
import Testing

/// A phone with nothing wrong with it, which each test then breaks in one place.
private func healthy(
    screenTime: Bool = true,
    appGroup: Bool = true,
    notifications: Bool? = true,
    registrationError: String? = nil
) -> Diagnostics.Reading {
    Diagnostics.Reading(
        screenTimeAllowed: screenTime,
        appGroupAvailable: appGroup,
        notificationsAllowed: notifications,
        registrationError: registrationError
    )
}

@Test func diagnosticsSaysAllGoodWhenNothingIsWrong() {
    let summary = Diagnostics.summary(healthy())
    #expect(summary.line == "All good")
    #expect(summary.level == .well)
    #expect(summary.isWell)
}

@Test func diagnosticsNamesEachFault() {
    #expect(Diagnostics.summary(healthy(screenTime: false)).line == "Screen Time access is off")
    #expect(Diagnostics.summary(healthy(appGroup: false)).line == "The App Group is missing")
    #expect(Diagnostics.summary(healthy(registrationError: "denied")).line == "A schedule did not register")
    #expect(Diagnostics.summary(healthy(notifications: false)).line == "Notifications are off")
}

/// Off notifications are worth saying and not worth alarming about; the other three mean
/// something is not being enforced.
@Test func diagnosticsGradesNotificationsBelowTheRest() {
    #expect(Diagnostics.summary(healthy(notifications: false)).level == .warn)
    #expect(Diagnostics.summary(healthy(screenTime: false)).level == .bad)
    #expect(Diagnostics.summary(healthy(appGroup: false)).level == .bad)
    #expect(Diagnostics.summary(healthy(registrationError: "denied")).level == .bad)
}

/// A phone that has never been asked about notifications hears nothing either, so the row says
/// the same thing it says for a refusal.
@Test func diagnosticsTreatsUnaskedNotificationsAsOff() {
    #expect(Diagnostics.summary(healthy(notifications: nil)).line == "Notifications are off")
}

/// The line names the first thing wrong, not the last: fixing notifications on a phone with no
/// Screen Time access would leave the row saying nothing new.
@Test func diagnosticsReportsTheCostliestFaultFirst() {
    let everything = healthy(
        screenTime: false,
        appGroup: false,
        notifications: false,
        registrationError: "denied"
    )
    #expect(Diagnostics.summary(everything).line == "Screen Time access is off")

    let withAccess = healthy(appGroup: false, notifications: false, registrationError: "denied")
    #expect(Diagnostics.summary(withAccess).line == "The App Group is missing")

    let withGroup = healthy(notifications: false, registrationError: "denied")
    #expect(Diagnostics.summary(withGroup).line == "A schedule did not register")
}
