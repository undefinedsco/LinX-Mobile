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
