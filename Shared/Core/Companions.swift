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
/// The phone comes at it a step later. A Screen Time token says nothing about which app it is,
/// so nothing can be offered as it is added; but the shield learns the name the first time it
/// covers something, and `missingHosts`/`missingApp` answer from a name alone. Adding the other
/// half there is still Apple's picker's job — see `AddWebsiteGuideView` — so all the phone
/// offers is a nudge towards it.
enum Companions {
    /// One thing, however many names, identifiers and hosts it goes by.
    struct Pair: Hashable, Sendable {
        /// As the thing is written, first the name to show. Matching ignores case and spacing,
        /// so the table can carry "YouTube Music" and still recognise what Finder shows on the
        /// Mac and what the shield reports on iOS.
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

        /// What to call it: the first name in the table.
        var title: String { names[0] }

        /// True when this is the app: by identifier first, then by the name on its bundle.
        func matches(bundleID: String, name: String) -> Bool {
            let key = Companions.normalize(name: name)
            return bundleIDs.contains(Companions.normalize(bundleID: bundleID))
                || (!key.isEmpty && names.contains { Companions.normalize(name: $0) == key })
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

    // MARK: The phone's half

    /// The half of a thing that Furlough does not have yet.
    enum Half: Equatable, Sendable {
        /// Websites the app is also at, in table order.
        case sites([String])
        /// The app the website is also in, by name.
        case app(String)
    }

    /// The websites an app is also at that Furlough does not have, in table order.
    ///
    /// This is the lookup the phone can use. A Screen Time token says nothing about what it
    /// is, so nothing can be offered when a target is added; but the shield learns the name
    /// the first time it covers something (`SharedStore.learnName`), and from a name alone
    /// the table still answers. `knownHosts` is what Furlough already blocks — the domains
    /// its website targets have been learned as — so a site that is in is never offered.
    static func missingHosts(forAppNamed name: String, knownHosts: [String]) -> [String] {
        let hosts = hosts(forBundleID: "", name: name)
        guard !hosts.isEmpty else { return [] }
        let known = knownHosts.compactMap(Hosts.normalize)
        return hosts.filter { host in !known.contains { Hosts.matches($0, rule: host) } }
    }

    /// What to call the app a website is also in, when Furlough does not have it already.
    ///
    /// A name, not something to add: on the phone only Apple's picker can mint an app token,
    /// so the most anything can do is say which app to look for and open the picker.
    static func missingApp(forHost host: String, knownAppNames: [String]) -> String? {
        guard let pair = pair(forHost: host) else { return nil }
        guard !knownAppNames.contains(where: { pair.matches(bundleID: "", name: $0) }) else { return nil }
        return pair.title
    }

    // MARK: Normalizing

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
        Pair(["YouTube"], ["com.google.ios.youtube"], hosts: ["youtube.com"]),
        Pair(["YouTube Music"], ["com.google.ios.youtubemusic"], hosts: ["music.youtube.com"]),
        Pair(["Netflix"], ["com.netflix.netflix"], hosts: ["netflix.com"]),
        Pair(["Twitch"], ["tv.twitch"], hosts: ["twitch.tv"]),
        Pair(["Prime Video", "Amazon Prime Video"], ["com.amazon.aiv.aivapp"], hosts: ["primevideo.com"]),
        Pair(["Hulu"], ["com.hulu.plus"], hosts: ["hulu.com"]),
        Pair(["Disney+", "Disney Plus"], ["com.disney.disneyplus"], hosts: ["disneyplus.com"]),
        Pair(["Max", "HBO Max"], ["com.wbd.stream", "com.hbo.hbonow"], hosts: ["max.com"]),
        Pair(["Peacock TV", "Peacock"], ["com.peacocktv.peacock"], hosts: ["peacocktv.com"]),
        Pair(["Paramount+", "Paramount Plus"], ["com.cbsvideo.app"], hosts: ["paramountplus.com"]),
        Pair(["Crunchyroll"], ["com.crunchyroll.iphone"], hosts: ["crunchyroll.com"]),
        Pair(["Rumble"], ["com.rumble.battles"], hosts: ["rumble.com"]),
        Pair(["Kick"], ["com.kick.mobile"], hosts: ["kick.com"]),

        Pair(["TikTok"], ["com.zhiliaoapp.musically", "com.ss.iphone.ugc.ame"], hosts: ["tiktok.com"]),
        Pair(["Instagram"], ["com.burbn.instagram"], hosts: ["instagram.com"]),
        Pair(["Reddit"], ["com.reddit.reddit"], hosts: ["reddit.com"]),
        Pair(["X", "Twitter"], ["com.atebits.tweetie2"], hosts: ["x.com", "twitter.com"]),
        Pair(["Threads"], ["com.burbn.barcelona"], hosts: ["threads.com", "threads.net"]),
        Pair(["Bluesky"], ["xyz.blueskyweb.app"], hosts: ["bsky.app"]),
        Pair(["Snapchat"], ["com.toyopagroup.picaboo"], hosts: ["snapchat.com"]),
        Pair(["Facebook"], ["com.facebook.facebook"], hosts: ["facebook.com"]),
        Pair(["Messenger"], ["com.facebook.messenger"], hosts: ["messenger.com"]),
        Pair(["Pinterest"], ["pinterest", "com.pinterest"], hosts: ["pinterest.com"]),
        Pair(["LinkedIn"], ["com.linkedin.linkedin"], hosts: ["linkedin.com"]),
        Pair(["Tumblr"], ["com.tumblr.tumblr"], hosts: ["tumblr.com"]),
        Pair(["Quora"], ["com.quora.app.mobile"], hosts: ["quora.com"]),
        Pair(["Nextdoor"], ["com.nextdoor.nextdoor"], hosts: ["nextdoor.com"]),
        Pair(["BeReal"], ["alexisbarreyat.bereal"], hosts: ["bereal.com"]),

        Pair(["Discord"], ["com.hnc.discord", "com.hammerandchisel.discord"], hosts: ["discord.com"]),
        Pair(["Slack"], ["com.tinyspeck.slackmacgap", "com.tinyspeck.chatlyio"], hosts: ["slack.com"]),
        Pair(["WhatsApp"], ["net.whatsapp.whatsapp"], hosts: ["web.whatsapp.com"]),
        Pair(["Telegram"], ["ru.keepcoder.telegram", "ph.telegra.telegraph"], hosts: ["web.telegram.org"]),
        Pair(["Zoom", "zoom.us"], ["us.zoom.xos", "us.zoom.videomeetings"], hosts: ["zoom.us"]),
        Pair(["Notion"], ["notion.id"], hosts: ["notion.so"]),
        Pair(["Figma"], ["com.figma.desktop"], hosts: ["figma.com"]),
        Pair(["Canva"], ["com.canva.canvaeditor"], hosts: ["canva.com"]),
        Pair(["Trello"], ["com.fogcreek.trello", "com.atlassian.trello"], hosts: ["trello.com"]),
        Pair(["Substack"], ["com.substack.substack"], hosts: ["substack.com"]),
        Pair(["Medium"], ["com.medium.reader"], hosts: ["medium.com"]),
        Pair(["Duolingo"], ["com.duolingo.duolingomobile"], hosts: ["duolingo.com"]),

        Pair(["ChatGPT"], ["com.openai.chat"], hosts: ["chatgpt.com", "chat.openai.com"]),
        Pair(["Claude"], ["com.anthropic.claude"], hosts: ["claude.ai"]),
        Pair(["Gemini", "Google Gemini"], ["com.google.gemini"], hosts: ["gemini.google.com"]),
        Pair(["Perplexity"], ["ai.perplexity.app"], hosts: ["perplexity.ai"]),
        Pair(["Character.AI", "Character AI"], ["ai.character.app"], hosts: ["character.ai"]),
        Pair(["Grok"], ["ai.x.grokapp"], hosts: ["grok.com"]),

        Pair(["Spotify"], ["com.spotify.client"], hosts: ["open.spotify.com"]),
        Pair(["SoundCloud"], ["com.soundcloud.touchapp"], hosts: ["soundcloud.com"]),
        Pair(["Pandora"], ["com.pandora"], hosts: ["pandora.com"]),
        Pair(["TIDAL"], ["com.aspiro.tidal"], hosts: ["tidal.com"]),

        Pair(["ESPN"], ["com.espn.scorecenter"], hosts: ["espn.com"]),
        Pair(["NFL"], ["com.nfl.gamecenter"], hosts: ["nfl.com"]),
        Pair(["Bleacher Report"], ["com.bleacherreport.teamstream"], hosts: ["bleacherreport.com"]),
        Pair(["CNN"], ["com.cnn.iphone"], hosts: ["cnn.com"]),
        Pair(["FOX News"], ["com.foxnews.foxnews"], hosts: ["foxnews.com"]),
        Pair(["NYTimes", "The New York Times"], ["com.nytimes.nytimes"], hosts: ["nytimes.com"]),

        Pair(["Tinder"], ["com.cardify.tinder"], hosts: ["tinder.com"]),
        Pair(["Bumble"], ["com.moxco.bumble"], hosts: ["bumble.com"]),
        Pair(["Hinge"], ["co.hinge.mobile.ios"], hosts: ["hinge.co"]),
        Pair(["Grindr"], ["com.grindrguy.grindrx"], hosts: ["grindr.com"]),
        Pair(["OkCupid"], ["com.okcupid.app"], hosts: ["okcupid.com"]),

        Pair(["DraftKings", "DraftKings Sportsbook"], hosts: ["draftkings.com"]),
        Pair(["FanDuel", "FanDuel Sportsbook"], hosts: ["fanduel.com"]),
        Pair(["BetMGM"], ["com.playmgm.nj.sports2"], hosts: ["betmgm.com"]),
        Pair(["PrizePicks"], ["com.myprizepicks.prizepicks"], hosts: ["prizepicks.com"]),
        Pair(["Underdog", "Underdog Sports", "Underdog Fantasy"], ["com.underdogsports.fantasy"], hosts: ["underdogfantasy.com"]),
        Pair(["theScore Bet"], ["com.espn.bet"], hosts: ["thescore.bet"]),

        Pair(["Steam"], ["com.valvesoftware.steam"], hosts: ["store.steampowered.com", "steamcommunity.com"]),
        Pair(["Roblox"], ["com.roblox.robloxmobile"], hosts: ["roblox.com"]),
        Pair(["Chess.com"], ["com.chess.iphone"], hosts: ["chess.com"]),
        Pair(["Lichess"], ["org.lichess.mobilev2"], hosts: ["lichess.org"]),

        Pair(["Amazon"], ["com.amazon.amazon"], hosts: ["amazon.com"]),
        Pair(["eBay"], ["com.ebay.iphone"], hosts: ["ebay.com"]),
        Pair(["Etsy"], ["com.etsy.etsyforios"], hosts: ["etsy.com"]),
        Pair(["Temu"], ["com.einnovation.temu"], hosts: ["temu.com"]),
        Pair(["SHEIN"], ["zzkko.com.zzkko"], hosts: ["shein.com"]),
        Pair(["Walmart"], ["com.walmart.electronics"], hosts: ["walmart.com"]),
        Pair(["Target"], ["com.target.target"], hosts: ["target.com"]),
        Pair(["Poshmark"], ["com.poshmark.poshmark"], hosts: ["poshmark.com"]),
        Pair(["StockX"], ["com.campless.campless"], hosts: ["stockx.com"]),
        Pair(["Depop"], ["com.garageitaly.garage"], hosts: ["depop.com"]),
        Pair(["AliExpress"], ["com.alibaba.ialiexpress"], hosts: ["aliexpress.com"]),
        Pair(["craigslist"], ["org.craigslist.craigslistmobile"], hosts: ["craigslist.org"]),
    ]
}
