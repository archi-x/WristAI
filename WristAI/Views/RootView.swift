import SwiftUI

struct RootView: View {
    @Environment(PhoneStore.self) private var store
    @State private var selectedTab = 0
    @State private var showReceivedToast = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NotesListView()
                .tabItem { Label("笔记", systemImage: "note.text") }
                .tag(0)

            TodosView()
                .tabItem { Label("待办", systemImage: "checklist") }
                .tag(1)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: .receivedRecording)) { note in
            if let url = note.userInfo?["url"] as? URL,
               let date = note.userInfo?["date"] as? Date,
               let duration = note.userInfo?["duration"] as? TimeInterval {
                store.receiveRecording(url: url, createdAt: date, duration: duration)
                selectedTab = 0
                showReceivedToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showReceivedToast = false
                }
            }
        }
        .overlay(alignment: .top) {
            if showReceivedToast, let info = store.lastReceivedInfo {
                Label(
                    "收到录音 · \(store.formatDuration(info.duration))",
                    systemImage: "applewatch.watchface"
                )
                .font(.caption.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
                .animation(.spring(duration: 0.4), value: showReceivedToast)
            }
        }
    }
}
