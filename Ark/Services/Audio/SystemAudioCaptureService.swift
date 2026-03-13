import AVFoundation
import CoreAudio
import Observation

@Observable
final class SystemAudioCaptureService: @unchecked Sendable {
    struct BufferDiagnostics: Equatable, Sendable {
        let nativeRMS: Float
        let convertedRMS: Float
        let nativeFrameCount: Int
        let convertedFrameCount: Int
    }

    private final class OneShotBufferProvider: @unchecked Sendable {
        private let buffer: AVAudioPCMBuffer
        private var didSupplyBuffer = false

        init(buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func nextBuffer(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
            guard !didSupplyBuffer else {
                status.pointee = .noDataNow
                return nil
            }

            didSupplyBuffer = true
            status.pointee = .haveData
            return buffer
        }
    }

    private var engine: AVAudioEngine?
    private(set) var isCapturing = false
    private var tapCallbackCount = 0
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    var onBufferDiagnostics: ((BufferDiagnostics) -> Void)?

    func start(driverDeviceID: AudioDeviceID) throws {
        let engine = AVAudioEngine()
        self.engine = engine
        tapCallbackCount = 0

        try setInputDevice(driverDeviceID, on: engine)

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AudioError.formatCreationFailed
        }

        print("[Ark][SystemAudio] Native format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount)ch")

        guard let monoNativeFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nativeFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatCreationFailed
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: monoNativeFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            guard let self else { return }
            guard let monoBuffer = Self.makeMonoBuffer(from: buffer, monoFormat: monoNativeFormat) else { return }
            let frameCount = AVAudioFrameCount(
                Double(monoBuffer.frameLength) * Constants.sampleRate / monoNativeFormat.sampleRate
            )
            guard frameCount > 0 else { return }
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let provider = OneShotBufferProvider(buffer: monoBuffer)
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                provider.nextBuffer(status: outStatus)
            }

            let diagnostics = BufferDiagnostics(
                nativeRMS: Self.computeRMS(buffer),
                convertedRMS: Self.computeRMS(convertedBuffer),
                nativeFrameCount: Int(buffer.frameLength),
                convertedFrameCount: Int(convertedBuffer.frameLength)
            )
            self.onBufferDiagnostics?(diagnostics)

            // Diagnostic logging for first 5 callbacks
            if self.tapCallbackCount < 5 {
                self.tapCallbackCount += 1
                print("[Ark][SystemAudio] Tap #\(self.tapCallbackCount): in=\(buffer.frameLength) frames, inRMS=\(String(format: "%.6f", diagnostics.nativeRMS)), out=\(convertedBuffer.frameLength) frames, outRMS=\(String(format: "%.6f", diagnostics.convertedRMS)), status=\(status.rawValue)")
                if let error {
                    print("[Ark][SystemAudio] Converter error: \(error)")
                }
            }

            if error == nil, convertedBuffer.frameLength > 0 {
                self.onAudioBuffer?(convertedBuffer, time)
            }
        }

        try engine.start()
        isCapturing = true
    }

    static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        let sampleCount: Int
        if buffer.format.isInterleaved {
            let interleavedCount = frameCount * channelCount
            let samples = UnsafeBufferPointer(start: channelData[0], count: interleavedCount)
            for sample in samples {
                sum += sample * sample
            }
            sampleCount = interleavedCount
        } else {
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                for sample in samples {
                    sum += sample * sample
                }
            }
            sampleCount = frameCount * channelCount
        }

        return sqrtf(sum / Float(sampleCount))
    }

    private static func makeMonoBuffer(
        from buffer: AVAudioPCMBuffer,
        monoFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let sourceData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return nil }

        guard let monoBuffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: buffer.frameLength
        ) else {
            return nil
        }

        monoBuffer.frameLength = buffer.frameLength
        guard let monoData = monoBuffer.floatChannelData else { return nil }

        if buffer.format.isInterleaved {
            let interleavedData = sourceData[0]
            for frame in 0..<frameCount {
                let baseIndex = frame * channelCount
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += interleavedData[baseIndex + channel]
                }
                monoData[0][frame] = sum / Float(channelCount)
            }
        } else {
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += sourceData[channel][frame]
                }
                monoData[0][frame] = sum / Float(channelCount)
            }
        }

        return monoBuffer
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isCapturing = false
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
        var mutableDeviceID = deviceID
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw AudioError.audioUnitNotAvailable
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &mutableDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioError.deviceSetFailed(status)
        }
    }

    enum AudioError: LocalizedError {
        case formatCreationFailed
        case converterCreationFailed
        case audioUnitNotAvailable
        case deviceSetFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .formatCreationFailed: "Falha ao criar o formato de captura do áudio do sistema."
            case .converterCreationFailed: "Falha ao criar o conversor de áudio do sistema."
            case .audioUnitNotAvailable: "A unidade de áudio não está disponível."
            case .deviceSetFailed(let s): "Falha ao configurar o ArkAudio no CoreAudio (erro \(s))."
            }
        }
    }
}
