import Foundation

/// What Furlough guesses a target is worth. A static table rather than a model: exact,
/// offline, testable — and on the phone a Screen Time token is opaque anyway, so this can only
/// answer once the shield has learned a name (`Target.systemName`). Only a default; the rule
/// editor offers it as a suggestion, `Target.utility` is what actually decides.
enum AppUtility {
    /// A tier, plus the specific consequence of blocking this one where saying it plainly beats
    /// the generic line. Only essentials carry a detail: for the rest the tier says enough.
    struct Advice: Equatable, Sendable {
        var utility: Utility
        var detail: String?

        init(_ utility: Utility, _ detail: String? = nil) {
            self.utility = utility
            self.detail = detail
        }
    }

    /// The tier Furlough would pick for `target`, or nil when it has never heard of it. Nil is
    /// the common answer on a fresh phone: nothing is known until the shield learns a name.
    static func suggestion(for target: Target) -> Advice? {
        switch target.kind {
        #if os(iOS)
        case .application:
            return byName(target.systemName) ?? byName(target.nickname)
        case .webDomain:
            return byHost(target.systemName) ?? byHost(target.nickname) ?? byName(target.systemName)
        case .category:
            return nil // always blocked, so nothing to warn about
        case .host(let host):
            return byHost(host)
        #else
        case .macApp(let bundleID):
            return byBundleID(bundleID) ?? byName(target.nickname)
        case .host(let host):
            return byHost(host)
        #endif
        }
    }

    // MARK: Matching

    /// `RuleSuggestion` keys its exceptions table the same way, so neither file has its own
    /// idea of what counts as a match.

    static func key(forName name: String?) -> String? {
        guard let key = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !key.isEmpty
        else { return nil }
        return key
    }

    static func match<Value>(name: String?, in table: [String: Value]) -> Value? {
        key(forName: name).flatMap { table[$0] }
    }

    /// Exactly, then by prefix, so "com.apple.mobilesafari" and a vendor's whole suite land
    /// together without listing each one. A prefix stops at a dot: "com.ubercabbage" is not Uber.
    static func match<Value>(
        bundleID raw: String,
        in table: [String: Value],
        prefixes: [(prefix: String, value: Value)] = []
    ) -> Value? {
        let key = raw.lowercased()
        if let exact = table[key] { return exact }
        return prefixes
            .filter { key == $0.prefix || key.hasPrefix($0.prefix + ".") }
            .max { $0.prefix.count < $1.prefix.count }?
            .value
    }

    /// Subdomains count and the longest rule wins, so "shorts.youtube.com" beats "youtube.com".
    static func match<Value>(host raw: String?, in table: [(host: String, value: Value)]) -> Value? {
        guard let raw, let host = Hosts.normalize(raw) else { return nil }
        return table
            .filter { Hosts.matches(host, rule: $0.host) }
            .max { $0.host.count < $1.host.count }?
            .value
    }

    // MARK: Lookups

    static func byName(_ name: String?) -> Advice? { match(name: name, in: names) }

    static func byBundleID(_ raw: String) -> Advice? {
        match(bundleID: raw, in: bundleIDs, prefixes: bundleIDPrefixes)
    }

    /// Checks `properNameByBundleID` (names confirmed against the App Store) first. Failing
    /// that, falls back to reverse-matching `bundleIDs` -> `names` via shared `Advice` — but
    /// only when exactly one name maps to that advice, since many apps share a bare
    /// `.init(.useful)` and guessing among them would put the wrong name on a target.
    static func name(forBundleID raw: String) -> String? {
        let key = raw.lowercased()
        if let exact = properNameByBundleID[key] { return exact }
        guard let advice = byBundleID(raw) else { return nil }
        let matches = names.filter { $0.value == advice }
        guard matches.count == 1, let matchKey = matches.keys.first else { return nil }
        return properName(matchKey)
    }

