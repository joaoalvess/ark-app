import Foundation

enum Constants {
    static let appName = "Ark"
    static let whisperModel = "large-v3"
    static let whisperLanguage = "pt"
    static let transcriptMaxDuration: TimeInterval = 30 * 60 // 30 minutes
    static let chunkDuration: TimeInterval = 5 // seconds
    static let sampleRate: Double = 16_000
    static let codexTimeoutSeconds: TimeInterval = 300

    enum AudioDriver {
        static let BLACKHOLE_UID_SUBSTRING = "BlackHole2ch"
        static let DRIVER_HAL_PATH = "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
        static let AGGREGATE_DEVICE_NAME = "Ark Audio Bridge"
        static let AGGREGATE_DEVICE_UID = "com.ark.aggregate.bridge"
        static let PKG_RESOURCE_NAME = "ArkAudioDriver"
        static let PKG_RESOURCE_EXT = "pkg"
        static let ORIGINAL_OUTPUT_UID_KEY = "ArkOriginalOutputDeviceUID"
    }

    enum UI {
        static let barHeight: CGFloat = 48
        static let barWidth: CGFloat = 260
        static let chatPanelWidth: CGFloat = 420
        static let chatPanelHeight: CGFloat = 480
        static let cornerRadius: CGFloat = 22
        static let iconButtonSize: CGFloat = 36
        static let inputBarHeight: CGFloat = 52
    }
}
