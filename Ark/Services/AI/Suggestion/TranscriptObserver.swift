import Foundation

enum SuggestionPriority: Int, Comparable, Sendable {
    case followUp = 1
    case interviewerQuestion = 2
    case userStuck = 3
    case userCommand = 4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum SuggestionSignalKind: String, Sendable {
    case question
    case stuck
    case followUp
}

struct ConversationTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let speaker: TranscriptEntry.Speaker
    let text: String
    let startedAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        speaker: TranscriptEntry.Speaker,
        text: String,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    var formatted: String {
        "[\(speaker.promptLabel)]: \(text)"
    }
}

struct SpeechActivityEvent: Sendable {
    let speaker: TranscriptEntry.Speaker
    let didProduceText: Bool
    let timestamp: Date
}

struct SuggestionSignal: Sendable {
    let kind: SuggestionSignalKind
    let priority: SuggestionPriority
    let transcript: String
    let focusText: String
    let source: String
    let timestamp: Date

    init(
        kind: SuggestionSignalKind,
        priority: SuggestionPriority,
        transcript: String,
        focusText: String,
        source: String,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.priority = priority
        self.transcript = transcript
        self.focusText = focusText
        self.source = source
        self.timestamp = timestamp
    }
}

struct PendingSignals: Sendable {
    private(set) var question: SuggestionSignal?
    private(set) var stuck: SuggestionSignal?
    private(set) var followUp: SuggestionSignal?

    var isEmpty: Bool {
        question == nil && stuck == nil && followUp == nil
    }

    mutating func store(_ signal: SuggestionSignal) {
        switch signal.kind {
        case .question:
            question = signal
        case .stuck:
            stuck = signal
        case .followUp:
            followUp = signal
        }
    }

    mutating func remove(_ kind: SuggestionSignalKind) {
        switch kind {
        case .question:
            question = nil
        case .stuck:
            stuck = nil
        case .followUp:
            followUp = nil
        }
    }

    mutating func clear() {
        question = nil
        stuck = nil
        followUp = nil
    }

    func bestAvailable() -> SuggestionSignal? {
        [stuck, question, followUp]
            .compactMap { $0 }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.timestamp > rhs.timestamp
            }
            .first
    }
}

struct SuggestionRequestContext: Sendable {
    let requestID: UUID
    let priority: SuggestionPriority
    let prompt: String
    let systemPrompt: String
    let source: String
    let historyLabel: String?
    let signalKind: SuggestionSignalKind?
}

@MainActor
protocol TranscriptObserver: AnyObject {
    func processTurn(_ turn: ConversationTurn, recentTurns: [ConversationTurn])
    func processSpeechActivity(_ activity: SpeechActivityEvent, recentTurns: [ConversationTurn])
    var onSignal: ((SuggestionSignal) -> Void)? { get set }
    func reset()
}
