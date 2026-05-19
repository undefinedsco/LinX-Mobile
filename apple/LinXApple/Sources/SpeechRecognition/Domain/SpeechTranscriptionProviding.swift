import Foundation

protocol SpeechTranscriptionProviding: Sendable {
    func transcribe(
        audioURL: URL,
        options: SpeechTranscriptionOptions
    ) async throws -> SpeechTranscriptionResult
}
