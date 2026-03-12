import Foundation
import Observation
import SwiftUI

enum SuggestionCoordinatorState: Equatable {
    case idle
    case generatingAuto
    case generatingManual
    case holdingVisibleSuggestion(isManual: Bool)
}

struct SuggestionTimings: Sendable {
    var holdMinimumSeconds: TimeInterval = Constants.Suggestion.HOLD_MINIMUM_SECONDS
    var readingThresholdSeconds: TimeInterval = Constants.Suggestion.READING_THRESHOLD_SECONDS
    var readingCharsPerSecond: Double = Constants.Suggestion.READING_CHARS_PER_SECOND
    var turnPauseSeconds: TimeInterval = Constants.Suggestion.TURN_PAUSE_SECONDS
    var reevaluationGraceSeconds: TimeInterval = Constants.Suggestion.SIGNAL_REEVALUATION_GRACE_SECONDS
}

private struct PartialTurn {
    let speaker: TranscriptEntry.Speaker
    let startedAt: Date
    var updatedAt: Date
    var text: String

    mutating func append(fragment: String, timestamp: Date) {
        text = merge(existing: text, incoming: fragment)
        updatedAt = timestamp
    }

    private func merge(existing: String, incoming: String) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return existing }
        guard !existing.isEmpty else { return trimmedIncoming }

        if trimmedIncoming.hasPrefix(existing) {
            return trimmedIncoming
        }

        if existing.hasSuffix(trimmedIncoming) {
            return existing
        }

        let existingWords = existing.split(separator: " ").map(String.init)
        let incomingWords = trimmedIncoming.split(separator: " ").map(String.init)
        let maxOverlap = min(existingWords.count, incomingWords.count)

        if maxOverlap > 0 {
            for overlap in stride(from: maxOverlap, through: 1, by: -1) {
                let existingSuffix = existingWords.suffix(overlap)
                let incomingPrefix = incomingWords.prefix(overlap)
                if Array(existingSuffix) == Array(incomingPrefix) {
                    return (existingWords + incomingWords.dropFirst(overlap)).joined(separator: " ")
                }
            }
        }

        return "\(existing) \(trimmedIncoming)"
    }
}

@MainActor @Observable
final class SuggestionEngine {
    // MARK: - Output
    var displayedText = ""
    var isStreaming = false
    var contentHeight: CGFloat = 0
    private(set) var state: SuggestionCoordinatorState = .idle

    // MARK: - Dependencies
    private let codexService: any SuggestionCodexClient
    private let settingsStore: SettingsStore
    private let timings: SuggestionTimings

    // MARK: - Internal state
    private var observers: [TranscriptObserver] = []
    private var activeTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var reevaluationTask: Task<Void, Never>?
    private var buffer = ""
    private var activeRequest: SuggestionRequestContext?
    private var activeGenerationID: UUID?
    private var pendingSignals = PendingSignals()
    private var partialTurns: [TranscriptEntry.Speaker: PartialTurn] = [:]
    private var recentTurns: [ConversationTurn] = []
    private var lastSuggestionDisplayedAt: Date?
    private var holdUntil: Date?
    private var lastCompletedSuggestionText: String?
    private var lastUserOwnSpeechAt: Date?
    private var sessionHistory: [(action: String, answer: String)] = []
    private var automaticSuggestionsEnabled = true

    init(
        codexService: any SuggestionCodexClient,
        settingsStore: SettingsStore,
        timings: SuggestionTimings = SuggestionTimings()
    ) {
        self.codexService = codexService
        self.settingsStore = settingsStore
        self.timings = timings
    }

    // MARK: - Observer registration

    func register(_ observer: TranscriptObserver) {
        observer.onSignal = { [weak self] signal in
            Task { @MainActor [weak self] in
                self?.store(signal: signal)
            }
        }
        observers.append(observer)
    }

    // MARK: - Public helpers

    var isUserCommandActive: Bool {
        state == .generatingManual || state == .holdingVisibleSuggestion(isManual: true)
    }

    var areAutomaticSuggestionsEnabled: Bool {
        automaticSuggestionsEnabled
    }

    var recentTurnsTranscript: String {
        recentTurns
            .suffix(Constants.Suggestion.MAX_RECENT_TURNS)
            .map(\.formatted)
            .joined(separator: "\n")
    }

