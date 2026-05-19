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

    enum ModelSize: String, CaseIterable, Equatable, Sendable {
        case tiny = "ggml-tiny"
        case base = "ggml-base"

        var fileName: String {
            rawValue
        }
    }

    var language: Language
    var modelSize: ModelSize
    var translateToEnglish: Bool
    var useTimestamps: Bool
    var maxAudioDuration: TimeInterval?

    init(
        language: Language = .auto,
        modelSize: ModelSize = .base,
        translateToEnglish: Bool = false,
        useTimestamps: Bool = true,
        maxAudioDuration: TimeInterval? = 300
    ) {
        self.language = language
        self.modelSize = modelSize
        self.translateToEnglish = translateToEnglish
        self.useTimestamps = useTimestamps
        self.maxAudioDuration = maxAudioDuration
    }
}
