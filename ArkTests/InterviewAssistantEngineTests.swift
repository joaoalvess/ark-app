import XCTest
import CoreAudio
@testable import Ark

@MainActor
final class InterviewAssistantEngineTests: XCTestCase {
    func testIsLikelyQuestionDetectsQuestionMark() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyQuestion("Como funciona o React?"))
    }

    func testIsLikelyQuestionDetectsQuestionPrefix() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyQuestion("Como você lida com estado global"))
        XCTAssertTrue(InterviewAssistantEngine.isLikelyQuestion("What is your experience with Swift"))
    }

    func testIsLikelyQuestionReturnsFalseForStatements() {
        XCTAssertFalse(InterviewAssistantEngine.isLikelyQuestion("Ok"))
        XCTAssertFalse(InterviewAssistantEngine.isLikelyQuestion("Muito bem"))
    }

    func testShouldTriggerSuggestionForQuestion() {
        XCTAssertTrue(InterviewAssistantEngine.shouldTriggerSuggestion(for: "Como funciona o React?"))
    }

    func testShouldTriggerSuggestionForLongStatement() {
        XCTAssertTrue(InterviewAssistantEngine.shouldTriggerSuggestion(for: "Vamos falar agora sobre a sua experiência"))
    }

    func testShouldNotTriggerSuggestionForShortStatement() {
        XCTAssertFalse(InterviewAssistantEngine.shouldTriggerSuggestion(for: "Ok"))
    }

    func testIsLikelyIncompleteResponseDetectsEllipsis() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é importante porque..."))
    }

    func testIsLikelyIncompleteResponseDetectsFillers() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é importante para o ecossistema JavaScript porque an"))
    }

    func testIsLikelyIncompleteResponseDetectsDanglingConnectors() {
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é importante para"))
        XCTAssertTrue(InterviewAssistantEngine.isLikelyIncompleteResponse("Eu uso hooks porque"))
    }

    func testIsLikelyIncompleteResponseReturnsFalseForComplete() {
        XCTAssertFalse(InterviewAssistantEngine.isLikelyIncompleteResponse("O React é muito importante no ecossistema."))
    }

    func testQuestionObserverEmitsSignalForInterviewerQuestion() {
        let observer = QuestionObserver()
        let turn = makeTurn(.interviewer, "Como você lida com concorrência no Swift?")
        var signals: [SuggestionSignal] = []

        observer.onSignal = { signals.append($0) }
        observer.processTurn(turn, recentTurns: [turn])

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.kind, .question)
        XCTAssertEqual(signals.first?.focusText, turn.text)
    }

    func testStuckObserverEmitsSignalAfterRepeatedIncompleteTurns() {
        let observer = StuckObserver()
        let first = makeTurn(.me, "Eu costumo começar olhando para")
        let second = makeTurn(.me, "E depois eu tento alinhar com")
        var signals: [SuggestionSignal] = []

        observer.onSignal = { signals.append($0) }
        observer.processTurn(first, recentTurns: [first])
        observer.processTurn(second, recentTurns: [first, second])

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.kind, .stuck)
        XCTAssertEqual(signals.first?.source, "stuckObserver:hesitation")
    }

    func testStuckObserverEmitsSignalAfterPauseOnIncompleteTurn() {
        let observer = StuckObserver()
        let base = Date()
        let turn = makeTurn(.me, "Na prática eu começaria por", startedAt: base, updatedAt: base)
        let activity = SpeechActivityEvent(
            speaker: .me,
            didProduceText: false,
            timestamp: base.addingTimeInterval(Constants.Suggestion.TURN_PAUSE_SECONDS + 0.1)
        )
        var signals: [SuggestionSignal] = []

        observer.onSignal = { signals.append($0) }
        observer.processTurn(turn, recentTurns: [turn])
        observer.processSpeechActivity(activity, recentTurns: [turn])

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.source, "stuckObserver:pause")
    }

    func testFollowUpObserverOnlyFiresInLull() {
        let observer = FollowUpObserver()
        let first = makeTurn(.interviewer, "Falamos bastante sobre arquitetura distribuída.")
        let second = makeTurn(.me, "Eu lidei com isso liderando uma migração de monólito.")
        let activity = SpeechActivityEvent(
            speaker: .me,
            didProduceText: false,
            timestamp: second.updatedAt.addingTimeInterval(Constants.Suggestion.FOLLOW_UP_LULL_SECONDS + 0.1)
        )
        var signals: [SuggestionSignal] = []

        observer.onSignal = { signals.append($0) }
        observer.processSpeechActivity(activity, recentTurns: [first, second])

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.kind, .followUp)
    }

    func testManualCommandReleasesPendingQuestionAfterHold() async throws {
        let client = MockCodexClient(responses: ["Resposta manual curta", "Resposta automática curta"])
        let settings = makeSettingsStore()
        let engine = SuggestionEngine(
            codexService: client,
            settingsStore: settings,
            timings: SuggestionTimings(
                holdMinimumSeconds: 0.05,
                readingThresholdSeconds: 0.05,
                readingCharsPerSecond: 500,
                turnPauseSeconds: 0.01,
                reevaluationGraceSeconds: 0.01
            )
        )
        engine.register(QuestionObserver())
        engine.setAutomaticSuggestionsEnabled(true)

        let base = Date()
        let entries = [makeEntry(.interviewer, "Fale sobre sua experiência com Swift.", timestamp: base)]
        engine.handleUserCommand(action: .answer, entries: entries)

        try await waitUntil(timeout: 1) {
            !engine.isStreaming && engine.displayedText.contains("Resposta manual")
        }

        engine.ingestSpeechFragment(
            speaker: .interviewer,
            text: "Como você lida com concorrência no Swift?",
            timestamp: base.addingTimeInterval(0.02)
        )
        engine.ingestSpeechFragment(
            speaker: .interviewer,
            text: nil,
            timestamp: base.addingTimeInterval(0.05)
        )

        XCTAssertTrue(engine.displayedText.contains("Resposta manual"))

        try await waitUntil(timeout: 1) {
            !engine.isStreaming && engine.displayedText.contains("Resposta automática")
        }

        XCTAssertEqual(client.recordedPrompts.count, 2)
    }

    func testUserSpeechClearsVisibleSuggestion() async throws {
        let client = MockCodexClient(responses: ["Resposta visível"])
        let settings = makeSettingsStore()
        let engine = SuggestionEngine(
            codexService: client,
            settingsStore: settings,
            timings: SuggestionTimings(
                holdMinimumSeconds: 0.05,
                readingThresholdSeconds: 0.05,
                readingCharsPerSecond: 500,
                turnPauseSeconds: 0.01,
                reevaluationGraceSeconds: 0.01
            )
        )

        let base = Date()
        engine.handleUserCommand(
            action: .continueSpeaking,
            entries: [makeEntry(.me, "Eu começaria falando sobre", timestamp: base)]
        )

        try await waitUntil(timeout: 1) {
            !engine.isStreaming && !engine.displayedText.isEmpty
        }

        engine.ingestSpeechFragment(
            speaker: .me,
            text: "Na prática eu começaria com SwiftUI e Observation.",
            timestamp: base.addingTimeInterval(0.2)
        )

        XCTAssertTrue(engine.displayedText.isEmpty)
        XCTAssertEqual(engine.state, .idle)
    }

    func testTranscriptionCoordinatorProcessesSourcesInParallel() async {
        let probe = TranscriptionProbe()
        let coordinator = TranscriptionCoordinator(windowDuration: 3, strideDuration: 1) { job in
            let label = "\(job.source.rawValue)-\(Int(job.samples.first ?? 0))-\(job.sequence)"
            await probe.begin(label)
            try? await Task.sleep(nanoseconds: 30_000_000)
            await probe.end(label)
            return label
        }

        let outputsTask = Task {
            await collectOutputs(from: coordinator, count: 2)
        }

        await coordinator.submit(makeChunk(source: .mic, marker: 1, timestamp: Date(timeIntervalSinceReferenceDate: 1)))
        await coordinator.submit(makeChunk(source: .mic, marker: 1, timestamp: Date(timeIntervalSinceReferenceDate: 2)))
        await coordinator.submit(makeChunk(source: .mic, marker: 1, timestamp: Date(timeIntervalSinceReferenceDate: 3)))

        await coordinator.submit(makeChunk(source: .system, marker: 2, timestamp: Date(timeIntervalSinceReferenceDate: 1)))
        await coordinator.submit(makeChunk(source: .system, marker: 2, timestamp: Date(timeIntervalSinceReferenceDate: 2)))
        await coordinator.submit(makeChunk(source: .system, marker: 2, timestamp: Date(timeIntervalSinceReferenceDate: 3)))

        let results = await outputsTask.value
        let snapshot = await probe.snapshot()

        XCTAssertEqual(Set(results.map(\.source)), Set([.mic, .system]))
        XCTAssertEqual(snapshot.maxRunning, 2)
        XCTAssertTrue(results.compactMap(\.text).contains("mic-1-0"))
        XCTAssertTrue(results.compactMap(\.text).contains("system-2-0"))
    }

    func testTranscriptionCoordinatorKeepsDisjointFlushWindows() async throws {
        let probe = TranscriptionProbe()
        let coordinator = TranscriptionCoordinator(windowDuration: 3, strideDuration: 1) { job in
            let label = "\(job.source.rawValue)-\(Int(job.samples.first ?? 0))-\(job.sequence)"
            await probe.begin(label)
            if label == "system-1-0" {
                await probe.pause(label)
            }
            await probe.end(label)
            return label
        }

        let outputsTask = Task {
            await collectOutputs(from: coordinator, count: 2)
        }

        await coordinator.submit(makeChunk(source: .system, marker: 1, timestamp: Date(timeIntervalSinceReferenceDate: 1)))
        await coordinator.submit(makeChunk(source: .system, marker: 1, timestamp: Date(timeIntervalSinceReferenceDate: 2)))
        await coordinator.flush(
            source: .system,
            sessionID: testSessionID,
            timestamp: Date(timeIntervalSinceReferenceDate: 2.1),
            reason: .silence
        )
        try await waitUntilAsync(timeout: 1) {
            await probe.isWaiting("system-1-0")
        }

        await coordinator.submit(makeChunk(source: .system, marker: 1, timestamp: Date(timeIntervalSinceReferenceDate: 4)))
        await coordinator.submit(makeChunk(source: .system, marker: 1, timestamp: Date(timeIntervalSinceReferenceDate: 5)))
        await coordinator.flush(
            source: .system,
            sessionID: testSessionID,
            timestamp: Date(timeIntervalSinceReferenceDate: 5.1),
            reason: .silence
        )
        await probe.release("system-1-0")

        let results = await outputsTask.value
        let diagnostics = await coordinator.diagnostics(for: .system)

        XCTAssertEqual(results.compactMap(\.text), ["system-1-0", "system-1-1"])
        XCTAssertEqual(diagnostics.discardedWindowCount, 0)
    }

    func testTranscriptManagerMergesOverlappingLiveEntriesWithoutDuplication() {
        let manager = TranscriptManager()
        let base = Date()
        let entry = manager.upsertLiveEntry(
            id: nil,
            speaker: .me,
            text: "Eu começaria falando sobre arquitetura",
            timestamp: base
        )
        let updated = manager.upsertLiveEntry(
            id: entry.id,
            speaker: .me,
            text: "falando sobre arquitetura distribuída e filas",
            timestamp: base.addingTimeInterval(1)
        )

        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(updated.text, "Eu começaria falando sobre arquitetura distribuída e filas")
    }

    func testPendingSignalsIgnoreExpiredEntries() {
        var pendingSignals = PendingSignals()
        let oldTimestamp = Date().addingTimeInterval(-Constants.Suggestion.SIGNAL_MAX_AGE_SECONDS - 1)
        let freshTimestamp = Date()

        pendingSignals.store(
            SuggestionSignal(
                kind: .followUp,
                priority: .followUp,
                transcript: "old",
                focusText: "old",
                source: "old",
                timestamp: oldTimestamp
            )
        )
        pendingSignals.store(
            SuggestionSignal(
                kind: .question,
                priority: .interviewerQuestion,
                transcript: "fresh",
                focusText: "fresh",
                source: "fresh",
                timestamp: freshTimestamp
            )
        )

        pendingSignals.removeExpiredSignals(olderThan: Constants.Suggestion.SIGNAL_MAX_AGE_SECONDS)

        XCTAssertEqual(
            pendingSignals.bestAvailable(maxAge: Constants.Suggestion.SIGNAL_MAX_AGE_SECONDS)?.kind,
            .question
        )
    }

    func testTranscriptOverlayKeepsVoiceSuggestionsActive() {
        let appState = AppState()
        appState.isListening = true

        appState.toggleVoiceSuggestionsPanel()
        XCTAssertEqual(appState.panelMode, .voiceSuggestions)
        XCTAssertTrue(appState.suggestionEngine.areAutomaticSuggestionsEnabled)

        appState.toggleTranscriptOverlay()
        XCTAssertTrue(appState.isTranscriptOverlayVisible)
        XCTAssertEqual(appState.panelMode, .voiceSuggestions)
        XCTAssertTrue(appState.suggestionEngine.areAutomaticSuggestionsEnabled)
    }

    func testTranscriptDiagnosticsSeparateAudioFromRecognition() {
        let appState = AppState()
        let now = Date()

        appState.micCaptureState = TranscriptCaptureState(
            isCapturing: true,
            lastAudioActivityAt: now,
            lastRecognizedText: "",
            lastRecognizedAt: nil
        )

        XCTAssertEqual(appState.captureStatusText(for: .me), "Receiving audio")
        XCTAssertEqual(
            appState.lastTranscriptPreview(for: .me),
            "Audio detected, but no speech recognized yet."
        )

        appState.ingestTranscribedText(
            "I was describing my approach.",
            speaker: .me,
            timestamp: now
        )

        XCTAssertEqual(appState.captureStatusText(for: .me), "Recognized speech")
        XCTAssertEqual(appState.lastTranscriptPreview(for: .me), "I was describing my approach.")
    }

    func testRuntimeLabelsUseEnglish() {
        XCTAssertEqual(VoiceAction.answer.displayLabel, "Answer")
        XCTAssertEqual(VoiceAction.continueSpeaking.displayLabel, "Continue")
        XCTAssertEqual(TranscriptEntry.Speaker.me.displayLabel, "You")
        XCTAssertEqual(TranscriptEntry.Speaker.interviewer.displayLabel, "Interviewer")
        XCTAssertEqual(TranscriptEntry(speaker: .me, text: "teste", timestamp: Date()).formatted, "[Eu]: teste")
    }

    private var testSessionID: UUID {
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    }

    private func makeChunk(
        source: TranscriptionSource,
        marker: Float,
        seconds: TimeInterval = 1,
        timestamp: Date = Date(),
        sessionID: UUID? = nil
    ) -> TranscriptionChunk {
        let sampleCount = max(1, Int(Constants.sampleRate * seconds))
        return TranscriptionChunk(
            source: source,
            samples: Array(repeating: marker, count: sampleCount),
            timestamp: timestamp,
            sessionID: sessionID ?? testSessionID
        )
    }

    private func makeEntry(
        _ speaker: TranscriptEntry.Speaker,
        _ text: String,
        timestamp: Date = Date()
    ) -> TranscriptEntry {
        TranscriptEntry(speaker: speaker, text: text, timestamp: timestamp)
    }

    private func makeTurn(
        _ speaker: TranscriptEntry.Speaker,
        _ text: String,
        startedAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> ConversationTurn {
        ConversationTurn(speaker: speaker, text: text, startedAt: startedAt, updatedAt: updatedAt)
    }

    private func makeSettingsStore() -> SettingsStore {
        let store = SettingsStore()
        store.settings.autoSuggest = true
        store.settings.assistantProfile = .techInterview
        return store
    }

    private func waitUntil(
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Condition not met before timeout", file: file, line: line)
    }

    private func waitUntilAsync(
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Async condition not met before timeout", file: file, line: line)
    }
}

