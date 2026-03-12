import Foundation

struct TranscriptEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let speaker: Speaker
    let text: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        timestamp: Date
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }

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

    static func mergeText(existing: String, incoming: String) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return existing }

        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExisting.isEmpty else { return trimmedIncoming }

        if trimmedIncoming.hasPrefix(trimmedExisting) {
            return trimmedIncoming
        }

        if trimmedExisting.hasPrefix(trimmedIncoming) {
            return trimmedExisting
        }

        if trimmedExisting.hasSuffix(trimmedIncoming) {
            return trimmedExisting
        }

        let existingWords = trimmedExisting.split(separator: " ").map(String.init)
        let incomingWords = trimmedIncoming.split(separator: " ").map(String.init)
        let maxOverlap = min(existingWords.count, incomingWords.count)

        if maxOverlap > 0 {
            for overlap in stride(from: maxOverlap, through: 1, by: -1) {
                let existingSuffix = existingWords.suffix(overlap)
                let incomingPrefix = incomingWords.prefix(overlap)
                if Array(existingSuffix) == Array(incomingPrefix) {
                    return (existingWords + incomingWords.dropFirst(overlap)).joined(separator: " ")
                }
            }
        }

        return "\(trimmedExisting) \(trimmedIncoming)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
