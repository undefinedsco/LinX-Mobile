import AVFoundation
import Foundation

@MainActor
protocol SpeechAudioRecording: AnyObject {
    func startRecording() async throws
    func stopRecording() async throws -> URL
    func cancelRecording() async
}

@MainActor
final class SpeechAudioRecorder: NSObject, SpeechAudioRecording, AVAudioRecorderDelegate {
    private let sessionManager: SpeechAudioSessionManager
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var activeRecordingURL: URL?

    init(
        sessionManager: SpeechAudioSessionManager = SpeechAudioSessionManager(),
        fileManager: FileManager = .default
    ) {
        self.sessionManager = sessionManager
        self.fileManager = fileManager
    }

    func startRecording() async throws {
        guard recorder == nil else {
            throw SpeechRecognitionError.recordingFailed("A recording is already active.")
        }

        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw SpeechRecognitionError.microphonePermissionDenied
        }

        do {
            try sessionManager.activateForRecording()
            let url = makeTemporaryRecordingURL()
            let audioRecorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
            audioRecorder.delegate = self
            audioRecorder.isMeteringEnabled = true
            audioRecorder.prepareToRecord()

            guard audioRecorder.record() else {
                sessionManager.deactivate()
                throw SpeechRecognitionError.recordingFailed("AVAudioRecorder did not start.")
            }

            recorder = audioRecorder
            activeRecordingURL = url
            LinxDiagnostics.speech.info("recording started")
        } catch let error as SpeechRecognitionError {
            throw error
        } catch {
            sessionManager.deactivate()
            throw SpeechRecognitionError.recordingFailed(error.localizedDescription)
        }
    }

    func stopRecording() async throws -> URL {
        guard let recorder, let activeRecordingURL else {
            throw SpeechRecognitionError.recorderUnavailable
        }

        recorder.stop()
        self.recorder = nil
        self.activeRecordingURL = nil
        sessionManager.deactivate()
        LinxDiagnostics.speech.info("recording stopped")
        return activeRecordingURL
    }

    func cancelRecording() async {
        recorder?.stop()
        if let activeRecordingURL {
            try? fileManager.removeItem(at: activeRecordingURL)
        }
        recorder = nil
        activeRecordingURL = nil
        sessionManager.deactivate()
        LinxDiagnostics.speech.info("recording cancelled")
    }

    private func makeTemporaryRecordingURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("linx-speech-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("m4a")
    }

    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
}
