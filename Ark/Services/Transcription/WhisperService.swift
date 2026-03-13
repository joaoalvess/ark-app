import Foundation
import Observation
@preconcurrency import WhisperKit

enum TranscriptionSource: String, Sendable, CaseIterable {
    case mic
    case system

    var speaker: TranscriptEntry.Speaker {
        switch self {
        case .mic:
            .me
        case .system:
            .interviewer
        }
    }
}

enum TranscriptionFlushReason: String, Sendable {
    case stride
    case silence
    case speakerSwitch
    case sessionEnd

    var finalizesTurn: Bool {
        self != .stride
    }
}

struct TranscriptionChunk: Sendable {
    let source: TranscriptionSource
    let samples: [Float]
    let timestamp: Date
    let sessionID: UUID
}

struct TranscriptionJob: Sendable {
    let source: TranscriptionSource
    let samples: [Float]
    let timestamp: Date
    let sessionID: UUID
    let sequence: UInt64
    let windowStart: Date
    let windowEnd: Date
    let flushReason: TranscriptionFlushReason
}

struct TranscriptionDiagnostics: Equatable, Sendable {
    var queueDepth = 0
    var coalescedChunkCount = 0
    var discardedWindowCount = 0
    var lastError: String?
}

struct TranscriptionOutput: Sendable {
    let source: TranscriptionSource
    let timestamp: Date
    let sessionID: UUID
    let text: String?
    let sequence: UInt64
    let windowStart: Date
    let windowEnd: Date
    let flushReason: TranscriptionFlushReason
    let diagnostics: TranscriptionDiagnostics
}

