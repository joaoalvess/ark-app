import Foundation

@MainActor
final class StuckObserver: TranscriptObserver {
    var onRequest: ((SuggestionRequest) -> Void)?

    private let settingsStore: SettingsStore
    private var consecutiveSilenceCount = 0
    private var consecutiveIncompleteEntries = 0
    private var lastFireDate: Date?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func processNewEntry(_ entry: TranscriptEntry, allEntries: [TranscriptEntry]) {
        // Any new entry resets silence counter
        consecutiveSilenceCount = 0

        // Only track .me entries for filler detection
        guard entry.speaker == .me else {
            consecutiveIncompleteEntries = 0
            return
        }

        guard InterviewAssistantEngine.isLikelyIncompleteResponse(entry.text) else {
            consecutiveIncompleteEntries = 0
            return
        }

        consecutiveIncompleteEntries += 1

        guard consecutiveIncompleteEntries >= Constants.Suggestion.STUCK_INCOMPLETE_ENTRIES_THRESHOLD else {
            return
        }

        // Rate limit
        if let lastFire = lastFireDate,
           Date().timeIntervalSince(lastFire) < Constants.Suggestion.STUCK_MIN_INTERVAL_SECONDS {
            return
        }

        lastFireDate = Date()
        consecutiveIncompleteEntries = 0
        consecutiveSilenceCount = 0

        let profile = settingsStore.settings.assistantProfile
        let transcript = allEntries.suffix(20).map(\.formatted).joined(separator: "\n")
        let prompt = PromptBuilder.buildStuckContinuationPrompt(profile: profile, transcript: transcript)

        let request = SuggestionRequest(
            priority: .userStuck,
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt(for: profile),
            source: "stuckObserver:filler"
        )

        #if DEBUG
        print("[StuckObserver] User appears stuck after \(Constants.Suggestion.STUCK_INCOMPLETE_ENTRIES_THRESHOLD) incomplete entries")
        #endif

        onRequest?(request)
    }

    func processSilence(allEntries: [TranscriptEntry]) {
        consecutiveSilenceCount += 1

        guard consecutiveSilenceCount >= Constants.Suggestion.STUCK_SILENCE_CHUNKS_THRESHOLD else { return }

        // Rate limit
        if let lastFire = lastFireDate,
           Date().timeIntervalSince(lastFire) < Constants.Suggestion.STUCK_MIN_INTERVAL_SECONDS {
            return
        }

        // Check that last user entry looks incomplete
        guard let lastMeEntry = allEntries.last(where: { $0.speaker == .me }),
              InterviewAssistantEngine.isLikelyIncompleteResponse(lastMeEntry.text) else {
            return
        }

        lastFireDate = Date()
        consecutiveSilenceCount = 0

        let profile = settingsStore.settings.assistantProfile
        let transcript = allEntries.suffix(20).map(\.formatted).joined(separator: "\n")
        let prompt = PromptBuilder.buildStuckContinuationPrompt(profile: profile, transcript: transcript)

        let request = SuggestionRequest(
            priority: .userStuck,
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt(for: profile),
            source: "stuckObserver:silence"
        )

        #if DEBUG
        print("[StuckObserver] User appears stuck after \(Constants.Suggestion.STUCK_SILENCE_CHUNKS_THRESHOLD) silent chunks")
        #endif

        onRequest?(request)
    }

    func resetAccumulation() {
        // No-op: silence counter is self-managed via processNewEntry/processSilence.
        // Other observers generating should not reset stuck detection progress.
    }
}
