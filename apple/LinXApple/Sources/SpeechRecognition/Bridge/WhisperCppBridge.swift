import Foundation
import whisper

struct WhisperBridgeConfiguration: Equatable, Sendable {
    var modelURL: URL
    var modelName: String
    var languageCode: String?
    var translateToEnglish: Bool
    var useTimestamps: Bool
    var audioDuration: TimeInterval
}

protocol WhisperBridgeTranscribing: Sendable {
    func transcribe(
        pcmURL: URL,
        configuration: WhisperBridgeConfiguration
    ) async throws -> SpeechTranscriptionResult
}

actor WhisperCppBridge: WhisperBridgeTranscribing {
    private let pcmReader: WhisperPCMReader
    private let maxThreadCount: Int32

    init(
        pcmReader: WhisperPCMReader = WhisperPCMReader(),
        maxThreadCount: Int32 = 4
    ) {
        self.pcmReader = pcmReader
        self.maxThreadCount = max(1, maxThreadCount)
    }

    func transcribe(
        pcmURL: URL,
        configuration: WhisperBridgeConfiguration
    ) async throws -> SpeechTranscriptionResult {
        try Task.checkCancellation()
        let samples = try pcmReader.readSamples(from: pcmURL)
        guard !samples.isEmpty else {
            throw SpeechRecognitionError.unsupportedAudioFormat
        }
        try Task.checkCancellation()

        let startedAt = Date()
        let ctx = try loadContext(
            modelURL: configuration.modelURL,
            modelName: configuration.modelName
        )
        defer {
            whisper_free(ctx)
        }

        let cancellationToken = WhisperCancellationToken()
        let params = makeFullParams(
            configuration: configuration,
            cancellationToken: cancellationToken
        )
        defer {
            if let language = params.language {
                free(UnsafeMutableRawPointer(mutating: language))
            }
        }

        let status = await withTaskCancellationHandler {
            samples.withUnsafeBufferPointer { buffer -> Int32 in
                guard let baseAddress = buffer.baseAddress else {
                    return -1
                }
                return whisper_full(ctx, params, baseAddress, Int32(buffer.count))
            }
        } onCancel: {
            cancellationToken.cancel()
        }

        if cancellationToken.isCancelled || Task.isCancelled {
            throw SpeechRecognitionError.cancelled
        }

        guard status == 0 else {
            throw SpeechRecognitionError.transcriptionFailed(
                "whisper.cpp inference failed with code \(status)."
            )
        }

        return buildResult(
            ctx: ctx,
            configuration: configuration,
            processingDuration: Date().timeIntervalSince(startedAt)
        )
    }

    private func loadContext(
        modelURL: URL,
        modelName: String
    ) throws -> OpaquePointer {
        let contextParams = whisper_context_default_params()

        let ctx = modelURL.path.withCString { path in
            whisper_init_from_file_with_params(path, contextParams)
        }

        guard let ctx else {
            throw SpeechRecognitionError.modelLoadFailed(
                "Unable to initialize whisper.cpp context for \(modelName)."
            )
        }

        return ctx
    }

    private func makeFullParams(
        configuration: WhisperBridgeConfiguration,
        cancellationToken: WhisperCancellationToken
    ) -> whisper_full_params {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        params.n_threads = min(Int32(processorCount), maxThreadCount)
        params.translate = configuration.translateToEnglish
        params.no_context = true
        params.no_timestamps = !configuration.useTimestamps
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.detect_language = configuration.languageCode == nil
        params.language = nil
        if let languageCode = configuration.languageCode {
            params.language = strdup(languageCode).map { UnsafePointer($0) }
        }
        params.abort_callback = { userData in
            guard let userData else {
                return false
            }
            let token = Unmanaged<WhisperCancellationToken>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return token.isCancelled
        }
        params.abort_callback_user_data = Unmanaged.passUnretained(cancellationToken).toOpaque()
        return params
    }

    private func buildResult(
        ctx: OpaquePointer,
        configuration: WhisperBridgeConfiguration,
        processingDuration: TimeInterval
    ) -> SpeechTranscriptionResult {
        let segmentCount = max(0, Int(whisper_full_n_segments(ctx)))
        let segments = (0..<segmentCount).map { index in
            SpeechTranscriptionSegment(
                id: UUID(),
                start: TimeInterval(whisper_full_get_segment_t0(ctx, Int32(index))) / 100.0,
                end: TimeInterval(whisper_full_get_segment_t1(ctx, Int32(index))) / 100.0,
                text: segmentText(ctx: ctx, index: index)
            )
        }
        let text = segments
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SpeechTranscriptionResult(
            text: text,
            segments: segments,
            detectedLanguage: detectedLanguage(ctx: ctx),
            audioDuration: configuration.audioDuration,
            processingDuration: processingDuration
        )
    }

    private func segmentText(ctx: OpaquePointer, index: Int) -> String {
        guard let pointer = whisper_full_get_segment_text(ctx, Int32(index)) else {
            return ""
        }
        return String(cString: pointer)
    }

    private func detectedLanguage(ctx: OpaquePointer) -> String? {
        let languageID = whisper_full_lang_id(ctx)
        guard languageID >= 0, let pointer = whisper_lang_str(languageID) else {
            return nil
        }
        return String(cString: pointer)
    }
}

private final class WhisperCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.withLock {
            _isCancelled
        }
    }

    func cancel() {
        lock.withLock {
            _isCancelled = true
        }
    }
}
