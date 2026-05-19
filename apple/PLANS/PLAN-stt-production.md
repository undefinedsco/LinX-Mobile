# PLAN-stt-production.md

# Production PLAN: whisper.cpp 接入 LinXApple 原生 iOS App

> 目标：在当前 `apple/` 原生 SwiftUI App 中接入 `whisper.cpp` 本地 STT 能力，形成可维护、可测试、可扩展的语音输入模块。
>
> 首版产品目标：麦克风录音 -> 本地离线转写 -> 将转写文本回填到 `ChatScene` 的聊天输入草稿，由用户确认后再发送。
>
> 首版不做：自动发送、Pod 转写历史存储、模型热下载、Core ML encoder 加速、长音频分片识别、独立 demo 首页。

---

## 0. 当前工程事实

本计划只适用于当前 LinXApple 工程，不再保留通用 iOS 模板分支。

```text
apple/
|-- project.yml
|-- LinXApple.xcodeproj
|-- LinXApple/
|   |-- Resources/
|   |   |-- Info.plist
|   |   `-- Assets.xcassets/
|   `-- Sources/
|       |-- AppCore/
|       |-- Auth/
|       |-- ChatUI/
|       |-- PodData/
|       `-- Runtime/
|-- LinXAppleTests/
`-- LinXAppleUITests/
```

工程配置：

- App target: `LinXApple`
- Unit test target: `LinXAppleTests`
- UI test target: `LinXAppleUITests`
- Project generator: XcodeGen, source of truth is `project.yml`
- Deployment target: iOS `17.0`
- Swift version: `6.0`
- Strict concurrency: `complete`
- App type: standalone native SwiftUI app
- Package manager: Swift Package Manager through `project.yml`

现有关键接入点：

- `LinXApple/Sources/AppCore/LinXAppleApp.swift`: app entry, creates `AuthSessionController` and `ChatExperienceModel`
- `LinXApple/Sources/AppCore/RootView.swift`: authenticated route presents `ChatScene`
- `LinXApple/Sources/ChatUI/ChatScene.swift`: chat screen and `draftText` input binding
- `LinXApple/Sources/ChatUI/ChatExperienceModel.swift`: existing send flow through `enqueueSend(_:)`
- `LinXApple/Sources/AppCore/LinxDiagnostics.swift`: OSLog categories
- `LinXApple/Resources/Info.plist`: privacy usage strings

当前仓库尚未包含：

- `ThirdParty/whisper.cpp`
- `Vendors/Whisper/whisper.xcframework`
- `LinXApple/Resources/WhisperModels/`

这些 artifact 是 STT 实现前置条件。

---

## 1. 总体目标

### 1.1 首版功能目标

- 支持麦克风录音
- 支持 whisper.cpp 本地离线转写
- 支持中文、英文、自动语言识别
- 支持录音中、准备音频、加载模型、转写中、完成、失败、取消等状态
- 转写完成后写入聊天输入框草稿，不自动发送
- 用户点击现有发送按钮后复用当前 Pod 持久化和 LinX runtime 回复流程
- 支持模型缺失、权限拒绝、录音失败、音频转换失败、推理失败的明确错误
- 支持基础性能日志
- 支持模拟器可跑的单元测试和真机手动验证

### 1.2 工程目标

- 保持当前 SwiftUI + `@MainActor` coordinator 架构
- UI 与录音、音频转换、whisper bridge 解耦
- 通过 protocol 隔离 STT provider，后续可替换为 Apple Speech、OpenAI API、Deepgram 等
- 不污染 `Auth`、`PodData`、`Runtime` 的职责边界
- 不手动编辑 generated `LinXApple.xcodeproj`
- 保持 Swift 6 strict concurrency clean
- 不在主线程执行音频转换或 whisper 推理
- 不把模型路径硬编码为开发机绝对路径

---

## 2. LinXApple 专用架构

### 2.1 目录结构

推荐新增目录：

