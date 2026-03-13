import AVFoundation
import Foundation
import Observation
import SwiftUI

enum PanelMode: Equatable {
    case hidden
    case ask
    case voiceSuggestions
}

struct TranscriptCaptureState: Equatable, Sendable {
    var isCapturing = false
    var lastAudioActivityAt: Date?
    var lastRecognizedText = ""
    var lastRecognizedAt: Date?
    var queueDepth = 0
    var coalescedChunkCount = 0
    var discardedWindowCount = 0
    var lastError: String?
    var audioLevel: Float = 0

    func status(now: Date = Date()) -> String {
        guard isCapturing else { return "Stopped" }

        let hasRecentRecognition = lastRecognizedAt.map {
            now.timeIntervalSince($0) <= Constants.Suggestion.ACTIVE_AUDIO_WINDOW_SECONDS
        } ?? false
        if hasRecentRecognition {
            return "Recognized speech"
        }

        let hasRecentAudio = lastAudioActivityAt.map {
            now.timeIntervalSince($0) <= Constants.Suggestion.ACTIVE_AUDIO_WINDOW_SECONDS
        } ?? false
        if hasRecentAudio {
            return "Receiving audio"
        }

        if lastRecognizedAt == nil {
            return "No speech recognized"
        }

        return "Capturing"
    }

    var previewText: String {
        if !lastRecognizedText.isEmpty {
            return lastRecognizedText
        }

        if lastAudioActivityAt != nil {
            return "Audio detected, but no speech recognized yet."
        }

        return "No speech recognized yet."
    }

    var audioLevelDB: Float {
        guard audioLevel > 0 else { return -Float.infinity }
        return 20 * log10f(audioLevel)
    }

    var diagnosticsText: String {
        var parts = [
            "Queue \(queueDepth)",
            "Merged \(coalescedChunkCount)",
            "Discarded \(discardedWindowCount)"
        ]

        if audioLevel > 0 {
            parts.append(String(format: "%.0f dB", audioLevelDB))
        }

        if let lastError, !lastError.isEmpty {
            parts.append(lastError)
        }

        return parts.joined(separator: " · ")
    }
}

struct AudioRoutingValidationSnapshot: Equatable, Sendable {
    let callbackCount: Int
    let maxNativeRMS: Float
    let maxConvertedRMS: Float

    func outcome(threshold: Float) -> AudioRoutingValidationOutcome {
        guard callbackCount > 0 else { return .noCallbacks }
        guard maxNativeRMS >= threshold else { return .nativeSignalMissing }
        guard maxConvertedRMS >= threshold else { return .conversionSignalMissing }
        return .passed
    }
}

enum AudioRoutingValidationOutcome: Equatable, Sendable {
    case noCallbacks
    case nativeSignalMissing
    case conversionSignalMissing
    case passed
}

final class AudioRoutingValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var maxNativeRMS: Float = 0
    private var maxConvertedRMS: Float = 0
    private var callbackCount = 0

    func record(diagnostics: SystemAudioCaptureService.BufferDiagnostics) {
        lock.withLock {
            maxNativeRMS = max(maxNativeRMS, diagnostics.nativeRMS)
            maxConvertedRMS = max(maxConvertedRMS, diagnostics.convertedRMS)
            callbackCount += 1
        }
    }

    func snapshot() -> AudioRoutingValidationSnapshot {
        lock.withLock {
            AudioRoutingValidationSnapshot(
                callbackCount: callbackCount,
                maxNativeRMS: maxNativeRMS,
                maxConvertedRMS: maxConvertedRMS
            )
        }
    }
}

@MainActor @Observable
final class AppState {
    // Services
    var audioManager = AudioSessionManager()
    var whisperService: WhisperService
    var openAIWhisperService = OpenAIWhisperService()
    var transcriptManager = TranscriptManager()
    var codexService: CodexCLIService
    var settingsStore: SettingsStore
    let suggestionEngine: SuggestionEngine

    private var transcriptionCoordinator: TranscriptionCoordinator

    // UI State
    var isListening = false
    var panelMode: PanelMode = .hidden
    var isTranscriptOverlayVisible = false
    var messages: [ChatMessage] = []
    var currentInput = ""
    var isProcessing = false
    var errorMessage: String?
    var askDisplayedText = ""
    var isAskStreaming = false
    var askContentHeight: CGFloat = 0
    var askPanelMeasuredHeight: CGFloat = 0
    var voicePanelMeasuredHeight: CGFloat = 0
    var transcriptPanelMeasuredHeight: CGFloat = 0
    var isMicLoading = false
    var isAudioRoutingValidationRunning = false
    var audioRoutingValidationMessage: String?
    var didAudioRoutingValidationSucceed: Bool?

