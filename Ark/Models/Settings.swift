import Foundation

struct AppSettings: Codable {
    var whisperModel: String = Constants.whisperModel
    var inputDeviceID: String?
    var autoSuggest: Bool = true
    var chunkDuration: TimeInterval = Constants.chunkDuration
    var aiModel: String = "gpt-5.4"
    var aiReasoningLevel: String = "high"
    var assistantProfile: AssistantProfile = .techInterview

    enum CodingKeys: String, CodingKey {
        case whisperModel
        case inputDeviceID
        case autoSuggest
        case chunkDuration
        case aiModel
        case aiReasoningLevel
        case assistantProfile
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whisperModel = try container.decodeIfPresent(String.self, forKey: .whisperModel) ?? Constants.whisperModel
        inputDeviceID = try container.decodeIfPresent(String.self, forKey: .inputDeviceID)
        autoSuggest = try container.decodeIfPresent(Bool.self, forKey: .autoSuggest) ?? true
        let storedWindow = try container.decodeIfPresent(TimeInterval.self, forKey: .chunkDuration) ?? Constants.chunkDuration
        chunkDuration = min(
            max(storedWindow, Constants.Suggestion.TRANSCRIPTION_WINDOW_MIN_SECONDS),
            Constants.Suggestion.TRANSCRIPTION_WINDOW_MAX_SECONDS
        )
        aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? "gpt-5.4"
        aiReasoningLevel = try container.decodeIfPresent(String.self, forKey: .aiReasoningLevel) ?? "high"
        assistantProfile = try container.decodeIfPresent(AssistantProfile.self, forKey: .assistantProfile) ?? .techInterview
    }
}
