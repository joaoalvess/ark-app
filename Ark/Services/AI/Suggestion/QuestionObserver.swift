import Foundation

@MainActor
final class QuestionObserver: TranscriptObserver {
    var onSignal: ((SuggestionSignal) -> Void)?

    private var lastProcessedTurnID: UUID?

    func processTurn(_ turn: ConversationTurn, recentTurns: [ConversationTurn]) {
        guard turn.speaker == .interviewer else { return }
        guard turn.id != lastProcessedTurnID else { return }
        guard InterviewAssistantEngine.isLikelyQuestion(turn.text) else { return }

        lastProcessedTurnID = turn.id

        onSignal?(
            SuggestionSignal(
                kind: .question,
                priority: .interviewerQuestion,
                transcript: recentTranscript(from: recentTurns),
                focusText: turn.text,
                source: "questionObserver"
            )
        )
    }

    func processSpeechActivity(_ activity: SpeechActivityEvent, recentTurns: [ConversationTurn]) {}

    func reset() {
        lastProcessedTurnID = nil
    }

    private func recentTranscript(from turns: [ConversationTurn]) -> String {
        turns
            .suffix(Constants.Suggestion.MAX_RECENT_TURNS)
            .map(\.formatted)
            .joined(separator: "\n")
    }
}
