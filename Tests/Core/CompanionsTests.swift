import Foundation
import Testing

@Suite("Companions: the site an app is also at, and back")
struct CompanionsTests {
    @Test("An app finds its website by bundle identifier, whatever the case")
    func byBundleID() {
        #expect(Companions.hosts(forBundleID: "com.google.ios.YouTube", name: "Whatever") == ["youtube.com"])
        #expect(Companions.hosts(forBundleID: "com.atebits.Tweetie2", name: "X") == ["x.com", "twitter.com"])
    }

    @Test("A Catalyst app matches its iOS twin")
    func catalyst() {
        #expect(Companions.hosts(forBundleID: "maccatalyst.com.atebits.Tweetie2", name: "X") == ["x.com", "twitter.com"])
    }

    @Test("An unknown identifier falls back to the name on the bundle")
    func byName() {
        #expect(Companions.hosts(forBundleID: "com.example.wrapper", name: "YouTube") == ["youtube.com"])
        #expect(Companions.hosts(forBundleID: "com.example.wrapper", name: "  Disney+ ") == ["disneyplus.com"])
    }

    @Test("Most apps are not also a site")
    func unknown() {
        #expect(Companions.hosts(forBundleID: "com.apple.safari", name: "Safari").isEmpty)
        #expect(Companions.pair(forBundleID: "com.apple.dt.xcode", name: "Xcode") == nil)
    }

    @Test("A website finds its app, subdomains included")
    func byHost() {
        #expect(Companions.pair(forHost: "m.youtube.com")?.title == "YouTube")
        #expect(Companions.pair(forHost: "https://old.reddit.com/r/all")?.title == "Reddit")
        #expect(Companions.pair(forHost: "twitter.com")?.title == "X")
    }

    @Test("The longest host wins, so YouTube Music is not YouTube")
    func longestHostWins() {
        #expect(Companions.pair(forHost: "music.youtube.com")?.title == "YouTube Music")
        #expect(Companions.pair(forHost: "www.youtube.com")?.title == "YouTube")
    }

    @Test("The name to show keeps the case the table wrote it in")
    func title() {
        #expect(Companions.pair(forBundleID: "com.openai.chat", name: "")?.title == "ChatGPT")
        #expect(Companions.pair(forBundleID: "", name: "youtube music")?.title == "YouTube Music")
        #expect(Companions.pair(forHost: "primevideo.com")?.title == "Prime Video")
    }

    @Test("An empty name matches nothing, so an app with no learned name offers nothing")
    func emptyNameMatchesNothing() {
        #expect(Companions.pair(forBundleID: "", name: "") == nil)
        #expect(Companions.missingHosts(forAppNamed: "", knownHosts: []).isEmpty)
    }

    // MARK: The phone's half

    @Test("A named app offers the sites Furlough does not have")
    func missingHosts() {
        #expect(Companions.missingHosts(forAppNamed: "YouTube", knownHosts: []) == ["youtube.com"])
        #expect(Companions.missingHosts(forAppNamed: "  chatgpt ", knownHosts: []) == ["chatgpt.com", "chat.openai.com"])
        #expect(Companions.missingHosts(forAppNamed: "Xcode", knownHosts: []).isEmpty)
    }

    @Test("A site already in Furlough is not offered again, subdomains included")
    func missingHostsSkipsWhatIsIn() {
        #expect(Companions.missingHosts(forAppNamed: "YouTube", knownHosts: ["youtube.com"]).isEmpty)
        #expect(Companions.missingHosts(forAppNamed: "YouTube", knownHosts: ["m.youtube.com"]).isEmpty)
        #expect(Companions.missingHosts(forAppNamed: "ChatGPT", knownHosts: ["chatgpt.com"]) == ["chat.openai.com"])
        // The other way round is not a match: youtube.com does not cover music.youtube.com.
        #expect(Companions.missingHosts(forAppNamed: "YouTube Music", knownHosts: ["youtube.com"]) == ["music.youtube.com"])
    }

    @Test("A named site says which app to look for")
    func missingApp() {
        #expect(Companions.missingApp(forHost: "m.youtube.com", knownAppNames: []) == "YouTube")
        #expect(Companions.missingApp(forHost: "twitter.com", knownAppNames: []) == "X")
        #expect(Companions.missingApp(forHost: "example.org", knownAppNames: []) == nil)
    }

    @Test("An app Furlough already has is not asked for again, under any of its names")
    func missingAppSkipsWhatIsIn() {
        #expect(Companions.missingApp(forHost: "x.com", knownAppNames: ["X"]) == nil)
        #expect(Companions.missingApp(forHost: "x.com", knownAppNames: ["Twitter"]) == nil)
        #expect(Companions.missingApp(forHost: "primevideo.com", knownAppNames: ["Amazon Prime Video"]) == nil)
        #expect(Companions.missingApp(forHost: "x.com", knownAppNames: ["Safari", ""]) == "X")
    }

    @Test("A site with no app, or no site at all, is nobody's other half")
    func hostUnknown() {
        #expect(Companions.pair(forHost: "example.org") == nil)
        #expect(Companions.pair(forHost: "not a host") == nil)
    }

    @Test("Every pair can be found from each of its own hosts and identifiers")
    func tableIsConsistent() {
        for pair in Companions.pairs {
            #expect(!pair.names.isEmpty && !pair.hosts.isEmpty)
            for host in pair.hosts {
                #expect(Hosts.normalize(host) == host, "\(host) is not a normalized host")
                #expect(Companions.pair(forHost: host) == pair)
            }
            for bundleID in pair.bundleIDs {
                #expect(bundleID == bundleID.lowercased(), "\(bundleID) is not lowercased")
                #expect(Companions.pair(forBundleID: bundleID, name: "") == pair)
            }
            for name in pair.names {
                #expect(Companions.pair(forBundleID: "", name: name.uppercased()) == pair, "\(name) does not find its own pair")
            }
        }
    }

    /// Two pairs claiming the same host is a bug: `pair(forHost:)` answers with the first and
    /// the second becomes unreachable from the web side. A *subdomain* of another pair's host is
    /// the one legal overlap — music.youtube.com is YouTube Music, not YouTube — because the
    /// longest match wins, and that is tested above.
    @Test("No host or identifier is claimed by two pairs")
    func nothingIsClaimedTwice() {
        var hosts: [String: String] = [:]
        var bundleIDs: [String: String] = [:]
        for pair in Companions.pairs {
            for host in pair.hosts {
                #expect(hosts[host] == nil, "\(host) is claimed by both \(hosts[host] ?? "") and \(pair.title)")
                hosts[host] = pair.title
            }
            for bundleID in pair.bundleIDs {
                #expect(bundleIDs[bundleID] == nil, "\(bundleID) is claimed by both \(bundleIDs[bundleID] ?? "") and \(pair.title)")
                bundleIDs[bundleID] = pair.title
            }
        }
    }

    /// A name that normalizes to nothing would match every app whose name the shield has not
    /// learned yet, so the table must never carry one.
    @Test("Every name survives normalizing, and no pair is listed twice")
    func namesAreRealAndPairsAreDistinct() {
        var seen: [String: String] = [:]
        for pair in Companions.pairs {
            for name in pair.names {
                let key = Companions.normalize(name: name)
                #expect(!key.isEmpty, "\(pair.title) carries an empty name")
                #expect(seen[key] == nil, "\(name) names both \(seen[key] ?? "") and \(pair.title)")
                seen[key] = pair.title
            }
        }
        #expect(Set(Companions.pairs).count == Companions.pairs.count, "the table lists a pair twice")
    }
}