@MainActor
final class AudioDriverManagerTests: XCTestCase {
    func testStatusIsNotInstalledWhenNoDriverIsPresent() {
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertEqual(manager.status, .notInstalled)
    }

    func testStatusDetectsLegacyBlackHole() {
        let legacy = makeDevice(id: 76, name: "BlackHole 2ch", uid: "BlackHole2ch_UID")
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(devices: [legacy], defaultOutput: legacy),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertEqual(manager.status, .legacyDriverInstalled)
        XCTAssertTrue(manager.statusDetail.contains("BlackHole"))
    }

    func testStatusNeedsRestartWhenArkBundleExistsButDriverIsNotLoaded() {
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(
                existingPaths: [Constants.AudioDriver.DRIVER_HAL_PATH]
            ),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertEqual(manager.status, .needsRestart)
    }

    func testStatusRequiresValidationWhenArkAudioIsDetectedWithoutStoredRouting() {
        let arkAudio = makeDevice(id: 91, name: "ArkAudio 2ch", uid: "ArkAudio2ch_UID")
        let speakers = makeDevice(id: 111, name: "Alto-falantes", uid: "BuiltInSpeakerDevice")
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(devices: [arkAudio, speakers], defaultOutput: speakers),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertEqual(manager.status, .routingNotVerified)
    }