    /// Offered as a *nickname*, never written into `systemName` directly — filling that in
    /// behind someone's back would put a name they never chose into their own config. Nil once
    /// a nickname exists, so it never talks over a name someone already picked.
    static func offeredNickname(for target: Target) -> String? {
        guard target.nickname.isEmpty, let known = knownName(of: target) else { return nil }
        return known == target.defaultName ? nil : known
    }

    private static func knownName(of target: Target) -> String? {
        switch target.kind {
        #if os(iOS)
        case .application, .category:
            return nil // a token carries no identity to look up
        case .webDomain:
            return Companions.pair(forHost: target.systemName ?? "")?.title
        case .host(let host):
            return Companions.pair(forHost: host)?.title
        #else
        case .macApp(let bundleID):
            return Companions.pair(forBundleID: bundleID, name: target.systemName ?? "")?.title
                ?? name(forBundleID: bundleID)
        case .host(let host):
            return Companions.pair(forHost: host)?.title
        #endif
        }
    }

    /// Only entries `Companions` doesn't already carry (checked first by the caller).
    static let properNameByBundleID: [String: String] = [
        "net.kortina.labs.venmo": "Venmo",
        "com.squareup.cash": "Cash App",
        "com.yourcompany.ppclient": "PayPal",
        "doordash.doordashconsumer": "DoorDash",
        "com.ubercab.ubereats": "Uber Eats",
        "com.airbnb.app": "Airbnb",
        "com.ebay.iphone": "eBay",
        "com.etsy.etsyforios": "Etsy",
        "com.microsoft.skype.teams": "Microsoft Teams",
        "com.fogcreek.trello": "Trello",
        "com.asana.asana": "Asana",
        "com.duolingo.duolingomobile": "Duolingo",
        "com.soundcloud.touchapp": "SoundCloud",
        "com.pandora": "Pandora",
        "com.anthropic.claude": "Claude",
        "com.google.gemini": "Gemini",
        "ai.perplexity.app": "Perplexity",
        "com.evernote.iphone.evernote": "Evernote",
        "com.todoist.ios": "Todoist",
        "com.monday.monday": "monday.com",
        "com.canva.canvaeditor": "Canva",
        "org.khanacademy.khan-academy": "Khan Academy",
        "org.coursera.coursera": "Coursera",
        "com.audible.iphone": "Audible",
        "com.amazon.lassen": "Kindle",
        "com.quora.app.experts": "Poe",
        "com.microsoft.officemobile": "Microsoft Copilot",
        "com.instacart": "Instacart",
        "com.walmart.electronics": "Walmart",
        "com.target.target": "Target",

        "com.peacocktv.peacock": "Peacock",
        "com.cbsvideo.app": "Paramount+",
        "com.apple.tv": "Apple TV",
        "com.apple.music": "Music",
        "com.apple.news": "News",
        "com.apple.mobilesafari": "Safari",
        "com.google.chrome.ios": "Chrome",
        "com.espn.scorecenter": "ESPN",
        "iphone.thescore.com": "theScore",
        "com.flipboard.flipboard-ipad": "Flipboard",
        "com.quora.app.mobile": "Quora",
        "com.nextdoor.nextdoor": "Nextdoor",
        "imgurmobile": "Imgur",
        "com.roblox.robloxmobile": "Roblox",
        "com.epicgames.fortnitegame": "Fortnite",
        "com.midasplayer.apps.candycrushsaga": "Candy Crush Saga",
        "com.zynga.wordswithfriends3": "Words With Friends",
        "com.nianticlabs.pokemongo": "Pokémon GO",
        "com.chess.iphone": "Chess.com",
        "com.poshmark.poshmark": "Poshmark",
        "com.garageitaly.garage": "Depop",
        "com.vimeo": "Vimeo",
        "com.crunchyroll.iphone": "Crunchyroll",
        "com.nfl.gamecenter": "NFL",
        "com.bleacherreport.teamstream": "Bleacher Report",
        "com.mojang.minecraftpe": "Minecraft",
        "com.mercariapp.ios.mercari": "Mercari",
        "com.offerup.iphone.consumer": "OfferUp",
        "com.alibaba.ialiexpress": "AliExpress",
        "com.innersloth.amongus": "Among Us!",
        "com.activision.callofduty.shooter": "Call of Duty: Mobile",
        "com.vilcsak.bitcoin2": "Coinbase",

        "com.bereal.bereal": "BeReal",
        "com.9gag.ios.mobile": "9GAG",
        "com.einnovation.temu": "Temu",
        "zzkko.com.zzkko": "Shein",
        "com.cardify.tinder": "Tinder",
        "com.moxco.bumble": "Bumble",
        "co.hinge.mobile.ios": "Hinge",
        "com.grindrguy.grindrx": "Grindr",
        "com.okcupid.app": "OkCupid",
        "ai.character.app": "Character.AI",
        "com.draftkings.sportsbook": "DraftKings",
        "com.fanduel.sportsbook": "FanDuel",
        "com.playmgm.nj.sports2": "BetMGM",
        "us.williamhill.nj.sports": "Caesars Sportsbook",
        "com.espn.bet": "ESPN Bet",
        "com.myprizepicks.prizepicks": "PrizePicks",
        "com.kick.mobile": "Kick",
        "com.kick.streaming": "Kick",
        "com.supercell.magic": "Clash of Clans",
        "com.supercell.scroll": "Clash Royale",
        "com.supercell.laser": "Brawl Stars",
        "com.match.match.com": "Match",
        "com.robinhood.release.robinhood": "Robinhood",
    ]

