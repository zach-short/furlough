import SwiftUI

@main
struct FurloughApp: App {
    /// The notification delegate has to exist before launch finishes; see `NotificationDelegate`.
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { model.activate() }
                }
        }
    }
}
