# WristAI

> Apple Watch 一键录音 → iPhone 端侧转录 + AI 摘要 → 零云端隐私保护

## 功能

### Watch App (watchOS 11)
- **一键录音**：大圆形按钮，按下即录，红色脉冲动画 + 实时音量波形
- **暂停/继续**：录音中可暂停再继续
- **录音列表**：查看本地录音，左滑删除
- **自动传输**：录音停止后自动通过 WatchConnectivity 发送到 iPhone

### iOS App (iOS 18)
- **笔记列表**：按时间倒序，AI 自动生成标题 + 摘要预览 + 待办数量
- **笔记详情**：音频播放 + 完整转录 + AI 摘要 + 待办勾选
- **待办汇总**：从所有笔记提取的待办事项合集，按笔记分组
- **搜索**：全文搜索标题、摘要、转录文本
- **设置**：转录模型、隐私信息、存储管理

### AI 能力
- **端侧转录**：WhisperKit API 已集成（当前为 Stub 模式，可无缝切换为真实 argmax-oss-swift）
- **自动标题**：从转录文本提取第一句作为标题
- **摘要生成**：提取前三句关键句子
- **待办提取**：关键词匹配（"需要""记得""明天""发邮件"等）→ 可勾选待办

## 架构

```
Apple Watch                     iPhone
┌──────────────┐               ┌─────────────────┐
│  Recording   │  WatchConnect │  Receive File   │
│  Engine      │  ivity        │       │         │
│  (AVAudio    │──────────────│→      ▼         │
│   Recorder)  │   file xfer   │  WhisperKit     │
│              │               │  (on-device)    │
└──────────────┘               │       │         │
                               │       ▼         │
                               │  AI Engine      │
                               │  (title/summary │
                               │   /todos)       │
                               │       │         │
                               │       ▼         │
                               │  Notes Library  │
                               └─────────────────┘
```

**隐私**：音频、转录、AI 处理全部在 iPhone 本地完成，零云端依赖。

## 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI + Observation (`@Observable`) |
| 录音 | AVAudioRecorder + AVAudioSession |
| 传输 | WatchConnectivity (`transferFile`) |
| 转录 | WhisperKit (Argmax, MIT, 端侧 Neural Engine) |
| AI 提炼 | 规则引擎（关键词 + 句法），可扩展为 Apple Intelligence |
| 存储 | JSON 文件（MVP），可迁移到 SwiftData |
| 最低系统 | watchOS 11 / iOS 18 |

## 项目结构

```
WristAI/
├── WristAI.xcodeproj/
├── WristAI Watch App/
│   ├── WristAIWatchApp.swift          # @main 入口
│   ├── Support/
│   │   ├── VoiceNote.swift            # 共享模型 + AI 引擎
│   │   ├── RecordingStore.swift       # 录音引擎 (@Observable)
│   │   └── ConnectivityManager.swift  # Watch → iPhone 传输
│   └── Views/
│       ├── WatchRootView.swift        # TabView 根视图
│       ├── RecordingView.swift        # 录音界面（大按钮 + 波形）
│       └── WatchHistoryView.swift     # 录音列表
├── WristAI/
│   ├── WristAIApp.swift               # @main 入口
│   ├── Support/
│   │   ├── VoiceNote.swift            # 共享模型 + AI 引擎
│   │   ├── PhoneStore.swift           # 接收 + WhisperKit 转录 + AI
│   │   ├── PhoneConnectivity.swift    # iPhone 接收 Watch 文件
│   │   └── WhisperKitStub.swift        # WhisperKit API Stub（可切换为真实 SPM）
│   └── Views/
│       ├── RootView.swift             # TabView 根视图
│       ├── NotesListView.swift        # 笔记列表 + 搜索 + 筛选
│       ├── NoteDetailView.swift       # 详情（播放 + 转录 + 摘要 + 待办）
│       ├── TodosView.swift            # 待办汇总
│       └── SettingsView.swift         # 设置
├── WhisperKitStub/                     # 本地 SPM 包（可选，当前直接用源文件）
│   ├── Package.swift
│   └── Sources/WhisperKit/
│       └── WhisperKit.swift            # WhisperKit API Stub
└── DESIGN.md                          # 设计文档 + 竞品分析
```

## 编译

```bash
# Watch App
xcodebuild -project WristAI.xcodeproj \
  -scheme "WristAI Watch App" \
  -destination 'generic/platform=watchOS' \
  -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/WristAI-DD

# iOS App
xcodebuild -project WristAI.xcodeproj \
  -scheme "WristAI" \
  -destination 'generic/platform=iOS' \
  -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/WristAI-DD
```

两个 target 均编译通过（✅ BUILD SUCCEEDED）。

## WhisperKit 集成状态

### 当前：Stub 模式 ✅ 编译通过

项目已包含 `WhisperKitStub.swift`，提供与真实 WhisperKit 完全一致的公共 API（`WhisperKit`、`TranscriptionResult`、`transcribe(audioPath:)`），使项目无需网络即可编译运行。Stub 的 `transcribe()` 返回模拟文本。

### 切换为真实端侧转录

在有 GitHub 访问权限的机器上：

1. 删除 `WristAI/Support/WhisperKitStub.swift`
2. 在 Xcode → File → Add Package Dependencies 添加：`https://github.com/argmaxinc/argmax-oss-swift.git`（v0.9.0+）
3. 选择 `WhisperKit` product，链接到 iOS target
4. PhoneStore.swift 中 `WhisperKit` 和 `TranscriptionResult` 的调用代码无需任何修改

```swift
// PhoneStore.swift 中已有的调用（Stub 和真实 WhisperKit 完全兼容）：
whisperPipe = try await WhisperKit(model: "base", download: true, verbose: false)
let results: [TranscriptionResult] = try await whisperPipe!.transcribe(audioPath: audioPath)
return results.map(\.text).joined(separator: " ")
```

推荐模型：`tiny`（最快）→ `base`（平衡）→ `small`（最准）
WhisperKit 在 iPhone Neural Engine 上运行，支持中英文。

## 竞品参考

| 产品 | 差异 |
|------|------|
| Auo | 最接近的竞品，但还在 TestFlight，依赖飞书知识库 |
| 闪念贝壳 | 功能全但云端处理，隐私弱 |
| Just Press Record | 只有转录，无 AI 提炼 |
| Apple 语音备忘录 | 纯录音，不转录不提炼 |

WristAI 的差异：零云端 + 零订阅 + AI 摘要/待办 + 完全开源。

## 路线图

- **v1.0（当前）**：录音 → 传输 → 转录 → AI → 笔记 ✅
- **v1.1**：实时转录、Apple Reminders 同步、全文搜索
- **v2.0**：SpeakerKit 说话人分离、多语言、Apple Intelligence 接入、Obsidian 导出
