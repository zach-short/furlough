import Foundation
import NetworkExtension

// A system extension is a plain executable. This hands it to the Network Extension machinery,
// which instantiates `FilterDataProvider` from the `NEProviderClasses` map in Info.plist and
// calls it as flows open; nothing else ever runs here.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