    func testValidationPreflightRejectsNonAggregateOutputWithoutArkAudio() {
        let arkAudio = makeDevice(id: 91, name: "ArkAudio 2ch", uid: "ArkAudio2ch_UID")
        let speakers = makeDevice(id: 111, name: "Alto-falantes", uid: "BuiltInSpeakerDevice")
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(devices: [arkAudio, speakers], defaultOutput: speakers),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertEqual(
            manager.validationPreflightError(),
            "A saída padrão atual não é um Multi-Output Device. Crie um com sua saída física primeiro e o ArkAudio como secundário."
        )
    }

    func testValidationPreflightRejectsAggregateWhenArkAudioIsFirstSubdevice() {
        let arkAudio = makeDevice(id: 91, name: "ArkAudio 2ch", uid: "ArkAudio2ch_UID")
        let speakers = makeDevice(id: 111, name: "Alto-falantes", uid: "BuiltInSpeakerDevice")
        let multiOutput = makeDevice(id: 222, name: "Interview Mix", uid: "InterviewMix_UID")
        let routing = AudioOutputRoutingSnapshot(
            output: multiOutput,
            kind: .aggregate,
            subdevices: [
                AudioOutputSubdeviceSnapshot(uid: arkAudio.uid, name: arkAudio.name, driftCompensationEnabled: true),
                AudioOutputSubdeviceSnapshot(uid: speakers.uid, name: speakers.name, driftCompensationEnabled: false)
            ],
            mainSubdeviceUID: speakers.uid,
            clockDeviceUID: nil
        )
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(
                devices: [arkAudio, speakers, multiOutput],
                defaultOutput: multiOutput,
                routingSnapshots: [multiOutput.uid: routing]
            ),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertEqual(
            manager.validationPreflightError(),
            "O ArkAudio está no topo do Multi-Output Device. Deixe sua saída física como primeiro dispositivo e o ArkAudio como secundário."
        )
    }

