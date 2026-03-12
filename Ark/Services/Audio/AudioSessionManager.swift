import AVFoundation
import CoreAudio
import Observation

@MainActor @Observable
final class AudioSessionManager {
    let micService = MicrophoneCaptureService()
    let systemService = SystemAudioCaptureService()
    let driverManager = AudioDriverManager()
    let aggregateManager = AggregateDeviceManager()

    final class AudioBufferStorage: @unchecked Sendable {
        private let lock = NSLock()
        var micBuffer: [Float] = []
        var systemBuffer: [Float] = []
        var onMicChunk: (([Float]) -> Void)?
        var onSystemChunk: (([Float]) -> Void)?
        var chunkSampleCount: Int

        init(chunkSampleCount: Int) {
            self.chunkSampleCount = chunkSampleCount
        }

        func withLock<T>(_ body: (AudioBufferStorage) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(self)
        }
    }

    @ObservationIgnored nonisolated let storage = AudioBufferStorage(
        chunkSampleCount: Int(Constants.sampleRate * Constants.chunkDuration)
    )

    var isListening: Bool {
        micService.isCapturing || systemService.isCapturing
    }

    init() {
        micService.onAudioBuffer = { [weak self] buffer, _ in
            self?.handleBuffer(buffer, source: .mic)
        }

        systemService.onAudioBuffer = { [weak self] buffer, _ in
            self?.handleBuffer(buffer, source: .system)
        }

        // Restore original output if previous session crashed
        aggregateManager.restoreIfNeeded()
    }

    func checkMicPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micService.permissionGranted = granted
    }

    func configure(chunkDuration: TimeInterval) {
        let sanitizedDuration = max(1, chunkDuration)
        storage.withLock { s in
            s.chunkSampleCount = Int(Constants.sampleRate * sanitizedDuration)
            s.micBuffer.removeAll()
            s.systemBuffer.removeAll()
        }
    }

    func startListening(deviceID: String? = nil) throws {
        guard let blackHoleDeviceID = driverManager.findBlackHoleDeviceID() else {
            throw AudioSessionError.driverNotInstalled
        }

        try aggregateManager.createAggregateDevice(blackHoleDeviceID: blackHoleDeviceID)
        try aggregateManager.activateAsSystemOutput()
        try micService.start(deviceID: deviceID)
        try systemService.start(blackHoleDeviceID: blackHoleDeviceID)
    }

    func stopListening() {
        micService.stop()
        systemService.stop()
        aggregateManager.cleanup()
        storage.withLock { s in
            s.micBuffer.removeAll()
            s.systemBuffer.removeAll()
        }
    }

    nonisolated private func handleBuffer(_ buffer: AVAudioPCMBuffer, source: AudioSource) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        let result: (chunk: [Float], callback: (([Float]) -> Void)?)? = storage.withLock { s in
            switch source {
            case .mic:
                s.micBuffer.append(contentsOf: samples)
                if s.micBuffer.count >= s.chunkSampleCount {
                    let chunk = Array(s.micBuffer.prefix(s.chunkSampleCount))
                    s.micBuffer.removeFirst(s.chunkSampleCount)
                    return (chunk, s.onMicChunk)
                }
            case .system:
                s.systemBuffer.append(contentsOf: samples)
                if s.systemBuffer.count >= s.chunkSampleCount {
                    let chunk = Array(s.systemBuffer.prefix(s.chunkSampleCount))
                    s.systemBuffer.removeFirst(s.chunkSampleCount)
                    return (chunk, s.onSystemChunk)
                }
            }
            return nil
        }

        result?.callback?(result!.chunk)
    }

    private enum AudioSource {
        case mic, system
    }

    enum AudioSessionError: LocalizedError {
        case driverNotInstalled

        var errorDescription: String? {
            switch self {
            case .driverNotInstalled: "BlackHole audio driver not found. Install it in Settings."
            }
        }
    }
}
