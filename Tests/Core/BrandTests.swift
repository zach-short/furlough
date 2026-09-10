import Foundation
import Testing

/// What the usage page can call an app before Screen Time says: the tables' name for its bundle
/// identifier, and the colour and letter its tile carries until the real icon lands. See `Brand`.
@Suite("Brand")
struct BrandTests {
    @Test("a bundle identifier the tables know is named without asking Screen Time")
    func namesFromTheTables() {
        #expect(Brand.name(forKey: "com.burbn.instagram") == "Instagram")
        #expect(Brand.name(forKey: "com.zhiliaoapp.musically") == "TikTok")
        #expect(Brand.name(forKey: "com.google.ios.youtube") == "YouTube")
        // AppUtility knows more apps than are also websites.
        #expect(Brand.name(forKey: "net.kortina.labs.venmo") == "Venmo")
    }

    @Test("a domain is its own name, and an unknown identifier has none")
    func domainsAndStrangers() {
        #expect(Brand.name(forKey: "web:youtube.com") == "youtube.com")
        #expect(Brand.name(forKey: "com.example.nobody") == nil)
    }

    @Test("the colour is keyed by identifier, and a site answers through its app")
    func colours() {
        #expect(Brand.color(forKey: "com.burbn.instagram") == 0xE1306C)
        #expect(Brand.color(forKey: "COM.BURBN.INSTAGRAM") == 0xE1306C)
        #expect(Brand.color(forKey: "web:youtube.com") == 0xFF0000)
        #expect(Brand.color(forKey: "web:m.youtube.com") == 0xFF0000)
        #expect(Brand.color(forKey: "web:example.com") == nil)
        #expect(Brand.color(forKey: "com.example.nobody") == nil)
    }

    /// A colour is only ever drawn under a letter, and the letter comes from the name, so a
    /// colour for an identifier the tables cannot name is dead weight — or a sign the name is
    /// missing from `AppUtility.properNameByBundleID`.
    @Test("every colour in the table belongs to an identifier the tables can name")
    func everyColourHasAName() {
        for key in Brand.colors.keys.sorted() {
            #expect(Brand.name(forKey: key) != nil, "\(key) has a colour but no name")
        }
    }

    @Test("the tile carries the first letter, uppercased")
    func monograms() {
        #expect(Brand.monogram("YouTube") == "Y")
        #expect(Brand.monogram("monday.com") == "M")
        #expect(Brand.monogram("X") == "X")
        #expect(Brand.monogram("  ") == nil)
    }

    @Test("light tiles take dark lettering, dark tiles cream")
    func lettering() {
        #expect(Brand.isLight(0xFFFC00), "Snapchat")
        #expect(Brand.isLight(0x1CE783), "Hulu")
        #expect(!Brand.isLight(0xE1306C), "Instagram")
        #expect(!Brand.isLight(0x25D366), "WhatsApp")
        #expect(!Brand.isLight(Brand.ink))
    }
}
