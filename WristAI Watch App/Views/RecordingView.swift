import SwiftUI

struct RecordingView: View {
    @Environment(RecordingStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            // Timer
            Text(formatTime(store.elapsedTime))
                .font(.system(.title2, design: .monospaced).weight(.medium))
                .foregroundStyle(store.isRecording ? .red : .primary)
                .contentTransition(.numericText())

            // Waveform
            if store.isRecording {
                WaveformView(levels: store.audioLevels)
                    .frame(height: 50)
                    .padding(.horizontal, 4)
            }

            // Record Button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(store.isRecording ? Color.red.opacity(0.2) : Color.red)
                        .frame(width: 80, height: 80)

                    if store.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 100, height: 100)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .heavy), trigger: store.isRecording)

            // Status label
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Pause/Resume
            if store.isRecording {
                Button(store.isPaused ? "继续" : "暂停") {
                    if store.isPaused {
                        store.resumeRecording()
                    } else {
                        store.pauseRecording()
                    }
                }
                .font(.caption)
            }

            // Permission denied warning
            if store.permissionDenied {
                Label("麦克风权限被拒绝", systemImage: "mic.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusText: String {
        if store.permissionDenied {
            return "请在设置中开启麦克风权限"
        }
        if store.isRecording {
            return store.isPaused ? "已暂停" : "录音中"
        }
        return "点按开始录音"
    }

    private func toggleRecording() {
        if store.isRecording {
            if let result = store.stopRecording() {
                let createdAt = Date()
                store.registerRecording(
                    fileName: result.url.lastPathComponent,
                    createdAt: createdAt,
                    duration: result.duration
                )
                ConnectivityManager.shared.sendRecording(url: result.url, createdAt: createdAt, duration: result.duration)
                store.lastRecordingInfo = (fileName: result.url.lastPathComponent, duration: result.duration, transferred: false)
            }
        } else {
            store.startRecording()
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 4, height: max(4, CGFloat(level) * 50))
                    .animation(.easeOut(duration: 0.05), value: levels)
            }
        }
    }
}
