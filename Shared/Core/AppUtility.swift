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

        "youtube": .init(.idle),
        "netflix": .init(.idle),
        "news": .init(.idle),
        "apple news": .init(.idle),
        "twitch": .init(.idle),
        "pinterest": .init(.idle),
        "linkedin": .init(.idle),

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

        "com.google.ios.youtube": .init(.idle),
        "com.netflix.netflix": .init(.idle),
        "tv.twitch": .init(.idle),
        "com.pinterest": .init(.idle),
        "com.linkedin.linkedin": .init(.idle),

        "com.zhiliaoapp.musically": .init(.hazard),
        "com.ss.iphone.ugc.ame": .init(.hazard),
        "com.burbn.instagram": .init(.hazard),
        "com.reddit.reddit": .init(.hazard),
        "com.atebits.tweetie2": .init(.hazard),
        "com.toyopagroup.picaboo": .init(.hazard),
        "com.facebook.facebook": .init(.hazard),
        "com.burbn.barcelona": .init(.hazard),
        "com.bereal.bereal": .init(.hazard),
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

        ("youtube.com", .init(.idle)),
        ("netflix.com", .init(.idle)),
        ("twitch.tv", .init(.idle)),
        ("news.ycombinator.com", .init(.idle)),
        ("nytimes.com", .init(.idle)),
        ("espn.com", .init(.idle)),
        ("pinterest.com", .init(.idle)),
        ("imgur.com", .init(.idle)),

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
    ]
}