```text
LinXApple/Sources/
|-- SpeechRecognition/
|   |-- Domain/
|   |   |-- SpeechTranscriptionProviding.swift
|   |   |-- SpeechTranscriptionOptions.swift
|   |   |-- SpeechTranscriptionResult.swift
|   |   |-- SpeechRecognitionState.swift
|   |   `-- SpeechRecognitionError.swift
|   |-- Infrastructure/
|   |   |-- SpeechAudioRecorder.swift
|   |   |-- SpeechAudioSessionManager.swift
|   |   |-- SpeechAudioConverter.swift
|   |   |-- WhisperModelStore.swift
|   |   `-- WhisperTranscriptionService.swift
|   `-- Bridge/
|       |-- WhisperCppBridge.swift
|       `-- WhisperPCMReader.swift
|
|-- ChatUI/
|   |-- SpeechRecognitionViewModel.swift
|   `-- SpeechInputSheet.swift
|
`-- AppCore/
    `-- LinxDiagnostics.swift

LinXApple/Resources/
`-- WhisperModels/
    |-- ggml-tiny.bin
    `-- ggml-base.bin

Vendors/
`-- Whisper/
    `-- whisper.xcframework

LinXAppleTests/
`-- SpeechRecognitionTests.swift
```

说明：

- 非 UI STT 能力放在 `LinXApple/Sources/SpeechRecognition/`。
- Chat 专属 ViewModel 和 sheet/overlay 放在 `LinXApple/Sources/ChatUI/`。
- `AppCore` 只允许补充共享诊断 category，不放音频或推理逻辑。
- 首版不修改 `PodData` 存储布局。
- 首版不把 whisper 本地推理放入 `Runtime`，`Runtime` 继续只表示 LinX runtime/OpenAI-compatible API。

### 2.2 数据流

```text
ChatScene mic button
-> SpeechInputSheet / SpeechRecognitionViewModel
-> SpeechAudioRecorder
-> SpeechAudioConverter
-> WhisperModelStore
-> WhisperCppBridge
-> SpeechTranscriptionResult
-> ChatScene draftText
-> user taps existing send button
-> ChatExperienceModel.enqueueSend(_:) existing flow
-> PodChatRepository + LinxOpenAIChatService
```

首版必须保留 `ChatExperienceModel.enqueueSend(_:)` 的语义：只有用户发送后的文本才进入 Pod chat history。

### 2.3 模块边界

| 模块 | STT 相关规则 |
|---|---|
| AppCore | 只放 `LinxDiagnostics` speech logger 等共享小能力 |
| Auth | 不处理录音、转写、模型路径 |
| ChatUI | 语音入口、状态展示、draft 回填、错误展示 |
| SpeechRecognition | STT domain、录音、转换、模型查找、whisper bridge |
| PodData | 首版不存储原始音频或转写历史 |
| Runtime | 不放本地 whisper 推理 |

---

## 3. 依赖与 artifact

### 3.1 必需依赖

| 依赖 | 来源 | 用途 |
|---|---|---|
| whisper.cpp | `ThirdParty/whisper.cpp` 或外部构建源 | 本地 STT 推理 |
| whisper.xcframework | `Vendors/Whisper/whisper.xcframework` | iOS 可链接二进制 |
| AVFoundation | Apple SDK | 录音、音频格式读取和转换 |
| Foundation | Apple SDK | 文件、并发、错误处理 |
| OSLog | Apple SDK | 性能和错误诊断 |
| Swift Concurrency | Swift 6 | async/await、actor、取消 |

### 3.2 不新增依赖

首版不新增 SPM 包。不要为 STT 引入额外 UI wrapper、Combine-only abstraction、音频第三方库或模型下载库，除非后续阶段证明 Apple SDK 无法满足需求。

---

## 4. 构建 whisper.xcframework

### 4.1 添加 whisper.cpp

推荐使用 Git submodule，但当前仓库尚未包含该目录，执行前需要确认团队接受 submodule 方式。

```bash
cd apple
mkdir -p ThirdParty
git submodule add https://github.com/ggml-org/whisper.cpp.git ThirdParty/whisper.cpp
git submodule update --init --recursive
```

### 4.2 构建 iOS XCFramework

```bash
cd apple/ThirdParty/whisper.cpp
./build-xcframework.sh
```

预期产物：

```text
apple/ThirdParty/whisper.cpp/build-apple/whisper.xcframework
```

### 4.3 复制到工程

```bash
cd apple
mkdir -p Vendors/Whisper
cp -R ThirdParty/whisper.cpp/build-apple/whisper.xcframework Vendors/Whisper/
```

### 4.4 Header 校验要求

实现 bridge 前必须打开并核对当前版本 C API：

```text
apple/ThirdParty/whisper.cpp/include/whisper.h
```

