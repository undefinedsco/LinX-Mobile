import Foundation

@MainActor
final class SpeechRecognitionViewModel: ObservableObject {
    @Published private(set) var state: SpeechRecognitionState = .idle
    @Published private(set) var transcribedText = ""

    private let recorder: any SpeechAudioRecording
    private let transcriptionProvider: any SpeechTranscriptionProviding
    private let options: SpeechTranscriptionOptions
    private let fileManager: FileManager

    private var currentTask: Task<SpeechTranscriptionResult, Error>?
    private var operationID = UUID()

    init(
        recorder: any SpeechAudioRecording = SpeechAudioRecorder(),
        transcriptionProvider: any SpeechTranscriptionProviding = WhisperTranscriptionService(),
        options: SpeechTranscriptionOptions = SpeechTranscriptionOptions(),
        fileManager: FileManager = .default
    ) {
        self.recorder = recorder
        self.transcriptionProvider = transcriptionProvider
        self.options = options
        self.fileManager = fileManager
    }

    var canStartRecording: Bool {
        switch state {
        case .idle, .failed, .completed:
            return true
        case .requestingPermission, .recording, .preparingAudio, .loadingModel, .transcribing:
            return false
        }
    }

    var canStopRecording: Bool {
        state == .recording
    }

    func startRecording() async {
        guard canStartRecording else { return }

        let operationID = UUID()
        self.operationID = operationID
        currentTask?.cancel()
        currentTask = nil
        transcribedText = ""
        state = .requestingPermission

        do {
            try await recorder.startRecording()
            guard self.operationID == operationID else { return }
            state = .recording
        } catch {
            guard self.operationID == operationID else { return }
            state = .failed(Self.displayMessage(for: error))
        }
    }

    func stopRecording() async {
        guard state == .recording else { return }

        let operationID = operationID
        var recordingURL: URL?
        state = .preparingAudio

        do {
            let audioURL = try await recorder.stopRecording()
            recordingURL = audioURL
            guard self.operationID == operationID else { return }

            state = .loadingModel
            let task = Task(priority: .userInitiated) { [transcriptionProvider, options] in
                try await transcriptionProvider.transcribe(audioURL: audioURL, options: options)
            }
            currentTask = task
            state = .transcribing(progress: nil)

            let result = try await task.value
            guard self.operationID == operationID else { return }
            transcribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            state = .completed(result)
        } catch {
            guard self.operationID == operationID else { return }
            state = .failed(Self.displayMessage(for: error))
        }

        currentTask = nil
        if let recordingURL {
            try? fileManager.removeItem(at: recordingURL)
        }
    }

    func cancel() {
        operationID = UUID()
        currentTask?.cancel()
        currentTask = nil
        transcribedText = ""
        state = .idle

        Task {
            await recorder.cancelRecording()
        }
    }

    private static func displayMessage(for error: Error) -> String {
        if let speechError = error as? SpeechRecognitionError {
            return speechError.localizedDescription
        }
        if error is CancellationError {
            return SpeechRecognitionError.cancelled.localizedDescription
        }
        return error.localizedDescription
    }
}
