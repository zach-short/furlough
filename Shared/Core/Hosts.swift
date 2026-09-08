import Foundation

/// Websites as plain hosts. The Mac has no Screen Time tokens, so a site is the host it lives
/// on and every subdomain of it.
enum Hosts {
    /// "https://www.YouTube.com/watch?v=1" becomes "youtube.com"; nil when there is no host in it.
    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), var host = url.host(), host.contains(".") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }

    static func matches(_ host: String, rule: String) -> Bool {
        let host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return host == rule || host.hasSuffix("." + rule)
    }
}
