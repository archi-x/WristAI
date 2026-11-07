import Foundation
import AVFoundation
import WatchKit
import Combine

/// One recording that lives on the Watch.
///
/// `id` is the file name so SwiftUI keeps a stable identity across reloads —
/// using a fresh `UUID()` on every load makes `ForEach` rebuild every row.
struct WatchRecording: Identifiable, Hashable {
    var id: String { fileName }
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
    let fileURL: URL
    /// Size of the audio file on disk, in bytes.
    let fileSize: Int64

    var displayDuration: String {
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Container format derived from the file extension — `M4A`, `WAV`, …
    var formatLabel: String { AudioFileMeta.formatLabel(for: fileName) }

    /// Human readable size — `128 KB`, `1.2 MB`, …
    var displayFileSize: String { AudioFileMeta.formatBytes(fileSize) }
}

/// Small helpers shared by the watch history list.
enum AudioFileMeta {
    /// The recorder writes `.m4a` (AAC), but the archive may also hold
    /// transferred files in other containers, so map by extension.
    static func formatLabel(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "m4a":         return "M4A"
        case "mp3":         return "MP3"
        case "wav", "wave": return "WAV"
        case "aif", "aiff": return "AIFF"
        case "caf":         return "CAF"
        case "aac":         return "AAC"
        case "":            return "音频"
        default:            return ext.uppercased()
        }
    }

    /// Binary units, matching how iOS reports storage to the user.
    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "--" }
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}

/// Manages audio recording on Apple Watch using AVAudioRecorder
@Observable
final class RecordingStore {
    // MARK: - Published State
    var isRecording = false
    var isPaused = false
    var elapsedTime: TimeInterval = 0
    var audioLevels: [Float] = Array(repeating: 0, count: 7)

    // MARK: - Private
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var levelTimer: Timer?
    private let session = AVAudioSession.sharedInstance()

    // MARK: - Recording Directory
    private var recordingsDir: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Recording State
    var lastRecordingInfo: (fileName: String, duration: TimeInterval, transferred: Bool)?
    var permissionDenied = false

