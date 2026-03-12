import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppState {
    // Services
    var audioManager = AudioSessionManager()
    var whisperService = WhisperService()
    var transcriptManager = TranscriptManager()
    var codexService: CodexCLIService
    var settingsStore: SettingsStore
    let suggestionEngine: SuggestionEngine

    // UI State
    var isListening = false
    var isChatVisible = false
    var messages: [ChatMessage] = []
    var currentInput = ""
    var isProcessing = false
    var errorMessage: String?
    var askDisplayedText = ""
    var isAskStreaming = false
    var askContentHeight: CGFloat = 0

    var isMicLoading = false

    private var askBuffer = ""
    private var askRevealTask: Task<Void, Never>?
    private var consecutiveMicChunks = 0

    // Session history (cleared on hide)
    private var askSessionHistory: [(question: String, answer: String)] = []

    init() {
        let codex = CodexCLIService()
        let settings = SettingsStore()
        self.codexService = codex
        self.settingsStore = settings
        self.suggestionEngine = SuggestionEngine(codexService: codex, settingsStore: settings)

        let questionObserver = QuestionObserver(settingsStore: settings)
        let stuckObserver = StuckObserver(settingsStore: settings)
        let followUpObserver = FollowUpObserver(settingsStore: settings)
        suggestionEngine.register(questionObserver)
        suggestionEngine.register(stuckObserver)
        suggestionEngine.register(followUpObserver)

        setupAudioCallbacks()
    }

    // MARK: - Actions

    func setup() async {
        await codexService.checkAvailability()
        audioManager.driverManager.checkInstallation()
        await audioManager.checkMicPermission()
    }

    func installAudioDriver() {
        audioManager.driverManager.installDriver()
    }

    func recheckDriver() {
        audioManager.driverManager.checkInstallation()
    }

    func toggleListening() async {
        if isListening {
            stopListening()
        } else {
            await startListening()
        }
    }

    func toggleChat() {
        if isChatVisible {
            // Hiding — clear session
            askSessionHistory.removeAll()
            askDisplayedText = ""
            askBuffer = ""
            askContentHeight = 0
            isAskStreaming = false
            askRevealTask?.cancel()
            suggestionEngine.reset()
        }
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

    func sendAskMessage() async {
        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }

        currentInput = ""
        askRevealTask?.cancel()
        askBuffer = ""
        askDisplayedText = ""
        askContentHeight = 0
        isAskStreaming = true
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        startAskRevealLoop()

        let transcript = transcriptManager.formattedTranscript
        let prompt = PromptBuilder.buildAskPrompt(transcript: transcript, question: text, history: askSessionHistory)

        do {
            let response = try await codexService.chatStream(
                systemPrompt: PromptBuilder.askSystemPrompt(),
                userMessage: prompt,
                model: settingsStore.settings.aiModel,
                reasoningLevel: settingsStore.settings.aiReasoningLevel,
                onChunk: { [weak self] (chunk: String) in
                    Task { @MainActor in
                        self?.askBuffer += chunk
                    }
                }
            )

            // Use response as source-of-truth (eliminates onChunk race condition)
            askBuffer = response
            askSessionHistory.append((question: text, answer: response))
        } catch {
            askBuffer = "Erro: \(error.localizedDescription)"
            errorMessage = error.localizedDescription
        }
    }

    private func startAskRevealLoop() {
        askRevealTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                if self.askDisplayedText.count < self.askBuffer.count {
                    // Reveal next chunk of characters
                    let remaining = self.askBuffer.count - self.askDisplayedText.count
                    let charsToReveal = min(max(remaining / 4, 1), 3)
                    let endIndex = self.askBuffer.index(
                        self.askBuffer.startIndex,
                        offsetBy: self.askDisplayedText.count + charsToReveal
                    )
                    self.askDisplayedText = String(self.askBuffer[..<endIndex])
                    try? await Task.sleep(nanoseconds: 15_000_000) // ~15ms per tick
                } else if !self.isProcessing && self.askDisplayedText.count >= self.askBuffer.count {
                    // Done streaming and all text revealed
                    self.askDisplayedText = self.askBuffer
                    self.isAskStreaming = false
                    return
                } else {
                    // Waiting for more chunks
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
            }
        }
    }

    func useSuggestion(_ text: String) async {
        currentInput = text
        await sendMessage()
    }

    // MARK: - Private

    private func startListening() async {
        guard audioManager.driverManager.status == .installed else {
            errorMessage = "Driver de audio nao instalado. Instale nas configuracoes."
            return
        }

        isMicLoading = true

        do {
            if !whisperService.isModelLoaded {
                await whisperService.loadModel(name: settingsStore.settings.whisperModel)
            }

            suggestionEngine.reset()
            audioManager.configure(chunkDuration: settingsStore.settings.chunkDuration)
            try audioManager.startListening(deviceID: settingsStore.settings.inputDeviceID)
            isListening = true
            isChatVisible = true

            // Diagnóstico: verificar se system audio está a funcionar
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, self.isListening else { return }
                if self.transcriptManager.entries.filter({ $0.speaker == .interviewer }).isEmpty {
                    print("[Ark] WARNING: 10s sem audio do sistema. Verificar BlackHole.")
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isMicLoading = false
    }

    private func stopListening() {
        audioManager.stopListening()
        suggestionEngine.reset()
        consecutiveMicChunks = 0
        isListening = false

        // Fechar o chat panel ao sair do voice mode
        isChatVisible = false
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
            consecutiveMicChunks += 1
            // Only clear after sustained speech (2+ chunks), not a brief word
            // But don't clear if user is reading the suggestion aloud (echo)
            if consecutiveMicChunks >= 2,
               !suggestionEngine.isEchoingSuggestion(text),
               !suggestionEngine.isUserCommandActive {
                suggestionEngine.clearDisplay()
            }
            let entry = transcriptManager.addEntry(speaker: .me, text: text)
            suggestionEngine.feedEntry(entry, allEntries: transcriptManager.entries)
        } else {
            consecutiveMicChunks = 0
            suggestionEngine.feedSilence(allEntries: transcriptManager.entries)
        }
    }

    private func processSystemChunk(_ samples: [Float]) async {
        #if DEBUG
        print("[Ark] processSystemChunk called (\(samples.count) samples)")
        #endif
        guard let text = await whisperService.transcribe(audioSamples: samples) else {
            #if DEBUG
            print("[Ark] processSystemChunk: transcription returned nil")
            #endif
            return
        }
        #if DEBUG
        print("[Ark] System transcript: \(text.prefix(80))")
        #endif
        let entry = transcriptManager.addEntry(speaker: .interviewer, text: text)
        suggestionEngine.feedEntry(entry, allEntries: transcriptManager.entries)
    }
}
