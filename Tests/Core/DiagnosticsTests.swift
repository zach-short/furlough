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

// Off notifications are worth saying but not alarming; the other three mean something unenforced.
@Test func diagnosticsGradesNotificationsBelowTheRest() {
    #expect(Diagnostics.summary(healthy(notifications: false)).level == .warn)
    #expect(Diagnostics.summary(healthy(screenTime: false)).level == .bad)
    #expect(Diagnostics.summary(healthy(appGroup: false)).level == .bad)
    #expect(Diagnostics.summary(healthy(registrationError: "denied")).level == .bad)
}

// Unasked reads the same as refused.
@Test func diagnosticsTreatsUnaskedNotificationsAsOff() {
    #expect(Diagnostics.summary(healthy(notifications: nil)).line == "Notifications are off")
}

// Names the first thing wrong, not the last.
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

// The three that leave something unenforced are grave; the rest are not.
@Test func macDiagnosticsGradesTheFaultsApart() {
    #expect(Diagnostics.macSummary(healthyMac(filter: .broken)).level == .bad)
    #expect(Diagnostics.macSummary(healthyMac(refusedBrowser: "Chrome")).level == .bad)
    #expect(Diagnostics.macSummary(healthyMac(appGroup: false)).level == .bad)
    #expect(Diagnostics.macSummary(healthyMac(filter: .waiting)).level == .warn)
    #expect(Diagnostics.macSummary(healthyMac(notifications: false)).level == .warn)
    #expect(Diagnostics.macSummary(healthyMac(filter: .notInstalled)).level == .warn)
}

// Names the first thing wrong, not the last: the switched-off filter is the widest hole.
@Test func macDiagnosticsReportsTheCostliestFaultFirst() {
    let everything = healthyMac(filter: .broken, refusedBrowser: "Safari", appGroup: false, notifications: false)
    #expect(Diagnostics.macSummary(everything).line == "The web filter is switched off")

    let withFilter = healthyMac(refusedBrowser: "Safari", appGroup: false, notifications: false)
    #expect(Diagnostics.macSummary(withFilter).line == "Furlough cannot read Safari")

    let withBrowsers = healthyMac(appGroup: false, notifications: false)
    #expect(Diagnostics.macSummary(withBrowsers).line == "The App Group is missing")
}

// Declined is not a fault, so it ranks after faults and after the permission.
@Test func macDiagnosticsPutsAnUninstalledFilterLast() {
    #expect(Diagnostics.macSummary(healthyMac(filter: .notInstalled, notifications: false)).line == "Notifications are off")
}

@Test func macDiagnosticsTreatsUnaskedNotificationsAsOff() {
    #expect(Diagnostics.macSummary(healthyMac(notifications: nil)).line == "Notifications are off")
}
