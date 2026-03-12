import Foundation

@MainActor
final class QuestionObserver: TranscriptObserver {
    var onRequest: ((SuggestionRequest) -> Void)?

    private let settingsStore: SettingsStore
    private var lastProcessedInterviewerID: UUID?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func processNewEntry(_ entry: TranscriptEntry, allEntries: [TranscriptEntry]) {
        guard entry.speaker == .interviewer else { return }
        guard entry.id != lastProcessedInterviewerID else { return }

        let text = entry.text
        guard InterviewAssistantEngine.shouldTriggerSuggestion(for: text) else { return }

        lastProcessedInterviewerID = entry.id

        let profile = settingsStore.settings.assistantProfile
        let transcript = allEntries.suffix(20).map(\.formatted).joined(separator: "\n")
        let isQuestion = InterviewAssistantEngine.isLikelyQuestion(text)

        let prompt: String
        if isQuestion {
            prompt = PromptBuilder.buildSuggestionPrompt(profile: profile, transcript: transcript)
        } else {
            prompt = PromptBuilder.buildFollowUpSuggestionPrompt(profile: profile, transcript: transcript)
        }

        let request = SuggestionRequest(
            priority: .interviewerQuestion,
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt(for: profile),
            source: isQuestion ? "questionObserver:question" : "questionObserver:statement"
        )

        #if DEBUG
        print("[QuestionObserver] Detected interviewer entry: \(text.prefix(60))... isQuestion=\(isQuestion)")
        #endif

        onRequest?(request)
    }

    func resetAccumulation() { /* stateless per entry */ }
}
