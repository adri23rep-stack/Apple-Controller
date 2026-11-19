import SwiftUI

@main
struct HydraIOSApp: App {
    var body: some Scene {
        WindowGroup {
            HydraRootView().preferredColorScheme(.dark)
        }
    }
}
