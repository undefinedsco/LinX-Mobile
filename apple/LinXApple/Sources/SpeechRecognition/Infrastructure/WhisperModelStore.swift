import Foundation

protocol WhisperModelStoring: Sendable {
    func modelURL(for size: SpeechTranscriptionOptions.ModelSize) throws -> URL
}

final class WhisperModelStore: WhisperModelStoring, @unchecked Sendable {
    private let bundle: Bundle
    private let bundleDirectory: String
    private let resourceDirectoryURL: URL?

    init(bundle: Bundle = .main, bundleDirectory: String = "WhisperModels") {
        self.bundle = bundle
        self.bundleDirectory = bundleDirectory
        self.resourceDirectoryURL = nil
    }

    init(resourceDirectoryURL: URL) {
        self.bundle = .main
        self.bundleDirectory = ""
        self.resourceDirectoryURL = resourceDirectoryURL
    }

    func modelURL(for size: SpeechTranscriptionOptions.ModelSize) throws -> URL {
        if let resourceDirectoryURL {
            let url = resourceDirectoryURL
                .appendingPathComponent(size.fileName, isDirectory: false)
                .appendingPathExtension("bin")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SpeechRecognitionError.modelNotFound(size.fileName)
            }
            return url
        }

        guard let url = bundle.url(
            forResource: size.fileName,
            withExtension: "bin",
            subdirectory: bundleDirectory
        ) else {
            throw SpeechRecognitionError.modelNotFound(size.fileName)
        }
        return url
    }
}
