import SwiftUI
import AVFoundation

struct NoteDetailView: View {
    @Environment(PhoneStore.self) private var store
    let note: VoiceNote

    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    /// Non-nil while dragging; leads `playbackProgress` so the knob tracks the finger.
    @State private var dragFraction: Double?
    @State private var isScrubbing = false
    /// Whether audio was moving when the drag started, so it can be restored.
    @State private var resumeAfterScrub = false

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
                progressBar

                HStack {
                    Text(formatTime(displayedTime))
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

    /// Draggable scrubber. The visible line stays 4 pt slim, but the touch area
    /// is 28 pt tall — a 4 pt target is unhittable with a thumb.
    private var progressBar: some View {
        GeometryReader { geo in
            let knob: CGFloat = isScrubbing ? 14 : 10
            let inset = knob / 2
            let trackWidth = max(geo.size.width - knob, 1)
            let value = min(max(dragFraction ?? playbackProgress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.red)
                    .frame(width: max(4, trackWidth * value), height: 4)

                Circle()
                    .fill(Color.red)
                    .frame(width: knob, height: knob)
                    .offset(x: trackWidth * value)
                    .animation(.easeOut(duration: 0.12), value: isScrubbing)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, inset)
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragFraction == nil { beginScrub() }
                        let f = fraction(for: drag.location.x, inset: inset, width: trackWidth)
                        dragFraction = f
                        applyScrub(f)
                    }
                    .onEnded { drag in
                        let f = fraction(for: drag.location.x, inset: inset, width: trackWidth)
                        applyScrub(f)
                        dragFraction = nil
                        endScrub()
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int((dragFraction ?? playbackProgress) * 100))%")
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            let current = dragFraction ?? playbackProgress
            switch direction {
            case .increment: applyScrub(min(1, current + step))
            case .decrement: applyScrub(max(0, current - step))
            @unknown default: break
            }
        }
    }

    private func fraction(for x: CGFloat, inset: CGFloat, width: CGFloat) -> Double {
        min(max(Double((x - inset) / width), 0), 1)
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

    /// Time shown under the bar — follows the finger while scrubbing.
    private var displayedTime: TimeInterval {
        if let dragFraction, let total = player?.duration, total > 0 {
            return dragFraction * total
        }
        return player?.currentTime ?? 0
    }

    private func togglePlay() {
        if isPlaying {
            pausePlayback()
        } else {
            guard let player = ensurePlayer() else { return }
            player.play()
            isPlaying = true
            startPlaybackTimer()
        }
    }

    /// Loads the file on first use. Scrubbing before ever hitting play still
    /// works because this gives us a player and its real duration.
    @discardableResult
    private func ensurePlayer() -> AVAudioPlayer? {
        if let player { return player }
        guard let url = store.audioURL(for: note) else { return nil }
        guard let fresh = try? AVAudioPlayer(contentsOf: url) else { return nil }
        fresh.delegate = PlayDelegate.shared
        fresh.prepareToPlay()
        player = fresh
        return fresh
    }

    private func beginScrub() {
        guard ensurePlayer() != nil else { return }
        isScrubbing = true
        resumeAfterScrub = isPlaying
        if isPlaying { pausePlayback() }
    }

    private func applyScrub(_ fraction: Double) {
        guard let player, player.duration > 0 else { return }
        let target = min(max(fraction, 0), 1) * player.duration
        player.currentTime = target
        playbackProgress = min(max(fraction, 0), 1)
    }

    private func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        let shouldResume = resumeAfterScrub
        resumeAfterScrub = false
        if shouldResume, let player {
            player.play()
            isPlaying = true
            startPlaybackTimer()
        }
    }

    private func pausePlayback() {
        player?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        isScrubbing = false
        resumeAfterScrub = false
        dragFraction = nil
        playbackProgress = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player, player.duration > 0 else { return }
            DispatchQueue.main.async {
                guard !isScrubbing else { return }
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
