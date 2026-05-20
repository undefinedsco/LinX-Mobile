import AVFoundation
import XCTest
@testable import LinXApple

final class SpeechRecognitionTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    func testModelURL_whenModelExists_returnsURL() throws {
        let directoryURL = makeTemporaryDirectory()
        let modelURL = directoryURL.appendingPathComponent("ggml-base.bin")
        try Data([0x01]).write(to: modelURL)

        let store = WhisperModelStore(resourceDirectoryURL: directoryURL)

        XCTAssertEqual(try store.modelURL(for: .base), modelURL)
    }

    func testModelURL_whenModelMissing_throwsModelNotFound() throws {
        let directoryURL = makeTemporaryDirectory()
        let store = WhisperModelStore(resourceDirectoryURL: directoryURL)

        XCTAssertThrowsError(try store.modelURL(for: .base)) { error in
            XCTAssertEqual(error as? SpeechRecognitionError, .modelNotFound("ggml-base"))
        }
    }

    func testModelURL_whenBundledResourceIsFlattened_returnsTopLevelURL() throws {
        let bundleURL = makeTemporaryDirectory()
            .appendingPathComponent("SpeechFixtures.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let modelURL = bundleURL.appendingPathComponent("ggml-base.bin")
        try Data([0x01]).write(to: modelURL)

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        let store = WhisperModelStore(bundle: bundle, bundleDirectory: "WhisperModels")

        XCTAssertEqual(try store.modelURL(for: .base), modelURL)
    }

    func testDefaultOptions_useChineseLanguage() {
        XCTAssertEqual(SpeechTranscriptionOptions().language, .chinese)
    }

    func testConvertToWhisperPCM_outputs16kMonoFloat32() async throws {
        let inputURL = try makeSineWaveFile(sampleRate: 44_100, duration: 0.25)
        let converter = SpeechAudioConverter()

        let outputURL = try await converter.convertToWhisperPCM(inputURL: inputURL)
        temporaryURLs.append(outputURL)

        let file = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000, accuracy: 0.5)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(file.processingFormat.commonFormat, .pcmFormatFloat32)

        let samples = try WhisperPCMReader().readSamples(from: outputURL)
        XCTAssertFalse(samples.isEmpty)
    }

    func testConvertInvalidFile_throwsConversionFailure() async throws {
        let invalidURL = makeTemporaryFileURL(extension: "txt")
        try Data("not audio".utf8).write(to: invalidURL)
        let converter = SpeechAudioConverter()

        do {
            _ = try await converter.convertToWhisperPCM(inputURL: invalidURL)
            XCTFail("Expected conversion failure")
        } catch let error as SpeechRecognitionError {
            if case .audioConversionFailed = error {
                return
            }
            XCTFail("Expected audioConversionFailed, got \(error)")
        }
    }

    @MainActor
    func testStartRecording_whenPermissionDenied_setsFailedState() async throws {
        let recorder = FakeSpeechAudioRecorder(startError: .microphonePermissionDenied)
        let viewModel = SpeechRecognitionViewModel(
            recorder: recorder,
            transcriptionProvider: FakeTranscriptionProvider(outcome: .success(Self.sampleResult()))
        )

        await viewModel.startRecording()

        XCTAssertEqual(viewModel.state, .failed(SpeechRecognitionError.microphonePermissionDenied.localizedDescription))
    }

    @MainActor
    func testStopRecording_whenTranscriptionSucceeds_setsCompletedState() async throws {
        let audioURL = try makeSineWaveFile(sampleRate: 16_000, duration: 0.1)
        let result = Self.sampleResult(text: "hello from voice")
        let viewModel = SpeechRecognitionViewModel(
            recorder: FakeSpeechAudioRecorder(outputURL: audioURL),
            transcriptionProvider: FakeTranscriptionProvider(outcome: .success(result))
        )

        await viewModel.startRecording()
        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .completed(result))
        XCTAssertEqual(viewModel.transcribedText, "hello from voice")
    }

    @MainActor
    func testCancel_setsIdleState() async throws {
        let audioURL = try makeSineWaveFile(sampleRate: 16_000, duration: 0.1)
        let recorder = FakeSpeechAudioRecorder(outputURL: audioURL)
        let viewModel = SpeechRecognitionViewModel(
            recorder: recorder,
            transcriptionProvider: FakeTranscriptionProvider(outcome: .success(Self.sampleResult()))
        )

        await viewModel.startRecording()
        viewModel.cancel()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.transcribedText, "")
    }

    @MainActor
    func testStopRecording_whenTranscriptionFails_setsFailedState() async throws {
        let audioURL = try makeSineWaveFile(sampleRate: 16_000, duration: 0.1)
        let viewModel = SpeechRecognitionViewModel(
            recorder: FakeSpeechAudioRecorder(outputURL: audioURL),
            transcriptionProvider: FakeTranscriptionProvider(outcome: .failure(.transcriptionFailed("boom")))
        )

        await viewModel.startRecording()
        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .failed(SpeechRecognitionError.transcriptionFailed("boom").localizedDescription))
    }

    @MainActor
    func testStopRecording_whenTranscriptionReturnsEmptyText_setsNoSpeechFailedState() async throws {
        let audioURL = try makeSineWaveFile(sampleRate: 16_000, duration: 0.1)
        let viewModel = SpeechRecognitionViewModel(
            recorder: FakeSpeechAudioRecorder(outputURL: audioURL),
            transcriptionProvider: FakeTranscriptionProvider(outcome: .success(Self.sampleResult(text: "   ")))
        )

        await viewModel.startRecording()
        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .failed(SpeechRecognitionError.noSpeechDetected.localizedDescription))
        XCTAssertEqual(viewModel.transcribedText, "")
    }

    func testTranscribe_whenAudioTooLong_throwsAudioTooLong() async throws {
        let service = WhisperTranscriptionService(
            modelStore: FakeWhisperModelStore(modelURL: makeTemporaryFileURL(extension: "bin")),
            audioConverter: FakeSpeechAudioConverter(duration: 301),
            bridge: FakeWhisperBridge(outcome: .success(Self.sampleResult()))
        )

        do {
            _ = try await service.transcribe(
                audioURL: makeTemporaryFileURL(extension: "m4a"),
                options: SpeechTranscriptionOptions(maxAudioDuration: 300)
            )
            XCTFail("Expected audioTooLong")
        } catch let error as SpeechRecognitionError {
            XCTAssertEqual(error, .audioTooLong(maxDuration: 300))
        }
    }

    func testTranscribe_whenBridgeReturnsEmptyText_throwsNoSpeechDetected() async throws {
        let service = WhisperTranscriptionService(
            modelStore: FakeWhisperModelStore(modelURL: makeTemporaryFileURL(extension: "bin")),
            audioConverter: FakeSpeechAudioConverter(duration: 1),
            bridge: FakeWhisperBridge(outcome: .success(Self.sampleResult(text: "   ")))
        )

        do {
            _ = try await service.transcribe(audioURL: makeTemporaryFileURL(extension: "m4a"))
            XCTFail("Expected noSpeechDetected")
        } catch let error as SpeechRecognitionError {
            XCTAssertEqual(error, .noSpeechDetected)
        }
    }

    func testTranscribe_whenModelMissing_throwsModelNotFound() async throws {
        let service = WhisperTranscriptionService(
            modelStore: FakeWhisperModelStore(error: .modelNotFound("ggml-base")),
            audioConverter: FakeSpeechAudioConverter(duration: 1),
            bridge: FakeWhisperBridge(outcome: .success(Self.sampleResult()))
        )

        do {
            _ = try await service.transcribe(audioURL: makeTemporaryFileURL(extension: "m4a"))
            XCTFail("Expected modelNotFound")
        } catch let error as SpeechRecognitionError {
            XCTAssertEqual(error, .modelNotFound("ggml-base"))
        }
    }

    func testTranscribe_whenCancelled_mapsCancellation() async throws {
        let service = WhisperTranscriptionService(
            modelStore: FakeWhisperModelStore(modelURL: makeTemporaryFileURL(extension: "bin")),
            audioConverter: FakeSpeechAudioConverter(duration: 1, throwsCancellation: true),
            bridge: FakeWhisperBridge(outcome: .success(Self.sampleResult()))
        )

        do {
            _ = try await service.transcribe(audioURL: makeTemporaryFileURL(extension: "m4a"))
            XCTFail("Expected cancelled")
        } catch let error as SpeechRecognitionError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testTranscribe_whenBridgeFails_preservesSpeechRecognitionError() async throws {
        let expected = SpeechRecognitionError.modelLoadFailed("runtime unavailable")
        let service = WhisperTranscriptionService(
            modelStore: FakeWhisperModelStore(modelURL: makeTemporaryFileURL(extension: "bin")),
            audioConverter: FakeSpeechAudioConverter(duration: 1),
            bridge: FakeWhisperBridge(outcome: .failure(expected))
        )

        do {
            _ = try await service.transcribe(audioURL: makeTemporaryFileURL(extension: "m4a"))
            XCTFail("Expected bridge failure")
        } catch let error as SpeechRecognitionError {
            XCTAssertEqual(error, expected)
        }
    }

    private static func sampleResult(text: String = "hello") -> SpeechTranscriptionResult {
        SpeechTranscriptionResult(
            text: text,
            segments: [
                SpeechTranscriptionSegment(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    start: 0,
                    end: 1,
                    text: text
                ),
            ],
            detectedLanguage: "en",
            audioDuration: 1,
            processingDuration: 0.2
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linx-speech-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }

    private func makeTemporaryFileURL(extension pathExtension: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linx-speech-tests-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension(pathExtension)
        temporaryURLs.append(url)
        return url
    }

    private func makeSineWaveFile(sampleRate: Double, duration: TimeInterval) throws -> URL {
        let url = makeTemporaryFileURL(extension: "wav")
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ))
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount

        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frameCount) {
            let phase = 2.0 * Double.pi * 440.0 * Double(index) / sampleRate
            channel[index] = Float(sin(phase) * 0.2)
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

@MainActor
private final class FakeSpeechAudioRecorder: SpeechAudioRecording {
    private let startError: SpeechRecognitionError?
    private let outputURL: URL

    init(
        outputURL: URL = URL(fileURLWithPath: "/tmp/fake.m4a"),
        startError: SpeechRecognitionError? = nil
    ) {
        self.outputURL = outputURL
        self.startError = startError
    }

    func startRecording() async throws {
        if let startError {
            throw startError
        }
    }

    func stopRecording() async throws -> URL {
        outputURL
    }

    func cancelRecording() async {}
}

private enum FakeTranscriptionOutcome: Sendable {
    case success(SpeechTranscriptionResult)
    case failure(SpeechRecognitionError)
}

private struct FakeTranscriptionProvider: SpeechTranscriptionProviding {
    let outcome: FakeTranscriptionOutcome

    func transcribe(
        audioURL _: URL,
        options _: SpeechTranscriptionOptions
    ) async throws -> SpeechTranscriptionResult {
        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

private struct FakeWhisperModelStore: WhisperModelStoring {
    var modelURL: URL?
    var error: SpeechRecognitionError?

    func modelURL(for _: SpeechTranscriptionOptions.ModelSize) throws -> URL {
        if let error {
            throw error
        }
        return modelURL ?? URL(fileURLWithPath: "/tmp/ggml-base.bin")
    }
}

private struct FakeSpeechAudioConverter: SpeechAudioConverting {
    var duration: TimeInterval
    var throwsCancellation = false
    var conversionError: SpeechRecognitionError?

    func audioDuration(for _: URL) async throws -> TimeInterval {
        duration
    }

    func convertToWhisperPCM(inputURL _: URL) async throws -> URL {
        if throwsCancellation {
            throw CancellationError()
        }
        if let conversionError {
            throw conversionError
        }
        return URL(fileURLWithPath: "/tmp/fake-pcm.wav")
    }
}

private enum FakeWhisperBridgeOutcome: Sendable {
    case success(SpeechTranscriptionResult)
    case failure(SpeechRecognitionError)
}

private struct FakeWhisperBridge: WhisperBridgeTranscribing {
    var outcome: FakeWhisperBridgeOutcome

    func transcribe(
        pcmURL _: URL,
        configuration _: WhisperBridgeConfiguration
    ) async throws -> SpeechTranscriptionResult {
        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
