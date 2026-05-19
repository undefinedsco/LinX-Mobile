# PLAN-stt-production.md

# Production PLAN: whisper.cpp 接入现有 iOS 工程

> 目标：将 `whisper.cpp` / `whisper.swiftui` 的本地 STT 能力工程化接入现有 iOS App，形成可维护、可测试、可扩展的语音转文字模块。
>
> 适用场景：
>
> - 现有 iOS 工程
> - 本地离线语音识别
> - 中文 / 英文 / 中英混合转写
> - 可后续扩展 Core ML encoder 加速
> - 可后续扩展模型下载、模型切换、长音频分片识别

---

## 0. 总体目标

### 0.1 功能目标

实现一个独立的 iOS STT 模块：

- 支持麦克风录音
- 支持本地音频文件转写
- 支持 whisper.cpp 本地推理
- 支持中文、英文、自动识别语言
- 支持识别状态回调
- 支持错误处理
- 支持基础性能日志
- 支持后续模型热更新 / 下载

### 0.2 工程目标

模块应满足：

- 不污染现有业务代码
- 通过协议隔离 STT 实现
- UI 与推理逻辑解耦
- 可以替换为 Apple Speech / OpenAI API / Deepgram 等其他 STT Provider
- 支持单元测试
- 支持真机性能验证
- 支持 XcodeGen 或手动 Xcode 工程接入

---

## 1. 推荐架构

```text
App
 └── Features
      └── SpeechRecognition
           ├── UI
           │    └── SpeechRecognitionView.swift
           ├── ViewModel
           │    └── SpeechRecognitionViewModel.swift
           ├── Domain
           │    ├── TranscriptionService.swift
           │    ├── TranscriptionResult.swift
           │    ├── TranscriptionState.swift
           │    └── SpeechRecognitionError.swift
           ├── Infrastructure
           │    ├── WhisperTranscriptionService.swift
           │    ├── WhisperModelManager.swift
           │    ├── WhisperCppBridge.swift
           │    ├── AudioRecorderService.swift
           │    ├── AudioFileConverter.swift
           │    └── AudioSessionManager.swift
           └── Tests
                ├── WhisperModelManagerTests.swift
                ├── AudioFileConverterTests.swift
                └── SpeechRecognitionViewModelTests.swift

Vendors
 └── Whisper
      └── whisper.xcframework

Resources
 └── WhisperModels
      ├── ggml-tiny.bin
      ├── ggml-base.bin
      └── ggml-small.bin
```

---

## 2. 第三方依赖

### 2.1 必需依赖

| 依赖 | 用途 |
|---|---|
| whisper.cpp | 本地 STT 推理 |
| whisper.xcframework | iOS 可链接二进制 |
| AVFoundation | 录音、音频转换 |
| Foundation | 文件、并发、错误处理 |
| Swift Concurrency | async / await 推理封装 |

### 2.2 可选依赖

| 依赖 | 用途 |
|---|---|
| XcodeGen | 生成 Xcode project |
| Core ML | encoder 加速 |
| os.log | 性能日志 |
| Combine | ViewModel 状态绑定，SwiftUI 项目可选 |

---

## 3. 构建 whisper.xcframework

### 3.1 添加 whisper.cpp

推荐使用 Git submodule：

```bash
mkdir -p ThirdParty
git submodule add https://github.com/ggml-org/whisper.cpp.git ThirdParty/whisper.cpp
git submodule update --init --recursive
```

### 3.2 构建 iOS XCFramework

```bash
cd ThirdParty/whisper.cpp
./build-xcframework.sh
```

生成：

```text
ThirdParty/whisper.cpp/build-apple/whisper.xcframework
```

### 3.3 复制到工程

```bash
mkdir -p Vendors/Whisper
cp -R ThirdParty/whisper.cpp/build-apple/whisper.xcframework Vendors/Whisper/
```

### 3.4 常见错误

如果出现：

```text
iphoneos is not an iOS SDK
```

执行：

```bash
sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
```

---

## 4. XcodeGen 配置

如果现有项目使用 XcodeGen，将以下内容合并到 `project.yml`。

### 4.1 示例 project.yml 片段