actor TranscriptionCoordinator {
    nonisolated let results: AsyncStream<TranscriptionOutput>
    private let continuation: AsyncStream<TranscriptionOutput>.Continuation
    private let perform: @Sendable (TranscriptionJob) async -> String?

    private struct DeferredFlush: Sendable {
        let timestamp: Date
        let sessionID: UUID
        let reason: TranscriptionFlushReason
    }

    private struct SourceState: Sendable {
        var rawBuffer: [Float] = []
        var bufferStartTime: Date?
        var lastChunkEndTime: Date?
        var queue: [TranscriptionJob] = []
        var nextSequence: UInt64 = 0
        var coalescedChunkCount = 0
        var discardedWindowCount = 0
        var deferredFlush: DeferredFlush?
    }

    private var strideDuration = Constants.Suggestion.ANALYSIS_CHUNK_DURATION
    private var windowDuration = Constants.chunkDuration
    private var sourceStates = Dictionary(uniqueKeysWithValues: TranscriptionSource.allCases.map {
        ($0, SourceState())
    })
    private var processingTasks: [TranscriptionSource: Task<Void, Never>] = [:]

    init(
        windowDuration: TimeInterval = Constants.chunkDuration,
        strideDuration: TimeInterval = Constants.Suggestion.ANALYSIS_CHUNK_DURATION,
        perform: @escaping @Sendable (TranscriptionJob) async -> String?
    ) {
        self.perform = perform
        self.windowDuration = windowDuration
        self.strideDuration = strideDuration

        var streamContinuation: AsyncStream<TranscriptionOutput>.Continuation?
        self.results = AsyncStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation!
    }

    func configure(windowDuration: TimeInterval, strideDuration: TimeInterval) {
        self.windowDuration = min(
            max(windowDuration, Constants.Suggestion.TRANSCRIPTION_WINDOW_MIN_SECONDS),
            Constants.Suggestion.TRANSCRIPTION_WINDOW_MAX_SECONDS
        )
        self.strideDuration = max(Constants.Suggestion.ANALYSIS_CHUNK_DURATION, strideDuration)
    }

    func submit(_ chunk: TranscriptionChunk) {
        var state = sourceStates[chunk.source] ?? SourceState()
        let chunkDuration = Double(chunk.samples.count) / Constants.sampleRate

        if state.bufferStartTime == nil {
            state.bufferStartTime = chunk.timestamp.addingTimeInterval(-chunkDuration)
        } else {
            state.coalescedChunkCount += 1
        }

        state.rawBuffer.append(contentsOf: chunk.samples)
        state.lastChunkEndTime = chunk.timestamp
        state.deferredFlush = nil

        enqueueStrideWindows(for: chunk.source, sessionID: chunk.sessionID, state: &state)
        sourceStates[chunk.source] = state
        startProcessorIfNeeded(for: chunk.source)
    }

    func flush(
        source: TranscriptionSource,
        sessionID: UUID,
        timestamp: Date,
        reason: TranscriptionFlushReason
    ) {
        var state = sourceStates[source] ?? SourceState()

        if let bufferStartTime = state.bufferStartTime, !state.rawBuffer.isEmpty {
            let job = TranscriptionJob(
                source: source,
                samples: state.rawBuffer,
                timestamp: timestamp,
                sessionID: sessionID,
                sequence: state.nextSequence,
                windowStart: bufferStartTime,
                windowEnd: timestamp,
                flushReason: reason
            )
            state.nextSequence += 1
            state.rawBuffer.removeAll(keepingCapacity: true)
            state.bufferStartTime = nil
            state.lastChunkEndTime = nil
            enqueue(job, into: &state)
            sourceStates[source] = state
            startProcessorIfNeeded(for: source)
            return
        }

        if state.queue.isEmpty, processingTasks[source] == nil {
            state.lastChunkEndTime = nil
            sourceStates[source] = state
            emitNilOutput(
                source: source,
                sessionID: sessionID,
                timestamp: timestamp,
                reason: reason,
                diagnostics: diagnostics(from: state)
            )
            return
        }

        state.deferredFlush = DeferredFlush(timestamp: timestamp, sessionID: sessionID, reason: reason)
        state.lastChunkEndTime = nil
        sourceStates[source] = state
    }

    func diagnostics(for source: TranscriptionSource) -> TranscriptionDiagnostics {
        diagnostics(from: sourceStates[source] ?? SourceState())
    }

    func hasBufferedAudio(for source: TranscriptionSource) -> Bool {
        let state = sourceStates[source] ?? SourceState()
        return !state.rawBuffer.isEmpty || !state.queue.isEmpty || state.deferredFlush != nil
    }

    func reset() {
        for task in processingTasks.values {
            task.cancel()
        }
        processingTasks.removeAll()
        sourceStates = Dictionary(uniqueKeysWithValues: TranscriptionSource.allCases.map {
            ($0, SourceState())
        })
    }

    private func enqueueStrideWindows(
        for source: TranscriptionSource,
        sessionID: UUID,
        state: inout SourceState
    ) {
        let windowSampleCount = max(1, Int(windowDuration * Constants.sampleRate))
        let strideSampleCount = max(1, Int(strideDuration * Constants.sampleRate))

        while state.rawBuffer.count >= windowSampleCount, let bufferStartTime = state.bufferStartTime {
            let samples = Array(state.rawBuffer.prefix(windowSampleCount))
            let windowEnd = bufferStartTime.addingTimeInterval(Double(samples.count) / Constants.sampleRate)
            let job = TranscriptionJob(
                source: source,
                samples: samples,
                timestamp: windowEnd,
                sessionID: sessionID,
                sequence: state.nextSequence,
                windowStart: bufferStartTime,
                windowEnd: windowEnd,
                flushReason: .stride
            )
            state.nextSequence += 1
            enqueue(job, into: &state)

            let consumedCount = min(strideSampleCount, state.rawBuffer.count)
            state.rawBuffer.removeFirst(consumedCount)
            if state.rawBuffer.isEmpty {
                state.bufferStartTime = nil
            } else {
                state.bufferStartTime = bufferStartTime.addingTimeInterval(
                    Double(consumedCount) / Constants.sampleRate
                )
            }
        }
    }

    private func enqueue(_ job: TranscriptionJob, into state: inout SourceState) {
        if let lastJob = state.queue.last,
           lastJob.sessionID == job.sessionID,
           job.windowStart <= lastJob.windowStart,
           job.windowEnd >= lastJob.windowEnd {
            state.queue[state.queue.count - 1] = job
            state.discardedWindowCount += 1
            return
        }

        state.queue.append(job)
    }

    private func startProcessorIfNeeded(for source: TranscriptionSource) {
        guard processingTasks[source] == nil else { return }
        processingTasks[source] = Task { await processLoop(for: source) }
    }

    private func processLoop(for source: TranscriptionSource) async {
        while !Task.isCancelled {
            guard let job = dequeueJob(for: source) else { break }

            let text = await perform(job)
            guard !Task.isCancelled else { break }

            let state = sourceStates[source] ?? SourceState()
            continuation.yield(
                TranscriptionOutput(
                    source: source,
                    timestamp: job.timestamp,
                    sessionID: job.sessionID,
                    text: text,
                    sequence: job.sequence,
                    windowStart: job.windowStart,
                    windowEnd: job.windowEnd,
                    flushReason: job.flushReason,
                    diagnostics: diagnostics(from: state)
                )
            )

            await emitDeferredFlushIfNeeded(for: source)
        }

        processingTasks[source] = nil
        if let state = sourceStates[source], !state.queue.isEmpty {
            startProcessorIfNeeded(for: source)
        }
    }

    private func dequeueJob(for source: TranscriptionSource) -> TranscriptionJob? {
        guard var state = sourceStates[source], !state.queue.isEmpty else { return nil }
        let job = state.queue.removeFirst()
        sourceStates[source] = state
        return job
    }

    private func emitDeferredFlushIfNeeded(for source: TranscriptionSource) async {
        guard var state = sourceStates[source] else { return }
        guard state.rawBuffer.isEmpty, state.queue.isEmpty, let deferredFlush = state.deferredFlush else {
            return
        }

        state.deferredFlush = nil
        sourceStates[source] = state

        emitNilOutput(
            source: source,
            sessionID: deferredFlush.sessionID,
            timestamp: deferredFlush.timestamp,
            reason: deferredFlush.reason,
            diagnostics: diagnostics(from: state)
        )
    }

    private func diagnostics(from state: SourceState) -> TranscriptionDiagnostics {
        TranscriptionDiagnostics(
            queueDepth: state.queue.count,
            coalescedChunkCount: state.coalescedChunkCount,
            discardedWindowCount: state.discardedWindowCount,
            lastError: nil
        )
    }

    private func emitNilOutput(
        source: TranscriptionSource,
        sessionID: UUID,
        timestamp: Date,
        reason: TranscriptionFlushReason,
        diagnostics: TranscriptionDiagnostics
    ) {
        continuation.yield(
            TranscriptionOutput(
                source: source,
                timestamp: timestamp,
                sessionID: sessionID,
                text: nil,
                sequence: 0,
                windowStart: timestamp,
                windowEnd: timestamp,
                flushReason: reason,
                diagnostics: diagnostics
            )
        )
    }
}

