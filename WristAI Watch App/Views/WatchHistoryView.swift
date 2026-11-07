import SwiftUI

struct WatchHistoryView: View {
    @Environment(RecordingStore.self) private var store
    @Environment(WatchPlayer.self) private var player

    var body: some View {
        NavigationStack {
            List {
                if store.recordings.isEmpty {
                    emptyState
                } else {
                    ForEach(store.recordings) { rec in
                        row(for: rec)
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(rec)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }

                    Text("共 \(store.recordings.count) 条 · \(AudioFileMeta.formatBytes(store.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("录音列表")
        }
        .task { store.loadRecordings() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
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
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for rec: WatchRecording) -> some View {
        let isCurrent = player.currentFileName == rec.fileName
        let isPlaying = isCurrent && player.isPlaying

        Button {
            player.toggle(url: rec.fileURL)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isCurrent ? Color.green : Color.accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Label(formatDate(rec.createdAt), systemImage: "clock")
                                .font(.caption2.weight(.medium))
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)

                            Spacer(minLength: 2)

                            Text(rec.formatLabel)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.22))
                                )
                        }

                        HStack(spacing: 4) {
                            Text(isCurrent
                                 ? "\(formatDuration(player.currentTime)) / \(rec.displayDuration)"
                                 : rec.displayDuration)
                                .monospacedDigit()

                            Text("·")
                                .foregroundStyle(.tertiary)

                            Text(rec.displayFileSize)
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)
                }

                if isCurrent && player.duration > 0 {
                    ProgressView(value: player.progress)
                        .progressViewStyle(.linear)
                        .tint(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func delete(_ rec: WatchRecording) {
        player.handleDeleted(fileName: rec.fileName)
        store.deleteRecording(named: rec.fileName)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")

        if cal.isDateInToday(date) {
            f.dateFormat = "今天 HH:mm"
        } else if cal.isDateInYesterday(date) {
            f.dateFormat = "昨天 HH:mm"
        } else if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            f.dateFormat = "M月d日 HH:mm"
        } else {
            f.dateFormat = "yyyy年M月d日"
        }
        return f.string(from: date)
    }
}