    /// Keys are lowercased (to match the shield's reporting), so capitalizing each word
    /// recovers most casing but not all ("facetime" -> "Facetime" is wrong); only the
    /// exceptions are listed here.
    static func properName(_ key: String) -> String {
        if let exact = properNames[key] { return exact }
        return key.split(separator: " ").map(\.capitalized).joined(separator: " ")
    }

    private static let properNames: [String: String] = [
        "facetime": "FaceTime",
        "1password": "1Password",
        "bereal": "BeReal",
        "youtube": "YouTube",
        "youtube shorts": "YouTube Shorts",
        "whatsapp": "WhatsApp",
        "linkedin": "LinkedIn",
        "tiktok": "TikTok",
        "draftkings": "DraftKings",
        "fanduel": "FanDuel",
        "iphone": "iPhone",
        "9gag": "9GAG",
        "thescore": "theScore",
        "espn bet": "ESPN Bet",
        "espn": "ESPN",
        "okcupid": "OkCupid",
        "betmgm": "BetMGM",
        "prizepicks": "PrizePicks",
        "chess.com": "Chess.com",
        "chatgpt": "ChatGPT",
        "disney+": "Disney+",
        "hbo max": "HBO Max",
        "paramount+": "Paramount+",
        "apple tv": "Apple TV",
        "pokémon go": "Pokémon GO",
        "pokemon go": "Pokémon GO",
        "youtube music": "YouTube Music",
        "monday.com": "monday.com",
        "khan academy": "Khan Academy",
        "poe": "Poe",
        "nfl": "NFL",
        "aliexpress": "AliExpress",
        "offerup": "OfferUp",
        "among us!": "Among Us!",
    ]

    static func byHost(_ raw: String?) -> Advice? { match(host: raw, in: hosts) }

    // MARK: The table

