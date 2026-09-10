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

// MARK: - The Mac

/// A Mac with nothing wrong with it, which each test then breaks in one place.
private func healthyMac(
    filter: Diagnostics.MacReading.Filter = .on,
    refusedBrowser: String? = nil,
    appGroup: Bool = true,
    notifications: Bool? = true
) -> Diagnostics.MacReading {
    Diagnostics.MacReading(
        filter: filter,
        refusedBrowser: refusedBrowser,
        appGroupAvailable: appGroup,
        notificationsAllowed: notifications
    )
}

@Test func macDiagnosticsSaysAllGoodWhenNothingIsWrong() {
    let summary = Diagnostics.macSummary(healthyMac())
    #expect(summary.line == "All good")
    #expect(summary.level == .well)
}

@Test func macDiagnosticsNamesEachFault() {
    #expect(Diagnostics.macSummary(healthyMac(filter: .broken)).line == "The web filter is switched off")
    #expect(Diagnostics.macSummary(healthyMac(refusedBrowser: "Safari")).line == "Furlough cannot read Safari")
    #expect(Diagnostics.macSummary(healthyMac(appGroup: false)).line == "The App Group is missing")
    #expect(Diagnostics.macSummary(healthyMac(filter: .waiting)).line == "The web filter is waiting on System Settings")
    #expect(Diagnostics.macSummary(healthyMac(notifications: false)).line == "Notifications are off")
    #expect(Diagnostics.macSummary(healthyMac(filter: .notInstalled)).line == "The web filter is not installed")
}

/// The three that leave something unenforced are grave; the two that only cost knowing, or that
/// were offered and declined, are not.
@Test func macDiagnosticsGradesTheFaultsApart() {
    #expect(Diagnostics.macSummary(healthyMac(filter: .broken)).level == .bad)
    #expect(Diagnostics.macSummary(healthyMac(refusedBrowser: "Chrome")).level == .bad)
    #expect(Diagnostics.macSummary(healthyMac(appGroup: false)).level == .bad)
    #expect(Diagnostics.macSummary(healthyMac(filter: .waiting)).level == .warn)
    #expect(Diagnostics.macSummary(healthyMac(notifications: false)).level == .warn)
    #expect(Diagnostics.macSummary(healthyMac(filter: .notInstalled)).level == .warn)
}

/// The line names the first thing wrong, not the last: a filter that was switched off is the
/// widest hole, and fixing the notifications under it would leave the row saying nothing new.
@Test func macDiagnosticsReportsTheCostliestFaultFirst() {
    let everything = healthyMac(filter: .broken, refusedBrowser: "Safari", appGroup: false, notifications: false)
    #expect(Diagnostics.macSummary(everything).line == "The web filter is switched off")

    let withFilter = healthyMac(refusedBrowser: "Safari", appGroup: false, notifications: false)
    #expect(Diagnostics.macSummary(withFilter).line == "Furlough cannot read Safari")

    let withBrowsers = healthyMac(appGroup: false, notifications: false)
    #expect(Diagnostics.macSummary(withBrowsers).line == "The App Group is missing")
}

/// Not installing it is a thing somebody was offered and declined, so it comes after the faults
/// and after the permission — a Mac with no filter and no notifications should say the one that
/// went wrong on its own.
@Test func macDiagnosticsPutsAnUninstalledFilterLast() {
    #expect(Diagnostics.macSummary(healthyMac(filter: .notInstalled, notifications: false)).line == "Notifications are off")
}

/// A Mac that has never been asked about notifications hears nothing either.
@Test func macDiagnosticsTreatsUnaskedNotificationsAsOff() {
    #expect(Diagnostics.macSummary(healthyMac(notifications: nil)).line == "Notifications are off")
}
