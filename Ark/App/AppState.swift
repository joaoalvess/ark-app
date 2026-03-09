import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppState {
    // Services
    var audioManager = AudioSessionManager()
    var whisperService = WhisperService()
    var transcriptManager = TranscriptManager()
    var codexService = CodexCLIService()
    var settingsStore = SettingsStore()

    // UI State
    var isListening = false
    var isChatVisible = false
    var messages: [ChatMessage] = []
    var currentInput = ""
    var isProcessing = false
    var isSuggestionProcessing = false
    var errorMessage: String?

    private var activeSuggestionMessageID: UUID?
    private var interviewSuggestionState: InterviewSuggestionState = .idle
    private var suggestionTask: Task<Void, Never>?
    private var suggestionRequestID = 0
    private let suggestionDebounceNanoseconds: UInt64 = 250_000_000

    init() {
        setupAudioCallbacks()
    }

    // MARK: - Actions

    func setup() async {
        await codexService.checkAvailability()
        await audioManager.systemService.checkPermission()
        await audioManager.checkMicPermission()
    }

    func toggleListening() async {
        if isListening {
            await stopListening()
        } else {
            await startListening()
        }
    }

    func toggleChat() {
        isChatVisible.toggle()
    }

    func sendMessage() async {
        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }

        currentInput = ""
        messages.append(.user(text))
        messages.append(.assistant("", streaming: true))
        isProcessing = true
        errorMessage = nil

        let transcript = transcriptManager.formattedTranscript
        let profile = settingsStore.settings.assistantProfile
        let prompt = PromptBuilder.buildChatPrompt(profile: profile, transcript: transcript, question: text)
        let messageID = messages[messages.count - 1].id

        do {
            let response = try await codexService.chatStream(
                systemPrompt: PromptBuilder.systemPrompt(for: profile),
                userMessage: prompt,
                model: settingsStore.settings.aiModel,
                reasoningLevel: settingsStore.settings.aiReasoningLevel,
                onChunk: { [weak self] (chunk: String) in
                    Task { @MainActor in
                        guard let self,
                              let index = self.messages.firstIndex(where: { $0.id == messageID }) else { return }
                        self.messages[index].text += chunk
                    }
                }
            )

            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = response
                messages[index].isStreaming = false
            }
        } catch {
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = "Erro: \(error.localizedDescription)"
                messages[index].isStreaming = false
            }
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    func requestSuggestion() async {
        guard settingsStore.settings.autoSuggest else { return }

        let profile = settingsStore.settings.assistantProfile
        switch profile {
        case .techInterview:
            guard let context = transcriptManager.interviewTurnContext(trigger: .interviewerEntry) else { return }
            scheduleInterviewSuggestion(for: context)

        case .generalist, .code:
            let transcript = transcriptManager.recentTranscript
            guard !transcript.isEmpty else { return }
            scheduleGenericSuggestion(profile: profile, transcript: transcript)
        }
    }

    func useSuggestion(_ text: String) async {
        currentInput = text
        await sendMessage()
    }

    // MARK: - Private

    private func startListening() async {
        do {
            if !whisperService.isModelLoaded {
                await whisperService.loadModel(name: settingsStore.settings.whisperModel)
            }

            resetSuggestionPipeline(clearMessageReference: true)
            audioManager.configure(chunkDuration: settingsStore.settings.chunkDuration)
            try await audioManager.startListening(deviceID: settingsStore.settings.inputDeviceID)
            isListening = true
            isChatVisible = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopListening() async {
        await audioManager.stopListening()
        resetSuggestionPipeline(clearMessageReference: true)
        isListening = false
    }

    private func setupAudioCallbacks() {
        audioManager.storage.onMicChunk = { [weak self] samples in
            guard let self else { return }
            Task {
                await self.processMicrophoneChunk(samples)
            }
        }

        audioManager.storage.onSystemChunk = { [weak self] samples in
            guard let self else { return }
            Task {
                await self.processSystemChunk(samples)
            }
        }
    }

    private func processMicrophoneChunk(_ samples: [Float]) async {
        if let text = await whisperService.transcribe(audioSamples: samples) {
            transcriptManager.addEntry(speaker: .me, text: text)
            await handleCandidateTranscript()
        } else {
            await handleCandidateSilence()
        }
    }

    private func processSystemChunk(_ samples: [Float]) async {
        guard let text = await whisperService.transcribe(audioSamples: samples) else { return }
        transcriptManager.addEntry(speaker: .interviewer, text: text)
        await handleInterviewerTranscript()
    }

    private func handleInterviewerTranscript() async {
        guard settingsStore.settings.autoSuggest else { return }

        let profile = settingsStore.settings.assistantProfile
        switch profile {
        case .techInterview:
            guard let context = transcriptManager.interviewTurnContext(trigger: .interviewerEntry) else { return }
            scheduleInterviewSuggestion(for: context)

        case .generalist, .code:
            let transcript = transcriptManager.recentTranscript
            guard !transcript.isEmpty else { return }
            scheduleGenericSuggestion(profile: profile, transcript: transcript)
        }
    }

    private func handleCandidateTranscript() async {
        guard settingsStore.settings.autoSuggest,
              settingsStore.settings.assistantProfile == .techInterview,
              let turnID = transcriptManager.lastInterviewerEntry?.id else {
            return
        }

        let nextState = InterviewAssistantEngine.stateAfterCandidateSpeech(
            currentState: interviewSuggestionState,
            turnID: turnID
        )
        guard nextState != interviewSuggestionState else { return }

        cancelSuggestionTask()
        interviewSuggestionState = nextState
    }

    private func handleCandidateSilence() async {
        guard settingsStore.settings.autoSuggest,
              settingsStore.settings.assistantProfile == .techInterview,
              let context = transcriptManager.interviewTurnContext(trigger: .candidateSilence) else {
            return
        }

        guard InterviewAssistantEngine.shouldRequestSuggestionAfterCandidateSilence(
            currentState: interviewSuggestionState,
            context: context
        ) else {
            return
        }

        scheduleInterviewSuggestion(for: context)
    }

    private func scheduleInterviewSuggestion(for context: InterviewTurnContext) {
        cancelSuggestionTask()

        interviewSuggestionState = .live(turnID: context.turnID)
        isSuggestionProcessing = true
        let requestID = suggestionRequestID
        let model = settingsStore.settings.aiModel
        let reasoningLevel = settingsStore.settings.aiReasoningLevel
        let prompt = PromptBuilder.buildInterviewSuggestionPrompt(context: context)
        let debounceNanoseconds = suggestionDebounceNanoseconds

        suggestionTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }

                let response = try await self.codexService.chat(
                    systemPrompt: PromptBuilder.systemPrompt(for: .techInterview),
                    userMessage: prompt,
                    model: model,
                    reasoningLevel: reasoningLevel
                )
                guard !Task.isCancelled else { return }

                self.applyInterviewSuggestion(response, requestID: requestID, context: context)
            } catch {
                self.handleSuggestionError(error, requestID: requestID)
            }
        }
    }

    private func scheduleGenericSuggestion(profile: AssistantProfile, transcript: String) {
        cancelSuggestionTask()

        isSuggestionProcessing = true
        let requestID = suggestionRequestID
        let model = settingsStore.settings.aiModel
        let reasoningLevel = settingsStore.settings.aiReasoningLevel
        let prompt = PromptBuilder.buildSuggestionPrompt(profile: profile, transcript: transcript)
        let debounceNanoseconds = suggestionDebounceNanoseconds

        suggestionTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }

                let response = try await self.codexService.chat(
                    systemPrompt: PromptBuilder.systemPrompt(for: profile),
                    userMessage: prompt,
                    model: model,
                    reasoningLevel: reasoningLevel
                )
                guard !Task.isCancelled else { return }

                self.applyGenericSuggestion(response, requestID: requestID)
            } catch {
                self.handleSuggestionError(error, requestID: requestID)
            }
        }
    }

    private func applyInterviewSuggestion(
        _ response: String,
        requestID: Int,
        context: InterviewTurnContext
    ) {
        guard requestID == suggestionRequestID else { return }

        suggestionTask = nil
        isSuggestionProcessing = false

        guard case .live(context.turnID) = interviewSuggestionState else { return }

        let cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedResponse.isEmpty else { return }

        upsertActiveSuggestion(with: cleanedResponse)
    }

    private func applyGenericSuggestion(_ response: String, requestID: Int) {
        guard requestID == suggestionRequestID else { return }

        suggestionTask = nil
        isSuggestionProcessing = false

        let cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedResponse.isEmpty else { return }

        messages.append(.suggestion(cleanedResponse))
    }

    private func handleSuggestionError(_ error: Error, requestID: Int) {
        guard requestID == suggestionRequestID else { return }
        guard !(error is CancellationError) else { return }

        suggestionTask = nil
        isSuggestionProcessing = false
        errorMessage = error.localizedDescription
    }

    private func upsertActiveSuggestion(with text: String) {
        if let activeSuggestionMessageID,
           let index = messages.firstIndex(where: { $0.id == activeSuggestionMessageID }) {
            messages[index].text = text
            messages[index].isStreaming = false
            return
        }

        let message = ChatMessage.suggestion(text)
        messages.append(message)
        activeSuggestionMessageID = message.id
    }

    private func cancelSuggestionTask() {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestionRequestID += 1
        isSuggestionProcessing = false
    }

    private func resetSuggestionPipeline(clearMessageReference: Bool) {
        cancelSuggestionTask()
        interviewSuggestionState = .idle

        if clearMessageReference {
            activeSuggestionMessageID = nil
        }
    }
}
