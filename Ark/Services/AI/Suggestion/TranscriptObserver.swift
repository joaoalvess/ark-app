import Foundation

enum SuggestionPriority: Int, Comparable, Sendable {
    case followUp = 1
    case interviewerQuestion = 2
    case userStuck = 3
    case userCommand = 4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct SuggestionRequest: Sendable {
    let priority: SuggestionPriority
    let prompt: String
    let systemPrompt: String
    let source: String
    let timestamp: Date = Date()
}

@MainActor
protocol TranscriptObserver: AnyObject {
    func processNewEntry(_ entry: TranscriptEntry, allEntries: [TranscriptEntry])
    var onRequest: ((SuggestionRequest) -> Void)? { get set }
    func resetAccumulation()
}