    static let names: [String: Advice] = [
        "messages": .init(.essential, "Messages is how people reach you, and how codes texted to you arrive."),
        "phone": .init(.essential, "Phone is how you call anyone, and how anyone calls you."),
        "facetime": .init(.essential, "FaceTime is how you reach people who call you that way."),
        "maps": .init(.essential, "Maps is how you find your way somewhere unfamiliar."),
        "google maps": .init(.essential, "Google Maps is how you find your way somewhere unfamiliar."),
        "wallet": .init(.essential, "Wallet holds your cards, passes and tickets."),
        "find my": .init(.essential, "Find My is how you locate a lost phone, or a person expecting you."),
        "clock": .init(.essential, "Clock holds your alarms."),
        "settings": .init(.essential, "Settings is also where Furlough itself is switched off, so blocking it locks the escape hatch."),
        "health": .init(.essential),
        "authenticator": .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code."),
        "google authenticator": .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code."),
        "microsoft authenticator": .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code."),
        "duo mobile": .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code."),
        "authy": .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code."),
        "1password": .init(.essential, "1Password holds the passwords you need to sign in anywhere."),
        "bitwarden": .init(.essential, "Bitwarden holds the passwords you need to sign in anywhere."),
        "uber": .init(.essential, "Uber may be how you get home."),
        "lyft": .init(.essential, "Lyft may be how you get home."),
        "waze": .init(.essential, "Waze is how you find your way somewhere unfamiliar."),
        "life360": .init(.essential, "Life360 is how family finds each other."),

        "mail": .init(.useful),
        "gmail": .init(.useful),
        "calendar": .init(.useful),
        "notes": .init(.useful),
        "reminders": .init(.useful),
        "slack": .init(.useful),
        "zoom": .init(.useful),
        "safari": .init(.useful),
        "chrome": .init(.useful),
        "music": .init(.useful),
        "spotify": .init(.useful),
        "podcasts": .init(.useful),
        "photos": .init(.useful),
        "camera": .init(.useful),
        "whatsapp": .init(.useful),
        "signal": .init(.useful),
        "discord": .init(.useful),
        "venmo": .init(.useful),
        "cash app": .init(.useful),
        "paypal": .init(.useful),
        "doordash": .init(.useful),
        "uber eats": .init(.useful),
        "airbnb": .init(.useful),
        "ebay": .init(.useful),
        "etsy": .init(.useful),
        "microsoft teams": .init(.useful),
        "trello": .init(.useful),
        "asana": .init(.useful),
        "duolingo": .init(.useful),
        "soundcloud": .init(.useful),
        "pandora": .init(.useful),
        "youtube music": .init(.useful),
        "chatgpt": .init(.useful),
        "claude": .init(.useful),
        "gemini": .init(.useful),
        "perplexity": .init(.useful),
        "telegram": .init(.useful),
        "messenger": .init(.useful),
        "notion": .init(.useful),
        "evernote": .init(.useful),
        "todoist": .init(.useful),
        "monday.com": .init(.useful),
        "canva": .init(.useful),
        "khan academy": .init(.useful),
        "coursera": .init(.useful),
        "audible": .init(.useful),
        "kindle": .init(.useful),
        "poe": .init(.useful),
        "copilot": .init(.useful),
        "microsoft copilot": .init(.useful),
        "instacart": .init(.useful),
        "walmart": .init(.useful),
        "target": .init(.useful),
        "amazon": .init(.useful),

        "youtube": .init(.idle),
        "netflix": .init(.idle),
        "news": .init(.idle),
        "apple news": .init(.idle),
        "twitch": .init(.idle),
        "pinterest": .init(.idle),
        "linkedin": .init(.idle),
        "hulu": .init(.idle),
        "disney+": .init(.idle),
        "max": .init(.idle),
        "hbo max": .init(.idle),
        "prime video": .init(.idle),
        "peacock": .init(.idle),
        "paramount+": .init(.idle),
        "apple tv": .init(.idle),
        "espn": .init(.idle),
        "thescore": .init(.idle),
        "flipboard": .init(.idle),
        "quora": .init(.idle),
        "nextdoor": .init(.idle),
        "imgur": .init(.idle),
        "roblox": .init(.idle),
        "fortnite": .init(.idle),
        "candy crush saga": .init(.idle),
        "words with friends": .init(.idle),
        "pokémon go": .init(.idle),
        "pokemon go": .init(.idle),
        "chess.com": .init(.idle),
        "poshmark": .init(.idle),
        "depop": .init(.idle),
        "vimeo": .init(.idle),
        "crunchyroll": .init(.idle),
        "nfl": .init(.idle),
        "bleacher report": .init(.idle),
        "minecraft": .init(.idle),
        "mercari": .init(.idle),
        "offerup": .init(.idle),
        "aliexpress": .init(.idle),
        "among us": .init(.idle),
        "among us!": .init(.idle),
        "call of duty": .init(.idle),
        "call of duty: mobile": .init(.idle),
        "coinbase": .init(.idle),

        "tiktok": .init(.hazard),
        "instagram": .init(.hazard),
        "reddit": .init(.hazard),
        "x": .init(.hazard),
        "twitter": .init(.hazard),
        "snapchat": .init(.hazard),
        "facebook": .init(.hazard),
        "threads": .init(.hazard),
        "tumblr": .init(.hazard),
        "bereal": .init(.hazard),
        "youtube shorts": .init(.hazard),
        "draftkings": .init(.hazard),
        "fanduel": .init(.hazard),
        "9gag": .init(.hazard),
        "temu": .init(.hazard),
        "shein": .init(.hazard),
        "tinder": .init(.hazard),
        "bumble": .init(.hazard),
        "hinge": .init(.hazard),
        "grindr": .init(.hazard),
        "okcupid": .init(.hazard),
        "character.ai": .init(.hazard),
        "character ai": .init(.hazard),
        "betmgm": .init(.hazard),
        "caesars sportsbook": .init(.hazard),
        "espn bet": .init(.hazard),
        "prizepicks": .init(.hazard),
        "kick": .init(.hazard),
        "clash of clans": .init(.hazard),
        "clash royale": .init(.hazard),
        "brawl stars": .init(.hazard),
        "match": .init(.hazard),
        "robinhood": .init(.hazard),
        "bluesky": .init(.hazard),
    ]

