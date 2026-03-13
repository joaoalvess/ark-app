import Foundation
import SwiftUI

enum Constants {
    static let appName = "Ark"
    static let whisperModel = "large-v3-turbo"
    static let whisperLanguage = "pt"
    static let transcriptMaxDuration: TimeInterval = 30 * 60 // 30 minutes
    static let chunkDuration: TimeInterval = 5 // seconds
    static let sampleRate: Double = 16_000
    static let codexTimeoutSeconds: TimeInterval = 300

    enum AudioDriver {
        static let DEVICE_NAME = "ArkAudio 2ch"
        static let DEVICE_UID_SUBSTRING = "ArkAudio"
        static let DRIVER_BUNDLE_NAME = "ArkAudio2ch.driver"
        static let DRIVER_HAL_PATH = "/Library/Audio/Plug-Ins/HAL/ArkAudio2ch.driver"
        static let LEGACY_DEVICE_NAME = "BlackHole 2ch"
        static let LEGACY_DEVICE_UID_SUBSTRING = "BlackHole2ch"
        static let LEGACY_DRIVER_HAL_PATH = "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
        static let PKG_RESOURCE_NAME = "ArkAudioDriver"
        static let PKG_RESOURCE_EXT = "pkg"
        static let ROUTING_VALIDATED_OUTPUT_UID_KEY = "ArkAudioRoutingValidatedOutputUID"
        static let ROUTING_VALIDATED_DRIVER_UID_KEY = "ArkAudioRoutingValidatedDriverUID"
        static let ROUTING_VALIDATION_DURATION_SECONDS: TimeInterval = 5
        static let ROUTING_VALIDATION_RMS_THRESHOLD: Float = 0.001
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

    enum Transcription {
        static let OPENAI_WHISPER_ENDPOINT = "https://api.openai.com/v1/audio/transcriptions"
        static let OPENAI_WHISPER_MODEL = "gpt-4o-mini-transcribe"
    }

    enum Hallucination {
        static let MAX_CONSECUTIVE_REPEATS = 2
        static let BLOCKLIST: Set<String> = [
            "obrigado", "obrigado.", "obrigada", "obrigada.",
            "legendas por", "legendas pela", "legenda adriana zanotto",
            "thank you", "thank you.", "thanks for watching",
            "please subscribe", "like and subscribe",
            "subtítulos", "sous-titres", "untertitel",
        ]
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
