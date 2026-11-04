// WhisperKit Stub — provides the same public API surface as the real WhisperKit
// for compilation without network access. Replace with the real argmax-oss-swift
// SPM dependency when building on a machine with GitHub access.
//
// This stub allows the WristAI project to compile and run in "simulation mode".
// The real WhisperKit performs on-device neural engine transcription.

import Foundation

// MARK: - TranscriptionResult

public struct TranscriptionResult: Codable {
    public var text: String
    public var segments: [TranscriptionSegment]
    public var language: String
    public var seekTime: Float?

    public init(text: String, segments: [TranscriptionSegment] = [], language: String = "zh", seekTime: Float? = nil) {
        self.text = text
        self.segments = segments
        self.language = language
        self.seekTime = seekTime
    }
}

public struct TranscriptionSegment: Codable {
    public var text: String
    public var start: Float
    public var end: Float

    public init(text: String, start: Float = 0, end: Float = 0) {
        self.text = text
        self.start = start
        self.end = end
    }
}

// MARK: - WhisperKit

@available(macOS 13, iOS 16, watchOS 10, visionOS 1, *)
open class WhisperKit {

    public init(model: String? = nil,
                downloadBase: URL? = nil,
                modelRepo: String? = nil,
                modelFolder: String? = nil,
                tokenizerFolder: URL? = nil,
                computeOptions: ModelComputeOptions? = nil,
                audioProcessor: Any? = nil,
                featureExtractor: Any? = nil,
                audioEncoder: Any? = nil,
                textDecoder: Any? = nil,
                logitsFilters: [Any]? = nil,
                segmentSeeker: Any? = nil,
                verbose: Bool = true,
                logLevel: LogLevel = .info,
                prewarm: Bool? = nil,
                load: Bool? = nil,
                download: Bool = true,
                useBackgroundDownloadSession: Bool = false) async throws {
        // Stub: no actual model loading
    }

    /// Transcribes an audio file from the given path asynchronously.
    open func transcribe(
        audioPath: String,
        decodeOptions: DecodingOptions? = nil,
        callback: ((TranscriptionProgress) -> Bool)? = nil
    ) async throws -> [TranscriptionResult] {
        // Stub: return a simulated result
        // In production, this runs the Whisper model on the Neural Engine
        let simulatedText = "【模拟转录】WhisperKit 当前为 Stub 模式。音频文件：\(audioPath)。请在 Xcode 中替换为真实的 argmax-oss-swift SPM 依赖以启用端侧转录。"
        return [TranscriptionResult(text: simulatedText)]
    }
}

// MARK: - Supporting Types

public struct ModelComputeOptions {
    public init() {}
}

public struct DecodingOptions {
    public init() {}
}

public enum LogLevel {
    case debug, info, warning, error
}

public struct TranscriptionProgress {
    public var text: String
    public init(text: String = "") { self.text = text }
}

public typealias TranscriptionCallback = ((TranscriptionProgress) -> Bool)?