    static let bundleIDs: [String: Advice] = [
        "com.apple.mobilesms": .init(.essential, "Messages is how people reach you, and how codes texted to you arrive."),
        "com.apple.mobilephone": .init(.essential, "Phone is how you call anyone, and how anyone calls you."),
        "com.apple.facetime": .init(.essential, "FaceTime is how you reach people who call you that way."),
        "com.apple.maps": .init(.essential, "Maps is how you find your way somewhere unfamiliar."),
        "com.apple.passbook": .init(.essential, "Wallet holds your cards, passes and tickets."),
        "com.apple.findmy": .init(.essential, "Find My is how you locate a lost phone, or a person expecting you."),
        "com.apple.mobiletimer": .init(.essential, "Clock holds your alarms."),
        "com.apple.preferences": .init(.essential, "Settings is also where Furlough itself is switched off, so blocking it locks the escape hatch."),
        "com.apple.systempreferences": .init(.essential, "System Settings is also where Furlough is switched off, so blocking it locks the escape hatch."),
        "com.waze.iphone": .init(.essential, "Waze is how you find your way somewhere unfamiliar."),
        "com.life360.safetymap": .init(.essential, "Life360 is how family finds each other."),

        "com.apple.mail": .init(.useful),
        "com.apple.mobilemail": .init(.useful),
        "com.apple.ical": .init(.useful),
        "com.apple.notes": .init(.useful),
        "com.apple.mobilenotes": .init(.useful),
        "com.apple.reminders": .init(.useful),
        "com.apple.safari": .init(.useful),
        "com.apple.mobilesafari": .init(.useful),
        "com.apple.terminal": .init(.useful),
        "com.apple.dt.xcode": .init(.useful),
        "com.google.chrome": .init(.useful),
        "com.google.chrome.ios": .init(.useful),
        "com.apple.music": .init(.useful),
        "com.tinyspeck.slackmacgap": .init(.useful),
        "us.zoom.xos": .init(.useful),
        "com.hnc.discord": .init(.useful),
        "net.kortina.labs.venmo": .init(.useful),
        "com.squareup.cash": .init(.useful),
        "com.yourcompany.ppclient": .init(.useful),
        "doordash.doordashconsumer": .init(.useful),
        "com.ubercab.ubereats": .init(.useful),
        "com.airbnb.app": .init(.useful),
        "com.ebay.iphone": .init(.useful),
        "com.etsy.etsyforios": .init(.useful),
        "com.microsoft.skype.teams": .init(.useful),
        "com.fogcreek.trello": .init(.useful),
        "com.asana.asana": .init(.useful),
        "com.duolingo.duolingomobile": .init(.useful),
        "com.soundcloud.touchapp": .init(.useful),
        "com.pandora": .init(.useful),
        "com.google.ios.youtubemusic": .init(.useful),
        "com.openai.chat": .init(.useful),
        "com.anthropic.claude": .init(.useful),
        "com.google.gemini": .init(.useful),
        "ai.perplexity.app": .init(.useful),
        "ph.telegra.telegraph": .init(.useful),
        "com.facebook.messenger": .init(.useful),
        "notion.id": .init(.useful),
        "com.evernote.iphone.evernote": .init(.useful),
        "com.todoist.ios": .init(.useful),
        "com.monday.monday": .init(.useful),
        "com.canva.canvaeditor": .init(.useful),
        "org.khanacademy.khan-academy": .init(.useful),
        "org.coursera.coursera": .init(.useful),
        "com.audible.iphone": .init(.useful),
        "com.amazon.lassen": .init(.useful),
        "com.quora.app.experts": .init(.useful),
        "com.microsoft.officemobile": .init(.useful),
        "com.instacart": .init(.useful),
        "com.walmart.electronics": .init(.useful),
        "com.target.target": .init(.useful),
        "com.amazon.amazon": .init(.useful),

        "com.google.ios.youtube": .init(.idle),
        "com.netflix.netflix": .init(.idle),
        "tv.twitch": .init(.idle),
        "com.pinterest": .init(.idle),
        "com.linkedin.linkedin": .init(.idle),
        "com.hulu.plus": .init(.idle),
        "com.disney.disneyplus": .init(.idle),
        "com.wbd.stream": .init(.idle),
        "com.amazon.aiv.aivapp": .init(.idle),
        "com.peacocktv.peacock": .init(.idle),
        "com.cbsvideo.app": .init(.idle),
        "com.apple.tv": .init(.idle),
        "com.apple.news": .init(.idle),
        "com.espn.scorecenter": .init(.idle),
        "iphone.thescore.com": .init(.idle),
        "com.flipboard.flipboard-ipad": .init(.idle),
        "com.quora.app.mobile": .init(.idle),
        "com.nextdoor.nextdoor": .init(.idle),
        "imgurmobile": .init(.idle),
        "com.roblox.robloxmobile": .init(.idle),
        "com.epicgames.fortnitegame": .init(.idle),
        "com.midasplayer.apps.candycrushsaga": .init(.idle),
        "com.zynga.wordswithfriends3": .init(.idle),
        "com.nianticlabs.pokemongo": .init(.idle),
        "com.chess.iphone": .init(.idle),
        "com.poshmark.poshmark": .init(.idle),
        "com.garageitaly.garage": .init(.idle),
        "com.vimeo": .init(.idle),
        "com.crunchyroll.iphone": .init(.idle),
        "com.nfl.gamecenter": .init(.idle),
        "com.bleacherreport.teamstream": .init(.idle),
        "com.mojang.minecraftpe": .init(.idle),
        "com.mercariapp.ios.mercari": .init(.idle),
        "com.offerup.iphone.consumer": .init(.idle),
        "com.alibaba.ialiexpress": .init(.idle),
        "com.innersloth.amongus": .init(.idle),
        "com.activision.callofduty.shooter": .init(.idle),
        "com.vilcsak.bitcoin2": .init(.idle),

        "com.zhiliaoapp.musically": .init(.hazard),
        "com.ss.iphone.ugc.ame": .init(.hazard),
        "com.burbn.instagram": .init(.hazard),
        "com.reddit.reddit": .init(.hazard),
        "com.atebits.tweetie2": .init(.hazard),
        "com.toyopagroup.picaboo": .init(.hazard),
        "com.facebook.facebook": .init(.hazard),
        "com.burbn.barcelona": .init(.hazard),
        "com.bereal.bereal": .init(.hazard),
        "com.9gag.ios.mobile": .init(.hazard),
        "com.einnovation.temu": .init(.hazard),
        "zzkko.com.zzkko": .init(.hazard),
        "com.cardify.tinder": .init(.hazard),
        "com.moxco.bumble": .init(.hazard),
        "co.hinge.mobile.ios": .init(.hazard),
        "com.grindrguy.grindrx": .init(.hazard),
        "com.okcupid.app": .init(.hazard),
        "ai.character.app": .init(.hazard),
        "com.draftkings.sportsbook": .init(.hazard),
        "com.fanduel.sportsbook": .init(.hazard),
        "com.playmgm.nj.sports2": .init(.hazard),
        "us.williamhill.nj.sports": .init(.hazard),
        "com.espn.bet": .init(.hazard),
        "com.myprizepicks.prizepicks": .init(.hazard),
        "com.kick.mobile": .init(.hazard),
        "com.kick.streaming": .init(.hazard),
        "com.supercell.magic": .init(.hazard),
        "com.supercell.scroll": .init(.hazard),
        "com.supercell.laser": .init(.hazard),
        "com.match.match.com": .init(.hazard),
        "com.robinhood.release.robinhood": .init(.hazard),
        "xyz.blueskyweb.app": .init(.hazard),
    ]

