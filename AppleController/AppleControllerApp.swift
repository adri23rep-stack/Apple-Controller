import SwiftUI

@main
struct AppleControllerApp: App {
    var body: some Scene {
        WindowGroup {
            RemoteScreen()
                .preferredColorScheme(.dark)
        }
    }
}