    func setAutomaticSuggestionsEnabled(_ isEnabled: Bool) {
        automaticSuggestionsEnabled = isEnabled
        if !isEnabled {
            pendingSignals.clear()
            clearDisplay()
        } else {
            evaluatePendingSignals()
        }
    }

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

    func ingestSpeechFragment(
        speaker: TranscriptEntry.Speaker,
        text: String?,
        timestamp: Date
    ) {
        finalizeExpiredTurns(now: timestamp, excluding: text == nil ? nil : speaker)

        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if speaker == .me, isEchoingSuggestion(text) {
                return
            }

            if speaker == .me {
                lastUserOwnSpeechAt = timestamp
                clearDisplay()
            }

            ingestTurnFragment(text, speaker: speaker, timestamp: timestamp)
            notifySpeechActivity(
                SpeechActivityEvent(speaker: speaker, didProduceText: true, timestamp: timestamp)
            )
            return
        }

        let activity = SpeechActivityEvent(speaker: speaker, didProduceText: false, timestamp: timestamp)
        notifySpeechActivity(activity)
        evaluatePendingSignals()
    }

    func handleUserCommand(action: VoiceAction, entries: [TranscriptEntry]) {
        let transcript = manualTranscript(for: action, entries: entries)
        guard !transcript.isEmpty else {
            displayedText = "Waiting for transcript... say something first."
            buffer = displayedText
            lastSuggestionDisplayedAt = Date()
            holdUntil = Date().addingTimeInterval(timings.holdMinimumSeconds)
            state = .holdingVisibleSuggestion(isManual: true)
            scheduleReevaluation()
            return
        }

        let profile = settingsStore.settings.assistantProfile
        let request = SuggestionRequestContext(
            requestID: UUID(),
            priority: .userCommand,
            prompt: PromptBuilder.buildVoiceActionPrompt(
                action: action,
                profile: profile,
                transcript: transcript,
                history: sessionHistory
            ),
            systemPrompt: PromptBuilder.systemPrompt(for: profile),
            source: "userCommand:\(action.rawValue)",
            historyLabel: action.promptLabel,
            signalKind: nil
        )

        generate(request, isManual: true)
    }

    // MARK: - Signal handling

    private func store(signal: SuggestionSignal) {
        guard settingsStore.settings.autoSuggest else { return }
        guard automaticSuggestionsEnabled else { return }
        pendingSignals.store(signal)
        evaluatePendingSignals()
    }

    private func evaluatePendingSignals() {
        reevaluationTask?.cancel()

        guard settingsStore.settings.autoSuggest else { return }
        guard automaticSuggestionsEnabled else { return }
        guard activeTask == nil else { return }
        if !isDisplayProtected, displayedText.isEmpty == false {
            state = .idle
        }
        guard !pendingSignals.isEmpty else { return }

        if let lastUserOwnSpeechAt {
            let blockedUntil = lastUserOwnSpeechAt.addingTimeInterval(timings.turnPauseSeconds)
            if blockedUntil > Date() {
                scheduleReevaluation(for: blockedUntil)
                return
            }
        }

        if isDisplayProtected {
            scheduleReevaluation()
            return
        }

        guard let signal = pendingSignals.bestAvailable() else { return }
        pendingSignals.remove(signal.kind)
        generate(request(for: signal), isManual: false)
    }

    // MARK: - Generation

    private func request(for signal: SuggestionSignal) -> SuggestionRequestContext {
        let profile = settingsStore.settings.assistantProfile
        let prompt: String

        switch signal.kind {
        case .question:
            prompt = PromptBuilder.buildQuestionResponsePrompt(
                profile: profile,
                transcript: signal.transcript,
                focus: signal.focusText
            )
        case .stuck:
            prompt = PromptBuilder.buildStuckContinuationPrompt(
                profile: profile,
                transcript: signal.transcript
            )
        case .followUp:
            prompt = PromptBuilder.buildFollowUpSuggestionPrompt(
                profile: profile,
                transcript: signal.transcript
            )
        }

        return SuggestionRequestContext(
            requestID: UUID(),
            priority: signal.priority,
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt(for: profile),
            source: signal.source,
            historyLabel: nil,
            signalKind: signal.kind
        )
    }

    private func generate(_ request: SuggestionRequestContext, isManual: Bool) {
        activeTask?.cancel()
        revealTask?.cancel()
        reevaluationTask?.cancel()

        activeRequest = request
        activeGenerationID = request.requestID
        state = isManual ? .generatingManual : .generatingAuto
        isStreaming = true
        buffer = ""
        displayedText = ""
        contentHeight = 0
        holdUntil = nil
        lastSuggestionDisplayedAt = nil
        lastCompletedSuggestionText = nil

        startRevealLoop()

        activeTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.codexService.chatStream(
                    systemPrompt: request.systemPrompt,
                    userMessage: request.prompt,
                    model: self.settingsStore.settings.aiModel,
                    reasoningLevel: self.settingsStore.settings.aiReasoningLevel,
                    requestID: request.requestID
                ) { [weak self] requestID, chunk in
                    Task { @MainActor in
                        guard let self else { return }
                        guard self.activeGenerationID == requestID else { return }
                        self.buffer += chunk
                    }
                }

                guard !Task.isCancelled else { return }
                guard self.activeGenerationID == request.requestID else { return }

                self.buffer = response

                if isManual {
                    self.sessionHistory.append((action: request.historyLabel ?? request.source, answer: response))
                }
            } catch {
                guard !(error is CancellationError) else { return }
                guard self.activeGenerationID == request.requestID else { return }
                self.buffer = "Error: \(error.localizedDescription)"
            }

            guard self.activeGenerationID == request.requestID else { return }
            self.activeTask = nil
        }
    }

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
                    let finishedManual = self.activeRequest?.priority == .userCommand
                    self.displayedText = self.buffer
                    self.isStreaming = false
                    self.state = .holdingVisibleSuggestion(isManual: finishedManual)
                    self.lastSuggestionDisplayedAt = Date()
                    self.holdUntil = Date().addingTimeInterval(self.timings.holdMinimumSeconds)
                    self.lastCompletedSuggestionText = self.buffer
                    self.activeGenerationID = nil
                    self.activeRequest = nil
                    self.scheduleReevaluation()
                    return
                } else {
                    try? await Task.sleep(nanoseconds: Constants.Suggestion.REVEAL_WAIT_NANOSECONDS)
                }
            }
        }
    }

    // MARK: - Turn assembly

    private func ingestTurnFragment(_ text: String, speaker: TranscriptEntry.Speaker, timestamp: Date) {
        if let otherSpeaker = TranscriptEntry.Speaker.allCases.first(where: { $0 != speaker }),
           partialTurns[otherSpeaker] != nil {
            finalizeTurn(for: otherSpeaker)
        }

        if var partialTurn = partialTurns[speaker] {
            if timestamp.timeIntervalSince(partialTurn.updatedAt) > timings.turnPauseSeconds {
                finalizeTurn(for: speaker)
                partialTurns[speaker] = PartialTurn(
                    speaker: speaker,
                    startedAt: timestamp,
                    updatedAt: timestamp,
                    text: text
                )
            } else {
                partialTurn.append(fragment: text, timestamp: timestamp)
                partialTurns[speaker] = partialTurn
            }
        } else {
            partialTurns[speaker] = PartialTurn(
                speaker: speaker,
                startedAt: timestamp,
                updatedAt: timestamp,
                text: text
            )
        }
    }

    private func finalizeExpiredTurns(now: Date, excluding speaker: TranscriptEntry.Speaker?) {
        let speakersToFinalize = partialTurns.values.compactMap { partialTurn -> TranscriptEntry.Speaker? in
            guard partialTurn.speaker != speaker else { return nil }
            let elapsed = now.timeIntervalSince(partialTurn.updatedAt)
            return elapsed >= timings.turnPauseSeconds ? partialTurn.speaker : nil
        }

        for speaker in speakersToFinalize {
            finalizeTurn(for: speaker)
        }
    }

    private func finalizeTurn(for speaker: TranscriptEntry.Speaker) {
        guard let partialTurn = partialTurns.removeValue(forKey: speaker) else { return }
        let trimmedText = partialTurn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let turn = ConversationTurn(
            speaker: speaker,
            text: trimmedText,
            startedAt: partialTurn.startedAt,
            updatedAt: partialTurn.updatedAt
        )

        recentTurns.append(turn)
        trimRecentTurns()

        guard settingsStore.settings.autoSuggest else { return }
        for observer in observers {
            observer.processTurn(turn, recentTurns: recentTurns)
        }
    }

    private func notifySpeechActivity(_ activity: SpeechActivityEvent) {
        guard settingsStore.settings.autoSuggest else { return }
        for observer in observers {
            observer.processSpeechActivity(activity, recentTurns: recentTurns)
        }
    }

    private func trimRecentTurns() {
        let cutoff = Date().addingTimeInterval(-Constants.Suggestion.TRANSCRIPT_WINDOW_SECONDS)
        recentTurns.removeAll { $0.updatedAt < cutoff }

        if recentTurns.count > Constants.Suggestion.MAX_RECENT_TURNS {
            recentTurns.removeFirst(recentTurns.count - Constants.Suggestion.MAX_RECENT_TURNS)
        }
    }

    // MARK: - Reading / hold

    private var isDisplayProtected: Bool {
        guard !displayedText.isEmpty else { return false }

        if let holdUntil, holdUntil > Date() {
            return true
        }

        return isUserReading
    }

    private var readingDeadline: Date? {
        guard !displayedText.isEmpty else { return nil }
        guard let displayedAt = lastSuggestionDisplayedAt else { return nil }
        let readingTime = max(
            timings.readingThresholdSeconds,
            Double(displayedText.count) / timings.readingCharsPerSecond
        )
        return displayedAt.addingTimeInterval(readingTime)
    }

    private var isUserReading: Bool {
        guard let readingDeadline else { return false }
        return readingDeadline > Date()
    }

    private func scheduleReevaluation(for explicitDate: Date? = nil) {
        reevaluationTask?.cancel()

        let targetDate = explicitDate ?? {
            var dates: [Date] = []
            if let holdUntil {
                dates.append(holdUntil)
            }
            if let readingDeadline {
                dates.append(readingDeadline)
            }
            if let lastUserOwnSpeechAt {
                dates.append(lastUserOwnSpeechAt.addingTimeInterval(timings.turnPauseSeconds))
            }
            return dates.max()
        }()

        guard let targetDate else {
            state = displayedText.isEmpty ? .idle : state
            evaluatePendingSignals()
            return
        }

        let delay = targetDate.timeIntervalSinceNow + timings.reevaluationGraceSeconds
        if delay <= 0 {
            state = displayedText.isEmpty ? .idle : state
            evaluatePendingSignals()
            return
        }

        reevaluationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.displayedText.isEmpty {
                    self.state = .idle
                }
                self.evaluatePendingSignals()
            }
        }
    }

    // MARK: - Lifecycle

    func clearDisplay() {
        revealTask?.cancel()
        activeTask?.cancel()
        reevaluationTask?.cancel()
        activeTask = nil
        revealTask = nil
        isStreaming = false
        displayedText = ""
        buffer = ""
        contentHeight = 0
        holdUntil = nil
        lastSuggestionDisplayedAt = nil
        activeRequest = nil
        activeGenerationID = nil
        state = .idle
        scheduleReevaluation()
    }

    func reset() {
        clearDisplay()
        pendingSignals.clear()
        partialTurns.removeAll()
        recentTurns.removeAll()
        lastCompletedSuggestionText = nil
        lastUserOwnSpeechAt = nil
        sessionHistory.removeAll()
        observers.forEach { $0.reset() }
    }

    // MARK: - Helpers

    private func manualTranscript(for action: VoiceAction, entries: [TranscriptEntry]) -> String {
        let relevantEntries: [TranscriptEntry]
        if action == .recap {
            let recent = entries.filter {
                $0.timestamp >= Date().addingTimeInterval(-Constants.Suggestion.TRANSCRIPT_WINDOW_SECONDS)
            }
            relevantEntries = recent.isEmpty ? entries.suffix(20).map { $0 } : recent
        } else {
            relevantEntries = entries.suffix(20).map { $0 }
        }

        return relevantEntries.map(\.formatted).joined(separator: "\n")
    }

    private func tokenize(_ text: String) -> [String] {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}

private extension TranscriptEntry.Speaker {
    static let allCases: [TranscriptEntry.Speaker] = [.me, .interviewer]
}
