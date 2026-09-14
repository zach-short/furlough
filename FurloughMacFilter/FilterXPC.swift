import Foundation

// Compiled into both app and filter so they can't disagree on a name or method.

enum FilterXPC {
    /// What `OSSystemExtensionRequest` activates and `filterDataProviderBundleIdentifier` names.
    static let extensionID = "com.zachshort.furlough.mac.filter"
    /// macOS requires the Mach service name start with one of the extension's App Groups, hence the team prefix.
    static let serviceName = "X9V4L6HR2R.com.zachshort.furlough.filter"
}

/// Lets the extension report a drop so the floating card can explain it — Firefox and Dock web apps get no shield page otherwise.
@objc protocol FilterListening {
    /// Bundle identifier of the opening process, its path if unsigned, or empty if unreadable.
    func blocked(host: String, in app: String)
}

/// Lets the app confirm the extension is alive; connecting is the registration itself.
@objc protocol FilterControl {
    func hello(reply: @escaping @Sendable (Bool) -> Void)
}
