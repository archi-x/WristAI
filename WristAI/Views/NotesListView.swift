import SwiftUI

struct NotesListView: View {
    @Environment(PhoneStore.self) private var store
    @State private var searchText = ""
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable {
        case all = "全部"
        case today = "今天"
        case withTodos = "有待办"
    }

    var filteredNotes: [VoiceNote] {
        var result = store.notes
        switch filter {
        case .all:
            break
        case .today:
            let cal = Calendar.current
            result = result.filter { cal.isDateInToday($0.createdAt) }
        case .withTodos:
            result = result.filter { !$0.todos.filter { !$0.isCompleted }.isEmpty }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.title.localizedStandardContains(searchText)) ||
                ($0.transcription?.localizedStandardContains(searchText) ?? false) ||
                ($0.summary?.localizedStandardContains(searchText) ?? false)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if store.isProcessing {
                    ProgressView("正在转录…")
                        .padding()
                }

                if filteredNotes.isEmpty {
                    ContentUnavailableView(
                        "还没有笔记",
                        systemImage: "waveform",
                        description: Text("在 Apple Watch 上录音，笔记会自动出现在这里")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredNotes) { note in
                            NavigationLink(value: note) {
                                NoteRow(note: note, store: store)
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                store.deleteNote(filteredNotes[idx])
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("WristAI")
            .searchable(text: $searchText, prompt: "搜索笔记")
            .navigationDestination(for: VoiceNote.self) { note in
                NoteDetailView(note: note)
            }
        }
    }
}

// MARK: - Note Row
struct NoteRow: View {
    let note: VoiceNote
    let store: PhoneStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: note.transcriptionStatus.icon)
                    .foregroundStyle(statusColor)
                    .font(.caption)
                Text(note.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
            }

            if let summary = note.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label(store.formatDuration(note.duration), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(note.formatLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))

                if let bytes = store.fileSize(for: note) {
                    Label(AudioFileMeta.formatBytes(bytes), systemImage: "internaldrive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !note.todos.isEmpty {
                    let pending = note.todos.filter { !$0.isCompleted }.count
                    Label("\(pending)", systemImage: "checklist")
                        .font(.caption2)
                        .foregroundStyle(pending > 0 ? .orange : .secondary)
                }

                Spacer(minLength: 4)

                Text(Self.formatDate(note.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch note.transcriptionStatus {
        case .completed: return .green
        case .transcribing: return .orange
        case .failed: return .red
        case .pending: return .blue
        case .notTransferred: return .gray
        }
    }

    /// Matches the watch list: 今天 HH:mm / 昨天 HH:mm / M月d日 HH:mm.
    private static func formatDate(_ date: Date) -> String {
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
