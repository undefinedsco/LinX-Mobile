import Foundation

struct SpeechTranscriptionResult: Equatable, Sendable {
    var text: String
    var segments: [SpeechTranscriptionSegment]
    var detectedLanguage: String?
    var audioDuration: TimeInterval
    var processingDuration: TimeInterval

    init(
        text: String,
        segments: [SpeechTranscriptionSegment],
        detectedLanguage: String?,
        audioDuration: TimeInterval,
        processingDuration: TimeInterval
    ) {
        self.text = text
        self.segments = segments
        self.detectedLanguage = detectedLanguage
        self.audioDuration = audioDuration
        self.processingDuration = processingDuration
    }
}

struct SpeechTranscriptionSegment: Identifiable, Equatable, Sendable {
    var id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    init(
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