```yaml
name: YourApp
options:
  bundleIdPrefix: com.yourcompany

packages: {}

targets:
  YourApp:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - path: YourApp
      - path: Features/SpeechRecognition
      - path: Resources
    resources:
      - path: Resources/WhisperModels
    settings:
      base:
        INFOPLIST_FILE: YourApp/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.yourcompany.yourapp
        SWIFT_VERSION: 5.9
        ENABLE_BITCODE: NO
    dependencies:
      - framework: Vendors/Whisper/whisper.xcframework
        embed: true
        codeSign: true

  YourAppTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - path: YourAppTests
      - path: Features/SpeechRecognition/Tests
    dependencies:
      - target: YourApp
```

### 4.2 重新生成工程

```bash
xcodegen generate
```

---

## 5. Package.swift 方案

如果现有工程拆分为 Swift Package，可新增 `SpeechRecognitionKit`。

### 5.1 Package.swift

```swift
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpeechRecognitionKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SpeechRecognitionKit",
            targets: ["SpeechRecognitionKit"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "Whisper",
            path: "../../Vendors/Whisper/whisper.xcframework"
        ),
        .target(
            name: "SpeechRecognitionKit",
            dependencies: ["Whisper"],
            path: "Sources",
            resources: [
                .copy("Resources/WhisperModels")
            ]
        ),
        .testTarget(
            name: "SpeechRecognitionKitTests",
            dependencies: ["SpeechRecognitionKit"],
            path: "Tests"
        )
    ]
)
```

### 5.2 Package 目录

```text
Packages/
 └── SpeechRecognitionKit/
      ├── Package.swift
      ├── Sources/
      │    ├── Domain/
      │    ├── Infrastructure/
      │    └── UI/
      ├── Resources/
      │    └── WhisperModels/
      └── Tests/
```

---

## 6. Info.plist 权限

添加：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要使用麦克风进行语音识别</string>
```

如果支持从文件 App 导入音频：

```xml
<key>UISupportsDocumentBrowser</key>
<true/>
```

---

## 7. Domain 层 Skeleton

### 7.1 TranscriptionService.swift

```swift
import Foundation

public protocol TranscriptionService {
    func transcribe(
        audioURL: URL,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult
}
```

### 7.2 TranscriptionOptions.swift

```swift
import Foundation

public struct TranscriptionOptions: Equatable, Sendable {
    public enum Language: Equatable, Sendable {
        case auto
        case chinese
        case english
        case custom(String)

        public var whisperCode: String? {
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

    public let language: Language
    public let translateToEnglish: Bool
    public let useTimestamps: Bool
    public let maxAudioDuration: TimeInterval?

    public init(
        language: Language = .auto,
        translateToEnglish: Bool = false,
        useTimestamps: Bool = true,
        maxAudioDuration: TimeInterval? = nil
    ) {
        self.language = language
        self.translateToEnglish = translateToEnglish
        self.useTimestamps = useTimestamps
        self.maxAudioDuration = maxAudioDuration
    }
}
```

### 7.3 TranscriptionResult.swift

```swift
import Foundation

public struct TranscriptionResult: Equatable, Sendable {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let detectedLanguage: String?
    public let duration: TimeInterval
    public let processingTime: TimeInterval

    public init(
        text: String,
        segments: [TranscriptionSegment],
        detectedLanguage: String?,
        duration: TimeInterval,
        processingTime: TimeInterval
    ) {
        self.text = text
        self.segments = segments
        self.detectedLanguage = detectedLanguage
        self.duration = duration
        self.processingTime = processingTime
    }
}

public struct TranscriptionSegment: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}
```

### 7.4 TranscriptionState.swift

```swift
import Foundation

public enum TranscriptionState: Equatable {
    case idle
    case requestingPermission
    case recording
    case preparingAudio
    case loadingModel
    case transcribing(progress: Double?)
    case completed(TranscriptionResult)
    case failed(String)
}
```

### 7.5 SpeechRecognitionError.swift

```swift
import Foundation

public enum SpeechRecognitionError: Error, LocalizedError, Equatable {
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

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "麦克风权限未开启"
        case .modelNotFound(let name):
            return "未找到语音识别模型：\(name)"
        case .modelLoadFailed(let reason):
            return "模型加载失败：\(reason)"
        case .recorderUnavailable:
            return "录音服务不可用"
        case .recordingFailed(let reason):
            return "录音失败：\(reason)"
        case .audioConversionFailed(let reason):
            return "音频转换失败：\(reason)"
        case .unsupportedAudioFormat:
            return "不支持的音频格式"
        case .transcriptionFailed(let reason):
            return "语音识别失败：\(reason)"
        case .cancelled:
            return "识别已取消"
        case .audioTooLong(let maxDuration):
            return "音频过长，最大支持 \(Int(maxDuration)) 秒"
        }
    }
}
```

---

## 8. Infrastructure 层 Skeleton

### 8.1 WhisperModelManager.swift

```swift
import Foundation

