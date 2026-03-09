import Foundation

enum InterviewSuggestionMode: String, Sendable {
    case answerQuestion
    case continueCandidate
}

enum InterviewSuggestionState: Equatable, Sendable {
    case idle
    case live(turnID: UUID)
    case locked(turnID: UUID)

    var turnID: UUID? {
        switch self {
        case .idle:
            nil
        case .live(let turnID), .locked(let turnID):
            turnID
        }
    }
}

enum InterviewTurnTrigger: Sendable {
    case interviewerEntry
    case candidateEntry
    case candidateSilence
}

struct InterviewTurnContext: Equatable, Sendable {
    let turnID: UUID
    let interviewerPrompt: String
    let candidateResponse: String
    let latestCandidateSegment: String?
    let mode: InterviewSuggestionMode
    let candidateResponseLikelyIncomplete: Bool
}

enum InterviewAssistantEngine {
    static func makeContext(
        from entries: [TranscriptEntry],
        trigger: InterviewTurnTrigger
    ) -> InterviewTurnContext? {
        guard let interviewerIndex = entries.lastIndex(where: { $0.speaker == .interviewer }) else {
            return nil
        }

        let interviewerEntry = entries[interviewerIndex]
        let candidateEntries: [TranscriptEntry]
        if interviewerIndex + 1 < entries.count {
            candidateEntries = entries[(interviewerIndex + 1)...].filter { $0.speaker == .me }
        } else {
            candidateEntries = []
        }
        let candidateResponse = candidateEntries.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let latestCandidateSegment = candidateEntries.last?.text
        let candidateResponseLikelyIncomplete = isLikelyIncompleteResponse(candidateResponse)

        switch trigger {
        case .interviewerEntry:
            guard shouldTriggerSuggestion(for: interviewerEntry.text) else { return nil }
            return InterviewTurnContext(
                turnID: interviewerEntry.id,
                interviewerPrompt: interviewerEntry.text,
                candidateResponse: candidateResponse,
                latestCandidateSegment: latestCandidateSegment,
                mode: .answerQuestion,
                candidateResponseLikelyIncomplete: candidateResponseLikelyIncomplete
            )

        case .candidateEntry, .candidateSilence:
            guard !candidateResponse.isEmpty, candidateResponseLikelyIncomplete else { return nil }
            return InterviewTurnContext(
                turnID: interviewerEntry.id,
                interviewerPrompt: interviewerEntry.text,
                candidateResponse: candidateResponse,
                latestCandidateSegment: latestCandidateSegment,
                mode: .continueCandidate,
                candidateResponseLikelyIncomplete: true
            )
        }
    }

    static func shouldTriggerSuggestion(for interviewerText: String) -> Bool {
        let normalized = normalizedText(interviewerText)
        guard !normalized.isEmpty else { return false }

        if isLikelyQuestion(interviewerText) {
            return true
        }

        let wordCount = tokens(in: normalized).count
        return wordCount >= 5
    }

    static func isLikelyQuestion(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return false }

        if normalized.hasSuffix("?") {
            return true
        }

        let lowercased = normalized.lowercased()
        let questionPrefixes = [
            "como",
            "qual",
            "quais",
            "por que",
            "porque",
            "quando",
            "onde",
            "quem",
            "o que",
            "me conta",
            "me conte",
            "fale sobre",
            "fala sobre",
            "descreva",
            "descreve",
            "explique",
            "explica",
            "tell me about",
            "walk me through",
            "can you",
            "could you",
            "what",
            "why",
            "how"
        ]

        return questionPrefixes.contains { lowercased.hasPrefix($0) }
    }

    static func isLikelyIncompleteResponse(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return false }

        if normalized.contains("...") || normalized.contains("…") {
            return true
        }

        let lowercased = normalized.lowercased()
        let lastToken = tokens(in: lowercased).last ?? ""
        let fillers: Set<String> = [
            "ah",
            "ahn",
            "an",
            "eh",
            "hum",
            "hmm",
            "tipo",
            "assim",
            "ne"
        ]
        let danglingTokens: Set<String> = [
            "porque",
            "por",
            "que",
            "pra",
            "para",
            "com",
            "sem",
            "e",
            "ou",
            "mas",
            "entao",
            "como"
        ]
        let completeEndingTokens: Set<String> = [
            "la", "ja", "ai", "no", "se", "so", "eu"
        ]

        if fillers.contains(lastToken) || danglingTokens.contains(lastToken) {
            return true
        }

        if normalized.hasSuffix(",") || normalized.hasSuffix(":") || normalized.hasSuffix("-") {
            return true
        }

        return lastToken.count <= 2 && tokens(in: lowercased).count >= 4 && !completeEndingTokens.contains(lastToken)
    }

    static func stateAfterCandidateSpeech(
        currentState: InterviewSuggestionState,
        turnID: UUID
    ) -> InterviewSuggestionState {
        guard currentState.turnID == turnID else { return currentState }
        guard case .live = currentState else { return currentState }
        return .locked(turnID: turnID)
    }

    static func shouldRequestSuggestionAfterCandidateSilence(
        currentState: InterviewSuggestionState,
        context: InterviewTurnContext
    ) -> Bool {
        if case .live(let turnID) = currentState, turnID == context.turnID {
            return false
        }

        return true
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(in text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