    // Transcript diagnostics
    var micCaptureState = TranscriptCaptureState()
    var systemCaptureState = TranscriptCaptureState()

    private var askBuffer = ""
    private var askRevealTask: Task<Void, Never>?
    private var askSessionHistory: [(question: String, answer: String)] = []
    private var transcriptionResultsTask: Task<Void, Never>?
    private var listeningSessionID = UUID()
    private var silenceFlushTasks: [TranscriptionSource: Task<Void, Never>] = [:]
    private var liveTranscriptEntryIDs: [TranscriptEntry.Speaker: UUID] = [:]

    init() {
        let codex = CodexCLIService()
        let settings = SettingsStore()
        let whisper = WhisperService()
        let openAI = OpenAIWhisperService()
        self.codexService = codex
        self.settingsStore = settings
        self.whisperService = whisper
        self.openAIWhisperService = openAI
        self.suggestionEngine = SuggestionEngine(codexService: codex, settingsStore: settings)
        self.transcriptionCoordinator = TranscriptionCoordinator(perform: Self.makeTranscriptionPerform(
            provider: settings.settings.transcriptionProvider,
            whisper: whisper,
            openAI: openAI,
            cloudModel: settings.settings.cloudTranscriptionModel,
            apiKey: settings.settings.openAIAPIKey
        ))

        suggestionEngine.register(QuestionObserver())
        suggestionEngine.register(StuckObserver())
        suggestionEngine.register(FollowUpObserver())

        setupAudioCallbacks()
        setupTranscriptionResultsLoop()
        syncSuggestionPresentation()
    }

    // MARK: - Derived UI state

    var isChatVisible: Bool {
        panelMode != .hidden || isTranscriptOverlayVisible
    }

    var isAskPanelVisible: Bool {
        panelMode == .ask
    }

    var isVoiceSuggestionsPanelVisible: Bool {
        panelMode == .voiceSuggestions
    }

    // MARK: - Actions

    func setup() async {
        await codexService.checkAvailability()
        audioManager.driverManager.checkInstallation()
        await audioManager.checkMicPermission()
    }

    func installAudioDriver() {
        audioRoutingValidationMessage = nil
        didAudioRoutingValidationSucceed = nil
        audioManager.driverManager.installDriver()
    }

    func recheckDriver() {
        audioManager.driverManager.checkInstallation()
    }