public final class WhisperModelManager {
    public enum ModelSize: String, CaseIterable, Sendable {
        case tiny = "ggml-tiny"
        case base = "ggml-base"
        case small = "ggml-small"
    }

    private let bundle: Bundle
    private let modelDirectory: String

    public init(
        bundle: Bundle = .main,
        modelDirectory: String = "WhisperModels"
    ) {
        self.bundle = bundle
        self.modelDirectory = modelDirectory
    }

    public func modelPath(for size: ModelSize) throws -> String {
        guard let url = bundle.url(
            forResource: size.rawValue,
            withExtension: "bin",
            subdirectory: modelDirectory
        ) else {
            throw SpeechRecognitionError.modelNotFound(size.rawValue)
        }
        return url.path
    }

    public func availableModels() -> [ModelSize] {
        ModelSize.allCases.filter {
            try? modelPath(for: $0) != nil
        }
    }
}
```

### 8.2 AudioSessionManager.swift

```swift
import AVFoundation

public final class AudioSessionManager {
    public init() {}

    public func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true)
    }

    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
```

### 8.3 AudioRecorderService.swift

```swift
import AVFoundation
import Foundation

public final class AudioRecorderService: NSObject {
    private var recorder: AVAudioRecorder?
    private let audioSessionManager: AudioSessionManager

    public init(audioSessionManager: AudioSessionManager = AudioSessionManager()) {
        self.audioSessionManager = audioSessionManager
        super.init()
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func startRecording() throws {
        try audioSessionManager.configureForRecording()

        let outputURL = Self.makeRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw SpeechRecognitionError.recordingFailed("AVAudioRecorder record() returned false")
        }

        self.recorder = recorder
    }

    public func stopRecording() throws -> URL {
        guard let recorder else {
            throw SpeechRecognitionError.recorderUnavailable
        }

        recorder.stop()
        self.recorder = nil
        audioSessionManager.deactivate()

        return recorder.url
    }

    private static func makeRecordingURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
    }
}
```

### 8.4 AudioFileConverter.swift

```swift
import AVFoundation
import Foundation

public final class AudioFileConverter {
    public init() {}

    public func convertToWhisperCompatibleWav(inputURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let inputFile = try AVAudioFile(forReading: inputURL)

            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ) else {
                throw SpeechRecognitionError.audioConversionFailed("Cannot create output AVAudioFormat")
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("whisper-\(UUID().uuidString).wav")

            guard let converter = AVAudioConverter(
                from: inputFile.processingFormat,
                to: outputFormat
            ) else {
                throw SpeechRecognitionError.audioConversionFailed("Cannot create AVAudioConverter")
            }

            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: outputFormat.settings
            )

            let frameCapacity = AVAudioFrameCount(outputFormat.sampleRate)
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCapacity
            ) else {
                throw SpeechRecognitionError.audioConversionFailed("Cannot create output buffer")
            }

            var didReachEnd = false

            while !didReachEnd {
                try converter.convert(to: outputBuffer) { _, outStatus in
                    let inputFrameCapacity = AVAudioFrameCount(inputFile.processingFormat.sampleRate)

                    guard let inputBuffer = AVAudioPCMBuffer(
                        pcmFormat: inputFile.processingFormat,
                        frameCapacity: inputFrameCapacity
                    ) else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }

                    do {
                        try inputFile.read(into: inputBuffer)
                        if inputBuffer.frameLength == 0 {
                            outStatus.pointee = .endOfStream
                            didReachEnd = true
                            return nil
                        } else {
                            outStatus.pointee = .haveData
                            return inputBuffer
                        }
                    } catch {
                        outStatus.pointee = .endOfStream
                        didReachEnd = true
                        return nil
                    }
                }

                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                    outputBuffer.frameLength = 0
                }
            }

            return outputURL
        }.value
    }
}
```

---

## 9. Whisper C/C++ Bridge 设计

> 说明：具体 symbol 名称需要以当前 `whisper.xcframework` 暴露的 C API 为准。Codex 实现时必须打开 whisper.cpp 的 `whisper.h` 校验函数签名。

### 9.1 WhisperCppBridge.swift

```swift
import Foundation

