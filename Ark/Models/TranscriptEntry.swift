import Foundation

struct TranscriptEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let speaker: Speaker
    let text: String
    let timestamp: Date

    enum Speaker: String, Sendable {
        case me
        case interviewer

        var promptLabel: String {
            switch self {
            case .me:
                "Eu"
            case .interviewer:
                "Entrevistador"
            }
        }

        var displayLabel: String {
            switch self {
            case .me:
                "You"
            case .interviewer:
                "Interviewer"
            }
        }
    }

    var formatted: String {
        "[\(speaker.promptLabel)]: \(text)"
    }

    var shortTimeLabel: String {
        Self.timeFormatter.string(from: timestamp)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
