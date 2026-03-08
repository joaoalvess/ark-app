import Foundation

struct TranscriptEntry: Identifiable, Equatable {
    let id = UUID()
    let speaker: Speaker
    let text: String
    let timestamp: Date

    enum Speaker: String {
        case me = "Eu"
        case interviewer = "Entrevistador"
    }

    var formatted: String {
        "[\(speaker.rawValue)]: \(text)"
    }
}
