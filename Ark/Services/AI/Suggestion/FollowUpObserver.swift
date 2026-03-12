import Foundation

@MainActor
final class FollowUpObserver: TranscriptObserver {
    var onRequest: ((SuggestionRequest) -> Void)?

    private let settingsStore: SettingsStore
    private var entriesSinceLastFire = 0

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func processNewEntry(_ entry: TranscriptEntry, allEntries: [TranscriptEntry]) {
        entriesSinceLastFire += 1

        guard entriesSinceLastFire >= Constants.Suggestion.FOLLOW_UP_ENTRIES_BETWEEN_FIRES else { return }

        // Don't fire if latest entry is an interviewer question (QuestionObserver handles that)
        if entry.speaker == .interviewer,
           InterviewAssistantEngine.isLikelyQuestion(entry.text) {
            return
        }

        // Suppress if recent entries look incomplete — let StuckObserver handle it
        let recentMeEntries = allEntries.suffix(3).filter { $0.speaker == .me }
        let incompleteCount = recentMeEntries.filter {
            InterviewAssistantEngine.isLikelyIncompleteResponse($0.text)
        }.count
        if incompleteCount >= 2 {
            return // Don't reset entriesSinceLastFire — retry on next entry
        }

        entriesSinceLastFire = 0

        let profile = settingsStore.settings.assistantProfile
        let transcript = allEntries.suffix(20).map(\.formatted).joined(separator: "\n")
        let prompt = PromptBuilder.buildFollowUpSuggestionPrompt(profile: profile, transcript: transcript)

        let request = SuggestionRequest(
            priority: .followUp,
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt(for: profile),
            source: "followUpObserver"
        )

        #if DEBUG
        print("[FollowUpObserver] Firing follow-up suggestion after \(Constants.Suggestion.FOLLOW_UP_ENTRIES_BETWEEN_FIRES) entries")
        #endif

        onRequest?(request)
    }

    func resetAccumulation() {
        entriesSinceLastFire = 0
    }
}
