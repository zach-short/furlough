import AppKit
import Foundation

struct BrowserAccess: Identifiable, Equatable {
    enum Status: Equatable { case allowed, denied, notAsked, notRunning }
    let bundleID: String
    let name: String
    let status: Status
    var id: String { bundleID }
}

/// Reads and rewrites the front tab's address in Safari and the Chromium family through
/// Apple Events. macOS asks once per browser whether Furlough may control it; refusing means
/// that browser is not enforced, which Settings shows.
@MainActor
final class Browsers {
    enum Kind { case safari, chromium }

    static let known: [String: Kind] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.canary": .chromium,
        "com.google.Chrome.beta": .chromium,
        "org.chromium.Chromium": .chromium,
        "com.brave.Browser": .chromium,
        "com.brave.Browser.beta": .chromium,
        "com.brave.Browser.nightly": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.microsoft.edgemac.Beta": .chromium,
        "company.thebrowser.Browser": .chromium,
        "company.thebrowser.dia": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "com.operasoftware.Opera": .chromium,
        "com.operasoftware.OperaGX": .chromium,
    ]

    private var readers: [String: NSAppleScript] = [:]
    /// Browsers that refused automation, and when, so the prompt is not repeated every second.
    private var refused: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 60

    func kind(of bundleID: String) -> Kind? { Self.known[bundleID] }

    /// The address of the front tab, or nil when there is none or Furlough may not look.
    func currentURL(of bundleID: String, kind: Kind) -> URL? {
        if let when = refused[bundleID], Date.now.timeIntervalSince(when) < Self.retryAfter { return nil }
        let script = readers[bundleID] ?? NSAppleScript(source: Self.readSource(bundleID: bundleID, kind: kind))
        guard let script else { return nil }
        readers[bundleID] = script
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            note(error, for: bundleID)
            return nil
        }
        guard let string = result.stringValue, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    /// Sends the front tab to `url`.
    func redirect(_ bundleID: String, kind: Kind, to url: URL) {
        guard let script = NSAppleScript(source: Self.writeSource(bundleID: bundleID, kind: kind, url: url)) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error { note(error, for: bundleID) }
    }

    /// Automation status for every known browser that is running.
    func access() -> [BrowserAccess] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, Self.known[bundleID] != nil else { return nil }
            let name = app.localizedName ?? bundleID
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let status: BrowserAccess.Status
            switch AEDeterminePermissionToAutomateTarget(target.aeDesc!, typeWildCard, typeWildCard, false) {
            case noErr: status = .allowed
            case OSStatus(errAEEventNotPermitted): status = .denied
            case OSStatus(procNotFound): status = .notRunning
            default: status = .notAsked
            }
            return BrowserAccess(bundleID: bundleID, name: name, status: status)
        }
        .sorted { $0.name < $1.name }
    }

    /// Asks macOS now, for every running browser, instead of the first time one is in front.
    func requestAccess() {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, Self.known[bundleID] != nil else { continue }
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            _ = AEDeterminePermissionToAutomateTarget(target.aeDesc!, typeWildCard, typeWildCard, true)
            refused[bundleID] = nil
        }
    }

    private func note(_ error: NSDictionary, for bundleID: String) {
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 {
            if refused[bundleID] == nil {
                SharedStore.log("\(AppInfo.name(for: bundleID) ?? bundleID) refused automation; not enforced until allowed in System Settings > Privacy & Security > Automation")
            }
            refused[bundleID] = .now
        } else if code != -1728 && code != -1719 { // no window / no such tab: nothing to read
            SharedStore.log("browser script failed (\(code)) for \(bundleID)")
        }
    }

    private static func readSource(bundleID: String, kind: Kind) -> String {
        let tab = kind == .safari ? "current tab" : "active tab"
        return """
        tell application id "\(bundleID)"
            if (count of windows) is 0 then return ""
            return URL of \(tab) of front window
        end tell
        """
    }

    private static func writeSource(bundleID: String, kind: Kind, url: URL) -> String {
        let tab = kind == .safari ? "current tab" : "active tab"
        let escaped = url.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "\(bundleID)"
            if (count of windows) is 0 then return
            set URL of \(tab) of front window to "\(escaped)"
        end tell
        """
    }
}
