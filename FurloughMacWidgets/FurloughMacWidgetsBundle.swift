import CoreText
import SwiftUI
import WidgetKit

@main
struct FurloughMacWidgetsBundle: WidgetBundle {
    init() {
        WidgetFonts.register()
    }

    var body: some Widget {
        MacStatusWidget()
    }
}

/// Mac widget extensions don't pick up `ATSApplicationFontsPath` like the app does, so fonts
/// are registered by hand from the bundled Fonts folder.
enum WidgetFonts {
    static func register() {
        guard let folder = Bundle.main.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let urls = files.filter { $0.pathExtension.lowercased() == "ttf" }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