private struct UnsafeWhisperKit: @unchecked Sendable {
    let value: WhisperKit
}

private actor WhisperRuntime {
    private var whisperKit: UnsafeWhisperKit?
    private var lastTranscribedText: String?
    private var consecutiveRepeatCount = 0
    func loadModel(name: String) async throws {
        let config = WhisperKitConfig(
            model: name,
            verbose: false,
            prewarm: true
        )
        let loadedWhisperKit = try await WhisperKit(config)
        whisperKit = UnsafeWhisperKit(value: loadedWhisperKit)
        resetHallucinationState()
    }

    func transcribe(audioSamples: [Float], language: String) async throws -> String? {
        guard let whisperKit else { return nil }

        let result = try await whisperKit.value.transcribe(
            audioArray: audioSamples,
            decodeOptions: DecodingOptions(
                language: language,
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.0,
                temperatureFallbackCount: 0,
                sampleLength: 128,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                suppressBlank: true,
                noSpeechThreshold: 0.3
            )
        )

        let text = result
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        return isHallucination(text) ? nil : text
    }

    func resetHallucinationState() {
        lastTranscribedText = nil
        consecutiveRepeatCount = 0
    }

    private func isHallucination(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if Constants.Hallucination.BLOCKLIST.contains(normalized) {
            return true
        }

        if normalized == lastTranscribedText {
            consecutiveRepeatCount += 1
            if consecutiveRepeatCount > Constants.Hallucination.MAX_CONSECUTIVE_REPEATS {
                return true
            }
        } else {
            lastTranscribedText = normalized
            consecutiveRepeatCount = 1
        }

        return false
    }
}

@Observable
final class WhisperService: @unchecked Sendable {
    private let runtime = WhisperRuntime()
    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress: Double = 0
    private(set) var error: String?

    func loadModel(name: String = Constants.whisperModel) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            try await runtime.loadModel(name: name)
            isModelLoaded = true
        } catch {
            self.error = "Failed to load model: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func transcribe(audioSamples: [Float]) async -> String? {
        guard isModelLoaded else { return nil }

        do {
            let text = try await runtime.transcribe(
                audioSamples: audioSamples,
                language: Constants.whisperLanguage
            )
            await MainActor.run {
                self.error = nil
            }
            return text
        } catch {
            await MainActor.run {
                self.error = "Transcription failed: \(error.localizedDescription)"
            }
            return nil
        }
    }
}