如果只拿到了 `whisper.xcframework`，则从 framework 内部 headers/module map 校验 Swift import 模块名和 C symbols。不要从旧示例复制函数签名。

### 4.5 常见错误

如果出现：

```text
iphoneos is not an iOS SDK
```

先确认 Xcode command line tools 指向完整 Xcode：

```bash
sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
```

---

## 5. XcodeGen 配置

### 5.1 `project.yml` 修改点

只编辑 `project.yml`，不要手动编辑 `LinXApple.xcodeproj`。

当前 `project.yml` 已经包含：

```yaml
options:
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: 6.0
    SWIFT_STRICT_CONCURRENCY: complete
targets:
  LinXApple:
    sources:
      - path: LinXApple/Sources
      - path: LinXApple/Resources
        buildPhase: resources
        excludes:
          - Info.plist
```

接入 `whisper.xcframework` 时，在 `LinXApple` target 的 `dependencies` 中追加：

```yaml
targets:
  LinXApple:
    dependencies:
      - package: AppAuthPackage
        product: AppAuth
      - package: ExyteChatPackage
        product: ExyteChat
      - package: MarkdownViewPackage
        product: MarkdownView
      - framework: Vendors/Whisper/whisper.xcframework
        embed: true
        codeSign: true
```

模型资源首版放入：

```text
LinXApple/Resources/WhisperModels/
```

因为 `LinXApple/Resources` 已经作为 resources build phase 纳入 target，不需要额外 `resources:` 配置。若未来模型迁移到 `Vendors/Whisper/Models/`，再同步更新 `project.yml` resources。

### 5.2 重新生成工程

修改 `project.yml` 后执行：

```bash
cd apple
xcodegen generate
```

---

## 6. Info.plist 权限

在 `LinXApple/Resources/Info.plist` 添加：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>LinX uses the microphone to transcribe speech into chat text on this device.</string>
```

首版不支持从 Files app 导入音频，因此不要添加 document browser 配置。如果后续支持本地音频文件导入，再单独更新权限和 UI 流程。

---

## 7. Domain 层设计

Domain 层位于 `LinXApple/Sources/SpeechRecognition/Domain/`。该 app target 内部使用即可，默认使用 internal 可见性；测试通过 `@testable import LinXApple` 访问。

### 7.1 `SpeechTranscriptionProviding.swift`

```swift
import Foundation

protocol SpeechTranscriptionProviding: Sendable {
    func transcribe(
        audioURL: URL,
        options: SpeechTranscriptionOptions
    ) async throws -> SpeechTranscriptionResult
}
```

### 7.2 `SpeechTranscriptionOptions.swift`

```swift
import Foundation

struct SpeechTranscriptionOptions: Equatable, Sendable {
    enum Language: Equatable, Sendable {
        case auto
        case chinese
        case english
        case custom(String)

        var whisperCode: String? {
            switch self {
            case .auto:
                return nil
            case .chinese:
                return "zh"
            case .english:
                return "en"
            case .custom(let code):
                return code
            }
        }
    }

    var language: Language = .auto
    var translateToEnglish = false
    var useTimestamps = true
    var maxAudioDuration: TimeInterval? = 300
}
```

### 7.3 `SpeechTranscriptionResult.swift`

```swift
import Foundation

struct SpeechTranscriptionResult: Equatable, Sendable {
    var text: String
    var segments: [SpeechTranscriptionSegment]
    var detectedLanguage: String?
    var audioDuration: TimeInterval
    var processingDuration: TimeInterval
}

struct SpeechTranscriptionSegment: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}
```

### 7.4 `SpeechRecognitionState.swift`

```swift
import Foundation

enum SpeechRecognitionState: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording
    case preparingAudio
    case loadingModel
    case transcribing(progress: Double?)
    case completed(SpeechTranscriptionResult)
    case failed(String)
}
```

### 7.5 `SpeechRecognitionError.swift`

```swift
import Foundation

