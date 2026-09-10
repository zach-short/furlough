import Foundation

/// What an app is known by before Screen Time says: the name its bundle identifier stands for,
/// and the colour its icon is mostly made of.
///
/// With data access Screen Time hands the usage page minutes and a bundle identifier and nothing
/// else — no name, and no token to draw Apple's icon with. The token comes from a second query
/// that takes seconds when it answers and sometimes never does, and a page that waited on it sat
/// under an hourglass for minutes at a time. Nothing about Instagram needs asking: the tables
/// already know the identifier, and know it offline. So a card is drawn from here first — the
/// name from `Companions` and `AppUtility`, and a letter on the brand's colour where the icon will
/// go — and Apple's own name and artwork take over the moment the token lands.
///
/// A colour and a letter rather than the icon itself: the artwork is the app's trademark, and the
/// one place Furlough may draw it from is `Label(token)`. The colour is only ever an interim, so
/// it is close rather than exact, and an app the table does not know simply has none.
enum Brand {
    /// What the tables call the thing behind a usage key — a bundle identifier, or "web:" and a
    /// domain. `Companions` first, because its names are the ones written to be shown; then
    /// `AppUtility`, which knows many more apps than are also websites. A domain is its own name.
    /// Nil when neither table knows, which is the honest answer: a guess would put the wrong name
    /// on a card and on the rule it writes. The same order `AppModel.nameFromTables` asks in.
    static func name(forKey key: String) -> String? {
        if let domain = UsageAnalysis.domain(inKey: key) { return domain }
        if let pair = Companions.pair(forBundleID: key, name: "") { return pair.title }
        return AppUtility.name(forBundleID: key)
    }

    /// The colour the thing behind `key` is known by, as RGB, or nil when the table has none. A
    /// web key answers through `Companions`, so youtube.com is YouTube's red.
    static func color(forKey key: String) -> UInt32? {
        if let domain = UsageAnalysis.domain(inKey: key) {
            guard let pair = Companions.pair(forHost: domain) else { return nil }
            return pair.bundleIDs.lazy.compactMap { colors[$0] }.first
        }
        return colors[Companions.normalize(bundleID: key)]
    }

    /// The letter a tile carries in place of the icon: the first character of the name,
    /// uppercased. Nil for a name that is nothing but space.
    static func monogram(_ name: String) -> String? {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    /// True when a colour is light enough to want dark lettering: Snapchat's yellow and Hulu's
    /// green, not Instagram's magenta or WhatsApp's. Relative luminance in sRGB, split at a half,
    /// which is where those four fall on the sides their own icons put them.
    static func isLight(_ rgb: UInt32) -> Bool {
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb >> 16) + 0.7152 * linear(rgb >> 8) + 0.0722 * linear(rgb)
        return luminance > 0.5
    }

    /// The dark a near-black icon is lifted to. Black on Furlough's ground is a hole, and it is
    /// also what dark lettering on a light tile is drawn in, so the two agree.
    static let ink: UInt32 = 0x2A2724

    /// RGB by lowercased bundle identifier: the colour each icon is mostly made of, near enough
    /// to be placed at a glance. Icons that are black or nearly so — X, Threads, ChatGPT, Uber —
    /// are `ink` instead. Identifiers are spelled the way `Companions` spells them.
    static let colors: [String: UInt32] = [
        // Video
        "com.google.ios.youtube": 0xFF0000,
        "com.google.ios.youtubemusic": 0xFF0000,
        "com.netflix.netflix": 0xE50914,
        "tv.twitch": 0x9146FF,
        "com.amazon.aiv.aivapp": 0x00A8E1,
        "com.hulu.plus": 0x1CE783,
        "com.disney.disneyplus": 0x113CCF,
        "com.wbd.stream": 0x002BE7,
        "com.hbo.hbonow": 0x002BE7,
        "com.peacocktv.peacock": ink,
        "com.cbsvideo.app": 0x0064FF,
        "com.crunchyroll.iphone": 0xF47521,
        "com.kick.mobile": 0x53FC18,
        "com.apple.tv": ink,
        "com.vimeo": 0x1AB7EA,

        // Social
        "com.zhiliaoapp.musically": 0xEE1D52,
        "com.ss.iphone.ugc.ame": 0xEE1D52,
        "com.burbn.instagram": 0xE1306C,
        "com.reddit.reddit": 0xFF4500,
        "com.atebits.tweetie2": ink,
        "com.burbn.barcelona": ink,
        "xyz.blueskyweb.app": 0x1185FE,
        "com.toyopagroup.picaboo": 0xFFFC00,
        "com.facebook.facebook": 0x1877F2,
        "com.facebook.messenger": 0x0084FF,
        "pinterest": 0xE60023,
        "com.pinterest": 0xE60023,
        "com.linkedin.linkedin": 0x0A66C2,
        "com.tumblr.tumblr": 0x35465C,
        "com.quora.app.mobile": 0xB92B27,
        "com.nextdoor.nextdoor": 0x8ED500,
        "alexisbarreyat.bereal": ink,
        "com.bereal.bereal": ink,
        "com.9gag.ios.mobile": ink,

        // Messaging
        "com.hammerandchisel.discord": 0x5865F2,
        "com.hnc.discord": 0x5865F2,
        "com.tinyspeck.chatlyio": 0x4A154B,
        "com.tinyspeck.slackmacgap": 0x4A154B,
        "net.whatsapp.whatsapp": 0x25D366,
        "ph.telegra.telegraph": 0x26A5E4,
        "us.zoom.videomeetings": 0x2D8CFF,
        "com.apple.mobilesms": 0x34C759,

        // Games
        "com.roblox.robloxmobile": ink,
        "com.nianticlabs.pokemongo": 0x3D7DCA,
        "com.mojang.minecraftpe": 0x5B8731,
        "com.chess.iphone": 0x769656,
        "com.midasplayer.apps.candycrushsaga": 0xF7941D,
        "com.zynga.wordswithfriends3": 0xE8862E,

        // Assistants, reading, listening
        "com.openai.chat": ink,
        "com.anthropic.claude": 0xD97757,
        "com.google.gemini": 0x4E8DF5,
        "ai.perplexity.app": 0x20808D,
        "com.substack.substack": 0xFF6719,
        "com.medium.reader": ink,
        "com.spotify.client": 0x1DB954,
        "com.soundcloud.touchapp": 0xFF5500,
        "com.pandora": 0x3668FF,
        "com.audible.iphone": 0xF8991C,
        "com.amazon.lassen": 0x232F3E,
        "com.apple.music": 0xFA243C,
        "com.apple.news": 0xFD415E,
        "com.duolingo.duolingomobile": 0x58CC02,

        // Shopping, dating, money, browsing
        "com.amazon.amazon": 0xFF9900,
        "com.einnovation.temu": 0xFB7701,
        "zzkko.com.zzkko": ink,
        "com.cardify.tinder": 0xFE3C72,
        "co.hinge.mobile.ios": ink,
        "com.moxco.bumble": 0xFFC629,
        "com.grindrguy.grindrx": 0xFFC900,
        "doordash.doordashconsumer": 0xFF3008,
        "com.ubercab.ubereats": 0x06C167,
        "com.ubercab.uberclient": ink,
        "net.kortina.labs.venmo": 0x008CFF,
        "com.squareup.cash": 0x00D632,
        "com.robinhood.release.robinhood": 0x00C805,
        "com.google.chrome.ios": 0x4285F4,
        "com.apple.mobilesafari": 0x0A84FF,
    ]
}
