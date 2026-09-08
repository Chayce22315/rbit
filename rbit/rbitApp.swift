import SwiftUI

@main
struct RbitApp: App {
    init() {
        RbitPairingController.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