enum SpeechRecognitionError: LocalizedError, Equatable, Sendable {
    case microphonePermissionDenied
    case modelNotFound(String)
    case modelLoadFailed(String)
    case recorderUnavailable
    case recordingFailed(String)
    case audioConversionFailed(String)
    case unsupportedAudioFormat
    case transcriptionFailed(String)
    case cancelled
    case audioTooLong(maxDuration: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to transcribe speech."
        case .modelNotFound(let name):
            return "Speech model not found: \(name)."
        case .modelLoadFailed(let reason):
            return "Speech model failed to load: \(reason)."
        case .recorderUnavailable:
            return "Audio recorder is unavailable."
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)."
        case .audioConversionFailed(let reason):
            return "Audio conversion failed: \(reason)."
        case .unsupportedAudioFormat:
            return "Unsupported audio format."
        case .transcriptionFailed(let reason):
            return "Speech transcription failed: \(reason)."
        case .cancelled:
            return "Speech transcription was cancelled."
        case .audioTooLong(let maxDuration):
            return "Audio is too long. Maximum duration is \(Int(maxDuration)) seconds."
        }
    }
}
```

---

## 8. Infrastructure 层设计

### 8.1 `WhisperModelStore.swift`

职责：查找 bundle 内置模型，后续扩展 Application Support 下载模型。

首版模型目录：

```text
LinXApple/Resources/WhisperModels/
```

首版默认模型：

```text
ggml-base.bin
```

建议 API：

```swift
import Foundation

final class WhisperModelStore {
    enum ModelSize: String, CaseIterable, Sendable {
        case tiny = "ggml-tiny"
        case base = "ggml-base"
    }

    private let bundle: Bundle
    private let bundleDirectory: String

    init(bundle: Bundle = .main, bundleDirectory: String = "WhisperModels") {
        self.bundle = bundle
        self.bundleDirectory = bundleDirectory
    }

    func modelURL(for size: ModelSize) throws -> URL {
        guard let url = bundle.url(
            forResource: size.rawValue,
            withExtension: "bin",
            subdirectory: bundleDirectory
        ) else {
            throw SpeechRecognitionError.modelNotFound(size.rawValue)
        }
        return url
    }
}
```

### 8.2 `SpeechAudioSessionManager.swift`

职责：配置 `AVAudioSession` 用于录音，录音完成后恢复音频会话。

要求：

- 使用 `.playAndRecord` + `.measurement`
- 允许蓝牙麦克风
- 停止录音后 deactivate，并使用 `.notifyOthersOnDeactivation`
- 只在需要录音时激活 audio session

### 8.3 `SpeechAudioRecorder.swift`

职责：请求麦克风权限、开始录音、停止录音并返回临时音频 URL。

要求：

- ViewModel 调用时在 MainActor 协调状态
- 录音文件写入 `FileManager.default.temporaryDirectory`
- 首版录制 `m4a`，单声道，44.1kHz 或系统合适采样率
- 权限拒绝时返回 `SpeechRecognitionError.microphonePermissionDenied`
- `stopRecording()` 在没有 active recorder 时返回 `recorderUnavailable`

### 8.4 `SpeechAudioConverter.swift`

职责：将录音输出转换为 whisper 兼容 PCM。

要求：

- 输入：首版录音产生的 `m4a`；后续可扩展 `wav`、`caf`
- 输出：16kHz、mono、Float32 PCM
- 不在 MainActor 执行转换
- 失败时映射到 `SpeechRecognitionError.audioConversionFailed`
- 单元测试验证输出格式

实现可以选择：

- 直接输出 temporary `.wav`，由 `WhisperPCMReader` 读取 Float32 PCM
- 或直接返回 `[Float]` PCM buffer，减少中间文件

首版优先选择易测试的 `.wav` 文件输出。

### 8.5 `WhisperTranscriptionService.swift`

职责：orchestrate 模型查找、时长限制、音频转换、bridge 调用和性能日志。

要求：

- 实现 `SpeechTranscriptionProviding`
- 默认 `maxAudioDuration` 为 300 秒
- 转换和推理都不能在 MainActor 执行
- 捕获 `CancellationError` 并映射为 `SpeechRecognitionError.cancelled`
- 成功或失败都通过 `LinxDiagnostics.speech` 打点

---

## 9. Whisper C/C++ Bridge 设计

Bridge 位于 `LinXApple/Sources/SpeechRecognition/Bridge/`。

### 9.1 实现前置检查

实现 `WhisperCppBridge` 前必须确认：

1. 当前 `whisper.h` 中 context init API 名称
2. 当前 full params API 名称和字段
3. Swift 可 import 的 module 名称
4. `whisper_full` 的 PCM 输入格式要求
5. segment text/time API 名称
6. context 释放 API 名称
7. 是否需要额外 linker flags 或 C++ runtime 设置

不得硬编码未验证的旧 API，例如只凭示例假设 `whisper_init_from_file` 一定存在。

### 9.2 并发和生命周期要求

- whisper context 和 C pointer 不得裸露给 UI 或 `@MainActor` ViewModel
- 非 Sendable C pointer 需要封装在 actor、单一 serial executor、或严格局部后台执行闭包中
- 推理执行必须离开 MainActor
- cancellation 后需要停止后续处理并释放 context
- 任意 error path 都必须释放 context
- 多次识别不应复用已释放 context
- 如果后续缓存 context，需要明确模型切换、内存上限和 teardown 策略

### 9.3 `WhisperCppBridge.swift` API 草案

```swift
import Foundation

