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

        VStack(alignment: .leading, spacing: 6) {
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
            // Tap anywhere on the text row to play/pause; the scrub bar below
            // owns horizontal drags, so the two never fight over the gesture.
            .contentShape(Rectangle())
            .onTapGesture { player.toggle(url: rec.fileURL) }

            if isCurrent && player.duration > 0 {
                ScrubBar(
                    fraction: player.progress,
                    isScrubbing: player.isScrubbing,
                    onScrubStart: { player.beginScrubbing() },
                    onScrub: { player.scrub(toFraction: $0) },
                    onScrubEnd: { player.endScrubbing() }
                )
            }
        }
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

// MARK: - Scrub Bar

/// A draggable playback progress bar sized for a 40 mm watch face.
///
/// Not a `Slider`: on watchOS the stock thumb is too fat for a list row and it
/// brings its own tint/haptics we can't align with the row's green play state.
/// A plain `DragGesture` on a capsule also lets a tap jump straight to a point,
/// which is the fastest way to rewind a few seconds on a tiny screen.
private struct ScrubBar: View {
    /// 0...1 position reported by the player.
    let fraction: Double
    let isScrubbing: Bool
    let onScrubStart: () -> Void
    let onScrub: (Double) -> Void
    let onScrubEnd: () -> Void

    /// Local copy of the drag position. It leads `fraction` by one frame, which
    /// is what keeps the knob glued to the finger instead of stuttering behind.
    @State private var dragFraction: Double?

    private let trackHeight: CGFloat = 6
    private let knobSize: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let inset = knobSize / 2
            let trackWidth = max(geo.size.width - knobSize, 1)
            let value = min(max(dragFraction ?? fraction, 0), 1)
            let knob = isScrubbing ? knobSize + 3 : knobSize

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.green)
                    .frame(width: max(trackHeight, trackWidth * value), height: trackHeight)

                Circle()
                    .fill(Color.green)
                    .frame(width: knob, height: knob)
                    .offset(x: trackWidth * value + inset - knob / 2)
                    .animation(.easeOut(duration: 0.12), value: isScrubbing)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, inset)
            // A 26 pt tall hit area keeps the 6 pt track usable with a fingertip.
            .frame(height: 26)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragFraction == nil { onScrubStart() }
                        let f = fraction(for: value.location.x, inset: inset, width: trackWidth)
                        dragFraction = f
                        onScrub(f)
                    }
                    .onEnded { value in
                        let f = fraction(for: value.location.x, inset: inset, width: trackWidth)
                        onScrub(f)
                        dragFraction = nil
                        onScrubEnd()
                    }
            )
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int((dragFraction ?? fraction) * 100))%")
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            let current = dragFraction ?? fraction
            switch direction {
            case .increment: onScrub(min(1, current + step))
            case .decrement: onScrub(max(0, current - step))
            @unknown default: break
            }
        }
    }

    private func fraction(for x: CGFloat, inset: CGFloat, width: CGFloat) -> Double {
        let raw = (x - inset) / width
        return min(max(Double(raw), 0), 1)
    }
}
