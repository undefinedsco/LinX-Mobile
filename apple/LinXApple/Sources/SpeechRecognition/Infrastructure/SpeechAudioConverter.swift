import AVFoundation
import Foundation

protocol SpeechAudioConverting: Sendable {
    func audioDuration(for inputURL: URL) async throws -> TimeInterval
    func convertToWhisperPCM(inputURL: URL) async throws -> URL
}

struct SpeechAudioConverter: SpeechAudioConverting {
    private let outputSampleRate: Double
    private let outputChannelCount: AVAudioChannelCount

    init(
        outputSampleRate: Double = 16_000,
        outputChannelCount: AVAudioChannelCount = 1
    ) {
        self.outputSampleRate = outputSampleRate
        self.outputChannelCount = outputChannelCount
    }

    func audioDuration(for inputURL: URL) async throws -> TimeInterval {
        try await Task.detached(priority: .userInitiated) {
            do {
                let sourceFile = try AVAudioFile(forReading: inputURL)
                let sampleRate = sourceFile.processingFormat.sampleRate
                guard sampleRate > 0 else {
                    throw SpeechRecognitionError.unsupportedAudioFormat
                }
                return Double(sourceFile.length) / sampleRate
            } catch let error as SpeechRecognitionError {
                throw error
            } catch {
                throw SpeechRecognitionError.audioConversionFailed(error.localizedDescription)
            }
        }.value
    }

    func convertToWhisperPCM(inputURL: URL) async throws -> URL {
        let outputSampleRate = outputSampleRate
        let outputChannelCount = outputChannelCount
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("linx-whisper-pcm-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("wav")

        return try await Task.detached(priority: .userInitiated) {
            try Self.convert(
                inputURL: inputURL,
                outputURL: outputURL,
                outputSampleRate: outputSampleRate,
                outputChannelCount: outputChannelCount
            )
        }.value
    }

    private static func convert(
        inputURL: URL,
        outputURL: URL,
        outputSampleRate: Double,
        outputChannelCount: AVAudioChannelCount
    ) throws -> URL {
        do {
            guard outputChannelCount == 1 else {
                throw SpeechRecognitionError.unsupportedAudioFormat
            }
            let sourceFile = try AVAudioFile(forReading: inputURL)
            let sourceFormat = sourceFile.processingFormat
            let sourceSampleRate = sourceFormat.sampleRate
            let frameCount = sourceFile.length
            guard sourceSampleRate > 0, frameCount > 0, frameCount <= AVAudioFramePosition(UInt32.max) else {
                throw SpeechRecognitionError.unsupportedAudioFormat
            }
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else {
                throw SpeechRecognitionError.audioConversionFailed("Unable to allocate input buffer.")
            }

            try Task.checkCancellation()
            try sourceFile.read(into: inputBuffer)
            let monoSamples = try makeMonoSamples(from: inputBuffer)
            try Task.checkCancellation()
            let outputSamples = resample(
                monoSamples,
                sourceSampleRate: sourceSampleRate,
                outputSampleRate: outputSampleRate
            )
            try writeFloatWAV(
                samples: outputSamples,
                sampleRate: UInt32(outputSampleRate),
                outputURL: outputURL
            )

            return outputURL
        } catch is CancellationError {
            throw SpeechRecognitionError.cancelled
        } catch let error as SpeechRecognitionError {
            throw error
        } catch {
            throw SpeechRecognitionError.audioConversionFailed(error.localizedDescription)
        }
    }

    private static func makeMonoSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0, let channelData = buffer.floatChannelData else {
            throw SpeechRecognitionError.unsupportedAudioFormat
        }

        var monoSamples = Array(repeating: Float.zero, count: frameLength)
        for channelIndex in 0..<channelCount {
            let channel = channelData[channelIndex]
            for frameIndex in 0..<frameLength {
                monoSamples[frameIndex] += channel[frameIndex] / Float(channelCount)
            }
        }
        return monoSamples
    }

    private static func resample(
        _ samples: [Float],
        sourceSampleRate: Double,
        outputSampleRate: Double
    ) -> [Float] {
        guard samples.isEmpty == false else { return [] }
        guard abs(sourceSampleRate - outputSampleRate) > 0.5 else {
            return samples
        }

        let outputCount = max(1, Int((Double(samples.count) / sourceSampleRate * outputSampleRate).rounded()))
        let ratio = sourceSampleRate / outputSampleRate
        var output = Array(repeating: Float.zero, count: outputCount)

        for index in 0..<outputCount {
            let sourcePosition = Double(index) * ratio
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            output[index] = samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * fraction
        }

        return output
    }

    private static func writeFloatWAV(
        samples: [Float],
        sampleRate: UInt32,
        outputURL: URL
    ) throws {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 32
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataByteCount = UInt32(samples.count) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * UInt16(bytesPerSample)

        var data = Data()
        data.reserveCapacity(44 + Int(dataByteCount))
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + dataByteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(3))
        data.appendLittleEndian(channels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.appendASCII("data")
        data.appendLittleEndian(dataByteCount)
        samples.withUnsafeBytes { sampleBytes in
            data.append(contentsOf: sampleBytes)
        }

        try data.write(to: outputURL, options: [.atomic])
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
