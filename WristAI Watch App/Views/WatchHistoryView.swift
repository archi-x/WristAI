import SwiftUI

struct WatchHistoryView: View {
    @State private var recordings: [WatchRecordingMeta] = []

    var body: some View {
        NavigationStack {
            List {
                if recordings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("还没有录音")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("在上一页点按红色按钮开始")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(recordings) { rec in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "iphone.gen3")
                                    .foregroundStyle(.orange)
                                    .font(.caption2)
                                Text(formatDate(rec.createdAt))
                                    .font(.caption2.weight(.medium))
                            }
                            Text(formatDuration(rec.duration))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteRecording(rec)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("录音列表")
        }
        .onAppear { reload() }
    }

    private func reload() {
        let raw = UserDefaults.standard.array(forKey: "watchRecordings") as? [[String: Any]] ?? []
        recordings = raw.compactMap { dict in
            guard let fileName = dict["fileName"] as? String,
                  let createdAt = dict["createdAt"] as? TimeInterval,
                  let duration = dict["duration"] as? TimeInterval else { return nil }
            return WatchRecordingMeta(fileName: fileName, createdAt: Date(timeIntervalSince1970: createdAt), duration: duration)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func deleteRecording(_ rec: WatchRecordingMeta) {
        let raw = UserDefaults.standard.array(forKey: "watchRecordings") as? [[String: Any]] ?? []
        let filtered = raw.filter { ($0["fileName"] as? String) != rec.fileName }
        UserDefaults.standard.set(filtered, forKey: "watchRecordings")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings")
        let fileURL = dir.appendingPathComponent(rec.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        reload()
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

struct WatchRecordingMeta: Identifiable {
    let id = UUID()
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
}
