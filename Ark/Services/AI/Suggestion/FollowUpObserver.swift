import Foundation

@MainActor
final class FollowUpObserver: TranscriptObserver {
    var onSignal: ((SuggestionSignal) -> Void)?

    private var lastSuggestedTurnID: UUID?
    private var lastFireDate: Date?

    func processTurn(_ turn: ConversationTurn, recentTurns: [ConversationTurn]) {}

    func processSpeechActivity(_ activity: SpeechActivityEvent, recentTurns: [ConversationTurn]) {
        guard !activity.didProduceText else { return }
        guard recentTurns.count >= 2 else { return }
        guard let lastTurn = recentTurns.last else { return }
        guard lastTurn.id != lastSuggestedTurnID else { return }
        guard activity.timestamp.timeIntervalSince(lastTurn.updatedAt) >= Constants.Suggestion.FOLLOW_UP_LULL_SECONDS else {
            return
        }

        if lastTurn.speaker == .interviewer,
           InterviewAssistantEngine.isLikelyQuestion(lastTurn.text) {
            return
        }

        if lastTurn.speaker == .me,
           InterviewAssistantEngine.isLikelyIncompleteResponse(lastTurn.text) {
            return
        }

        if let lastFireDate,
           activity.timestamp.timeIntervalSince(lastFireDate) < Constants.Suggestion.HOLD_MINIMUM_SECONDS {
            return
        }

        lastSuggestedTurnID = lastTurn.id
        lastFireDate = activity.timestamp

        onSignal?(
            SuggestionSignal(
                kind: .followUp,
                priority: .followUp,
                transcript: recentTranscript(from: recentTurns),
                focusText: lastTurn.text,
                source: "followUpObserver",
                timestamp: activity.timestamp
            )
        )
    }

    func reset() {
        lastSuggestedTurnID = nil
        lastFireDate = nil
    }

    private func recentTranscript(from turns: [ConversationTurn]) -> String {
        turns
            .suffix(Constants.Suggestion.MAX_RECENT_TURNS)
            .map(\.formatted)
            .joined(separator: "\n")
    }
}
