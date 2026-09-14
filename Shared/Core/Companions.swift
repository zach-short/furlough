import Foundation

/// Maps an app to the website it's also at, and vice versa — closes the gap where blocking the
/// YouTube app still leaves youtube.com open in a browser tab. A static table for the same
/// reason as `AppUtility` (exact, offline, testable); on the phone a Screen Time token can't
/// identify the app, so `missingHosts`/`missingApp` only work once the shield has learned a
/// name, and adding the other half there is still Apple's picker's job.
enum Companions {
    struct Pair: Hashable, Sendable {
        /// Matching ignores case/spacing, so entries like "YouTube Music" still match Finder's
        /// and the shield's own casing.
        let names: [String]
        /// Lowercased Mac and iOS identifiers — the iOS ones matter on Apple silicon too,
        /// since it runs iPhone apps under their own identifier.
        let bundleIDs: [String]
        /// Subdomains match, so youtube.com covers m.youtube.com.
        let hosts: [String]

        init(_ names: [String], _ bundleIDs: [String] = [], hosts: [String]) {
            self.names = names
            self.bundleIDs = bundleIDs
            self.hosts = hosts
        }

        var title: String { names[0] }

        func matches(bundleID: String, name: String) -> Bool {
            let key = Companions.normalize(name: name)
            return bundleIDs.contains(Companions.normalize(bundleID: bundleID))
                || (!key.isEmpty && names.contains { Companions.normalize(name: $0) == key })
        }
    }

    // MARK: Lookups

    static func pair(forBundleID bundleID: String, name: String) -> Pair? {
        pairs.first { $0.matches(bundleID: bundleID, name: name) }
    }

    static func hosts(forBundleID bundleID: String, name: String) -> [String] {
        pair(forBundleID: bundleID, name: name)?.hosts ?? []
    }

    /// Longest matching host wins, so a subdomain-specific pair beats a whole-domain one.
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

    enum Half: Equatable, Sendable {
        case sites([String])
        case app(String)
    }

    /// Works from a name alone (learned by the shield via `SharedStore.learnName`) since a
    /// Screen Time token itself says nothing about what app it is.
    static func missingHosts(forAppNamed name: String, knownHosts: [String]) -> [String] {
        let hosts = hosts(forBundleID: "", name: name)
        guard !hosts.isEmpty else { return [] }
        let known = knownHosts.compactMap(Hosts.normalize)
        return hosts.filter { host in !known.contains { Hosts.matches($0, rule: host) } }
    }

    /// Only a name, not something addable directly: on the phone only Apple's picker can mint
    /// an app token.
    static func missingApp(forHost host: String, knownAppNames: [String]) -> String? {
        guard let pair = pair(forHost: host) else { return nil }
        guard !knownAppNames.contains(where: { pair.matches(bundleID: "", name: $0) }) else { return nil }
        return pair.title
    }

    // MARK: Normalizing

    /// Sheds a Catalyst app's "maccatalyst." prefix so the Mac and phone builds match.
    static func normalize(bundleID: String) -> String {
        let key = bundleID.lowercased()
        let catalyst = "maccatalyst."
        return key.hasPrefix(catalyst) ? String(key.dropFirst(catalyst.count)) : key
    }

    static func normalize(name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: The table

    /// Only apps worth pairing for blocking purposes — e.g. Mail is also at gmail.com, but
    /// nobody adds Mail to keep off it.
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
