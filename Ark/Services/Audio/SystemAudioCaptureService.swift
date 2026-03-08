import ScreenCaptureKit
import AVFoundation
import Observation
import CoreMedia

@Observable
final class SystemAudioCaptureService: NSObject, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private(set) var isCapturing = false
    private(set) var permissionGranted = false
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func checkPermission() async {
        do {
            // Attempting to get shareable content checks permission
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            permissionGranted = true
        } catch {
            permissionGranted = false
        }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(Constants.sampleRate)
        config.channelCount = 1
        // Disable video capture - we only need audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 FPS minimum

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        try await stream.startCapture()
        self.stream = stream
        isCapturing = true
        permissionGranted = true
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        isCapturing = false
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        var streamDesc = asbd.pointee
        guard let audioFormat = AVAudioFormat(streamDescription: &streamDesc) else { return }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)

        if let channelData = pcmBuffer.floatChannelData {
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: channelData[0])
        }

        let time = AVAudioTime(sampleTime: 0, atRate: asbd.pointee.mSampleRate)
        onAudioBuffer?(pcmBuffer, time)
    }

    enum CaptureError: LocalizedError {
        case noDisplay
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noDisplay: "Nenhum display encontrado."
            case .permissionDenied: "Permissao de captura de tela negada. Va em Ajustes do Sistema > Privacidade > Gravacao de Tela."
            }
        }
    }
}
