import Foundation

final class WhisperTranscriptionService: SpeechTranscriptionProviding, @unchecked Sendable {
    private let modelStore: any WhisperModelStoring
    private let audioConverter: any SpeechAudioConverting
    private let bridge: any WhisperBridgeTranscribing
    private let fileManager: FileManager

    init(
        modelStore: any WhisperModelStoring = WhisperModelStore(),
        audioConverter: any SpeechAudioConverting = SpeechAudioConverter(),
        bridge: any WhisperBridgeTranscribing = WhisperCppBridge(),
        fileManager: FileManager = .default
    ) {
        self.modelStore = modelStore
        self.audioConverter = audioConverter
        self.bridge = bridge
        self.fileManager = fileManager
    }

    func transcribe(
        audioURL: URL,
        options: SpeechTranscriptionOptions = SpeechTranscriptionOptions()
    ) async throws -> SpeechTranscriptionResult {
        let startedAt = Date()
        let modelName = options.modelSize.fileName

        do {
            try Task.checkCancellation()
            let audioDuration = try await audioConverter.audioDuration(for: audioURL)
            if let maxAudioDuration = options.maxAudioDuration, audioDuration > maxAudioDuration {
                throw SpeechRecognitionError.audioTooLong(maxDuration: maxAudioDuration)
            }

            let modelURL = try modelStore.modelURL(for: options.modelSize)
            let conversionStartedAt = Date()
            let pcmURL = try await audioConverter.convertToWhisperPCM(inputURL: audioURL)
            let conversionDurationMs = Int(Date().timeIntervalSince(conversionStartedAt) * 1000)
            defer {
                try? fileManager.removeItem(at: pcmURL)
            }

            let inferenceStartedAt = Date()
            let result = try await bridge.transcribe(
                pcmURL: pcmURL,
                configuration: WhisperBridgeConfiguration(
                    modelURL: modelURL,
                    modelName: modelName,
                    languageCode: options.language.whisperCode,
                    translateToEnglish: options.translateToEnglish,
                    useTimestamps: options.useTimestamps,
                    audioDuration: audioDuration
                )
            )
            let transcriptionDurationMs = Int(Date().timeIntervalSince(inferenceStartedAt) * 1000)
            let totalDurationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            LinxDiagnostics.speech.info("transcription succeeded audioDurationMs=\(Int(audioDuration * 1000), privacy: .public) conversionDurationMs=\(conversionDurationMs, privacy: .public) transcriptionDurationMs=\(transcriptionDurationMs, privacy: .public) totalDurationMs=\(totalDurationMs, privacy: .public) model=\(modelName, privacy: .public)")
            return result
        } catch is CancellationError {
            LinxDiagnostics.speech.info("transcription cancelled model=\(modelName, privacy: .public)")
            throw SpeechRecognitionError.cancelled
        } catch let error as SpeechRecognitionError {
            logFailure(error, modelName: modelName, startedAt: startedAt)
            throw error
        } catch {
            let mapped = SpeechRecognitionError.transcriptionFailed(error.localizedDescription)
            logFailure(mapped, modelName: modelName, startedAt: startedAt)
            throw mapped
        }
    }

    private func logFailure(
        _ error: SpeechRecognitionError,
        modelName: String,
        startedAt: Date
    ) {
        let totalDurationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let message = error.localizedDescription
        LinxDiagnostics.speech.error("transcription failed error=\(message, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(message), privacy: .public) totalDurationMs=\(totalDurationMs, privacy: .public) model=\(modelName, privacy: .public)")
    }
}
