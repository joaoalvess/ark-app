import Foundation

struct AppSettings: Codable {
    var whisperModel: String = Constants.whisperModel
    var inputDeviceID: String?
    var autoSuggest: Bool = true
    var chunkDuration: TimeInterval = Constants.chunkDuration
    var aiModel: String = "gpt-5.4"
    var aiReasoningLevel: String = "high"
}
