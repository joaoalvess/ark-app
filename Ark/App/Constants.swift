import Foundation
import SwiftUI

enum Constants {
    static let appName = "Ark"
    static let whisperModel = "large-v3"
    static let whisperLanguage = "pt"
    static let transcriptMaxDuration: TimeInterval = 30 * 60 // 30 minutes
    static let chunkDuration: TimeInterval = 3 // seconds
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
        static let READING_THRESHOLD_SECONDS: TimeInterval = 3.0
        static let READING_CHARS_PER_SECOND: Double = 5.0
        static let HOLD_MINIMUM_SECONDS: TimeInterval = 3.0
        static let ANALYSIS_CHUNK_DURATION: TimeInterval = 1.0
        static let TRANSCRIPTION_WINDOW_MIN_SECONDS: TimeInterval = 2.0
        static let TRANSCRIPTION_WINDOW_MAX_SECONDS: TimeInterval = 6.0
        static let TURN_PAUSE_SECONDS: TimeInterval = 0.8
        static let FOLLOW_UP_LULL_SECONDS: TimeInterval = 1.6
        static let SIGNAL_REEVALUATION_GRACE_SECONDS: TimeInterval = 0.05
        static let SIGNAL_MAX_AGE_SECONDS: TimeInterval = 4.0
        static let TRANSCRIPT_WINDOW_SECONDS: TimeInterval = 5 * 60
        static let ACTIVE_AUDIO_WINDOW_SECONDS: TimeInterval = 3.0
        static let STUCK_MIN_INTERVAL_SECONDS: TimeInterval = 8.0
        static let STUCK_HESITATION_TURNS_THRESHOLD = 2
        static let MAX_RECENT_TURNS = 24
        static let REVEAL_TICK_NANOSECONDS: UInt64 = 10_000_000
        static let REVEAL_WAIT_NANOSECONDS: UInt64 = 20_000_000
    }

    enum UI {
        static let barHeight: CGFloat = 48
        static let barWidth: CGFloat = 220
        static let barWidthListening: CGFloat = 320
        static let chatPanelWidth: CGFloat = 420
        static let chatPanelHeight: CGFloat = 480
        static let cornerRadius: CGFloat = 22
        static let iconButtonSize: CGFloat = 36
        static let inputBarHeight: CGFloat = 52
        static let askPanelMaxHeight: CGFloat = 300
        static let askResponseMaxHeight: CGFloat = 200
        static let voiceResponseMaxHeight: CGFloat = 200
        static let voiceResponseCompactMaxHeight: CGFloat = 132
        static let transcriptPanelHeight: CGFloat = 320
        static let panelStackSpacing: CGFloat = 8
        static let subtlePanelTransitionDuration: Double = 0.18
        static let subtlePanelTransitionScale: CGFloat = 0.985
        static let subtlePanelTransition = Animation.easeOut(duration: subtlePanelTransitionDuration)
    }
}
