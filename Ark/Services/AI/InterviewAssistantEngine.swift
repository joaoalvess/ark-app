import Foundation

enum InterviewAssistantEngine {
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
