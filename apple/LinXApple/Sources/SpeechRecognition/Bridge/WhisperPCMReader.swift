import AVFoundation
import Foundation

struct WhisperPCMReader: Sendable {
    private let expectedSampleRate: Double
    private let expectedChannelCount: AVAudioChannelCount

    init(
        expectedSampleRate: Double = 16_000,
        expectedChannelCount: AVAudioChannelCount = 1
    ) {
        self.expectedSampleRate = expectedSampleRate
        self.expectedChannelCount = expectedChannelCount
    }

    func readSamples(from pcmURL: URL) throws -> [Float] {
        do {
            let audioFile = try AVAudioFile(forReading: pcmURL)
            let format = audioFile.processingFormat
            guard abs(format.sampleRate - expectedSampleRate) < 0.5 else {
                throw SpeechRecognitionError.unsupportedAudioFormat
            }
            guard format.channelCount == expectedChannelCount else {
                throw SpeechRecognitionError.unsupportedAudioFormat
            }
            guard format.commonFormat == .pcmFormatFloat32 else {
                throw SpeechRecognitionError.unsupportedAudioFormat
            }
            guard audioFile.length > 0, audioFile.length <= AVAudioFramePosition(Int32.max) else {
                throw SpeechRecognitionError.unsupportedAudioFormat
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            ) else {
                throw SpeechRecognitionError.audioConversionFailed("Unable to allocate PCM read buffer.")
            }

            try audioFile.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else {
                throw SpeechRecognitionError.unsupportedAudioFormat
            }
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        } catch let error as SpeechRecognitionError {
            throw error
        } catch {
            throw SpeechRecognitionError.audioConversionFailed(error.localizedDescription)
        }
    }
}
