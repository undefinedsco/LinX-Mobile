import Foundation

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

    init(pcmReader: WhisperPCMReader = WhisperPCMReader()) {
        self.pcmReader = pcmReader
    }

    func transcribe(
        pcmURL: URL,
        configuration: WhisperBridgeConfiguration
    ) async throws -> SpeechTranscriptionResult {
        try Task.checkCancellation()
        _ = try pcmReader.readSamples(from: pcmURL)

        throw SpeechRecognitionError.modelLoadFailed(
            "whisper.cpp runtime is not linked. Add Vendors/Whisper/whisper.xcframework, verify whisper.h, then replace WhisperCppBridge with the checked C API implementation."
        )
    }
}
