import SwiftUI

@main
struct GaugesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(layoutStore: appDelegate.layoutStore, store: appDelegate.store)
        }
    }
}
