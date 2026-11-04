import SwiftUI

@main
struct WristAIWatchApp: App {
    @State private var store = RecordingStore()

    init() {
        ConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}
