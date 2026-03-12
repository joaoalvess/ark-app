import AVFoundation
import CoreAudio
import Observation

@Observable
final class SystemAudioCaptureService: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private(set) var isCapturing = false
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func start(blackHoleDeviceID: AudioDeviceID) throws {
        let engine = AVAudioEngine()
        self.engine = engine

        try setInputDevice(blackHoleDeviceID, on: engine)

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            guard let self else { return }
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * Constants.sampleRate / nativeFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            nonisolated(unsafe) let sendableBuffer = buffer
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return sendableBuffer
            }

            if error == nil {
                self.onAudioBuffer?(convertedBuffer, time)
            }
        }

        try engine.start()
        isCapturing = true
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
            case .formatCreationFailed: "Failed to create the system audio format."
            case .converterCreationFailed: "Failed to create the system audio converter."
            case .audioUnitNotAvailable: "Audio unit is not available."
            case .deviceSetFailed(let s): "Failed to configure the audio device (error \(s))."
            }
        }
    }
}
