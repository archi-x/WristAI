# WristAI — Apple Watch 录音 + AI 笔记 App

> 在手表上一键录音，iPhone 端侧转录 + AI 提炼，零云端、全本地。

## 一、为什么做这个

### 用户痛点

1. **灵感转瞬即逝**：走路、开车、开会时冒出的想法，等掏出手机解锁打开笔记 App 时已经忘了。手表是离手最近的设备，抬腕就能录。
2. **录音不是终点**：录完不整理等于没录。原生「语音备忘录」只有音频文件，不转录不提炼，一周后翻出来没人听得完。
3. **隐私焦虑**：大部分 AI 录音工具把音频上传云端转录。会议、私人对话的音频不该离开设备。

### 竞品分析

| 产品 | 平台 | 核心功能 | 转录方式 | 缺口 |
|------|------|----------|----------|------|
| **Auo** | Watch + iPhone | 手表录音 → iPhone 实时转录 → AI 待办 + 知识库 | iPhone 端侧 | 还在 TestFlight，不接受新测试者；依赖飞书等外部知识库 |
| **Voice Memos AI** | iPhone | 录音 → 转录 → AI 摘要 | 云端 | 无 Watch 端；音频上云 |
| **闪念贝壳** | Watch + iPhone | 语音闪念 → AI 笔记 → 待办 | 云端 | 功能全但隐私弱；订阅制 |
| **Just Press Record** | Watch + iPhone | 一键录音 → 转录 → iCloud 同步 | 端侧 | 无 AI 提炼，只有转录 |
| **Apple 语音备忘录** | Watch + iPhone | 录音 → 同步 | 无 | 不转录不提炼，纯录音工具 |

**WristAI 的定位**：Watch 一键录音 + iPhone 端侧 WhisperKit 转录 + AI 摘要/待办提取 + 本地笔记。**零云端、零订阅、隐私完全在设备上**。对标 Auo 但不依赖外部知识库，对标闪念贝壳但隐私放端侧。

## 二、技术架构

```
Apple Watch (watchOS 11)                    iPhone (iOS 18)
┌─────────────────────┐               ┌──────────────────────────┐
│  WristAI Watch App  │               │   WristAI iOS App         │
│                     │  WatchConnect  │                          │
│  ┌───────────┐      │  ivity (file   │  ┌──────────┐           │
│  │ Recording │      │  transfer)     │  │ Receive  │           │
│  │  Engine   │──────│───────────────│→ │ & Store  │           │
│  │ AVAudio   │      │               │  └────┬─────┘           │
│  │ Recorder  │      │               │       │                  │
│  └─────┬─────┘      │               │       ▼                  │
│        │            │               │  ┌──────────┐           │
│        ▼            │               │  │WhisperKit│           │
│  ┌───────────┐      │               │  │端侧转录  │           │
│  │  Local    │      │               │  │(on-device)│          │
│  │  Storage  │      │               │  └────┬─────┘           │
│  └───────────┘      │               │       │                  │
│                     │               │       ▼                  │
│                     │               │  ┌──────────┐           │
│                     │               │  │ AI Engine│           │
│                     │               │  │摘要+待办 │           │
│                     │               │  └────┬─────┘           │
│                     │               │       │                  │
│                     │               │       ▼                  │
│                     │               │  ┌──────────┐           │
│                     │               │  │ Notes    │           │
│                     │               │  │ Library  │           │
│                     │               │  └──────────┘           │
└─────────────────────┘               └──────────────────────────┘
```

### 技术选型