actor WhisperCppBridge {
    struct Configuration: Sendable {
        var modelURL: URL
        var languageCode: String?
        var translateToEnglish: Bool
        var useTimestamps: Bool
    }

    func transcribe(
        pcmURL: URL,
        configuration: Configuration
    ) async throws -> SpeechTranscriptionResult {
        // Implementation must be written against the checked whisper.h API.
        throw SpeechRecognitionError.transcriptionFailed(
            "WhisperCppBridge is not implemented yet."
        )
    }
}
```

### 9.4 PCM Reader

`WhisperPCMReader` 负责读取转换后的 16kHz mono Float32 PCM，避免把 WAV parsing 逻辑混进 bridge。

要求：

- 验证采样率为 16kHz
- 验证 channel count 为 1
- 输出 `[Float]`
- 失败时抛 `unsupportedAudioFormat` 或 `audioConversionFailed`

---

## 10. ChatUI 集成

### 10.1 首版交互

首版不要新增独立 demo 首页。直接在 `ChatScene` 中增加语音输入入口。

推荐交互：

```text
mic button tap
-> present SpeechInputSheet
-> request microphone permission
-> start recording
-> stop
-> transcribe
-> pass result text back to ChatScene
-> ChatScene appends/replaces draftText
-> user reviews and taps existing send button
```

### 10.2 `SpeechRecognitionViewModel.swift`

位置：

```text
LinXApple/Sources/ChatUI/SpeechRecognitionViewModel.swift
```

职责：

- `@MainActor final class SpeechRecognitionViewModel: ObservableObject`
- 管理 `SpeechRecognitionState`
- 调用 recorder 开始/停止录音
- 调用 `SpeechTranscriptionProviding` 转写
- 暴露 `transcribedText`
- 支持 cancel
- 不直接 import 或调用 whisper C API

约束：

- 从 SwiftUI event handler 使用 `Task { await viewModel.startRecording() }`
- 不使用 detached task 管理 UI 状态
- `currentTask` 取消时恢复状态
- 错误只展示给语音输入 UI 或 `ChatScene` 的轻量错误提示，不混入认证/Pod 错误语义

### 10.3 `SpeechInputSheet.swift`

位置：

```text
LinXApple/Sources/ChatUI/SpeechInputSheet.swift
```

职责：

- 展示录音、转写、失败、完成状态
- 提供开始、停止、取消按钮
- 转写成功后调用 `onTranscript(String)`
- 使用 LinX 现有颜色和 SwiftUI 风格
- 不做独立 marketing/demo 页面

### 10.4 `ChatScene.swift` 修改点

在 `ChatScene` 中：

- 新增 mic button 或 toolbar item
- 持有 sheet presentation state
- 接收 transcript 后写入 `draftText`
- 保持 `send(_:)` 仍只调用 `viewModel.enqueueSend(draft.text)`

草案：

```swift
private func applyTranscript(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return }

    if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        draftText = trimmed
    } else {
        draftText += "\n" + trimmed
    }
}
```

---

## 11. 性能日志与隐私

### 11.1 `LinxDiagnostics` 扩展

在 `LinXApple/Sources/AppCore/LinxDiagnostics.swift` 新增：

```swift
static let speech = Logger(subsystem: subsystem, category: "speech")
```

### 11.2 记录字段

允许记录：

```text
audioDuration
conversionDuration
modelLoadDuration
transcriptionDuration
totalDuration
modelName
iOSVersion
deviceClass
errorHash
```

禁止记录：

```text
raw audio path
raw transcript text
WebID
access token
refresh token
local absolute model path
```

错误日志使用 `LinxDiagnostics.fingerprint(_:)` 对敏感值取 hash。

---

## 12. 模型文件策略

### 12.1 首版

内置一个或两个模型：

```text
LinXApple/Resources/WhisperModels/ggml-tiny.bin
LinXApple/Resources/WhisperModels/ggml-base.bin
```

默认：

```text
ggml-base.bin
```

如果包体积压力较大，首版只内置 `ggml-tiny.bin`，把 `base` 放到后续下载阶段。

### 12.2 后续下载目录

```text
Application Support/WhisperModels/
```

后续下载模型需要维护 manifest：

```json
{
  "models": [
    {
      "name": "ggml-base.bin",
      "sha256": "...",
      "size": 147000000,
      "language": "multilingual"
    }
  ]
}
```

首版不实现下载和 manifest 校验，但 `WhisperModelStore` 的接口应保留扩展空间。

---

## 13. 测试计划

### 13.1 单元测试位置

测试放入现有 target：

```text
LinXAppleTests/SpeechRecognitionTests.swift
```

或按主题拆分：

```text
LinXAppleTests/WhisperModelStoreTests.swift
LinXAppleTests/SpeechAudioConverterTests.swift
LinXAppleTests/SpeechRecognitionViewModelTests.swift
```

不要新增 test target 或独立 scheme。

### 13.2 必测用例

`WhisperModelStoreTests`：

```swift
func testModelURL_whenModelExists_returnsURL()
func testModelURL_whenModelMissing_throwsModelNotFound()
```

`SpeechAudioConverterTests`：

```swift
func testConvertToWhisperPCM_outputsFile()
func testConvertToWhisperPCM_outputs16kMonoFloat32()
func testConvertInvalidFile_throwsConversionFailure()
```

`SpeechRecognitionViewModelTests`：

```swift
func testStartRecording_whenPermissionDenied_setsFailedState()
func testStopRecording_whenTranscriptionSucceeds_setsCompletedState()
func testCancel_setsIdleState()
func testStopRecording_whenTranscriptionFails_setsFailedState()
```

`WhisperTranscriptionServiceTests`：

```swift
func testTranscribe_whenAudioTooLong_throwsAudioTooLong()
func testTranscribe_whenModelMissing_throwsModelNotFound()
func testTranscribe_whenCancelled_mapsCancellation()
```

### 13.3 Test doubles

模拟器和 CI 不依赖真实麦克风或大模型。

需要提供 fake：

- fake recorder permission granted/denied
- fake recorder output URL
- fake transcription service success/failure/cancellation
- fake model store
- fake bridge

真实 whisper 模型集成测试可以使用 `XCTSkip`，或归入手动真机验证。

### 13.4 验证命令

修改 `project.yml` 后：

```bash
cd apple
xcodegen generate
```

从仓库根目录运行测试：

```bash
xcodebuild test \
  -project apple/LinXApple.xcodeproj \
  -scheme LinXApple \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 14. 真机验证矩阵