    static let bundleIDPrefixes: [(prefix: String, value: Advice)] = [
        ("com.agilebits", .init(.essential, "1Password holds the passwords you need to sign in anywhere.")),
        ("com.1password", .init(.essential, "1Password holds the passwords you need to sign in anywhere.")),
        ("com.bitwarden", .init(.essential, "Bitwarden holds the passwords you need to sign in anywhere.")),
        ("com.google.authenticator", .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code.")),
        ("com.microsoft.azureauthenticator", .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code.")),
        ("com.authy", .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code.")),
        ("com.duosecurity", .init(.essential, "Blocking an authenticator means you cannot sign in to anything that asks for a code.")),
        ("com.ubercab", .init(.essential, "Uber may be how you get home.")),
        ("com.zimride", .init(.essential, "Lyft may be how you get home.")),
        ("com.apple.health", .init(.essential)),
        ("com.spotify", .init(.useful)),
        ("org.whispersystems", .init(.useful)),
        ("net.whatsapp", .init(.useful)),
    ]

    static let hosts: [(host: String, value: Advice)] = [
        ("web.whatsapp.com", .init(.essential, "WhatsApp Web is how some people reach you.")),
        ("messages.google.com", .init(.essential, "Messages is how people reach you, and how codes texted to you arrive.")),
        ("maps.google.com", .init(.essential, "Maps is how you find your way somewhere unfamiliar.")),
        ("maps.apple.com", .init(.essential, "Maps is how you find your way somewhere unfamiliar.")),

        ("mail.google.com", .init(.useful)),
        ("calendar.google.com", .init(.useful)),
        ("drive.google.com", .init(.useful)),
        ("docs.google.com", .init(.useful)),
        ("github.com", .init(.useful)),
        ("stackoverflow.com", .init(.useful)),
        ("slack.com", .init(.useful)),
        ("zoom.us", .init(.useful)),
        ("open.spotify.com", .init(.useful)),
        ("linkedin.com", .init(.idle)),
        ("google.com", .init(.useful)),
        ("soundcloud.com", .init(.useful)),
        ("pandora.com", .init(.useful)),
        ("ebay.com", .init(.useful)),
        ("etsy.com", .init(.useful)),
        ("doordash.com", .init(.useful)),
        ("airbnb.com", .init(.useful)),
        ("venmo.com", .init(.useful)),
        ("cash.app", .init(.useful)),
        ("paypal.com", .init(.useful)),
        ("asana.com", .init(.useful)),
        ("trello.com", .init(.useful)),
        ("duolingo.com", .init(.useful)),
        ("chatgpt.com", .init(.useful)),
        ("claude.ai", .init(.useful)),
        ("gemini.google.com", .init(.useful)),
        ("perplexity.ai", .init(.useful)),
        ("web.telegram.org", .init(.useful)),
        ("notion.so", .init(.useful)),
        ("evernote.com", .init(.useful)),
        ("todoist.com", .init(.useful)),
        ("monday.com", .init(.useful)),
        ("canva.com", .init(.useful)),
        ("khanacademy.org", .init(.useful)),
        ("coursera.org", .init(.useful)),
        ("audible.com", .init(.useful)),
        ("instacart.com", .init(.useful)),
        ("walmart.com", .init(.useful)),
        ("target.com", .init(.useful)),

        ("youtube.com", .init(.idle)),
        ("netflix.com", .init(.idle)),
        ("twitch.tv", .init(.idle)),
        ("news.ycombinator.com", .init(.idle)),
        ("nytimes.com", .init(.idle)),
        ("espn.com", .init(.idle)),
        ("pinterest.com", .init(.idle)),
        ("imgur.com", .init(.idle)),
        ("hulu.com", .init(.idle)),
        ("disneyplus.com", .init(.idle)),
        ("max.com", .init(.idle)),
        ("primevideo.com", .init(.idle)),
        ("peacocktv.com", .init(.idle)),
        ("paramountplus.com", .init(.idle)),
        ("quora.com", .init(.idle)),
        ("nextdoor.com", .init(.idle)),
        ("roblox.com", .init(.idle)),
        ("chess.com", .init(.idle)),
        ("poshmark.com", .init(.idle)),
        ("depop.com", .init(.idle)),
        ("vimeo.com", .init(.idle)),
        ("crunchyroll.com", .init(.idle)),
        ("nfl.com", .init(.idle)),
        ("bleacherreport.com", .init(.idle)),
        ("mercari.com", .init(.idle)),
        ("offerup.com", .init(.idle)),
        ("aliexpress.com", .init(.idle)),
        ("coinbase.com", .init(.idle)),

        ("tiktok.com", .init(.hazard)),
        ("instagram.com", .init(.hazard)),
        ("reddit.com", .init(.hazard)),
        ("old.reddit.com", .init(.hazard)),
        ("x.com", .init(.hazard)),
        ("twitter.com", .init(.hazard)),
        ("facebook.com", .init(.hazard)),
        ("threads.com", .init(.hazard)),
        ("threads.net", .init(.hazard)),
        ("snapchat.com", .init(.hazard)),
        ("tumblr.com", .init(.hazard)),
        ("9gag.com", .init(.hazard)),
        ("draftkings.com", .init(.hazard)),
        ("fanduel.com", .init(.hazard)),
        ("temu.com", .init(.hazard)),
        ("shein.com", .init(.hazard)),
        ("tinder.com", .init(.hazard)),
        ("bumble.com", .init(.hazard)),
        ("hinge.co", .init(.hazard)),
        ("grindr.com", .init(.hazard)),
        ("character.ai", .init(.hazard)),
        ("betmgm.com", .init(.hazard)),
        ("prizepicks.com", .init(.hazard)),
        ("kick.com", .init(.hazard)),
        ("match.com", .init(.hazard)),
        ("robinhood.com", .init(.hazard)),
        ("bsky.app", .init(.hazard)),
    ]
}