    func testValidationPreflightAllowsAggregateWithPhysicalOutputFirstAndArkAudioSecondary() {
        let arkAudio = makeDevice(id: 91, name: "ArkAudio 2ch", uid: "ArkAudio2ch_UID")
        let speakers = makeDevice(id: 111, name: "Alto-falantes", uid: "BuiltInSpeakerDevice")
        let multiOutput = makeDevice(id: 222, name: "Interview Mix", uid: "InterviewMix_UID")
        let routing = AudioOutputRoutingSnapshot(
            output: multiOutput,
            kind: .aggregate,
            subdevices: [
                AudioOutputSubdeviceSnapshot(uid: speakers.uid, name: speakers.name, driftCompensationEnabled: false),
                AudioOutputSubdeviceSnapshot(uid: arkAudio.uid, name: arkAudio.name, driftCompensationEnabled: true)
            ],
            mainSubdeviceUID: speakers.uid,
            clockDeviceUID: nil
        )
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(
                devices: [arkAudio, speakers, multiOutput],
                defaultOutput: multiOutput,
                routingSnapshots: [multiOutput.uid: routing]
            ),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertNil(manager.validationPreflightError())
    }

    func testStatusBecomesInstalledWhenValidationMatchesCurrentOutput() {
        let arkAudio = makeDevice(id: 91, name: "ArkAudio 2ch", uid: "ArkAudio2ch_UID")
        let multiOutput = makeDevice(id: 111, name: "Interview Mix", uid: "InterviewMix_UID")
        let speakers = makeDevice(id: 112, name: "Alto-falantes", uid: "BuiltInSpeakerDevice")
        let routing = AudioOutputRoutingSnapshot(
            output: multiOutput,
            kind: .aggregate,
            subdevices: [
                AudioOutputSubdeviceSnapshot(uid: speakers.uid, name: speakers.name, driftCompensationEnabled: false),
                AudioOutputSubdeviceSnapshot(uid: arkAudio.uid, name: arkAudio.name, driftCompensationEnabled: true)
            ],
            mainSubdeviceUID: speakers.uid,
            clockDeviceUID: nil
        )
        let store = InMemoryAudioDriverValidationStore(
            validatedOutputUID: multiOutput.uid,
            validatedDriverUID: arkAudio.uid
        )
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(
                devices: [arkAudio, speakers, multiOutput],
                defaultOutput: multiOutput,
                routingSnapshots: [multiOutput.uid: routing]
            ),
            validationStore: store
        )