首版必须真机验证：

- 首次麦克风权限允许
- 首次麦克风权限拒绝
- 录音开始/停止
- 录音中取消
- 转写中取消
- 模型缺失错误
- 10 秒中文
- 10 秒英文
- 10 秒中英混合
- 60 秒中文或中英混合
- 蓝牙耳机麦克风
- AirPods
- 锁屏/来电/后台切前台中断
- 低电量模式

记录指标：

```text
success/failure
audioDuration
conversionDuration
transcriptionDuration
totalDuration
peakMemory
noticeableUIStall
deviceModel
iOSVersion
modelName
```

---

## 15. 执行任务拆分

### Task 1: 结构确认

验收：

```text
App target: LinXApple
Build system: XcodeGen project.yml
Info.plist: LinXApple/Resources/Info.plist
Sources: LinXApple/Sources
Resources: LinXApple/Resources
Tests: LinXAppleTests
```

### Task 2: 引入 whisper artifact

操作：

1. 添加或确认 `ThirdParty/whisper.cpp`
2. 构建 `whisper.xcframework`
3. 复制到 `Vendors/Whisper/whisper.xcframework`
4. 打开 `whisper.h` 或 framework headers 校验 API

验收：

```text
Vendors/Whisper/whisper.xcframework exists
Current C API has been checked
Swift import module name is known
```

### Task 3: 更新 XcodeGen 和权限

操作：

1. 在 `project.yml` 中为 `LinXApple` 添加 framework dependency
2. 在 `LinXApple/Resources/Info.plist` 添加 microphone usage string
3. 运行 `xcodegen generate`

验收：

