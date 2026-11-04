import SwiftUI

@main
struct WristAIApp: App {
    @State private var store = PhoneStore()

    init() {
        PhoneConnectivity.shared.activate()
        PhoneConnectivity.shared.onReceiveRecording = { url, date, duration in
            // Will be connected in ContentView via environment
            NotificationCenter.default.post(
                name: .receivedRecording,
                object: nil,
                userInfo: ["url": url, "date": date, "duration": duration]
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

extension Notification.Name {
    static let receivedRecording = Notification.Name("receivedRecording")
}
