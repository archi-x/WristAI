import Foundation
import AVFoundation

/// Manages received recordings from Watch and processes them through transcription + AI
@Observable
final class PhoneStore {
    var notes: [VoiceNote] = []
    var isProcessing = false
    var lastReceivedInfo: (fileName: String, duration: TimeInterval)?
    var transcriptionStatus: String = ""
    private var whisperPipe: WhisperKit?

    /// Cloud mirror, attached by the app once the user is signed in.
    @ObservationIgnored private var cloud: CloudSyncService?

    private var recordingsDir: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var dataFile: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notes.json")
    }

    init() {
        loadNotes()
    }

    // MARK: - Receive Recording from Watch
    func receiveRecording(url: URL, createdAt: Date, duration: TimeInterval) {
        let destURL = recordingsDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.moveItem(at: url, to: destURL)

        let note = VoiceNote(
            createdAt: createdAt,
            duration: duration,
            fileName: url.lastPathComponent,
            transcriptionStatus: .pending,
            title: formatDuration(duration)
        )
        notes.insert(note, at: 0)
        saveNotes()
        lastReceivedInfo = (fileName: url.lastPathComponent, duration: duration)
        syncUp(note)

        // Auto-transcribe immediately
        transcribe(note)
    }

    // MARK: - Transcription (WhisperKit on-device)
    func transcribe(_ note: VoiceNote) {
        guard note.transcriptionStatus == .pending || note.transcriptionStatus == .failed else { return }
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }

        notes[idx].transcriptionStatus = .transcribing
        saveNotes()

        let audioURL = recordingsDir.appendingPathComponent(note.fileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            notes[idx].transcriptionStatus = .failed
            saveNotes()
            return
        }

        isProcessing = true
        transcriptionStatus = "准备转录…"

        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.runWhisperKit(audioPath: audioURL.path)

                await MainActor.run {
                    guard let idx = self.notes.firstIndex(where: { $0.id == note.id }) else { return }
                    let (title, summary, todos) = AIEngine.process(text)
                    self.notes[idx].transcription = text
                    self.notes[idx].title = title
                    self.notes[idx].summary = summary
                    self.notes[idx].todos = todos
                    self.notes[idx].transcriptionStatus = .completed
                    self.saveNotes()
                    self.syncUp(self.notes[idx])
                    self.isProcessing = false
                    self.transcriptionStatus = ""
                }
            } catch {
                await MainActor.run {
                    guard let idx = self.notes.firstIndex(where: { $0.id == note.id }) else { return }
                    self.notes[idx].transcriptionStatus = .failed
                    self.notes[idx].transcription = "转录失败：\(error.localizedDescription)"
                    self.saveNotes()
                    self.isProcessing = false
                    self.transcriptionStatus = ""
                }
            }
        }
    }

    // MARK: - WhisperKit Engine
    private func runWhisperKit(audioPath: String) async throws -> String {
        if whisperPipe == nil {
            transcriptionStatus = "正在加载 AI 模型（首次较慢）…"
            whisperPipe = try await WhisperKit(model: "base", verbose: false, download: true)
        }
        transcriptionStatus = "正在转录音频…"
        let results: [TranscriptionResult] = try await whisperPipe!.transcribe(audioPath: audioPath)
        return results.map(\.text).joined(separator: " ")
    }

    // MARK: - CRUD
    func deleteNote(_ note: VoiceNote) {
        notes.removeAll { $0.id == note.id }
        let audioURL = recordingsDir.appendingPathComponent(note.fileName)
        try? FileManager.default.removeItem(at: audioURL)
        fileSizeCache[note.fileName] = nil
        saveNotes()
        if let cloud {
            Task { await cloud.delete(noteID: note.id) }
        }
    }

    func toggleTodo(_ todo: TodoItem, in note: VoiceNote) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        if let todoIdx = notes[idx].todos.firstIndex(where: { $0.id == todo.id }) {
            notes[idx].todos[todoIdx].isCompleted.toggle()
            saveNotes()
            syncUp(notes[idx])
        }
    }

    func audioURL(for note: VoiceNote) -> URL? {
        let url = recordingsDir.appendingPathComponent(note.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// On-disk size of a note's audio file, cached so the list doesn't stat on every redraw.
    @ObservationIgnored private var fileSizeCache: [String: Int64] = [:]

    func fileSize(for note: VoiceNote) -> Int64? {
        if let cached = fileSizeCache[note.fileName] { return cached }
        let url = recordingsDir.appendingPathComponent(note.fileName)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size > 0 else { return nil }
        fileSizeCache[note.fileName] = Int64(size)
        return Int64(size)
    }

    /// `M4A · 128 KB` — falls back to the format alone when the audio is gone.
    func fileDescription(for note: VoiceNote) -> String {
        guard let bytes = fileSize(for: note) else { return note.formatLabel }
        return "\(note.formatLabel) · \(AudioFileMeta.formatBytes(bytes))"
    }

    var totalAudioSize: Int64 {
        notes.reduce(0) { $0 + (fileSize(for: $1) ?? 0) }
    }

    // MARK: - Persistence
    private func saveNotes() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: dataFile, options: .atomic)
        }
    }

    private func loadNotes() {
        guard let data = try? Data(contentsOf: dataFile),
              let loaded = try? JSONDecoder().decode([VoiceNote].self, from: data) else { return }
        notes = loaded
    }

    // MARK: - Cloud Sync
    func attachCloud(_ cloud: CloudSyncService) {
        self.cloud = cloud
    }

    /// Push one note (metadata + audio on first upload) to iCloud.
    private func syncUp(_ note: VoiceNote) {
        guard let cloud else { return }
        let url = audioURL(for: note)
        Task { await cloud.push(note: note, audioURL: url) }
    }

    /// Pull remote notes and merge them into the local library.
    ///
    /// Conflict rule: a local note that already carries a transcription wins,
    /// because re-downloading would throw away on-device ASR work. Otherwise the
    /// remote copy replaces the local placeholder.
    func syncFromCloud() async {
        guard let cloud else { return }
        let remotes = await cloud.pullAll(into: recordingsDir)
        guard !remotes.isEmpty else { return }

        var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        for remote in remotes {
            guard let local = byID[remote.note.id] else {
                byID[remote.note.id] = remote.note
                continue
            }
            let localHasText = !(local.transcription ?? "").isEmpty
            let remoteHasText = !(remote.note.transcription ?? "").isEmpty
            if !localHasText && remoteHasText {
                byID[remote.note.id] = remote.note
            } else if !localHasText && local.transcriptionStatus != .completed {
                byID[remote.note.id] = remote.note
            }
        }

        notes = byID.values.sorted { $0.createdAt > $1.createdAt }
        saveNotes()
    }

    /// Forget the cloud mirror (used on sign-out; local data stays put).
    func detachCloud() {
        cloud = nil
    }

    // MARK: - Helpers
    func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Stats
    var pendingCount: Int { notes.filter { $0.transcriptionStatus == .pending }.count }
    var allTodos: [(note: VoiceNote, todo: TodoItem)] {
        notes.flatMap { note in
            note.todos.filter { !$0.isCompleted }.map { (note, $0) }
        }
    }
}