```text
Project regenerates
LinXApple links whisper.xcframework
Info.plist contains NSMicrophoneUsageDescription
```

### Task 4: 添加 Domain 层

创建：

```text
LinXApple/Sources/SpeechRecognition/Domain/SpeechTranscriptionProviding.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechTranscriptionOptions.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechTranscriptionResult.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechRecognitionState.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechRecognitionError.swift
```

验收：

```text
No UI dependency
No whisper C API dependency
Sendable/Equatable requirements satisfied
```

### Task 5: 添加录音与音频会话

创建：

```text
LinXApple/Sources/SpeechRecognition/Infrastructure/SpeechAudioSessionManager.swift
LinXApple/Sources/SpeechRecognition/Infrastructure/SpeechAudioRecorder.swift
```

验收：

```text
Permission denied does not crash
Start/stop returns temporary audio URL on device
Audio session deactivates after stop/cancel
```

### Task 6: 添加音频转换

创建：

```text
LinXApple/Sources/SpeechRecognition/Infrastructure/SpeechAudioConverter.swift
LinXApple/Sources/SpeechRecognition/Bridge/WhisperPCMReader.swift
```

验收：

```text
Output is 16kHz mono Float32
Conversion does not run on MainActor
Invalid input maps to conversion error
```

### Task 7: 添加模型查找

创建：

```text
LinXApple/Sources/SpeechRecognition/Infrastructure/WhisperModelStore.swift
LinXApple/Resources/WhisperModels/ggml-tiny.bin
LinXApple/Resources/WhisperModels/ggml-base.bin
```

验收：

```text
Bundle model lookup succeeds when file exists
Missing model throws modelNotFound
No absolute developer machine paths
```

### Task 8: 实现 Whisper bridge

创建：

```text
LinXApple/Sources/SpeechRecognition/Bridge/WhisperCppBridge.swift
```

操作：

1. 根据当前 `whisper.h` 实现 context init
2. 设置 full params、language、translate、timestamp flags
3. 调用 full transcription
4. 解析 segments text、start、end
5. 释放 context
6. 处理 cancellation/error path

验收：

```text
Sample wav can transcribe on device
Repeated transcription does not crash
Context is released on success/failure/cancel
```

### Task 9: 实现 transcription service

创建：

```text
LinXApple/Sources/SpeechRecognition/Infrastructure/WhisperTranscriptionService.swift
```

验收：

```text
Implements SpeechTranscriptionProviding
Enforces maxAudioDuration
Runs conversion and inference off MainActor
Logs performance without leaking transcript/audio path
```

### Task 10: 接入 ChatUI

创建或修改：

```text
LinXApple/Sources/ChatUI/SpeechRecognitionViewModel.swift
LinXApple/Sources/ChatUI/SpeechInputSheet.swift
LinXApple/Sources/ChatUI/ChatScene.swift
```

验收：

```text
Mic entry is available in ChatScene
Transcript fills draftText
User must manually send
UI does not call WhisperCppBridge directly
```

### Task 11: 添加测试

创建：

```text
LinXAppleTests/SpeechRecognitionTests.swift
```

验收：

```text
Model store tests pass
Audio converter tests pass or skip only when simulator fixture unavailable
ViewModel fake-recorder/fake-transcriber tests pass
Service duration/error tests pass
```

### Task 12: 真机性能验证

验收：

```text
10s audio stable
60s audio stable
UI remains responsive
No repeated-run crash
No obvious memory leak
```

---

## 16. App Store 风险与策略

### 16.1 包体积

风险：

```text
Whisper model files can significantly increase app size.
```

策略：

```text
First bundle tiny or base only.
Move small/medium models to later on-demand download.
```

### 16.2 隐私说明

需要在隐私文案中说明：

```text
Speech is transcribed locally on device.
Audio is not uploaded for STT.
Only text that the user sends enters normal chat storage and runtime flow.
```

### 16.3 权限弹窗

麦克风权限文案应明确：

```text
Used to transcribe speech into chat text on this device.
```

---

## 17. 后续增强

### 17.1 本地音频文件转写

后续可增加 Files app importer：

- 更新 Info.plist 和 document picker UI
- 复用 `SpeechAudioConverter`
- 添加文件大小和时长限制
- 不自动发送，仍先回填 draft

### 17.2 模型下载和切换

后续扩展：

