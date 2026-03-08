import AVFoundation
import Observation

@MainActor @Observable
final class AudioSessionManager {
    let micService = MicrophoneCaptureService()
    let systemService = SystemAudioCaptureService()

    private var micBuffer: [Float] = []
    private var systemBuffer: [Float] = []
    private let bufferLock = NSLock()

    var onMicChunk: (([Float]) -> Void)?
    var onSystemChunk: (([Float]) -> Void)?

    private let chunkSampleCount: Int

    var isListening: Bool {
        micService.isCapturing || systemService.isCapturing
    }

    init() {
        chunkSampleCount = Int(Constants.sampleRate * Constants.chunkDuration)

        micService.onAudioBuffer = { [weak self] buffer, _ in
            self?.handleBuffer(buffer, source: .mic)
        }

        systemService.onAudioBuffer = { [weak self] buffer, _ in
            self?.handleBuffer(buffer, source: .system)
        }
    }

    func checkMicPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micService.permissionGranted = granted
    }

    func startListening(deviceID: String? = nil) async throws {
        try micService.start(deviceID: deviceID)
        try await systemService.start()
    }

    func stopListening() async {
        micService.stop()
        await systemService.stop()
        clearBuffers()
    }

    private func clearBuffers() {
        bufferLock.lock()
        micBuffer.removeAll()
        systemBuffer.removeAll()
        bufferLock.unlock()
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer, source: AudioSource) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        bufferLock.lock()
        switch source {
        case .mic:
            micBuffer.append(contentsOf: samples)
            if micBuffer.count >= chunkSampleCount {
                let chunk = Array(micBuffer.prefix(chunkSampleCount))
                micBuffer.removeFirst(chunkSampleCount)
                bufferLock.unlock()
                onMicChunk?(chunk)
                return
            }
        case .system:
            systemBuffer.append(contentsOf: samples)
            if systemBuffer.count >= chunkSampleCount {
                let chunk = Array(systemBuffer.prefix(chunkSampleCount))
                systemBuffer.removeFirst(chunkSampleCount)
                bufferLock.unlock()
                onSystemChunk?(chunk)
                return
            }
        }
        bufferLock.unlock()
    }

    private enum AudioSource {
        case mic, system
    }
}
