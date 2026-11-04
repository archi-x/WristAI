import SwiftUI

struct SettingsView: View {
    @Environment(PhoneStore.self) private var store
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("转录") {
                    HStack {
                        Label("模型", systemImage: "cpu")
                        Spacer()
                        Text("WhisperKit (端侧)")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("自动 AI 摘要", isOn: .constant(true))
                    HStack {
                        Label("处理位置", systemImage: "iphone")
                        Spacer()
                        Text("本机 Neural Engine")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("隐私") {
                    Label("音频不上云", systemImage: "lock.fill")
                        .foregroundStyle(.green)
                    Label("转录不上云", systemImage: "lock.fill")
                        .foregroundStyle(.green)
                    Label("零第三方依赖", systemImage: "shield.fill")
                        .foregroundStyle(.green)
                }

                Section("存储") {
                    HStack {
                        Label("录音数量", systemImage: "waveform")
                        Spacer()
                        Text("\(store.notes.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("待转录", systemImage: "clock")
                        Spacer()
                        Text("\(store.pendingCount)")
                            .foregroundStyle(.secondary)
                    }
                    Button("清除所有录音", role: .destructive) {
                        showClearConfirm = true
                    }
                }

                Section("关于") {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Link("WhisperKit 开源项目", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                    Link("Apple HIG 设计规范", destination: URL(string: "https://developer.apple.com/design/human-interface-guidelines")!)
                }
            }
            .navigationTitle("设置")
            .confirmationDialog(
                "确定清除所有录音？",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("删除全部", role: .destructive) {
                    for note in store.notes {
                        store.deleteNote(note)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这将永久删除 \(store.notes.count) 条录音及其转录，无法恢复。")
            }
        }
    }
}
