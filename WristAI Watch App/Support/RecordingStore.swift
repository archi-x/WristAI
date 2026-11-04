import Foundation
import AVFoundation
import WatchKit
import Combine

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

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
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
        return (try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey]))
            ?.sorted { a, b in
                (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast >
                (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            } ?? []
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    var recordingsDirURL: URL { recordingsDir }
}
