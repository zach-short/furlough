import Foundation

// What the app and its web filter say to each other. Compiled into both, so the two cannot
// disagree about a name or a method.

/// Names shared by the app and the filter extension.
enum FilterXPC {
    /// The extension's bundle identifier: what `OSSystemExtensionRequest` activates and what
    /// `NEFilterProviderConfiguration.filterDataProviderBundleIdentifier` names.
    static let extensionID = "com.zachshort.furlough.mac.filter"
    /// The Mach service the extension listens on. macOS insists it start with one of the
    /// extension's App Groups, which is why the team-prefixed group is in front.
    static let serviceName = "X9V4L6HR2R.com.zachshort.furlough.filter"
}

/// What the app exports to the extension: somewhere to say that a connection was dropped, so the
/// floating card can explain it. Firefox and a Dock web app get no shield page, so the card is
/// all the explanation there is.
@objc protocol FilterListening {
    /// `app` is the bundle identifier of the process that opened the connection, or its path
    /// when the signature says nothing, or empty when nothing could be read.
    func blocked(host: String, in app: String)
}

/// What the extension exports to the app. Connecting is the registration; this just lets the app
/// confirm the extension is alive on the other end.
@objc protocol FilterControl {
    func hello(reply: @escaping @Sendable (Bool) -> Void)
}