        manager.checkInstallation()

        XCTAssertEqual(manager.status, .installed)
    }

    func testStatusReturnsToRoutingNotVerifiedWhenDefaultOutputChangesAfterValidation() {
        let arkAudio = makeDevice(id: 91, name: "ArkAudio 2ch", uid: "ArkAudio2ch_UID")
        let speakers = makeDevice(id: 110, name: "Alto-falantes", uid: "BuiltInSpeakerDevice")
        let oldOutput = makeDevice(id: 111, name: "Interview Mix", uid: "InterviewMix_UID")
        let newOutput = makeDevice(id: 112, name: "Interview Mix 2", uid: "InterviewMixTwo_UID")
        let newRouting = AudioOutputRoutingSnapshot(
            output: newOutput,
            kind: .aggregate,
            subdevices: [
                AudioOutputSubdeviceSnapshot(uid: speakers.uid, name: speakers.name, driftCompensationEnabled: false),
                AudioOutputSubdeviceSnapshot(uid: arkAudio.uid, name: arkAudio.name, driftCompensationEnabled: true)
            ],
            mainSubdeviceUID: speakers.uid,
            clockDeviceUID: nil
        )
        let store = InMemoryAudioDriverValidationStore(
            validatedOutputUID: oldOutput.uid,
            validatedDriverUID: arkAudio.uid
        )
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(
                devices: [arkAudio, speakers, newOutput],
                defaultOutput: newOutput,
                routingSnapshots: [newOutput.uid: newRouting]
            ),
            validationStore: store
        )

        manager.checkInstallation()

        XCTAssertEqual(manager.status, .routingNotVerified)
        XCTAssertTrue(manager.statusDetail.contains("saída padrão mudou"))
    }

    func testAudioRoutingValidationSnapshotClassifiesOutcomes() {
        XCTAssertEqual(
            AudioRoutingValidationSnapshot(callbackCount: 0, maxNativeRMS: 0, maxConvertedRMS: 0)
                .outcome(threshold: Constants.AudioDriver.ROUTING_VALIDATION_RMS_THRESHOLD),
            .noCallbacks
        )
        XCTAssertEqual(
            AudioRoutingValidationSnapshot(callbackCount: 3, maxNativeRMS: 0.0004, maxConvertedRMS: 0.0002)
                .outcome(threshold: Constants.AudioDriver.ROUTING_VALIDATION_RMS_THRESHOLD),
            .nativeSignalMissing
        )
        XCTAssertEqual(
            AudioRoutingValidationSnapshot(callbackCount: 3, maxNativeRMS: 0.01, maxConvertedRMS: 0.0002)
                .outcome(threshold: Constants.AudioDriver.ROUTING_VALIDATION_RMS_THRESHOLD),
            .conversionSignalMissing
        )
        XCTAssertEqual(
            AudioRoutingValidationSnapshot(callbackCount: 3, maxNativeRMS: 0.01, maxConvertedRMS: 0.01)
                .outcome(threshold: Constants.AudioDriver.ROUTING_VALIDATION_RMS_THRESHOLD),
            .passed
        )
    }

    func testValidationPreflightRejectsUsingArkAudioAsDirectOutput() {
        let arkAudio = makeDevice(id: 91, name: "ArkAudio 2ch", uid: "ArkAudio2ch_UID")
        let manager = AudioDriverManager(
            hardwareInspector: MockAudioHardwareInspector(devices: [arkAudio], defaultOutput: arkAudio),
            validationStore: InMemoryAudioDriverValidationStore()
        )

        manager.checkInstallation()

        XCTAssertEqual(
            manager.validationPreflightError(),
            "O ArkAudio está como saída padrão direta. Crie um Multi-Output Device e selecione-o como saída do sistema."
        )
    }

    private func makeDevice(id: AudioDeviceID, name: String, uid: String) -> AudioDeviceSnapshot {
        AudioDeviceSnapshot(id: id, uid: uid, name: name)
    }
}

