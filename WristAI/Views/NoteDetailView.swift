import SwiftUI
import AVFoundation

struct NoteDetailView: View {
    @Environment(PhoneStore.self) private var store
    let note: VoiceNote

    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                audioPlayerCard

                if let summary = note.summary, !summary.isEmpty {
                    summaryCard(summary)
                }

                if !note.todos.isEmpty {
                    todosCard
                }

                if let transcription = note.transcription {
                    transcriptionCard(transcription)
                } else if note.transcriptionStatus == .pending {
                    pendingCard
                } else if note.transcriptionStatus == .failed {
                    failedCard
                }
            }
            .padding()
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopPlayback() }
    }

    // MARK: - Audio Player Card
    private var audioPlayerCard: some View {
        HStack(spacing: 16) {
            Button(action: togglePlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(Color.red)
                            .frame(width: geo.size.width * playbackProgress)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(player?.currentTime ?? 0))
                    Spacer()
                    Text(store.formatDuration(note.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                Text(note.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Summary Card
    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 摘要", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            Text(summary)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Todos Card
    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            let pendingCount = note.todos.filter { !$0.isCompleted }.count
            Label("待办 (\(pendingCount))", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            ForEach(note.todos) { todo in
                Button(action: { store.toggleTodo(todo, in: note) }) {
                    HStack {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        Text(todo.text)
                            .strikethrough(todo.isCompleted)
                            .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    }
                    .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Transcription Card
    private func transcriptionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("完整转录", systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Pending / Failed
    private var pendingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在转录…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var failedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("转录失败")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重试") {
                store.transcribe(note)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Audio Playback
    private func togglePlay() {
        if isPlaying {
            stopPlayback()
        } else {
            guard let url = store.audioURL(for: note) else { return }
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = PlayDelegate.shared
            player?.play()
            isPlaying = true
            startPlaybackTimer()
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackProgress = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player, player.duration > 0 else { return }
            DispatchQueue.main.async {
                playbackProgress = player.currentTime / player.duration
                if !player.isPlaying {
                    stopPlayback()
                }
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private final class PlayDelegate: NSObject, AVAudioPlayerDelegate {
    static let shared = PlayDelegate()
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        NotificationCenter.default.post(name: .audioFinished, object: nil)
    }
}

extension Notification.Name {
    static let audioFinished = Notification.Name("audioFinished")
}
