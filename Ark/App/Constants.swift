import Foundation

enum Constants {
    static let appName = "Ark"
    static let whisperModel = "large-v3"
    static let whisperLanguage = "pt"
    static let transcriptMaxDuration: TimeInterval = 30 * 60 // 30 minutes
    static let chunkDuration: TimeInterval = 15 // seconds
    static let sampleRate: Double = 16_000
    static let codexTimeoutSeconds: TimeInterval = 300

    enum UI {
        static let barHeight: CGFloat = 44
        static let barWidth: CGFloat = 280
        static let chatPanelWidth: CGFloat = 380
        static let chatPanelHeight: CGFloat = 480
        static let cornerRadius: CGFloat = 22
    }
}