    func validateAudioRouting() async {
        errorMessage = nil

        guard !isListening else {
            didAudioRoutingValidationSucceed = false
            audioRoutingValidationMessage = "Pare a escuta atual antes de validar o ArkAudio."
            return
        }

        audioManager.driverManager.checkInstallation()

        if let preflightError = audioManager.driverManager.validationPreflightError() {
            didAudioRoutingValidationSucceed = false
            audioRoutingValidationMessage = preflightError
            return
        }

        guard let driverDeviceID = audioManager.driverManager.findDriverDeviceID(),
              let driverUID = audioManager.driverManager.detectedDriver?.uid,
              let outputUID = audioManager.driverManager.currentDefaultOutputUID() else {
            didAudioRoutingValidationSucceed = false
            audioRoutingValidationMessage = "Não foi possível localizar o ArkAudio ou a saída padrão atual."
            audioManager.driverManager.checkInstallation()
            return
        }

        isAudioRoutingValidationRunning = true
        didAudioRoutingValidationSucceed = nil
        audioRoutingValidationMessage = "Toque qualquer áudio do sistema agora. O Ark vai ouvir o ArkAudio por 5 segundos."

        let validationProbe = AudioRoutingValidationProbe()
        let validationService = SystemAudioCaptureService()
        validationService.onBufferDiagnostics = { diagnostics in
            validationProbe.record(diagnostics: diagnostics)
        }

        defer {
            validationService.stop()
            isAudioRoutingValidationRunning = false
        }

        do {
            try validationService.start(driverDeviceID: driverDeviceID)
            try await Task.sleep(
                nanoseconds: UInt64(Constants.AudioDriver.ROUTING_VALIDATION_DURATION_SECONDS * 1_000_000_000)
            )

            let snapshot = validationProbe.snapshot()
            switch snapshot.outcome(threshold: Constants.AudioDriver.ROUTING_VALIDATION_RMS_THRESHOLD) {
            case .noCallbacks:
                didAudioRoutingValidationSucceed = false
                audioRoutingValidationMessage = "Nenhum buffer chegou do ArkAudio. Verifique o Multi-Output Device."
                audioManager.driverManager.checkInstallation()
                return

            case .nativeSignalMissing:
                didAudioRoutingValidationSucceed = false
                audioRoutingValidationMessage = """
                O ArkAudio abriu, mas o sinal já chegou silencioso do Multi-Output \
                (callbacks \(snapshot.callbackCount), RMS nativo \(formattedRMS(snapshot.maxNativeRMS)), RMS convertido \(formattedRMS(snapshot.maxConvertedRMS))). \
                Verifique a ordem da lista, deixe sua saída física no topo e toque áudio contínuo.
                """
                audioManager.driverManager.checkInstallation()
                return

            case .conversionSignalMissing:
                didAudioRoutingValidationSucceed = false
                audioRoutingValidationMessage = """
                O ArkAudio recebeu sinal antes da conversão, mas ele sumiu ao converter para 16 kHz mono \
                (callbacks \(snapshot.callbackCount), RMS nativo \(formattedRMS(snapshot.maxNativeRMS)), RMS convertido \(formattedRMS(snapshot.maxConvertedRMS))). \
                Isso aponta para o pipeline de captura do app.
                """
                audioManager.driverManager.checkInstallation()
                return

            case .passed:
                break
            }

            audioManager.driverManager.markRoutingValidated(outputUID: outputUID, driverUID: driverUID)
            didAudioRoutingValidationSucceed = true
            audioRoutingValidationMessage = """
            Validação concluída. O ArkAudio recebeu áudio do sistema nesta saída \
            (callbacks \(snapshot.callbackCount), RMS nativo \(formattedRMS(snapshot.maxNativeRMS)), RMS convertido \(formattedRMS(snapshot.maxConvertedRMS))).
            """
        } catch {
            didAudioRoutingValidationSucceed = false
            audioRoutingValidationMessage = "Falha ao abrir o ArkAudio para validação: \(error.localizedDescription)"
            audioManager.driverManager.checkInstallation()
        }
    }

    func toggleListening() async {
        if isListening {
            await stopListening()
        } else {
            await startListening()
        }
    }

    func toggleAskPanel() {
        transitionPanel(to: panelMode == .ask ? .hidden : .ask)
    }

    func toggleVoiceSuggestionsPanel() {
        transitionPanel(to: panelMode == .voiceSuggestions ? .hidden : .voiceSuggestions)
    }

