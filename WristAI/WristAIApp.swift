import SwiftUI

@main
struct WristAIApp: App {
    @State private var store = PhoneStore()
    @State private var auth = AuthService()
    @State private var cloud = CloudSyncService()

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
            AppGate()
                .environment(store)
                .environment(auth)
                .environment(cloud)
        }
    }
}

/// Chooses between the sign-in screen and the main app, and owns the
/// sign-in → cloud-bootstrap → initial-pull sequence.
struct AppGate: View {
    @Environment(PhoneStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(CloudSyncService.self) private var cloud

    var body: some View {
        Group {
            if auth.isSignedIn {
                RootView()
                    .transition(.opacity)
            } else {
                LogonView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isSignedIn)
        .task { await boot() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            Task {
                if signedIn {
                    await startCloudSync()
                } else {
                    store.detachCloud()
                }
            }
        }
    }

    private func boot() async {
        await auth.refreshCredentialState()
        guard auth.isSignedIn else { return }
        await startCloudSync()
    }

    private func startCloudSync() async {
        store.attachCloud(cloud)
        await cloud.bootstrap()
        guard cloud.isUsable else { return }
        await store.syncFromCloud()
    }
}

extension Notification.Name {
    static let receivedRecording = Notification.Name("receivedRecording")
}