- `Application Support/WhisperModels/`
- manifest sha256 校验
- 下载进度 UI
- tiny/base/small 选择
- 设备性能分级默认模型

### 17.3 Core ML encoder 加速

后续任务：

```text
1. Generate encoder mlmodel from matching whisper.cpp version
2. Compile mlmodelc
3. Bundle or download mlmodelc with matching ggml model
4. Enable Core ML params in bridge after API verification
5. Compare device transcription duration and memory
```

注意：即使启用 Core ML encoder，仍然需要 ggml 模型，decoder 仍由 whisper.cpp 执行。

### 17.4 长音频分片

后续扩展：

- 超过 300 秒音频分片处理
- segment 合并
- cancellation-aware batch pipeline
- 后台任务和内存峰值控制

---

## 18. Definition of Done

### 18.1 编译

- `xcodegen generate` 成功
- Debug build 成功
- Release build 成功
- Simulator tests 成功
- 真机 build 成功

### 18.2 功能

- 麦克风权限允许后可录音
- 麦克风权限拒绝有明确提示
- 录音停止后可本地转写
- 转写文本回填聊天 draft
- 用户手动发送后复用现有 chat flow
- 模型缺失有明确提示
- 转写中可取消

### 18.3 工程

- STT 能力封装在 `SpeechRecognition`
- Chat UI 只依赖 ViewModel/protocol，不直接调用 C bridge
- `ChatExperienceModel.enqueueSend(_:)` 语义不变
- 无主线程推理
- 无主线程音频转换
- 无硬编码本机绝对路径
- 有 fake-based 单元测试

### 18.4 性能

- 10 秒音频稳定识别
- 60 秒音频稳定识别
- 推理期间 UI 可操作
- 多次识别不崩溃
- 无明显内存泄漏

---

## 19. 执行纪律

执行本计划时必须遵守：

1. 不做大范围无关重构
2. 不复制 whisper 示例 app 作为生产代码
3. 不手动编辑 generated `LinXApple.xcodeproj`
4. 修改 `project.yml` 后运行 `xcodegen generate`
5. 每个阶段后至少运行可用的编译或测试命令
6. 不把 raw audio、transcript、token、WebID 写入日志
7. 不把模型路径硬编码为开发机绝对路径
8. 保留 provider 替换扩展点
9. 首版转写只回填 draft，不自动发送
10. 最终报告列出修改文件、新增文件、编译结果、测试结果、已知限制

---

## 20. 推荐提交顺序

```text
commit 1: add speech recognition domain models
commit 2: add whisper model store
commit 3: add audio recording service
commit 4: add audio conversion pipeline
commit 5: add whisper cpp bridge
commit 6: add whisper transcription service
commit 7: add speech recognition view model
commit 8: integrate speech input into chat scene
commit 9: add speech recognition tests
commit 10: add speech diagnostics and performance validation
```

---

## 21. 最终文件清单

```text
project.yml
LinXApple/Resources/Info.plist
LinXApple/Resources/WhisperModels/ggml-tiny.bin
LinXApple/Resources/WhisperModels/ggml-base.bin

LinXApple/Sources/AppCore/LinxDiagnostics.swift

LinXApple/Sources/SpeechRecognition/Domain/SpeechTranscriptionProviding.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechTranscriptionOptions.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechTranscriptionResult.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechRecognitionState.swift
LinXApple/Sources/SpeechRecognition/Domain/SpeechRecognitionError.swift

LinXApple/Sources/SpeechRecognition/Infrastructure/WhisperModelStore.swift
LinXApple/Sources/SpeechRecognition/Infrastructure/WhisperTranscriptionService.swift
LinXApple/Sources/SpeechRecognition/Infrastructure/SpeechAudioRecorder.swift
LinXApple/Sources/SpeechRecognition/Infrastructure/SpeechAudioConverter.swift
LinXApple/Sources/SpeechRecognition/Infrastructure/SpeechAudioSessionManager.swift

LinXApple/Sources/SpeechRecognition/Bridge/WhisperCppBridge.swift
LinXApple/Sources/SpeechRecognition/Bridge/WhisperPCMReader.swift

LinXApple/Sources/ChatUI/SpeechRecognitionViewModel.swift
LinXApple/Sources/ChatUI/SpeechInputSheet.swift
LinXApple/Sources/ChatUI/ChatScene.swift

Vendors/Whisper/whisper.xcframework

LinXAppleTests/SpeechRecognitionTests.swift
```
