import AVFoundation
import Observation

@Observable
final class MicrophoneCaptureService {
    private var engine: AVAudioEngine?
    private(set) var isCapturing = false
    var permissionGranted = false
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func checkPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        permissionGranted = granted
    }

    func start(deviceID: String? = nil) throws {
        let engine = AVAudioEngine()
        self.engine = engine

        if let deviceID,
           let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices.first(where: { $0.uniqueID == deviceID }) {
            setInputDevice(device, on: engine)
        }

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

    private func setInputDevice(_ device: AVCaptureDevice, on engine: AVAudioEngine) {
        var deviceID = AudioDeviceID(0)
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = device.uniqueID as CFString
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = withUnsafeMutablePointer(to: &uid) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propAddress, UInt32(MemoryLayout<CFString>.size), uidPtr,
                &size, &deviceID
            )
        }

        let audioUnit = engine.inputNode.audioUnit!
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    static func availableDevices() -> [(id: String, name: String)] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices.map { ($0.uniqueID, $0.localizedName) }
    }

    enum AudioError: LocalizedError {
        case formatCreationFailed
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .formatCreationFailed: "Failed to create the audio format."
            case .converterCreationFailed: "Failed to create the audio converter."
            }
        }
    }
}
