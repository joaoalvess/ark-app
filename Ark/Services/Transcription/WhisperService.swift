import Foundation
import WhisperKit
import Observation

@Observable
final class WhisperService: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress: Double = 0
    private(set) var error: String?

    func loadModel(name: String = Constants.whisperModel) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let config = WhisperKitConfig(
                model: name,
                verbose: false,
                prewarm: true
            )
            whisperKit = try await WhisperKit(config)
            isModelLoaded = true
        } catch {
            self.error = "Falha ao carregar modelo: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func transcribe(audioSamples: [Float]) async -> String? {
        guard let whisperKit, isModelLoaded else { return nil }

        do {
            let result = try await whisperKit.transcribe(
                audioArray: audioSamples,
                decodeOptions: DecodingOptions(
                    language: Constants.whisperLanguage,
                    skipSpecialTokens: true,
                    suppressBlank: true
                )
            )
            let text = result.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            self.error = "Erro na transcricao: \(error.localizedDescription)"
            return nil
        }
    }
}
