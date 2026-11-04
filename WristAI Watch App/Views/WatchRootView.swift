import SwiftUI

struct WatchRootView: View {
    @Environment(RecordingStore.self) private var store

    var body: some View {
        TabView {
            RecordingView()
                .tabItem { Label("录音", systemImage: "mic.fill") }

            WatchHistoryView()
                .tabItem { Label("列表", systemImage: "list.bullet") }
        }
    }
}
