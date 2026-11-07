import SwiftUI

@main
struct WristAIWatchApp: App {
    @State private var store = RecordingStore()
    @State private var player = WatchPlayer()

    init() {
        ConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .environment(player)
        }
    }
}
