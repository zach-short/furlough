import AppKit
import Foundation

struct BrowserAccess: Identifiable, Equatable {
    enum Status: Equatable { case allowed, denied, notAsked, notRunning }
    let bundleID: String
    let name: String
    let status: Status
    var id: String { bundleID }
}

/// Reads/rewrites tab addresses via Apple Events; each browser must grant automation permission separately.
/// Reads every window of every running browser, not just the front one, to catch tabs open in the background.
@MainActor
final class Browsers {
    enum Kind { case safari, chromium }

    struct Tab: Equatable {
        /// AppleScript's 1-based window index.
        let window: Int
        let url: URL
    }

    struct Snapshot {
        let bundleID: String
        let kind: Kind
        let tabs: [Tab]
    }

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
    /// Throttles re-reading a browser that has already refused automation.
    private var refused: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 60
    /// Keyed to uptime, not wall clock, so a clock change can't skew the cache.
    private var cache: [String: (at: TimeInterval, tabs: [Tab])] = [:]
    static let pollInterval: TimeInterval = 2

    func kind(of bundleID: String) -> Kind? { Self.known[bundleID] }

    func snapshots() -> [Snapshot] {
        var seen: Set<String> = []
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, let kind = Self.known[bundleID],
                  seen.insert(bundleID).inserted else { return nil }
            return Snapshot(bundleID: bundleID, kind: kind, tabs: tabs(of: bundleID, kind: kind))
        }
    }

    /// Empty when the browser has no windows or Furlough isn't permitted to look.
    func tabs(of bundleID: String, kind: Kind) -> [Tab] {
        let uptime = Clock.uptime
        if let cached = cache[bundleID], uptime - cached.at < Self.pollInterval { return cached.tabs }
        if let when = refused[bundleID], Date.now.timeIntervalSince(when) < Self.retryAfter { return [] }
        let script = readers[bundleID] ?? NSAppleScript(source: Self.readSource(bundleID: bundleID, kind: kind))
        guard let script else { return [] }
        readers[bundleID] = script
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            note(error, for: bundleID)
            return []
        }
        let tabs = Self.parse(result.stringValue ?? "")
        cache[bundleID] = (uptime, tabs)
        return tabs
    }

    func currentURL(of bundleID: String, kind: Kind) -> URL? {
        tabs(of: bundleID, kind: kind).first?.url
    }

    func redirect(_ bundleID: String, kind: Kind, window: Int = 1, to url: URL) {
        guard let script = NSAppleScript(source: Self.writeSource(bundleID: bundleID, kind: kind, window: window, url: url)) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error { note(error, for: bundleID) }
        // The tab has moved, so what was read a moment ago is stale.
        cache[bundleID] = nil
    }

    /// Format: "1\thttps://…\n2\thttps://…"; an unparsable line is skipped.
    private static func parse(_ output: String) -> [Tab] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let window = Int(parts[0]), let url = URL(string: String(parts[1])) else { return nil }
            return Tab(window: window, url: url)
        }
    }

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

    /// Each window read inside `try`: some windows (Safari's settings, a downloads window) have no tab and would abort the loop.
    private static func readSource(bundleID: String, kind: Kind) -> String {
        let tabRef = kind == .safari ? "current tab" : "active tab"
        // `character id 9`, not `tab` — inside a browser's `tell` block, `tab` is its tab class.
        return """
        set sep to character id 9
        tell application id "\(bundleID)"
            set out to ""
            repeat with i from 1 to (count of windows)
                try
                    set u to URL of \(tabRef) of window i
                    if u is not missing value then set out to out & i & sep & u & linefeed
                end try
            end repeat
            return out
        end tell
        """
    }

    private static func writeSource(bundleID: String, kind: Kind, window: Int, url: URL) -> String {
        let tabRef = kind == .safari ? "current tab" : "active tab"
        let escaped = url.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "\(bundleID)"
            if (count of windows) < \(window) then return
            set URL of \(tabRef) of window \(window) to "\(escaped)"
        end tell
        """
    }
}
