import Foundation
import NetworkExtension

// Hands off to Network Extension, which instantiates FilterDataProvider via the
// NEProviderClasses map in Info.plist.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
