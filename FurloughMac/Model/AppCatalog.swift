import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL
    /// A browser wrapper's start URL, e.g. Chrome's "YouTube Music" -> music.youtube.com. Empty for a real app.
    var webHosts: [String] = []
    var isRunning = false
    var id: String { bundleID }

    @MainActor var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    var companionHosts: [String] {
        var seen = Set<String>()
        return (webHosts + Companions.hosts(forBundleID: bundleID, name: name)).filter { seen.insert($0).inserted }
    }
}

enum AppCatalog {
    /// Apps that must never be blocked, or the Mac becomes unusable.
    static let excluded: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systempreferences", "com.apple.loginwindow",
        "com.apple.SystemSettings", "com.apple.ActivityMonitor", "com.zachshort.furlough.mac",
    ]

    private static let folders = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    @MainActor
    static func installed() -> [InstalledApp] {
        var found: [String: InstalledApp] = [:]
        let manager = FileManager.default
        for folder in folders {
            guard let items = try? manager.contentsOfDirectory(atPath: folder) else { continue }
            for item in items {
                let path = folder + "/" + item
                if item.hasSuffix(".app") {
                    add(URL(fileURLWithPath: path), to: &found)
                } else if let nested = try? manager.contentsOfDirectory(atPath: path) {
                    for inner in nested where inner.hasSuffix(".app") {
                        add(URL(fileURLWithPath: path + "/" + inner), to: &found)
                    }
                }
            }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, let url = app.bundleURL else { continue }
            if found[bundleID] == nil { add(url, to: &found) }
            found[bundleID]?.isRunning = true
        }
        return found.values
            .filter { !excluded.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func apps(for host: String) -> [InstalledApp] {
        let pair = Companions.pair(forHost: host)
        return installed().filter { app in
            app.webHosts.contains { Hosts.matches($0, rule: host) }
                || pair?.matches(bundleID: app.bundleID, name: app.name) == true
        }
    }

    @MainActor
    private static func add(_ url: URL, to found: inout [String: InstalledApp]) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, found[bundleID] == nil else { return }
        found[bundleID] = InstalledApp(bundleID: bundleID, name: AppInfo.name(at: url), url: url, webHosts: webHosts(of: bundle))
    }

    /// Chromium wrappers store the start URL in the bundle's Info.plist; Safari keeps a copy of the site's manifest instead.
    private static func webHosts(of bundle: Bundle) -> [String] {
        var addresses: [String] = []
        if let address = bundle.infoDictionary?["CrAppModeShortcutURL"] as? String { addresses.append(address) }
        if let manifest = bundle.url(forResource: "Manifest", withExtension: "plist"),
           let dictionary = NSDictionary(contentsOf: manifest) as? [String: Any] {
            for key in ["start_url", "scope"] {
                if let address = dictionary[key] as? String { addresses.append(address) }
            }
        }
        var seen = Set<String>()
        return addresses.compactMap(Hosts.normalize).filter { seen.insert($0).inserted }
    }
}