private struct MockAudioHardwareInspector: AudioHardwareInspecting {
    var devices: [AudioDeviceSnapshot] = []
    var defaultOutput: AudioDeviceSnapshot?
    var routingSnapshots: [String: AudioOutputRoutingSnapshot] = [:]
    var existingPaths: Set<String> = []

    func allDevices() -> [AudioDeviceSnapshot] {
        devices
    }

    func defaultOutputDevice() -> AudioDeviceSnapshot? {
        defaultOutput
    }

    func outputRoutingSnapshot(for device: AudioDeviceSnapshot) -> AudioOutputRoutingSnapshot? {
        routingSnapshots[device.uid] ?? AudioOutputRoutingSnapshot(
            output: device,
            kind: .direct,
            subdevices: [],
            mainSubdeviceUID: nil,
            clockDeviceUID: nil
        )
    }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }
}

private final class InMemoryAudioDriverValidationStore: AudioDriverValidationStoring {
    var validatedOutputUID: String?
    var validatedDriverUID: String?

    init(validatedOutputUID: String? = nil, validatedDriverUID: String? = nil) {
        self.validatedOutputUID = validatedOutputUID
        self.validatedDriverUID = validatedDriverUID
    }
}

private func collectOutputs(
    from coordinator: TranscriptionCoordinator,
    count: Int
) async -> [TranscriptionOutput] {
    var outputs: [TranscriptionOutput] = []

    for await output in coordinator.results {
        outputs.append(output)
        if outputs.count == count {
            return outputs
        }
    }

    return outputs
}