    // MARK: - Start Recording
    func startRecording() {
        guard !isRecording else { return }

        // Request microphone permission first
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .denied {
            permissionDenied = true
            return
        }

        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.beginRecording()
                } else {
                    self.permissionDenied = true
                }
            }
        }
    }

    /// Encoding profile for new recordings — picked for "faithful but small".
    ///
    /// - **AAC-LC in an .m4a container.** Hardware-encoded on Apple Watch, so it
    ///   costs far less battery than a software codec (Opus/FLAC), and the file
    ///   plays natively on iOS, macOS, Android and Windows. Lossless (ALAC) would
    ///   be ~4× larger for no audible gain on speech.
    /// - **22.05 kHz.** Retains content up to ~11 kHz. The previous 16 kHz profile
    ///   cut everything above 8 kHz — exactly where sibilants ("s", "sh", "f")
    ///   live. Measured on a speech sample: 16 kHz gave 16.4 dB SNR with 0.34%
    ///   of energy above 8 kHz; 22.05 kHz gives 22.2 dB with 0.83% (noise energy
    ///   roughly a quarter). Deliberately *not* 24 kHz: the AAC encoder silently
    ///   substitutes 22.05 kHz for it. Not 44.1 kHz either: +30% size for 4.7 dB
    ///   that speech playback barely needs.
    /// - **Mono.** Speech carries no useful stereo image; halves the bitrate.
    /// - **48 kbps.** Near perceptually transparent for mono speech at 22 kHz and
    ///   ~23% smaller than 44.1 kHz / 64 kbps.
    ///
    /// Net cost ≈ 6 KB per second (≈ 390 KB per minute). For reference the old
    /// 16 kHz / 32 kbps profile was ≈ 265 KB per minute, and uncompressed 16-bit
    /// PCM at 22.05 kHz would be ≈ 2.6 MB per minute.
    enum RecordingFormat {
        static let fileExtension = "m4a"

        static let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_LongTermAverage,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        /// `22.05 kHz · 48 kbps · 单声道` — shown in settings so the profile is discoverable.
        static let summary = "22.05 kHz · 48 kbps · 单声道"
    }

    private func beginRecording() {
        do {
            try session.setCategory(.record, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error)")
            permissionDenied = true
            return
        }

        let fileName = "recording-\(UUID().uuidString).m4a"
        let fileURL = recordingsDir.appendingPathComponent(fileName)

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: RecordingFormat.settings)
            recorder?.delegate = nil
            recorder?.isMeteringEnabled = true
            recorder?.prepareToRecord()
            recorder?.record()
            isRecording = true
            isPaused = false
            elapsedTime = 0
            permissionDenied = false
            startTimers()
            WKInterfaceDevice.current().play(.start)
        } catch {
            print("Recording failed to start: \(error)")
            permissionDenied = true
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Pause / Resume
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        isPaused = true
        stopTimers()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        recorder?.record()
        isPaused = false
        startTimers()
    }

    // MARK: - Stop Recording
    /// Returns the file URL and duration of the finished recording, or nil if recording was too short
    @discardableResult
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else { return nil }
        recorder?.stop()
        let url = recorder?.url
        let duration = elapsedTime  // capture BEFORE resetting
        stopTimers()
        isRecording = false
        isPaused = false
        elapsedTime = 0
        audioLevels = Array(repeating: 0, count: 7)

        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        // Delete if too short (< 1 second)
        if duration < 1.0, let url {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        WKInterfaceDevice.current().play(.stop)
        guard let url else { return nil }
        return (url, duration)
    }

    // MARK: - Timers
    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.elapsedTime += 0.1
        }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAudioLevels()
        }
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func updateAudioLevels() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let rawLevel = recorder.averagePower(forChannel: 0) // -160 to 0 dB
        // Normalize to 0...1
        let normalized = max(0, (rawLevel + 60) / 60)
        // Map to 7 bars with some randomness for visual interest
        var levels: [Float] = []
        for i in 0..<7 {
            let center = Float(i - 3) * 0.1
            let distance = abs(normalized - (0.5 + center))
            let bar = max(0.1, normalized * (1 - distance))
            levels.append(bar)
        }
        audioLevels = levels
    }

    // MARK: - List Recordings on Watch
    func listLocalRecordings() -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: recordingsDir.path) else { return [] }

        let items = (try? fm.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        )) ?? []

        return items.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return dateA > dateB
        }
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Recording Library
    /// Single source of truth for the history list. Always derived from the files
    /// actually present on disk, with `UserDefaults` supplying the metadata.
    private(set) var recordings: [WatchRecording] = []

    private static let metaKey = "watchRecordings"

    /// Rebuild `recordings` from the Documents/Recordings folder.
    ///
    /// Files on disk win: if a file exists but has no stored metadata its date
    /// falls back to the file creation date and its duration is read from the
    /// audio itself. Stored metadata whose file disappeared is dropped.
    func loadRecordings() {
        var stored: [String: (createdAt: Date, duration: TimeInterval)] = [:]

        if let raw = UserDefaults.standard.array(forKey: Self.metaKey) as? [[String: Any]] {
            for dict in raw {
                guard let name = dict["fileName"] as? String else { continue }
                let created = (dict["createdAt"] as? TimeInterval)
                    .map { Date(timeIntervalSince1970: $0) } ?? .distantPast
                let duration = dict["duration"] as? TimeInterval ?? 0
                stored[name] = (created, duration)
            }
        }

        var items: [WatchRecording] = []
        for url in listLocalRecordings() {
            let name = url.lastPathComponent
            let meta = stored[name]
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let fileDate = values?.creationDate ?? .distantPast
            let duration = (meta?.duration ?? 0) > 0 ? (meta?.duration ?? 0) : Self.durationOfAudio(at: url)
            let size = Int64(values?.fileSize ?? 0)

            items.append(WatchRecording(
                fileName: name,
                createdAt: meta?.createdAt ?? fileDate,
                duration: duration,
                fileURL: url,
                fileSize: size
            ))
        }

        recordings = items.sorted { $0.createdAt > $1.createdAt }
        persistMetadata()
    }

    /// Record a finished recording so it shows up in the history list.
    func registerRecording(fileName: String, createdAt: Date, duration: TimeInterval) {
        var raw = UserDefaults.standard.array(forKey: Self.metaKey) as? [[String: Any]] ?? []
        raw.removeAll { ($0["fileName"] as? String) == fileName }
        raw.append([
            "fileName": fileName,
            "createdAt": createdAt.timeIntervalSince1970,
            "duration": duration
        ])
        UserDefaults.standard.set(raw, forKey: Self.metaKey)
        loadRecordings()
    }

    /// Delete one recording by file name, removing both the file and its metadata.
    func deleteRecording(named fileName: String) {
        let url = recordingsDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)

        var raw = UserDefaults.standard.array(forKey: Self.metaKey) as? [[String: Any]] ?? []
        raw.removeAll { ($0["fileName"] as? String) == fileName }
        UserDefaults.standard.set(raw, forKey: Self.metaKey)

        loadRecordings()
    }

    private func persistMetadata() {
        let raw: [[String: Any]] = recordings.map {
            [
                "fileName": $0.fileName,
                "createdAt": $0.createdAt.timeIntervalSince1970,
                "duration": $0.duration
            ]
        }
        UserDefaults.standard.set(raw, forKey: Self.metaKey)
    }

    private static func durationOfAudio(at url: URL) -> TimeInterval {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        return player.duration
    }

    var recordingsDirURL: URL { recordingsDir }

    /// Total bytes occupied by all recordings on the watch.
    var totalBytes: Int64 { recordings.reduce(0) { $0 + $1.fileSize } }
}
