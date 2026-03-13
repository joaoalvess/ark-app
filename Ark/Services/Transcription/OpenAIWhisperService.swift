import Foundation
import Observation

@Observable
final class OpenAIWhisperService: @unchecked Sendable {
    private(set) var isReady = false
    private(set) var error: String?

    func prepare(apiKey: String) {
        if !apiKey.isEmpty {
            isReady = true
            error = nil
        } else {
            isReady = false
            error = "API key da OpenAI não configurada. Adicione em Configurações."
        }
    }

    func transcribe(audioSamples: [Float], model: String = Constants.Transcription.OPENAI_WHISPER_MODEL, apiKey: String) async -> String? {
        guard !apiKey.isEmpty else {
            await MainActor.run { self.error = "API key não encontrada." }
            return nil
        }

        let wavData = encodeWAV(samples: audioSamples)
        let boundary = UUID().uuidString

        var request = URLRequest(url: URL(string: Constants.Transcription.OPENAI_WHISPER_ENDPOINT)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField(name: "model", value: model, boundary: boundary)
        body.appendMultipartField(name: "language", value: Constants.whisperLanguage, boundary: boundary)
        body.appendMultipartFile(name: "file", filename: "audio.wav", mimeType: "audio/wav", data: wavData, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { self.error = "Resposta inválida do servidor." }
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run { self.error = "API error (\(httpResponse.statusCode)): \(errorBody)" }
                return nil
            }

            let result = try JSONDecoder().decode(WhisperAPIResponse.self, from: data)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { self.error = nil }
            return text.isEmpty ? nil : text
        } catch {
            await MainActor.run { self.error = "Transcription failed: \(error.localizedDescription)" }
            return nil
        }
    }

    // MARK: - WAV encoding

    private func encodeWAV(samples: [Float]) -> Data {
        let sampleRate: UInt32 = UInt32(Constants.sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)

        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        let dataSize = UInt32(int16Samples.count * 2)
        let fileSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendLittleEndian(fileSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLittleEndian(UInt32(16))        // chunk size
        data.appendLittleEndian(UInt16(1))          // PCM format
        data.appendLittleEndian(numChannels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndian(dataSize)

        for sample in int16Samples {
            data.appendLittleEndian(sample)
        }

        return data
    }
}

// MARK: - Helpers

private struct WhisperAPIResponse: Decodable {
    let text: String
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        let size = MemoryLayout<T>.size
        let bytes = Swift.withUnsafePointer(to: &le) { ptr in
            Data(bytes: ptr, count: size)
        }
        append(bytes)
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data fileData: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
