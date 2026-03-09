import Foundation

enum Constants {
    static let appName = "Ark"
    static let whisperModel = "large-v3"
    static let whisperLanguage = "pt"
    static let transcriptMaxDuration: TimeInterval = 30 * 60 // 30 minutes
    static let chunkDuration: TimeInterval = 5 // seconds
    static let sampleRate: Double = 16_000
    static let codexTimeoutSeconds: TimeInterval = 300

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
