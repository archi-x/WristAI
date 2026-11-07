import Foundation
import WatchConnectivity

/// Manages WatchConnectivity file transfer from Watch to iPhone
final class ConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = ConnectivityManager()

    private(set) var session: WCSession?
    /// Called when a file transfer completes (for UI feedback on Watch)
    var onTransferComplete: ((String, Bool) -> Void)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported")
            return
        }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Send Recording to iPhone
    func sendRecording(url: URL, createdAt: Date, duration: TimeInterval) {
        guard let session, session.activationState == .activated else {
            print("Session not activated, cannot send")
            onTransferComplete?(url.lastPathComponent, false)
            return
        }

        let metaData: [String: Any] = [
            "createdAt": createdAt.timeIntervalSince1970,
            "duration": duration,
            "fileName": url.lastPathComponent
        ]

        // transferFile works in background, queued until phone is available
        session.transferFile(url, metadata: metaData)
        print("Queued recording for transfer: \(url.lastPathComponent)")
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation error: \(error)")
        } else {
            print("WCSession activated: \(activationState.rawValue)")
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let fileName = fileTransfer.file.fileURL.lastPathComponent
        if let error {
            print("File transfer failed: \(error)")
            DispatchQueue.main.async {
                self.onTransferComplete?(fileName, false)
            }
        } else {
            print("File transfer completed: \(fileName)")
            DispatchQueue.main.async {
                self.onTransferComplete?(fileName, true)
            }
        }
    }
}