- **录音**：`AVAudioRecorder` + `AVAudioSession`（`.record` category），格式 m4a (AAC)，采样率 16kHz（WhisperKit 输入要求）
- **传输**：`WatchConnectivity` 的 `transferFile(_:metaData:)`，后台自动同步
- **转录**：[WhisperKit](https://github.com/argmaxinc/WhisperKit)（Argmax 开源，MIT），OpenAI Whisper 模型的 Swift 实现，跑在 Apple Neural Engine 上。iPhone 15 Pro 起可跑 `tiny`/`base` 模型实时转录
- **AI 提炼**：先用规则提取（关键词、时间、动作动词），后续可接入 Apple Intelligence（Foundation Models on-device）
- **存储**：录音文件存 App Sandbox，笔记数据存 SwiftData
- **零第三方云依赖**：全部处理在 iPhone 本地完成

## 三、UI 设计（遵循 watchOS HIG）

### Watch App — 三个界面

**1. 录音界面（主界面）**
- 全屏大圆形录音按钮，红色渐变，按下时脉冲扩散动画
- 上方显示计时器 `00:23`（SF Mono，大字号）
- 录音中显示实时音量波形条（5-7 根竖条，高低随音量跳动）
- 长按按钮 = 停止并保存；短按 = 暂停/继续
- 数字表冠可调节录音增益（HIG：Digital Crown 做精确调节）

**2. 录音列表**
- List 样式，每条显示：时长 + 日期 + 转录状态图标（⏳待转录 / ✅已完成 / ❌失败）
- 点击预览：播放/删除/重试转录
- 左滑删除

**3. 设置**
- 音质选择：标准(16kHz) / 高清(44.1kHz)
- 自动传输开关
- 清除本地缓存

### iOS App — 四个界面

**1. 笔记列表**
- 按时间倒序，卡片式布局
- 每条卡片：标题（AI 自动生成）+ 摘要预览 + 待办数 + 时长 + 日期
- 顶部筛选：全部 / 今天 / 有待办
- 下拉刷新

**2. 笔记详情**
- 顶部：音频播放器（波形 + 进度条 + 播放/暂停）
- 正文：完整转录文本（可编辑）
- AI 卡片：摘要 / 关键待办（checkbox 可勾选） / 关键词标签
- 底部：导出 / 分享 / 删除

**3. 待办汇总**
- 从所有笔记中提取的待办事项合集，按笔记分组
- 可标记完成

**4. 设置**
- 转录模型选择（tiny/base/small，影响速度与准确率）
- AI 自动摘要开关
- 存储管理（清除音频 / 清除转录文本）

### 设计原则（HIG 对齐）

- **Glanceable**：手表主界面 1 秒内看清状态（在录/不在录、时长）
- **Actionable**：核心操作（开始录音）一步触达，不需要滚动菜单
- **Lightweight**：Watch 只做录音和列表，不做转录和 AI（计算在 iPhone 上）
- **Focus**：录音界面只有一件事——录。不放广告、不弹引导
- **Color**：系统语义色为主，红色用于录音状态，绿色用于已完成，橙色用于处理中

## 四、功能优先级

### MVP（v1.0）
1. ✅ Watch 端录音（一键开始/停止）
2. ✅ Watch → iPhone 文件传输
3. ✅ iPhone 端 WhisperKit 转录
4. ✅ AI 摘要 + 待办提取
5. ✅ 笔记列表 + 详情查看

### v1.1
- 实时转录（录音过程中 iPhone 实时显示文字）
- 待办同步到 Apple Reminders
- 笔记搜索

### v2.0
- 说话人分离（SpeakerKit）
- 多语言转录（中文/英文自动检测）
- Apple Intelligence 接入（更智能的摘要和待办）
- 笔记导出到 Obsidian / Notion

## 五、隐私

| 数据 | 存储位置 | 是否上云 |
|------|----------|----------|
| 音频文件 | iPhone App Sandbox | 否 |
| 转录文本 | iPhone SwiftData | 否 |
| AI 摘要 | iPhone SwiftData | 否 |
| 模型推理 | iPhone Neural Engine | 否 |

**唯一的外部通信**是 Watch → iPhone 的文件传输，走系统级 WatchConnectivity，不经过任何服务器。
