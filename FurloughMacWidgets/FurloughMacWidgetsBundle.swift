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

/// The bundled faces, registered for this process. On the Mac a widget extension does not
/// pick up `ATSApplicationFontsPath` the way the app does, so the fonts are registered by
/// hand from the Fonts folder that ships with the extension.
enum WidgetFonts {
    static func register() {
        guard let folder = Bundle.main.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let urls = files.filter { $0.pathExtension.lowercased() == "ttf" }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
