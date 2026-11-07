import Foundation

// Re-export shared models from Watch App (same file is in the synchronized group)
// These are duplicated here for the iOS target's compilation.
// In production, these would live in a shared framework.

struct VoiceNote: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    var fileName: String
    var transcriptionStatus: TranscriptionStatus
    var transcription: String?
    var summary: String?
    var todos: [TodoItem]
    var title: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        fileName: String = "",
        transcriptionStatus: TranscriptionStatus = .pending,
        transcription: String? = nil,
        summary: String? = nil,
        todos: [TodoItem] = [],
        title: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = fileName
        self.transcriptionStatus = transcriptionStatus
        self.transcription = transcription
        self.summary = summary
        self.todos = todos
        self.title = title
    }

    /// Container format derived from the file extension — `M4A`, `WAV`, …
    var formatLabel: String { AudioFileMeta.formatLabel(for: fileName) }
}

/// Formatting helpers for audio files (kept per-target so both apps can use them).
enum AudioFileMeta {
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

enum TranscriptionStatus: String, Codable {
    case pending
    case transcribing
    case completed
    case failed
    case notTransferred

    var icon: String {
        switch self {
        case .pending:        return "clock"
        case .transcribing:   return "waveform"
        case .completed:      return "checkmark.circle.fill"
        case .failed:         return "exclamationmark.triangle"
        case .notTransferred: return "iphone.gen3"
        }
    }

    var label: String {
        switch self {
        case .pending:        return "待转录"
        case .transcribing:   return "转录中"
        case .completed:      return "已完成"
        case .failed:         return "失败"
        case .notTransferred: return "待传输"
        }
    }
}

struct TodoItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isCompleted: Bool

    init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

enum AIEngine {
    static func generateTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "新录音" }
        if let firstSentence = trimmed.split(separator: "。").first,
           firstSentence.count <= 30 {
            return String(firstSentence).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let firstComma = trimmed.split(separator: "，").first,
           firstComma.count <= 20 {
            return String(firstComma).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(trimmed.prefix(20))
    }

    static func generateSummary(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let sentences = trimmed.split(whereSeparator: { $0 == "。" || $0 == "." || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sentences.isEmpty { return String(trimmed.prefix(100)) }
        return sentences.prefix(3).joined(separator: "。") + "。"
    }

    static func extractTodos(from text: String) -> [TodoItem] {
        let actionKeywords = [
            "需要", "记得", "别忘了", "要去做", "明天", "下周",
            "发邮件", "打电话", "联系", "提醒", "准备", "完成",
            "买", "查一下", "确认", "安排", "预约", "提交"
        ]
        let sentences = text.split(whereSeparator: { $0 == "。" || $0 == "." || $0 == "\n" || $0 == "；" })
        var todos: [TodoItem] = []
        var seen = Set<String>()
        for sentence in sentences {
            let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            if actionKeywords.contains(where: { s.contains($0) }) && s.count <= 60 {
                let normalized = s.lowercased()
                if !seen.contains(normalized) {
                    seen.insert(normalized)
                    todos.append(TodoItem(text: s))
                }
            }
        }
        return Array(todos.prefix(10))
    }

    static func process(_ text: String) -> (title: String, summary: String, todos: [TodoItem]) {
        (generateTitle(from: text), generateSummary(from: text), extractTodos(from: text))
    }
}
