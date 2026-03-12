import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class SuggestionEngine {
    // MARK: - Output (observed by UI)
    var displayedText = ""
    var isStreaming = false
    var contentHeight: CGFloat = 0

    // MARK: - Dependencies
    private let codexService: CodexCLIService
    private let settingsStore: SettingsStore

    // MARK: - Internal state
    private var observers: [TranscriptObserver] = []
    private var activeTask: Task<Void, Never>?
    private var buffer = ""
    private var revealTask: Task<Void, Never>?
    private var activeRequestPriority: SuggestionPriority?
    private var lastCompletedPriority: SuggestionPriority?
    private var lastSuggestionDisplayedAt: Date?
    private var commandCooldownUntil: Date?
    private var holdUntil: Date?
    private var lastCompletedSuggestionText: String?
    private var userCommandLock = false
    private var sessionHistory: [(action: String, answer: String)] = []

    init(codexService: CodexCLIService, settingsStore: SettingsStore) {
        self.codexService = codexService
        self.settingsStore = settingsStore
    }

    // MARK: - Observer registration

    func register(_ observer: TranscriptObserver) {
        observer.onRequest = { [weak self] request in
            Task { @MainActor [weak self] in
                self?.handleRequest(request)
            }
        }
        observers.append(observer)
    }

    // MARK: - Echo detection

    func isEchoingSuggestion(_ text: String) -> Bool {
        guard let lastSuggestion = lastCompletedSuggestionText, !lastSuggestion.isEmpty else {
            return false
        }
        let textTokens = tokenize(text)
        let suggestionTokens = tokenize(lastSuggestion)
        guard !textTokens.isEmpty, !suggestionTokens.isEmpty else { return false }

        let textSet = Set(textTokens)
        let suggestionSet = Set(suggestionTokens)
        let intersection = textSet.intersection(suggestionSet).count
        let union = textSet.union(suggestionSet).count
        let similarity = Double(intersection) / Double(union)
        return similarity >= 0.4
    }

    var isUserCommandActive: Bool {
        userCommandLock || activeRequestPriority == .userCommand
    }

    private func tokenize(_ text: String) -> [String] {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    // MARK: - Entry distribution

    func feedEntry(_ entry: TranscriptEntry, allEntries: [TranscriptEntry]) {
        guard settingsStore.settings.autoSuggest else { return }

        // Skip echo — user reading suggestion aloud
        if entry.speaker == .me, isEchoingSuggestion(entry.text) {
            #if DEBUG
            print("[SuggestionEngine] Echo detected, skipping entry: \(entry.text.prefix(40))")
            #endif
            return
        }

        for observer in observers {
            observer.processNewEntry(entry, allEntries: allEntries)
        }
    }

    func feedSilence(allEntries: [TranscriptEntry]) {
        guard settingsStore.settings.autoSuggest else { return }
        for observer in observers {
            if let stuckObserver = observer as? StuckObserver {
                stuckObserver.processSilence(allEntries: allEntries)
            }
        }
    }

    // MARK: - User commands (buttons)

    func handleUserCommand(action: VoiceAction, transcript: String) {
        guard !transcript.isEmpty else {
            buffer = "Aguardando transcrição... Fale algo primeiro."
            displayedText = buffer
            return
        }

        let profile = settingsStore.settings.assistantProfile
        let prompt = PromptBuilder.buildVoiceActionPrompt(
            action: action,
            profile: profile,
            transcript: transcript,
            history: sessionHistory
        )

        let request = SuggestionRequest(
            priority: .userCommand,
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt(for: profile),
            source: "userCommand:\(action.rawValue)"
        )

        handleRequest(request)
    }

    // MARK: - Request handling (central decision)

    private func handleRequest(_ request: SuggestionRequest) {
        #if DEBUG
        print("[SuggestionEngine] Request: \(request.source) priority=\(request.priority) | state: active=\(activeTask != nil) activePriority=\(String(describing: activeRequestPriority)) lastCompleted=\(String(describing: lastCompletedPriority)) reading=\(isUserReading)")
        #endif

        // 1. userCommand always executes (total bypass)
        guard request.priority != .userCommand else {
            #if DEBUG
            print("[SuggestionEngine] ACCEPTED \(request.source) (userCommand bypass)")
            #endif
            generate(request: request)
            return
        }

        // 2. User command lock — manual results persist until dismissed or new command
        if userCommandLock {
            #if DEBUG
            print("[SuggestionEngine] REJECTED \(request.source): user command result is displayed")
            #endif
            return
        }

        // 3. Cooldown check
        if let cooldownEnd = commandCooldownUntil, Date() < cooldownEnd {
            #if DEBUG
            print("[SuggestionEngine] REJECTED \(request.source): in cooldown")
            #endif
            return
        }

        // 4. Hold time check: drop if within hold and priority <= last completed
        if let holdEnd = holdUntil, Date() < holdEnd,
           let lastPriority = lastCompletedPriority,
           request.priority <= lastPriority {
            #if DEBUG
            print("[SuggestionEngine] REJECTED \(request.source): in hold time (priority \(request.priority) <= \(lastPriority))")
            #endif
            return
        }

        // 5. Reading detection: drop if reading and priority <= effective
        let effectivePriority = activeRequestPriority ?? lastCompletedPriority
        if isUserReading, let priority = effectivePriority,
           request.priority <= priority {
            #if DEBUG
            print("[SuggestionEngine] REJECTED \(request.source): user is reading (priority \(request.priority) <= \(priority))")
            #endif
            return
        }

        // 6. Active task check: drop if priority <= active
        if activeTask != nil, let activePriority = activeRequestPriority,
           request.priority <= activePriority {
            #if DEBUG
            print("[SuggestionEngine] REJECTED \(request.source): lower priority than active (\(request.priority) <= \(activePriority))")
            #endif
            return
        }

        #if DEBUG
        print("[SuggestionEngine] ACCEPTED \(request.source) (priority \(request.priority))")
        #endif

        generate(request: request)
    }

    // MARK: - Generation

    private func generate(request: SuggestionRequest) {
        // Cancel active generation
        activeTask?.cancel()
        revealTask?.cancel()

        // Reset accumulation on all observers to prevent stale state
        for observer in observers {
            observer.resetAccumulation()
        }

        // Clear echo memory — new genuine content is being generated
        lastCompletedSuggestionText = nil

        activeRequestPriority = request.priority
        userCommandLock = false
        buffer = ""
        displayedText = ""
        contentHeight = 0
        isStreaming = true

        startRevealLoop()

        activeTask = Task { [weak self] in
            guard let self else { return }

            do {
                // Debounce only for followUp (lowest priority, most spammy)
                if request.priority == .followUp {
                    try await Task.sleep(nanoseconds: Constants.Suggestion.DEBOUNCE_NANOSECONDS)
                    guard !Task.isCancelled else { return }
                }

                let response = try await self.codexService.chatStream(
                    systemPrompt: request.systemPrompt,
                    userMessage: request.prompt,
                    model: self.settingsStore.settings.aiModel,
                    reasoningLevel: self.settingsStore.settings.aiReasoningLevel,
                    onChunk: { [weak self] (chunk: String) in
                        Task { @MainActor in
                            self?.buffer += chunk
                        }
                    }
                )

                guard !Task.isCancelled else { return }

                // Use response as source-of-truth
                self.buffer = response

                // Save to session history for user commands
                if request.priority == .userCommand {
                    self.sessionHistory.append((action: request.source, answer: response))
                    self.userCommandLock = true
                    self.commandCooldownUntil = Date().addingTimeInterval(
                        Constants.Suggestion.COMMAND_COOLDOWN_SECONDS
                    )
                }

                #if DEBUG
                print("[SuggestionEngine] Generation complete: \(response.count) chars from \(request.source)")
                #endif
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }

                #if DEBUG
                print("[SuggestionEngine] Generation error: \(error)")
                #endif
                self.buffer = "Erro: \(error.localizedDescription)"
            }

            self.lastCompletedPriority = self.activeRequestPriority
            self.activeTask = nil
            self.activeRequestPriority = nil
        }
    }

    // MARK: - Reveal loop

    private func startRevealLoop() {
        revealTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                if self.displayedText.count < self.buffer.count {
                    let remaining = self.buffer.count - self.displayedText.count
                    let charsToReveal = min(max(remaining / 4, 1), 3)
                    let endIndex = self.buffer.index(
                        self.buffer.startIndex,
                        offsetBy: self.displayedText.count + charsToReveal
                    )
                    self.displayedText = String(self.buffer[..<endIndex])
                    try? await Task.sleep(nanoseconds: Constants.Suggestion.REVEAL_TICK_NANOSECONDS)
                } else if self.activeTask == nil && self.displayedText.count >= self.buffer.count {
                    // Done streaming and all text revealed
                    self.displayedText = self.buffer
                    self.isStreaming = false
                    self.lastSuggestionDisplayedAt = Date()
                    self.holdUntil = Date().addingTimeInterval(Constants.Suggestion.HOLD_MINIMUM_SECONDS)
                    self.lastCompletedSuggestionText = self.buffer
                    return
                } else {
                    // Waiting for more chunks
                    try? await Task.sleep(nanoseconds: Constants.Suggestion.REVEAL_WAIT_NANOSECONDS)
                }
            }
        }
    }

    // MARK: - Reading detection

    private var isUserReading: Bool {
        guard !displayedText.isEmpty else { return false }
        guard let displayedAt = lastSuggestionDisplayedAt else { return false }
        let elapsed = Date().timeIntervalSince(displayedAt)
        let readingTime = max(
            Constants.Suggestion.READING_THRESHOLD_SECONDS,
            Double(displayedText.count) / Constants.Suggestion.READING_CHARS_PER_SECOND
        )
        return elapsed < readingTime
    }

    // MARK: - Lifecycle

    func clearDisplay() {
        guard !displayedText.isEmpty || isStreaming else { return }
        revealTask?.cancel()
        activeTask?.cancel()
        displayedText = ""
        buffer = ""
        isStreaming = false
        contentHeight = 0
        activeRequestPriority = nil
        lastCompletedPriority = nil
        lastSuggestionDisplayedAt = nil
        holdUntil = nil
        userCommandLock = false
    }

    func reset() {
        activeTask?.cancel()
        revealTask?.cancel()
        activeTask = nil
        revealTask = nil
        displayedText = ""
        buffer = ""
        isStreaming = false
        contentHeight = 0
        activeRequestPriority = nil
        lastCompletedPriority = nil
        lastSuggestionDisplayedAt = nil
        commandCooldownUntil = nil
        holdUntil = nil
        lastCompletedSuggestionText = nil
        userCommandLock = false
        sessionHistory.removeAll()
    }
}
