import Foundation

/// What Furlough guesses a target is worth, and what it costs to block.
///
/// A table rather than a model on purpose. On the Mac a target already *is* a bundle
/// identifier or a host, so a lookup is exact, offline and testable; asking a model would only
/// add latency and a way to be wrong. On the phone a Screen Time token is opaque, so this can
/// only answer once the shield has taught us a name (`Target.systemName`) — which is why the
/// guess is a suggestion the rule editor offers, never something applied behind anyone's back.
///
/// Everything here is a default. `Target.utility` is what actually decides, and Zach sets it.
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
            // A token says nothing. The name the shield learned is all there is to go on, and
            // failing that, whatever Zach called it himself.
            return byName(target.systemName) ?? byName(target.nickname)
        case .webDomain:
            // `WebDomain.domain` arrives through the same channel as an app's name.
            return byHost(target.systemName) ?? byHost(target.nickname) ?? byName(target.systemName)
        case .category:
            // Categories are always blocked, so there is no loosening to delay and nothing to warn about.
            return nil
        case .host(let host):
            // Typed, so the host is known from the start: the same answer the Mac gives.
            return byHost(host)
        #else
        case .macApp(let bundleID):
            return byBundleID(bundleID) ?? byName(target.nickname)
        case .host(let host):
            return byHost(host)
        #endif
        }
    }

    // MARK: Lookups

    static func byName(_ name: String?) -> Advice? {
        guard let key = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !key.isEmpty else { return nil }
        return names[key]
    }

    /// Bundle identifiers match exactly, then by prefix, so "com.apple.mobilesafari" and a
    /// vendor's whole suite land together without listing each one.
    static func byBundleID(_ raw: String) -> Advice? {
        let key = raw.lowercased()
        if let exact = bundleIDs[key] { return exact }
        return bundleIDPrefixes
            .filter { key == $0.prefix || key.hasPrefix($0.prefix + ".") }
            .max { $0.prefix.count < $1.prefix.count }?
            .advice
    }

    /// What to *call* the app with this bundle identifier, or nil when the table cannot tell.
    ///
    /// A Screen Time token says nothing, so a target has no name until the shield covers it. The
    /// two tables here are keyed differently — `bundleIDs` by identifier, `names` by the name the
    /// shield reports — and this is the bridge between them: take the advice the identifier maps
    /// to, and answer the display name that maps to the very same advice.
    ///
    /// Only when exactly one name does. Every essential carries its own detail sentence, so those
    /// are unique and answer here; the quieter tiers share a bare `.init(.useful)` between many
    /// apps, and for those the table genuinely does not know which one this is. Guessing between
    /// them would put the wrong name on a target and on the shield, which is worse than "This
    /// app". `Companions` is asked first by the caller and knows the rest by name outright.
    static func name(forBundleID raw: String) -> String? {
        guard let advice = byBundleID(raw) else { return nil }
        let matches = names.filter { $0.value == advice }
        guard matches.count == 1, let key = matches.keys.first else { return nil }
        return properName(key)
    }

    /// A key from `names` as a person writes it. The keys are lowercased because that is how the
    /// shield reports a name and so how the lookup has to match, which loses the casing — and
    /// capitalising each word recovers most of it but not all: "facetime" is not "Facetime".
    /// Only the ones it gets wrong are listed; `Companions` already carries proper names for the
    /// things that are also websites, and it is asked first.
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
    ]

    /// Subdomains count: "m.youtube.com" is YouTube.
    static func byHost(_ raw: String?) -> Advice? {
        guard let raw, let host = Hosts.normalize(raw) else { return nil }
        return hosts
            .filter { Hosts.matches(host, rule: $0.host) }
            .max { $0.host.count < $1.host.count }?
            .advice
    }

    // MARK: The table

    /// Names as the shield reports them on iOS, lowercased.
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
    ]

    /// Mac and iOS bundle identifiers. Messages, FaceTime and Maps share ids across platforms.
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
    ]

    /// Whole vendor suites, matched on the longest prefix that fits.
    static let bundleIDPrefixes: [(prefix: String, advice: Advice)] = [
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

    /// Websites, matched on the longest host that fits so "shorts.youtube.com" beats "youtube.com".
    static let hosts: [(host: String, advice: Advice)] = [
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
    ]
}
