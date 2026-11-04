import Foundation

// MARK: - Shared Models (used by both Watch and iOS)

/// A single voice note recording
struct VoiceNote: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    var fileName: String          // e.g. "recording-UUID.m4a"
    var transcriptionStatus: TranscriptionStatus
    var transcription: String?
    var summary: String?
    var todos: [TodoItem]
    var title: String             // AI-generated or fallback

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
}

enum TranscriptionStatus: String, Codable {
    case pending       // waiting to be transferred / transcribed
    case transcribing  // in progress
    case completed     // done
    case failed        // error
    case notTransferred // on watch, not yet sent to phone

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

// MARK: - AI Engine (rule-based extraction, no cloud)

enum AIEngine {
    /// Extract a title from transcription text (first meaningful sentence, truncated)
    static func generateTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "新录音" }
        // Take first sentence or first 20 chars
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

    /// Generate a concise summary
    static func generateSummary(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let sentences = trimmed.split(whereSeparator: { $0 == "。" || $0 == "." || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sentences.isEmpty { return String(trimmed.prefix(100)) }
        // Take up to 3 key sentences
        let keySentences = sentences.prefix(3)
        return keySentences.joined(separator: "。") + "。"
    }

    /// Extract action items (todos) using keyword matching
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

    /// Process full transcription into title + summary + todos
    static func process(_ text: String) -> (title: String, summary: String, todos: [TodoItem]) {
        let title = generateTitle(from: text)
        let summary = generateSummary(from: text)
        let todos = extractTodos(from: text)
        return (title, summary, todos)
    }
}
