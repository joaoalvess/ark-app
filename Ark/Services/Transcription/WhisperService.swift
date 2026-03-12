import Foundation
import Observation
@preconcurrency import WhisperKit

enum TranscriptionSource: String, Sendable {
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

struct TranscriptionJob: Sendable {
    let source: TranscriptionSource
    let samples: [Float]
    let timestamp: Date
    let sessionID: UUID
}

struct TranscriptionOutput: Sendable {
    let source: TranscriptionSource
    let timestamp: Date
    let sessionID: UUID
    let text: String?
}

actor TranscriptionCoordinator {
    nonisolated let results: AsyncStream<TranscriptionOutput>
    private let continuation: AsyncStream<TranscriptionOutput>.Continuation
    private let perform: @Sendable (TranscriptionJob) async -> String?

    private struct QueuedJob: Sendable {
        let order: UInt64
        let job: TranscriptionJob
    }

    private var pendingJobs: [TranscriptionSource: QueuedJob] = [:]
    private var nextOrder: UInt64 = 0
    private var processingTask: Task<Void, Never>?
    private(set) var droppedPendingJobs = 0

    init(perform: @escaping @Sendable (TranscriptionJob) async -> String?) {
        self.perform = perform

        var streamContinuation: AsyncStream<TranscriptionOutput>.Continuation?
        self.results = AsyncStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation!
    }

    func submit(_ job: TranscriptionJob) {
        let queuedJob = QueuedJob(order: nextOrder, job: job)
        nextOrder += 1

        if pendingJobs.updateValue(queuedJob, forKey: job.source) != nil {
            droppedPendingJobs += 1
        }

        guard processingTask == nil else { return }
        processingTask = Task { await processLoop() }
    }

    func reset() {
        pendingJobs.removeAll()
        droppedPendingJobs = 0
    }

    private func processLoop() async {
        while let queuedJob = dequeueNextJob() {
            let text = await perform(queuedJob.job)
            continuation.yield(
                TranscriptionOutput(
                    source: queuedJob.job.source,
                    timestamp: queuedJob.job.timestamp,
                    sessionID: queuedJob.job.sessionID,
                    text: text
                )
            )
        }

        processingTask = nil
    }

    private func dequeueNextJob() -> QueuedJob? {
        guard let queuedJob = pendingJobs.values.min(by: { $0.order < $1.order }) else {
            return nil
        }
        pendingJobs[queuedJob.job.source] = nil
        return queuedJob
    }
}

private struct UnsafeWhisperKit: @unchecked Sendable {
    let value: WhisperKit
}

private actor WhisperRuntime {
    private var whisperKit: UnsafeWhisperKit?

    func loadModel(name: String) async throws {
        let config = WhisperKitConfig(
            model: name,
            verbose: false,
            prewarm: true
        )
        let loadedWhisperKit = try await WhisperKit(config)
        whisperKit = UnsafeWhisperKit(value: loadedWhisperKit)
    }

    func transcribe(audioSamples: [Float], language: String) async throws -> String? {
        guard let whisperKit else { return nil }

        let result = try await whisperKit.value.transcribe(
            audioArray: audioSamples,
            decodeOptions: DecodingOptions(
                language: language,
                skipSpecialTokens: true,
                suppressBlank: true
            )
        )

        let text = result
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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
            return try await runtime.transcribe(
                audioSamples: audioSamples,
                language: Constants.whisperLanguage
            )
        } catch {
            await MainActor.run {
                self.error = "Transcription failed: \(error.localizedDescription)"
            }
            return nil
        }
    }
}
