import Foundation
import Testing

@Suite("ActivityNaming")
struct ActivityNamingTests {
    @Test("a window's name round-trips back into the span")
    func windows() {
        let evening = window(1200, 1320, .weekend)
        #expect(ActivityNaming.window(evening) == "window:1200-1320")
        // The days are deliberately not in the name: one activity covers every day of a span.
        #expect(ActivityNaming.parseWindow(ActivityNaming.window(evening)) == evening.span)
        #expect(ActivityNaming.parseWindow("window:0-1440") == window(0, 1440))
    }

    @Test("anything that is not a window name parses to nothing")
    func badWindows() {
        #expect(ActivityNaming.parseWindow(ActivityNaming.day) == nil)
        #expect(ActivityNaming.parseWindow("window:abc-def") == nil)
        #expect(ActivityNaming.parseWindow("window:1200") == nil)
        #expect(ActivityNaming.parseWindow("budget:1200-1320") == nil)
    }

    @Test("a budget event carries the target and the minutes")
    func budgets() {
        let id = UUID()
        let name = ActivityNaming.budgetEvent(targetID: id, minutes: 30)
        #expect(name == "budget:\(id.uuidString):30")
        let parsed = ActivityNaming.parseBudgetEvent(name)
        #expect(parsed?.targetID == id)
        #expect(parsed?.minutes == 30)
    }

    @Test("a malformed budget event parses to nothing")
    func badBudgets() {
        #expect(ActivityNaming.parseBudgetEvent("budget:not-a-uuid:30") == nil)
        #expect(ActivityNaming.parseBudgetEvent("budget:\(UUID().uuidString):lots") == nil)
        #expect(ActivityNaming.parseBudgetEvent("window:1200-1320") == nil)
        #expect(ActivityNaming.parseBudgetEvent(ActivityNaming.day) == nil)
    }
}

@Suite("Hosts")
struct HostsTests {
    @Test("an address becomes the bare host")
    func normalize() {
        #expect(Hosts.normalize("https://www.YouTube.com/watch?v=1") == "youtube.com")
        #expect(Hosts.normalize("youtube.com") == "youtube.com")
        #expect(Hosts.normalize("  M.Youtube.COM  ") == "m.youtube.com")
        #expect(Hosts.normalize("http://news.ycombinator.com/item?id=1") == "news.ycombinator.com")
        #expect(Hosts.normalize("sub.domain.co.uk/path") == "sub.domain.co.uk")
    }

    @Test("things that are not hosts are refused")
    func rejects() {
        #expect(Hosts.normalize("") == nil)
        #expect(Hosts.normalize("   ") == nil)
        #expect(Hosts.normalize("localhost") == nil)
        #expect(Hosts.normalize("what is this") == nil)
    }

    @Test("a rule covers its own host and every subdomain")
    func matches() {
        #expect(Hosts.matches("youtube.com", rule: "youtube.com"))
        #expect(Hosts.matches("www.youtube.com", rule: "youtube.com"))
        #expect(Hosts.matches("m.youtube.com", rule: "youtube.com"))
        #expect(Hosts.matches("music.youtube.com", rule: "youtube.com"))
        #expect(!Hosts.matches("notyoutube.com", rule: "youtube.com"))
        #expect(!Hosts.matches("youtube.com.evil.test", rule: "youtube.com"))
        #expect(!Hosts.matches("youtube.co", rule: "youtube.com"))
    }
}
