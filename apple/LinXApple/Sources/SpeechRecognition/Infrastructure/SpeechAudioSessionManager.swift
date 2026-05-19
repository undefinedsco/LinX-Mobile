import AVFoundation
import Foundation

@MainActor
final class SpeechAudioSessionManager {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func activateForRecording() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.allowBluetooth, .defaultToSpeaker]
        )
        try session.setActive(true)
    }

    func deactivate() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            LinxDiagnostics.speech.error("audio session deactivate failed error=\(error.localizedDescription, privacy: .private) errorHash=\(LinxDiagnostics.fingerprint(error.localizedDescription), privacy: .public)")
        }
    }
}
