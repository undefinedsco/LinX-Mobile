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