@MainActor
private final class MockCodexClient: SuggestionCodexClient {
    private(set) var recordedPrompts: [String] = []
    private var queuedResponses: [String]

    init(responses: [String]) {
        self.queuedResponses = responses
    }

    func chatStream(
        systemPrompt: String,
        userMessage: String,
        model: String?,
        reasoningLevel: String?,
        requestID: UUID,
        onChunk: @escaping @Sendable (UUID, String) -> Void
    ) async throws -> String {
        recordedPrompts.append(userMessage)

        let response = queuedResponses.isEmpty ? "" : queuedResponses.removeFirst()
        let midpoint = max(response.count / 2, 1)
        let chunks = response.isEmpty
            ? []
            : [String(response.prefix(midpoint)), String(response.dropFirst(midpoint))]

        for chunk in chunks where !chunk.isEmpty {
            try Task.checkCancellation()
            onChunk(requestID, chunk)
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        return response
    }
}

private actor TranscriptionProbe {
    private var currentRunning = 0
    private var maxRunning = 0
    private var processed: [String] = []
    private var waitingContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var waitingLabels: Set<String> = []

    func begin(_ label: String) {
        currentRunning += 1
        maxRunning = max(maxRunning, currentRunning)
        processed.append(label)
    }

    func pause(_ label: String) async {
        waitingLabels.insert(label)
        await withCheckedContinuation { continuation in
            waitingContinuations[label] = continuation
        }
    }

    func release(_ label: String) {
        waitingLabels.remove(label)
        waitingContinuations.removeValue(forKey: label)?.resume()
    }

    func end(_ label: String) {
        processed.append("done:\(label)")
        currentRunning -= 1
    }

    func hasStarted(_ label: String) -> Bool {
        processed.contains(label)
    }

    func isWaiting(_ label: String) -> Bool {
        waitingLabels.contains(label)
    }

    func processedLabels() -> [String] {
        processed
    }

    func snapshot() -> (maxRunning: Int, processed: [String]) {
        (maxRunning, processed)
    }
}
