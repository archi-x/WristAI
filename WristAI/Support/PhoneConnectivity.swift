import Foundation
import WatchConnectivity

/// Receives recordings from the Watch app via WatchConnectivity
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    var onReceiveRecording: ((URL, Date, TimeInterval) -> Void)?

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("WCSession activation error: \(error)") }
        else { print("Phone WCSession activated") }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for a new Apple Watch pairing.
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metaData = file.metadata ?? [:]

        // Copy the file to a temporary location (the original is managed by the system)
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(file.fileURL.lastPathComponent)
        try? FileManager.default.copyItem(at: file.fileURL, to: destURL)

        let createdAt: Date
        if let ts = metaData["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: ts)
        } else {
            createdAt = .now
        }

        let duration: TimeInterval
        if let d = metaData["duration"] as? TimeInterval {
            duration = d
        } else {
            duration = 0
        }

        DispatchQueue.main.async { [weak self] in
            self?.onReceiveRecording?(destURL, createdAt, duration)
        }
    }
}
