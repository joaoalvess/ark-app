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

    enum Suggestion {
        static let COMMAND_COOLDOWN_SECONDS: TimeInterval = 3.0
        static let READING_THRESHOLD_SECONDS: TimeInterval = 3.0
        static let READING_CHARS_PER_SECOND: Double = 5.0
        static let HOLD_MINIMUM_SECONDS: TimeInterval = 3.0
        static let STUCK_SILENCE_CHUNKS_THRESHOLD = 2
        static let STUCK_MIN_INTERVAL_SECONDS: TimeInterval = 8.0
        static let STUCK_INCOMPLETE_ENTRIES_THRESHOLD = 3
        static let FOLLOW_UP_ENTRIES_BETWEEN_FIRES = 4
        static let DEBOUNCE_NANOSECONDS: UInt64 = 100_000_000
        static let REVEAL_TICK_NANOSECONDS: UInt64 = 10_000_000
        static let REVEAL_WAIT_NANOSECONDS: UInt64 = 20_000_000
    }

    enum UI {
        static let barHeight: CGFloat = 48
        static let barWidth: CGFloat = 220
        static let barWidthListening: CGFloat = 270
        static let chatPanelWidth: CGFloat = 420
        static let chatPanelHeight: CGFloat = 480
        static let cornerRadius: CGFloat = 22
        static let iconButtonSize: CGFloat = 36
        static let inputBarHeight: CGFloat = 52
        static let askPanelMaxHeight: CGFloat = 300
        static let askResponseMaxHeight: CGFloat = 200
        static let voiceButtonsHeight: CGFloat = 32
        static let voiceResponseMaxHeight: CGFloat = 200
    }
}
