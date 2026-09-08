import Foundation

/// The website an app is also at, and the app a website is also in. Blocking the YouTube app
/// and leaving youtube.com open is the gap most people find a week later, from a browser tab,
/// so adding either side offers the other while it is still in hand.
///
/// A table, like `AppUtility`, and for the same reason: on the Mac a target already *is* a
/// bundle identifier or a host, so a lookup is exact, offline and testable. This is the half
/// that needs no Mac; `AppCatalog` adds the half that does, reading where a browser's
/// "install as app" wrapper opens straight out of its bundle.
///
/// Nothing here runs on the phone yet. A Screen Time token says nothing about which app it is
/// until the shield learns a name, and a website can only be minted inside Apple's picker, so
/// there is no side to offer and no way to add it: see `AddWebsiteGuideView`.
enum Companions {
    /// One thing, however many names, identifiers and hosts it goes by.
    struct Pair: Hashable, Sendable {
        /// Lowercased: as Finder shows an app on the Mac and as the shield reports it on iOS.
        let names: [String]
        /// Lowercased Mac and iOS identifiers. The iOS ones matter on the Mac too: an Apple
        /// silicon Mac runs iPhone apps under their own identifier.
        let bundleIDs: [String]
        /// Where the same thing lives on the web. Subdomains match, so youtube.com covers
        /// m.youtube.com, and the order is the order they are offered in.
        let hosts: [String]

        init(_ names: [String], _ bundleIDs: [String] = [], hosts: [String]) {
            self.names = names
            self.bundleIDs = bundleIDs
            self.hosts = hosts
        }

        /// True when this is the app: by identifier first, then by the name on its bundle.
        func matches(bundleID: String, name: String) -> Bool {
            bundleIDs.contains(Companions.normalize(bundleID: bundleID))
                || names.contains(Companions.normalize(name: name))
        }
    }

    // MARK: Lookups

    /// What `bundleID` (or, failing that, `name`) is one half of, or nil when it has no website
    /// worth offering. Nil is the common answer: most apps are not also a site.
    static func pair(forBundleID bundleID: String, name: String) -> Pair? {
        pairs.first { $0.matches(bundleID: bundleID, name: name) }
    }

    /// The hosts to offer beside an app, in table order. Empty when there are none.
    static func hosts(forBundleID bundleID: String, name: String) -> [String] {
        pair(forBundleID: bundleID, name: name)?.hosts ?? []
    }

    /// What a website is one half of; "m.youtube.com" is YouTube. The longest host that fits
    /// wins, so a pair that claims a subdomain beats one that claims the whole domain.
    static func pair(forHost raw: String) -> Pair? {
        guard let host = Hosts.normalize(raw) else { return nil }
        var best: (pair: Pair, length: Int)?
        for pair in pairs {
            for rule in pair.hosts where Hosts.matches(host, rule: rule) && rule.count > (best?.length ?? -1) {
                best = (pair, rule.count)
            }
        }
        return best?.pair
    }

    /// Identifiers lowercased, with a Catalyst app's "maccatalyst." shed so the X app on a Mac
    /// matches the X app on a phone.
    static func normalize(bundleID: String) -> String {
        let key = bundleID.lowercased()
        let catalyst = "maccatalyst."
        return key.hasPrefix(catalyst) ? String(key.dropFirst(catalyst.count)) : key
    }

    static func normalize(name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: The table

    /// Things that are both an app and a site. Only what is worth blocking: Mail is also at
    /// gmail.com, but nobody adds Mail to keep themselves off it.
    static let pairs: [Pair] = [
        Pair(["youtube"], ["com.google.ios.youtube"], hosts: ["youtube.com"]),
        Pair(["youtube music"], ["com.google.ios.youtubemusic"], hosts: ["music.youtube.com"]),
        Pair(["netflix"], ["com.netflix.netflix"], hosts: ["netflix.com"]),
        Pair(["twitch"], ["tv.twitch"], hosts: ["twitch.tv"]),
        Pair(["prime video", "amazon prime video"], ["com.amazon.aiv.aivapp"], hosts: ["primevideo.com"]),
        Pair(["hulu"], ["com.hulu.plus"], hosts: ["hulu.com"]),
        Pair(["disney+", "disney plus"], ["com.disney.disneyplus"], hosts: ["disneyplus.com"]),
        Pair(["max", "hbo max"], ["com.wbd.stream", "com.hbo.hbonow"], hosts: ["max.com"]),

        Pair(["tiktok"], ["com.zhiliaoapp.musically", "com.ss.iphone.ugc.ame"], hosts: ["tiktok.com"]),
        Pair(["instagram"], ["com.burbn.instagram"], hosts: ["instagram.com"]),
        Pair(["reddit"], ["com.reddit.reddit"], hosts: ["reddit.com"]),
        Pair(["x", "twitter"], ["com.atebits.tweetie2"], hosts: ["x.com", "twitter.com"]),
        Pair(["threads"], ["com.burbn.barcelona"], hosts: ["threads.com", "threads.net"]),
        Pair(["bluesky"], ["xyz.blueskyweb.app"], hosts: ["bsky.app"]),
        Pair(["snapchat"], ["com.toyopagroup.picaboo"], hosts: ["snapchat.com"]),
        Pair(["facebook"], ["com.facebook.facebook"], hosts: ["facebook.com"]),
        Pair(["messenger"], ["com.facebook.messenger"], hosts: ["messenger.com"]),
        Pair(["pinterest"], ["pinterest", "com.pinterest"], hosts: ["pinterest.com"]),
        Pair(["linkedin"], ["com.linkedin.linkedin"], hosts: ["linkedin.com"]),
        Pair(["tumblr"], ["com.tumblr.tumblr"], hosts: ["tumblr.com"]),

        Pair(["discord"], ["com.hnc.discord", "com.hammerandchisel.discord"], hosts: ["discord.com"]),
        Pair(["slack"], ["com.tinyspeck.slackmacgap", "com.tinyspeck.chatlyio"], hosts: ["slack.com"]),
        Pair(["whatsapp"], ["net.whatsapp.whatsapp"], hosts: ["web.whatsapp.com"]),
        Pair(["telegram"], ["ru.keepcoder.telegram", "ph.telegra.telegraph"], hosts: ["web.telegram.org"]),
        Pair(["zoom", "zoom.us"], ["us.zoom.xos", "us.zoom.videomeetings"], hosts: ["zoom.us"]),
        Pair(["spotify"], ["com.spotify.client"], hosts: ["open.spotify.com"]),
        Pair(["notion"], ["notion.id"], hosts: ["notion.so"]),
        Pair(["figma"], ["com.figma.desktop"], hosts: ["figma.com"]),
        Pair(["chatgpt"], ["com.openai.chat"], hosts: ["chatgpt.com", "chat.openai.com"]),

        Pair(["steam"], ["com.valvesoftware.steam"], hosts: ["store.steampowered.com", "steamcommunity.com"]),
        Pair(["amazon"], ["com.amazon.amazon"], hosts: ["amazon.com"]),
        Pair(["draftkings", "draftkings sportsbook"], hosts: ["draftkings.com"]),
        Pair(["fanduel", "fanduel sportsbook"], hosts: ["fanduel.com"]),
    ]
}