public final class WhisperCppBridge {
    public struct Configuration: Sendable {
        public let modelPath: String
        public let languageCode: String?
        public let translateToEnglish: Bool
        public let useTimestamps: Bool

        public init(
            modelPath: String,
            languageCode: String?,
            translateToEnglish: Bool,
            useTimestamps: Bool
        ) {
            self.modelPath = modelPath
            self.languageCode = languageCode
            self.translateToEnglish = translateToEnglish
            self.useTimestamps = useTimestamps
        }
    }

    public init() {}

    public func transcribe(
        wavURL: URL,
        configuration: Configuration
    ) async throws -> TranscriptionResult {
        try await Task.detached(priority: .userInitiated) {
            let startTime = Date()

            // TODO:
            // 1. Read WAV into Float32 PCM array
            // 2. whisper_init_from_file_with_params / whisper_init_from_file
            // 3. whisper_full_default_params
            // 4. configure language / translate / print flags
            // 5. whisper_full
            // 6. whisper_full_n_segments
            // 7. whisper_full_get_segment_text
            // 8. whisper_full_get_segment_t0 / t1
            // 9. whisper_free

            throw SpeechRecognitionError.transcriptionFailed(
                "WhisperCppBridge not implemented. Implement against whisper.h."
            )
        }.value
    }
}
```

### 9.2 Codex 实现要求

Codex 必须：

1. 打开 `ThirdParty/whisper.cpp/include/whisper.h`
2. 校验当前版本 C API
3. 根据 C API 实现 Swift bridge
4. 不要硬编码过期函数签名
5. 确保 context 生命周期正确释放
6. 确保推理不在主线程执行

---

## 10. WhisperTranscriptionService.swift

```swift
import Foundation

public final class WhisperTranscriptionService: TranscriptionService {
    private let modelManager: WhisperModelManager
    private let audioConverter: AudioFileConverter
    private let bridge: WhisperCppBridge
    private let modelSize: WhisperModelManager.ModelSize

    public init(
        modelManager: WhisperModelManager = WhisperModelManager(),
        audioConverter: AudioFileConverter = AudioFileConverter(),
        bridge: WhisperCppBridge = WhisperCppBridge(),
        modelSize: WhisperModelManager.ModelSize = .base
    ) {
        self.modelManager = modelManager
        self.audioConverter = audioConverter
        self.bridge = bridge
        self.modelSize = modelSize
    }

    public func transcribe(
        audioURL: URL,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult {
        if let maxDuration = options.maxAudioDuration {
            let duration = try Self.audioDuration(url: audioURL)
            guard duration <= maxDuration else {
                throw SpeechRecognitionError.audioTooLong(maxDuration: maxDuration)
            }
        }

        let modelPath = try modelManager.modelPath(for: modelSize)
        let wavURL = try await audioConverter.convertToWhisperCompatibleWav(inputURL: audioURL)

        let config = WhisperCppBridge.Configuration(
            modelPath: modelPath,
            languageCode: options.language.whisperCode,
            translateToEnglish: options.translateToEnglish,
            useTimestamps: options.useTimestamps
        )

        return try await bridge.transcribe(
            wavURL: wavURL,
            configuration: config
        )
    }

    private static func audioDuration(url: URL) throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
}
```

> 注意：该文件需要 import AVFoundation，因为使用了 `AVURLAsset`。

---

## 11. ViewModel Skeleton

```swift
import Foundation
import Combine

@MainActor
public final class SpeechRecognitionViewModel: ObservableObject {
    @Published public private(set) var state: TranscriptionState = .idle
    @Published public private(set) var transcribedText: String = ""

    private let recorder: AudioRecorderService
    private let transcriptionService: TranscriptionService
    private var currentTask: Task<Void, Never>?

    public init(
        recorder: AudioRecorderService = AudioRecorderService(),
        transcriptionService: TranscriptionService = WhisperTranscriptionService()
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
    }

