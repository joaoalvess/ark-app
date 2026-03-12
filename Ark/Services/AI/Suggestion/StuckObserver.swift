import Foundation

@MainActor
final class StuckObserver: TranscriptObserver {
    var onSignal: ((SuggestionSignal) -> Void)?

    private var consecutiveIncompleteTurns = 0
    private var lastIncompleteTurn: ConversationTurn?
    private var lastFireDate: Date?

    func processTurn(_ turn: ConversationTurn, recentTurns: [ConversationTurn]) {
        guard turn.speaker == .me else {
            consecutiveIncompleteTurns = 0
            lastIncompleteTurn = nil
            return
        }

        guard InterviewAssistantEngine.isLikelyIncompleteResponse(turn.text) else {
            consecutiveIncompleteTurns = 0
            lastIncompleteTurn = nil
            return
        }

        lastIncompleteTurn = turn
        consecutiveIncompleteTurns += 1

        guard consecutiveIncompleteTurns >= Constants.Suggestion.STUCK_HESITATION_TURNS_THRESHOLD else {
            return
        }

        emitSignal(
            transcript: recentTranscript(from: recentTurns),
            focusText: turn.text,
            source: "stuckObserver:hesitation",
            now: turn.updatedAt
        )
    }

    func processSpeechActivity(_ activity: SpeechActivityEvent, recentTurns: [ConversationTurn]) {
        guard activity.speaker == .me else { return }
        guard !activity.didProduceText else { return }
        guard let lastIncompleteTurn else { return }
        guard activity.timestamp.timeIntervalSince(lastIncompleteTurn.updatedAt) >= Constants.Suggestion.TURN_PAUSE_SECONDS else {
            return
        }

        emitSignal(
            transcript: recentTranscript(from: recentTurns),
            focusText: lastIncompleteTurn.text,
            source: "stuckObserver:pause",
            now: activity.timestamp
        )
    }

    func reset() {
        consecutiveIncompleteTurns = 0
        lastIncompleteTurn = nil
        lastFireDate = nil
    }

    private func emitSignal(
        transcript: String,
        focusText: String,
        source: String,
        now: Date
    ) {
        guard canFire(at: now) else { return }

        lastFireDate = now
        consecutiveIncompleteTurns = 0
        lastIncompleteTurn = nil

        onSignal?(
            SuggestionSignal(
                kind: .stuck,
                priority: .userStuck,
                transcript: transcript,
                focusText: focusText,
                source: source,
                timestamp: now
            )
        )
    }

    private func canFire(at date: Date) -> Bool {
        guard let lastFireDate else { return true }
        return date.timeIntervalSince(lastFireDate) >= Constants.Suggestion.STUCK_MIN_INTERVAL_SECONDS
    }

    private func recentTranscript(from turns: [ConversationTurn]) -> String {
        turns
            .suffix(Constants.Suggestion.MAX_RECENT_TURNS)
            .map(\.formatted)
            .joined(separator: "\n")
    }
}