    func toggleTranscriptOverlay() {
        guard isListening else {
            isTranscriptOverlayVisible = false
            return
        }

        isTranscriptOverlayVisible.toggle()
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
                onChunk: { [weak self] chunk in
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
                messages[index].text = "Error: \(error.localizedDescription)"
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
        let prompt = PromptBuilder.buildAskPrompt(
            transcript: transcript,
            question: text,
            history: askSessionHistory
        )

        do {
            let response = try await codexService.chatStream(
                systemPrompt: PromptBuilder.askSystemPrompt(),
                userMessage: prompt,
                model: settingsStore.settings.aiModel,
                reasoningLevel: settingsStore.settings.aiReasoningLevel,
                onChunk: { [weak self] chunk in
                    Task { @MainActor in
                        self?.askBuffer += chunk
                    }
                }
            )

            askBuffer = response
            askSessionHistory.append((question: text, answer: response))
        } catch {
            askBuffer = "Error: \(error.localizedDescription)"
            errorMessage = error.localizedDescription
        }
    }

    func useSuggestion(_ text: String) async {
        currentInput = text
        await sendMessage()
    }

    func captureState(for speaker: TranscriptEntry.Speaker) -> TranscriptCaptureState {
        speaker == .me ? micCaptureState : systemCaptureState
    }

    func captureStatusText(for speaker: TranscriptEntry.Speaker) -> String {
        captureState(for: speaker).status()
    }

    func lastTranscriptPreview(for speaker: TranscriptEntry.Speaker) -> String {
        captureState(for: speaker).previewText
    }

    func captureDiagnosticsText(for speaker: TranscriptEntry.Speaker) -> String {
        captureState(for: speaker).diagnosticsText
    }

    // MARK: - Private

    private func transitionPanel(to newMode: PanelMode) {
        if panelMode == .ask, newMode != .ask {
            resetAskPanelState()
        }

        panelMode = newMode
        syncSuggestionPresentation()
    }

    private func formattedRMS(_ value: Float) -> String {
        String(format: "%.6f", value)
    }

    private func syncSuggestionPresentation() {
        let shouldEnable = isListening && panelMode == .voiceSuggestions
        suggestionEngine.setAutomaticSuggestionsEnabled(shouldEnable)
    }

    private static func makeTranscriptionPerform(
        provider: TranscriptionProvider,
        whisper: WhisperService,
        openAI: OpenAIWhisperService,
        cloudModel: String = Constants.Transcription.OPENAI_WHISPER_MODEL,
        apiKey: String = ""
    ) -> @Sendable (TranscriptionJob) async -> String? {
        switch provider {
        case .local:
            return { job in await whisper.transcribe(audioSamples: job.samples) }
        case .cloud:
            let capturedKey = apiKey
            return { job in await openAI.transcribe(audioSamples: job.samples, model: cloudModel, apiKey: capturedKey) }
        }
    }

    private func rebuildTranscriptionCoordinator() {
        transcriptionResultsTask?.cancel()
        transcriptionCoordinator = TranscriptionCoordinator(perform: Self.makeTranscriptionPerform(
            provider: settingsStore.settings.transcriptionProvider,
            whisper: whisperService,
            openAI: openAIWhisperService,
            cloudModel: settingsStore.settings.cloudTranscriptionModel,
            apiKey: settingsStore.settings.openAIAPIKey
        ))
        setupTranscriptionResultsLoop()
    }

    private func startListening() async {
        audioManager.driverManager.checkInstallation()

        guard audioManager.driverManager.status == .installed else {
            errorMessage = audioManager.driverManager.startListeningErrorMessage()
            return
        }

        isMicLoading = true

        let provider = settingsStore.settings.transcriptionProvider

        do {
            switch provider {
            case .local:
                if !whisperService.isModelLoaded {
                    await whisperService.loadModel(name: settingsStore.settings.whisperModel)
                    guard whisperService.isModelLoaded else {
                        errorMessage = whisperService.error ?? "Failed to load the Whisper model."
                        isMicLoading = false
                        return
                    }
                }
            case .cloud:
                openAIWhisperService.prepare(apiKey: settingsStore.settings.openAIAPIKey)
                guard openAIWhisperService.isReady else {
                    errorMessage = openAIWhisperService.error ?? "OpenAI API key não configurada."
                    isMicLoading = false
                    return
                }
            }

            rebuildTranscriptionCoordinator()
            listeningSessionID = UUID()
            await transcriptionCoordinator.reset()
            await transcriptionCoordinator.configure(
                windowDuration: settingsStore.settings.chunkDuration,
                strideDuration: Constants.Suggestion.ANALYSIS_CHUNK_DURATION
            )
            transcriptManager.clear()
            resetTranscriptDiagnostics()
            suggestionEngine.reset()
            cancelSilenceFlushTasks()
            liveTranscriptEntryIDs.removeAll()
            voicePanelMeasuredHeight = 0
            transcriptPanelMeasuredHeight = 0
            audioManager.configure(chunkDuration: Constants.Suggestion.ANALYSIS_CHUNK_DURATION)
            try audioManager.startListening(deviceID: settingsStore.settings.inputDeviceID)
            isListening = true
            micCaptureState.isCapturing = true
            systemCaptureState.isCapturing = true
            isTranscriptOverlayVisible = false
            transitionPanel(to: .voiceSuggestions)

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.isListening else { return }
                let hasSystemActivity = self.systemCaptureState.lastAudioActivityAt != nil
                let systemRMS = self.audioManager.storage.withLock { $0.systemRMSLevel }
                if !hasSystemActivity {
                    print("[Ark] WARNING: Sem atividade de áudio do sistema. Verifique o driver de áudio.")
                } else if systemRMS < 0.001 {
                    print("[Ark] WARNING: Áudio do sistema detectado mas silencioso. Verifique o volume.")
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isMicLoading = false
    }

    private func stopListening() async {
        let stopTimestamp = Date()
        await flushPendingTranscription(
            source: .mic,
            sessionID: listeningSessionID,
            at: stopTimestamp,
            reason: .sessionEnd
        )
        await flushPendingTranscription(
            source: .system,
            sessionID: listeningSessionID,
            at: stopTimestamp,
            reason: .sessionEnd
        )

        listeningSessionID = UUID()
        cancelSilenceFlushTasks()
        audioManager.stopListening()
        await transcriptionCoordinator.reset()
        suggestionEngine.reset()
        transcriptManager.clear()
        resetTranscriptDiagnostics()
        liveTranscriptEntryIDs.removeAll()
        voicePanelMeasuredHeight = 0
        transcriptPanelMeasuredHeight = 0
        isListening = false
        isTranscriptOverlayVisible = false
        transitionPanel(to: .hidden)
    }

    private func resetTranscriptDiagnostics() {
        micCaptureState = TranscriptCaptureState()
        systemCaptureState = TranscriptCaptureState()
    }

    private func resetAskPanelState() {
        askSessionHistory.removeAll()
        askDisplayedText = ""
        askBuffer = ""
        askContentHeight = 0
        askPanelMeasuredHeight = 0
        isAskStreaming = false
        askRevealTask?.cancel()
    }

    private func startAskRevealLoop() {
        askRevealTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                if self.askDisplayedText.count < self.askBuffer.count {
                    let remaining = self.askBuffer.count - self.askDisplayedText.count
                    let charsToReveal = min(max(remaining / 4, 1), 3)
                    let endIndex = self.askBuffer.index(
                        self.askBuffer.startIndex,
                        offsetBy: self.askDisplayedText.count + charsToReveal
                    )
                    self.askDisplayedText = String(self.askBuffer[..<endIndex])
                    try? await Task.sleep(nanoseconds: 15_000_000)
                } else if !self.isProcessing && self.askDisplayedText.count >= self.askBuffer.count {
                    self.askDisplayedText = self.askBuffer
                    self.isAskStreaming = false
                    return
                } else {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
            }
        }
    }

    private func setupAudioCallbacks() {
        audioManager.storage.onMicChunk = { [weak self] samples in
            let timestamp = Date()
            Task { @MainActor [weak self] in
                self?.submitTranscription(samples, source: .mic, timestamp: timestamp)
            }
        }

        audioManager.storage.onSystemChunk = { [weak self] samples in
            let timestamp = Date()
            Task { @MainActor [weak self] in
                self?.submitTranscription(samples, source: .system, timestamp: timestamp)
            }
        }
    }

    private func setupTranscriptionResultsLoop() {
        transcriptionResultsTask = Task { [weak self] in
            guard let self else { return }

            for await output in self.transcriptionCoordinator.results {
                guard !Task.isCancelled else { return }
                self.handleTranscriptionOutput(output)
            }
        }
    }

    private func submitTranscription(
        _ samples: [Float],
        source: TranscriptionSource,
        timestamp: Date
    ) {
        guard isListening else { return }

        recordAudioActivity(source: source, timestamp: timestamp)
        flushStaleOppositeSource(ifNeededFor: source, timestamp: timestamp)
        scheduleSilenceFlush(for: source, lastAudioAt: timestamp)

        let chunk = TranscriptionChunk(
            source: source,
            samples: samples,
            timestamp: timestamp,
            sessionID: listeningSessionID
        )

        Task {
            await transcriptionCoordinator.submit(chunk)
            let diagnostics = await transcriptionCoordinator.diagnostics(for: source)
            await MainActor.run {
                self.applyDiagnostics(diagnostics, for: source)
            }
        }
    }

    private func handleTranscriptionOutput(_ output: TranscriptionOutput) {
        guard output.sessionID == listeningSessionID else { return }
        applyDiagnostics(output.diagnostics, for: output.source)

        if let text = output.text {
            ingestTranscribedText(
                text,
                speaker: output.source.speaker,
                timestamp: output.timestamp
            )
            if output.flushReason.finalizesTurn {
                liveTranscriptEntryIDs[output.source.speaker] = nil
                suggestionEngine.ingestSpeechFragment(
                    speaker: output.source.speaker,
                    text: nil,
                    timestamp: output.timestamp
                )
            }
        } else if output.flushReason.finalizesTurn {
            liveTranscriptEntryIDs[output.source.speaker] = nil
            suggestionEngine.ingestSpeechFragment(
                speaker: output.source.speaker,
                text: nil,
                timestamp: output.timestamp
            )
        }

        let transcriptionError: String? = switch settingsStore.settings.transcriptionProvider {
        case .local: whisperService.error
        case .cloud: openAIWhisperService.error
        }
        if let transcriptionError, !transcriptionError.isEmpty {
            var state = captureState(for: output.source.speaker)
            state.lastError = transcriptionError
            setCaptureState(state, for: output.source.speaker)
        }
    }

    private func recordAudioActivity(source: TranscriptionSource, timestamp: Date) {
        var state = captureState(for: source.speaker)
        state.isCapturing = true
        state.lastAudioActivityAt = timestamp
        state.lastError = nil
        let rms = audioManager.storage.withLock { s in
            source == .mic ? s.micRMSLevel : s.systemRMSLevel
        }
        state.audioLevel = rms
        setCaptureState(state, for: source.speaker)
    }

    private func applyDiagnostics(
        _ diagnostics: TranscriptionDiagnostics,
        for source: TranscriptionSource
    ) {
        var state = captureState(for: source.speaker)
        state.queueDepth = diagnostics.queueDepth
        state.coalescedChunkCount = diagnostics.coalescedChunkCount
        state.discardedWindowCount = diagnostics.discardedWindowCount
        let serviceError: String? = switch settingsStore.settings.transcriptionProvider {
        case .local: whisperService.error
        case .cloud: openAIWhisperService.error
        }
        state.lastError = diagnostics.lastError ?? serviceError
        setCaptureState(state, for: source.speaker)
    }

    private func setCaptureState(
        _ state: TranscriptCaptureState,
        for speaker: TranscriptEntry.Speaker
    ) {
        if speaker == .me {
            micCaptureState = state
        } else {
            systemCaptureState = state
        }
    }

    func ingestTranscribedText(
        _ text: String,
        speaker: TranscriptEntry.Speaker,
        timestamp: Date = Date()
    ) {
        var state = captureState(for: speaker)
        state.isCapturing = true
        state.lastAudioActivityAt = timestamp
        state.lastRecognizedText = text
        state.lastRecognizedAt = timestamp
        state.lastError = nil
        setCaptureState(state, for: speaker)

        let entry = transcriptManager.upsertLiveEntry(
            id: liveTranscriptEntryIDs[speaker],
            speaker: speaker,
            text: text,
            timestamp: timestamp
        )
        liveTranscriptEntryIDs[speaker] = entry.id
        suggestionEngine.ingestSpeechFragment(
            speaker: speaker,
            text: entry.text,
            timestamp: entry.timestamp
        )
    }

    private func flushStaleOppositeSource(ifNeededFor source: TranscriptionSource, timestamp: Date) {
        let oppositeSource: TranscriptionSource = source == .mic ? .system : .mic
        let oppositeSpeaker = oppositeSource.speaker
        let sessionID = listeningSessionID
        guard let oppositeLastAudio = captureState(for: oppositeSpeaker).lastAudioActivityAt else { return }
        guard timestamp.timeIntervalSince(oppositeLastAudio) >= Constants.Suggestion.TURN_PAUSE_SECONDS else {
            return
        }

        Task {
            guard await transcriptionCoordinator.hasBufferedAudio(for: oppositeSource) else { return }
            await flushPendingTranscription(
                source: oppositeSource,
                sessionID: sessionID,
                at: timestamp,
                reason: .speakerSwitch
            )
        }
    }

    private func scheduleSilenceFlush(for source: TranscriptionSource, lastAudioAt: Date) {
        silenceFlushTasks[source]?.cancel()
        let dueDate = lastAudioAt.addingTimeInterval(Constants.Suggestion.TURN_PAUSE_SECONDS)
        let sessionID = listeningSessionID

        silenceFlushTasks[source] = Task { [weak self] in
            let delay = max(0, dueDate.timeIntervalSinceNow + Constants.Suggestion.SIGNAL_REEVALUATION_GRACE_SECONDS)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            let shouldFlush = await MainActor.run { () -> Bool in
                guard self.isListening else { return false }
                guard self.listeningSessionID == sessionID else { return false }
                return self.captureState(for: source.speaker).lastAudioActivityAt == lastAudioAt
            }
            guard shouldFlush else { return }

            await self.flushPendingTranscription(
                source: source,
                sessionID: sessionID,
                at: dueDate,
                reason: .silence
            )
        }
    }

    private func flushPendingTranscription(
        source: TranscriptionSource,
        sessionID: UUID,
        at timestamp: Date,
        reason: TranscriptionFlushReason
    ) async {
        await transcriptionCoordinator.flush(
            source: source,
            sessionID: sessionID,
            timestamp: timestamp,
            reason: reason
        )
        let diagnostics = await transcriptionCoordinator.diagnostics(for: source)
        applyDiagnostics(diagnostics, for: source)
    }

    private func cancelSilenceFlushTasks() {
        for task in silenceFlushTasks.values {
            task.cancel()
        }
        silenceFlushTasks.removeAll()
    }
}