    public func startRecording() async {
        state = .requestingPermission

        let granted = await recorder.requestPermission()
        guard granted else {
            state = .failed(SpeechRecognitionError.microphonePermissionDenied.localizedDescription)
            return
        }

        do {
            try recorder.startRecording()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func stopRecordingAndTranscribe() {
        currentTask?.cancel()

        currentTask = Task { [weak self] in
            guard let self else { return }

            do {
                let audioURL = try self.recorder.stopRecording()
                self.state = .preparingAudio

                let result = try await self.transcriptionService.transcribe(
                    audioURL: audioURL,
                    options: TranscriptionOptions(
                        language: .auto,
                        translateToEnglish: false,
                        useTimestamps: true,
                        maxAudioDuration: 300
                    )
                )

                self.transcribedText = result.text
                self.state = .completed(result)
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }
}
```

---

## 12. SwiftUI 示例 UI

```swift
import SwiftUI

public struct SpeechRecognitionView: View {
    @StateObject private var viewModel = SpeechRecognitionViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("Local STT")
                .font(.title.bold())

            statusView

            ScrollView {
                Text(viewModel.transcribedText.isEmpty ? "识别结果将在这里显示" : viewModel.transcribedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            HStack {
                Button("开始录音") {
                    Task {
                        await viewModel.startRecording()
                    }
                }

                Button("停止并识别") {
                    viewModel.stopRecordingAndTranscribe()
                }

                Button("取消") {
                    viewModel.cancel()
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.state {
        case .idle:
            Text("空闲")
        case .requestingPermission:
            Text("请求麦克风权限中")
        case .recording:
            Text("录音中")
        case .preparingAudio:
            Text("准备音频中")
        case .loadingModel:
            Text("加载模型中")
        case .transcribing:
            Text("识别中")
        case .completed:
            Text("识别完成")
        case .failed(let message):
            Text("失败：\(message)")
                .foregroundStyle(.red)
        }
    }
}
```

---

## 13. UIKit 接入方式

如果现有 App 是 UIKit，不要强行引入 SwiftUI 页面。使用 ViewModel + UIKit 绑定。

```swift
final class SpeechRecognitionViewController: UIViewController {
    private let viewModel = SpeechRecognitionViewModel()

    private let textView = UITextView()
    private let recordButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
    }

    private func setupUI() {
        recordButton.setTitle("开始录音", for: .normal)
        stopButton.setTitle("停止并识别", for: .normal)

        recordButton.addTarget(self, action: #selector(startRecording), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopRecording), for: .touchUpInside)
    }

    private func bindViewModel() {
        // 如果项目使用 Combine，在这里订阅 @Published
        // 如果没有 Combine，可改为 closure callback
    }

    @objc private func startRecording() {
        Task {
            await viewModel.startRecording()
        }
    }

    @objc private func stopRecording() {
        viewModel.stopRecordingAndTranscribe()
    }
}
```

---

## 14. 模型文件策略

### 14.1 首版

内置：

```text
ggml-tiny.bin
ggml-base.bin
```

默认：

```text
ggml-base.bin
```

### 14.2 生产版

建议：

```text
App 首包：tiny 或 base
首次进入语音功能：提示下载 small
高端设备：small
低端设备：tiny/base
```

### 14.3 模型下载目录

```text
Application Support/WhisperModels/
```

### 14.4 模型校验

维护：

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

---

## 15. 性能与线程要求

### 15.1 必须遵守

- 禁止主线程推理
- 禁止主线程音频转换
- 推理 Task 使用 `.userInitiated`
- UI 状态更新必须回到 MainActor
- 长音频必须限制最大时长或分片

### 15.2 性能日志

记录：

```text
audio_duration
conversion_time
model_load_time
transcription_time
total_time
model_name
device_model
iOS_version
```

建议封装：

```swift
public struct STTPerformanceLog {
    public let audioDuration: TimeInterval
    public let conversionTime: TimeInterval
    public let modelLoadTime: TimeInterval
    public let transcriptionTime: TimeInterval
    public let totalTime: TimeInterval
    public let modelName: String
}
```

---

## 16. 测试计划

### 16.1 单元测试

#### WhisperModelManagerTests

```swift
func testModelPath_whenModelExists_returnsPath()
func testModelPath_whenModelMissing_throwsModelNotFound()
func testAvailableModels_returnsExistingModels()
```

#### AudioFileConverterTests

```swift
func testConvertToWhisperCompatibleWav_outputsFile()
func testConvertToWhisperCompatibleWav_outputs16kMono()
func testConvertInvalidFile_throws()
```

#### SpeechRecognitionViewModelTests

```swift
func testStartRecording_whenPermissionDenied_setsFailedState()
func testStopRecording_whenTranscriptionSucceeds_setsCompletedState()
func testCancel_setsIdleState()
```

### 16.2 集成测试

准备音频：

```text
sample-zh-10s.wav
sample-en-10s.wav
sample-mixed-10s.wav
sample-zh-60s.wav
sample-noisy-10s.wav
```

指标：

```text
是否成功
识别文本
耗时
内存峰值
CPU 峰值
是否阻塞 UI
```

### 16.3 真机测试矩阵

```text
iPhone 13
iPhone 14/15/16/17
低电量模式
蓝牙耳机麦克风
AirPods
飞行模式
弱电量
锁屏中断
来电中断
后台切前台
```

---

## 17. Codex 执行任务拆分

### Task 1: 检查现有工程结构

Codex 操作：

1. 识别项目是 Xcode project / workspace / XcodeGen / Swift Package
2. 找到 App target
3. 找到 Info.plist
4. 找到资源目录
5. 输出接入点说明

验收：

```text
能明确回答：
- App Target 名称
- 是否使用 XcodeGen
- 是否使用 Swift Package
- Info.plist 路径
- 资源目录路径
```

---

### Task 2: 引入 whisper.xcframework

Codex 操作：

1. 检查 `Vendors/Whisper/whisper.xcframework` 是否存在
2. 如果不存在，提示需要先运行 `build-xcframework.sh`
3. 将 framework 加入 App target
4. 设置 Embed & Sign
5. 确保真机可链接

验收：

```text
工程能编译
App target linked frameworks 中包含 whisper.xcframework
```

---

### Task 3: 添加 Domain 层

Codex 操作：

创建：

```text
TranscriptionService.swift
TranscriptionOptions.swift
TranscriptionResult.swift
TranscriptionState.swift
SpeechRecognitionError.swift
```

验收：

```text
Domain 层无 UI 依赖
Domain 层无 whisper.cpp 依赖
可以单独编译
```

---

### Task 4: 添加模型管理

Codex 操作：

创建：

```text
WhisperModelManager.swift
```

功能：

- 查找 Bundle 模型
- 返回可用模型
- 抛出 modelNotFound

验收：

```text
模型存在时返回路径
模型不存在时抛出明确错误
```

---

### Task 5: 添加录音服务

Codex 操作：

创建：

```text
AudioSessionManager.swift
AudioRecorderService.swift
```

功能：

- 请求麦克风权限
- 开始录音
- 停止录音并返回 URL
- 录音失败时返回明确错误

验收：

```text
真机可以录音
拒绝权限时不会崩溃
```

---

### Task 6: 添加音频转换

Codex 操作：

创建：

```text
AudioFileConverter.swift
```

功能：

- 输入 m4a / wav / caf
- 输出 whisper 兼容 wav
- 16kHz
- mono
- Float32 PCM

验收：

```text
输出文件存在
输出格式正确
转换不阻塞 UI
```

---

### Task 7: 实现 WhisperCppBridge

Codex 操作：

1. 打开当前 whisper.cpp 的 `whisper.h`
2. 校验 C API
3. 实现 WAV 读取
4. 实现 whisper context 初始化
5. 实现 full params 配置
6. 实现 transcribe
7. 实现 segments 解析
8. 释放 context

验收：

```text
sample wav 可以转写
context 不泄漏
多次识别不崩溃
```

---

### Task 8: 实现 WhisperTranscriptionService

Codex 操作：

创建：

```text
WhisperTranscriptionService.swift
```

功能：

- 校验音频时长
- 调用 AudioFileConverter
- 调用 WhisperCppBridge
- 返回 TranscriptionResult

验收：

```text
业务层只依赖 TranscriptionService protocol
```

---

### Task 9: 接入 ViewModel

Codex 操作：

创建：

```text
SpeechRecognitionViewModel.swift
```

功能：

- 开始录音
- 停止录音并识别
- 取消
- 状态更新
- 错误展示

验收：

```text
状态流转正确
UI 不直接调用 whisper bridge
```

---

### Task 10: 添加 Demo UI

Codex 操作：

根据项目类型选择：

- SwiftUI：添加 `SpeechRecognitionView`
- UIKit：添加 `SpeechRecognitionViewController`

验收：

```text
可以从现有 App 进入测试页面
可以录音并显示转写结果
```

---

### Task 11: 添加测试

Codex 操作：

添加单元测试和 sample audio。

验收：

```text
至少覆盖：
- model manager
- audio converter
- view model happy path
- error path
```

---

### Task 12: 性能优化

Codex 操作：

1. 添加性能日志
2. 确认推理后台执行
3. 确认长音频限制
4. 检查内存峰值

验收：

```text
10s 音频稳定
60s 音频稳定
UI 不掉帧明显
无主线程卡死
```

---

## 18. App Store 风险与策略

### 18.1 包体积

风险：

```text
模型文件较大，可能显著增加 App 包体积
```

策略：

```text
首包内置 tiny/base
small/medium 按需下载
```

### 18.2 隐私说明

需要在隐私文案中说明：

```text
语音数据在本地设备处理
不上传服务器
```

### 18.3 权限弹窗

麦克风权限文案应明确：

```text
用于本地语音转文字，不会上传录音
```

---

## 19. Core ML 后续增强

### 19.1 目标

使用 Core ML 加速 encoder。

### 19.2 注意事项

即使启用 Core ML encoder：

```text
仍然需要 ggml 模型文件
decoder 仍由 whisper.cpp 执行
```

### 19.3 任务

```text
1. 生成 encoder mlmodel
2. 编译为 mlmodelc
3. 放入 Bundle
4. bridge 中启用 Core ML 参数
5. 真机对比耗时
```

---

## 20. Definition of Done

### 20.1 编译

- Debug 编译通过
- Release 编译通过
- 真机编译通过
- CI 编译通过

### 20.2 功能

- 麦克风录音成功
- 本地音频转写成功
- 中文识别成功
- 英文识别成功
- 中英混合识别成功
- 权限拒绝有提示
- 模型缺失有提示

### 20.3 工程

- STT 能力封装为独立模块
- 业务层依赖 protocol
- 无主线程推理
- 无强耦合 UI
- 有基础单元测试

### 20.4 性能

- 10 秒音频稳定识别
- 60 秒音频稳定识别
- 推理期间 UI 可操作
- 多次识别不崩溃
- 内存无明显泄漏

---

## 21. 给 Codex 的执行要求

Codex 在执行本 PLAN 时必须遵守：

1. 不要一次性大范围重构现有工程
2. 先识别项目结构，再修改
3. 每个 Task 单独提交
4. 每个 Task 后运行编译
5. 不能主线程执行推理
6. 不能把模型路径硬编码为开发机绝对路径
7. 不能把 whisper 示例 App 直接复制成生产代码
8. 需要用 protocol 隔离 STT provider
9. 需要保留未来替换 Provider 的扩展点
10. 需要在最终报告中列出：
    - 修改文件
    - 新增文件
    - 编译结果
    - 测试结果
    - 已知限制

---

## 22. 推荐提交顺序

```text
commit 1: add speech recognition domain models
commit 2: add whisper model manager
commit 3: add audio recording service
commit 4: add audio conversion pipeline
commit 5: add whisper cpp bridge
commit 6: add whisper transcription service
commit 7: add view model
commit 8: add demo UI
commit 9: add tests
commit 10: add performance logging
```

---

## 23. 最终文件清单

```text
Features/SpeechRecognition/Domain/TranscriptionService.swift
Features/SpeechRecognition/Domain/TranscriptionOptions.swift
Features/SpeechRecognition/Domain/TranscriptionResult.swift
Features/SpeechRecognition/Domain/TranscriptionState.swift
Features/SpeechRecognition/Domain/SpeechRecognitionError.swift

Features/SpeechRecognition/Infrastructure/WhisperModelManager.swift
Features/SpeechRecognition/Infrastructure/WhisperCppBridge.swift
Features/SpeechRecognition/Infrastructure/WhisperTranscriptionService.swift
Features/SpeechRecognition/Infrastructure/AudioRecorderService.swift
Features/SpeechRecognition/Infrastructure/AudioFileConverter.swift
Features/SpeechRecognition/Infrastructure/AudioSessionManager.swift

Features/SpeechRecognition/ViewModel/SpeechRecognitionViewModel.swift
Features/SpeechRecognition/UI/SpeechRecognitionView.swift
Features/SpeechRecognition/UI/SpeechRecognitionViewController.swift

Vendors/Whisper/whisper.xcframework

Resources/WhisperModels/ggml-tiny.bin
Resources/WhisperModels/ggml-base.bin

Tests/SpeechRecognition/WhisperModelManagerTests.swift
Tests/SpeechRecognition/AudioFileConverterTests.swift
Tests/SpeechRecognition/SpeechRecognitionViewModelTests.swift
```
