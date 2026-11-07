import Foundation
import AVFoundation
import Observation

/// Plays back recordings that live in the Watch app's Documents/Recordings folder.
///
/// watchOS needs an explicit `.playback` audio session before any `AVAudioPlayer`
/// can make sound, otherwise `play()` returns `false` and nothing is heard —
/// that's the main reason audio silently fails on the watch.
@Observable
final class WatchPlayer: NSObject, AVAudioPlayerDelegate {

    // MARK: - Observable state
    /// File name of the item currently loaded in the player.
    private(set) var currentFileName: String?
    private(set) var isPlaying = false
    /// 0...1 progress of the current item.
    private(set) var progress: Double = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Non-nil when the file is missing or the decoder refused to open it.
    private(set) var errorMessage: String?

    // MARK: - Internal
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let session = AVAudioSession.sharedInstance()

    // MARK: - Public API

    /// Play the item, or pause it if it is the one already playing.
    func toggle(url: URL) {
        let name = url.lastPathComponent

        if currentFileName == name {
            if isPlaying {
                pause()
            } else {
                resume()
            }
        } else {
            play(url: url)
        }
    }

    func play(url: URL) {
        stopTicker()
        player?.stop()
        player = nil
        errorMessage = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            resetState()
            errorMessage = "录音文件已不存在"
            return
        }

        do {
            try activateSession()
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()

            guard newPlayer.play() else {
                resetState()
                errorMessage = "无法播放该录音"
                deactivateSession()
                return
            }

            player = newPlayer
            currentFileName = url.lastPathComponent
            duration = newPlayer.duration
            currentTime = 0
            progress = 0
            isPlaying = true
            startTicker()
        } catch {
            resetState()
            errorMessage = "播放失败：\(error.localizedDescription)"
            deactivateSession()
        }
    }

    func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
        stopTicker()
        deactivateSession()
    }

    func resume() {
        guard let player, !isPlaying, currentFileName != nil else { return }
        do {
            try activateSession()
        } catch {
            errorMessage = "播放失败：\(error.localizedDescription)"
            return
        }
        if player.play() {
            isPlaying = true
            startTicker()
        }
    }

    /// Fully stop playback and clear the current selection.
    func stop() {
        stopTicker()
        player?.stop()
        player = nil
        resetState()
        deactivateSession()
    }

    /// Call after a recording is deleted so the player doesn't keep a stale item.
    func handleDeleted(fileName: String) {
        guard currentFileName == fileName else { return }
        stop()
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopTicker()
        isPlaying = false
        progress = 1
        currentTime = duration
        deactivateSession()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        stopTicker()
        isPlaying = false
        errorMessage = "解码失败，无法播放"
        deactivateSession()
    }

    // MARK: - Helpers

    private func activateSession() throws {
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func deactivateSession() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resetState() {
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
        currentFileName = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            let total = player.duration
            self.duration = total
            self.currentTime = player.currentTime
            self.progress = total > 0 ? min(1, player.currentTime / total) : 0
            if !player.isPlaying && self.isPlaying {
                self.isPlaying = false
                self.stopTicker()
                self.deactivateSession()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
