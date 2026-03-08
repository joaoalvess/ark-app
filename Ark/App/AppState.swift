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
    var errorMessage: String?

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
        let prompt = PromptBuilder.buildChatPrompt(transcript: transcript, question: text)
        let lastIndex = messages.count - 1

        do {
            let response = try await codexService.chatStream(
                systemPrompt: PromptBuilder.systemPrompt,
                userMessage: prompt,
                model: settingsStore.settings.aiModel,
                reasoningLevel: settingsStore.settings.aiReasoningLevel
            ) { [weak self] chunk in
                Task { @MainActor in
                    guard let self, lastIndex < self.messages.count else { return }
                    self.messages[lastIndex].text += chunk
                }
            }

            if lastIndex < messages.count {
                messages[lastIndex].text = response
                messages[lastIndex].isStreaming = false
            }
        } catch {
            if lastIndex < messages.count {
                messages[lastIndex].text = "Erro: \(error.localizedDescription)"
                messages[lastIndex].isStreaming = false
            }
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    func requestSuggestion() async {
        guard !isProcessing else { return }
        let transcript = transcriptManager.recentTranscript
        guard !transcript.isEmpty else { return }

        isProcessing = true
        let prompt = PromptBuilder.buildSuggestionPrompt(transcript: transcript)

        do {
            let response = try await codexService.chat(
                systemPrompt: PromptBuilder.systemPrompt,
                userMessage: prompt,
                model: settingsStore.settings.aiModel,
                reasoningLevel: settingsStore.settings.aiReasoningLevel
            )
            messages.append(.suggestion(response))
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
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

            try await audioManager.startListening(deviceID: settingsStore.settings.inputDeviceID)
            isListening = true
            isChatVisible = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopListening() async {
        await audioManager.stopListening()
        isListening = false
    }

    private func setupAudioCallbacks() {
        audioManager.onMicChunk = { [weak self] samples in
            guard let self else { return }
            Task {
                if let text = await self.whisperService.transcribe(audioSamples: samples) {
                    await MainActor.run {
                        self.transcriptManager.addEntry(speaker: .me, text: text)
                    }
                }
            }
        }

        audioManager.onSystemChunk = { [weak self] samples in
            guard let self else { return }
            Task {
                if let text = await self.whisperService.transcribe(audioSamples: samples) {
                    await MainActor.run {
                        self.transcriptManager.addEntry(speaker: .interviewer, text: text)
                        // Auto-suggest when interviewer speaks
                        if self.settingsStore.settings.autoSuggest {
                            Task { await self.requestSuggestion() }
                        }
                    }
                }
            }
        }
    }
}
