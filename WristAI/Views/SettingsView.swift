import SwiftUI

struct SettingsView: View {
    @Environment(PhoneStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(CloudSyncService.self) private var cloud

    @State private var showClearConfirm = false
    @State private var showSignOutConfirm = false
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                cloudSection

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
                    Label("转录在本机完成", systemImage: "lock.fill")
                        .foregroundStyle(.green)
                    Label("仅同步到你的 iCloud 私有库", systemImage: "icloud.fill")
                        .foregroundStyle(.green)
                    Label("开发者无法读取你的数据", systemImage: "shield.fill")
                        .foregroundStyle(.green)
                }

                Section("存储") {
                    HStack {
                        Label("录音格式", systemImage: "waveform")
                        Spacer()
                        Text("M4A · AAC-LC")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("音频规格", systemImage: "dial.medium")
                        Spacer()
                        Text("22.05 kHz · 48 kbps · 单声道")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    HStack {
                        Label("每分钟占用", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("约 390 KB")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("已用空间", systemImage: "internaldrive")
                        Spacer()
                        Text(AudioFileMeta.formatBytes(store.totalAudioSize))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("录音数量", systemImage: "list.bullet")
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
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
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
                Text("这将永久删除 \(store.notes.count) 条录音及其转录（含 iCloud 中的副本），无法恢复。")
            }
            .confirmationDialog(
                "退出登录？",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("退出登录", role: .destructive) {
                    auth.signOut()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后不再同步到 iCloud，本机已有的笔记会保留。")
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("账户") {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)

                    Text(auth.profile?.initialsForBadge ?? "A")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.profile?.displayName ?? "Apple 用户")
                        .font(.body.weight(.medium))
                    Text(auth.profile?.email ?? "已通过 Apple 登录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)

            Button("退出登录", role: .destructive) {
                showSignOutConfirm = true
            }
        }
    }

    // MARK: - Cloud

    private var cloudSection: some View {
        Section("iCloud 同步") {
            HStack {
                Label("状态", systemImage: "icloud")
                Spacer()
                HStack(spacing: 6) {
                    if cloud.status.isBusy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(cloud.status.title)
                        .foregroundStyle(.secondary)
                }
            }

            Text(cloud.status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    isSyncing = true
                    await store.syncFromCloud()
                    isSyncing = false
                }
            } label: {
                HStack {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if isSyncing { ProgressView().controlSize(.mini) }
                }
            }
            .disabled(isSyncing || cloud.status.isBusy || !cloud.isUsable)

            HStack {
                Label("本地数据", systemImage: "internaldrive")
                Spacer()
                Text("\(store.notes.count) 条")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch cloud.status {
        case .ready:            return .green
        case .syncing, .checking: return .orange
        case .failed:           return .red
        case .offline:          return .gray
        case .idle:             return .secondary
        }
    }
}
