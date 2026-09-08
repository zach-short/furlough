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
        #expect(Companions.pair(forHost: "m.youtube.com")?.names == ["youtube"])
        #expect(Companions.pair(forHost: "https://old.reddit.com/r/all")?.names == ["reddit"])
        #expect(Companions.pair(forHost: "twitter.com")?.names == ["x", "twitter"])
    }

    @Test("The longest host wins, so YouTube Music is not YouTube")
    func longestHostWins() {
        #expect(Companions.pair(forHost: "music.youtube.com")?.names == ["youtube music"])
        #expect(Companions.pair(forHost: "www.youtube.com")?.names == ["youtube"])
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
                #expect(name == Companions.normalize(name: name), "\(name) is not normalized")
            }
        }
    }
}
