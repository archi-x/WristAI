import SwiftUI

struct TodosView: View {
    @Environment(PhoneStore.self) private var store

    var groupedTodos: [(note: VoiceNote, todos: [TodoItem])] {
        store.notes.compactMap { note in
            let pending = note.todos.filter { !$0.isCompleted }
            return pending.isEmpty ? nil : (note, pending)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groupedTodos.isEmpty {
                    ContentUnavailableView(
                        "没有待办",
                        systemImage: "checkmark.seal.fill",
                        description: Text("录音中的待办事项会出现在这里")
                    )
                } else {
                    List {
                        ForEach(groupedTodos, id: \.note.id) { group in
                            Section(group.note.title) {
                                ForEach(group.todos) { todo in
                                    Button(action: { store.toggleTodo(todo, in: group.note) }) {
                                        HStack {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.secondary)
                                            Text(todo.text)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("待办")
        }
    }
}
